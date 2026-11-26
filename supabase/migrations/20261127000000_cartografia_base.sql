-- Base cartográfica: límites administrativos, aporte libre de lugares y exportación del dataset.
--
-- 1) admin_areas: departamentos (nivel 1), comunas (nivel 2) y secciones comunales (nivel 3) con polígonos.
--    Los polígonos se cargan con supabase/scripts/limites-haiti.mjs (geoBoundaries), no en esta migración.
-- 2) Cada lugar queda asignado automáticamente a la comuna que contiene su punto.
-- 3) Misión de sistema HT-LIBRE: cualquier colaborador agrega un lugar sin misión. Sin pago; se modera igual.
-- 4) admin_export_places: exportación de lugares públicos aprobados (GeoJSON/CSV en el panel).

-- ---------------------------------------------------------------------------
-- 1) Límites administrativos
-- ---------------------------------------------------------------------------
create table if not exists public.admin_areas (
  id bigint generated always as identity primary key,
  level smallint not null check (level between 1 and 3),
  code text not null unique,
  name text not null,
  iso_code text,
  parent_id bigint references public.admin_areas (id) on delete set null,
  geom extensions.geometry (MultiPolygon, 4326),
  source text,
  license text,
  updated_at timestamptz not null default now()
);
create index if not exists admin_areas_geom_gix on public.admin_areas using gist (geom);
create index if not exists admin_areas_level_idx on public.admin_areas (level, name);

alter table public.admin_areas enable row level security;
drop policy if exists "límites visibles" on public.admin_areas;
create policy "límites visibles" on public.admin_areas for select using (true);
revoke all on public.admin_areas from public, anon, authenticated;
grant select on public.admin_areas to anon, authenticated;

-- Lista liviana (sin polígonos) para filtros y formularios.
create or replace view public.admin_areas_list with (security_invoker = true) as
select a.id, a.level, a.code, a.name, a.parent_id, p.name as parent_name
from public.admin_areas a
left join public.admin_areas p on p.id = a.parent_id;
grant select on public.admin_areas_list to anon, authenticated;

-- Comuna (y departamento) que contiene un punto. Si cae justo fuera del polígono simplificado
-- (costa, frontera), se toma la comuna más cercana a menos de ~2 km.
create or replace function public.admin_area_at(lat double precision, lng double precision)
returns table (commune_id bigint, commune text, department_id bigint, department text)
language sql stable security invoker set search_path = '' as $$
  with pt as (select extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326) as g)
  select c.id, c.name, d.id, d.name
  from public.admin_areas c
  cross join pt
  left join public.admin_areas d on d.id = c.parent_id
  where c.level = 2 and c.geom is not null
    and extensions.st_dwithin(c.geom, pt.g, 0.02)
  order by extensions.st_distance(c.geom, pt.g), c.id
  limit 1;
$$;
revoke all on function public.admin_area_at(double precision, double precision) from public;
grant execute on function public.admin_area_at(double precision, double precision) to anon, authenticated;

alter table public.places add column if not exists commune_id bigint references public.admin_areas (id) on delete set null;
create index if not exists places_commune_idx on public.places (commune_id);

create or replace function public.places_assign_area() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  a record;
begin
  select * into a
  from public.admin_area_at(extensions.st_y(new.location::extensions.geometry), extensions.st_x(new.location::extensions.geometry));
  if found and a.commune_id is not null then
    new.commune_id := a.commune_id;
    new.commune := a.commune;
    new.department := coalesce(a.department, new.department);
  else
    new.commune_id := null;
  end if;
  return new;
end;
$$;
revoke all on function public.places_assign_area() from public, anon, authenticated;

drop trigger if exists places_assign_area on public.places;
create trigger places_assign_area before insert or update of location on public.places
  for each row execute function public.places_assign_area();

-- Carga de polígonos desde GeoJSON (features de geoBoundaries). Solo desde el SQL Editor o service_role.
create or replace function public.import_admin_areas(p_level smallint, p_features jsonb, p_source text default null, p_license text default null)
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  if p_level not in (1, 2, 3) then raise exception 'Nivel no válido: %', p_level; end if;
  if jsonb_typeof(p_features) <> 'array' then raise exception 'Se esperaba una lista de features'; end if;

  insert into public.admin_areas as t (level, code, name, iso_code, geom, source, license, updated_at)
  select p_level,
         coalesce(nullif(f -> 'properties' ->> 'shapeID', ''), nullif(f -> 'properties' ->> 'code', '')),
         coalesce(nullif(f -> 'properties' ->> 'shapeName', ''), f -> 'properties' ->> 'name'),
         nullif(f -> 'properties' ->> 'shapeISO', ''),
         extensions.st_multi(extensions.st_collectionextract(extensions.st_makevalid(
           extensions.st_setsrid(extensions.st_geomfromgeojson((f -> 'geometry')::text), 4326)), 3)),
         p_source, p_license, now()
  from jsonb_array_elements(p_features) as f
  on conflict (code) do update
    set level = excluded.level, name = excluded.name, iso_code = excluded.iso_code, geom = excluded.geom,
        source = excluded.source, license = excluded.license, updated_at = now();
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.import_admin_areas(smallint, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.import_admin_areas(smallint, jsonb, text, text) to service_role;

-- Tras cargar: enlaza cada área con su área superior y reasigna todos los lugares.
create or replace function public.link_admin_areas()
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_linked integer;
  v_places integer;
begin
  update public.admin_areas c
     set parent_id = (
       select p.id from public.admin_areas p
        where p.level = c.level - 1 and p.geom is not null
          and extensions.st_covers(p.geom, extensions.st_pointonsurface(c.geom))
        order by p.id limit 1)
   where c.level > 1 and c.geom is not null;
  get diagnostics v_linked = row_count;

  update public.places set location = location;
  get diagnostics v_places = row_count;

  return jsonb_build_object('areas_linked', v_linked, 'places_reassigned', v_places);
end;
$$;
revoke all on function public.link_admin_areas() from public, anon, authenticated;
grant execute on function public.link_admin_areas() to service_role;

-- ---------------------------------------------------------------------------
-- 2) Aporte libre: misión de sistema HT-LIBRE
-- ---------------------------------------------------------------------------
alter table public.missions add column if not exists open_contribution boolean not null default false;
create unique index if not exists missions_single_open_contribution on public.missions (open_contribution) where open_contribution;
-- El catálogo de misiones se expone por columnas (api_least_privilege): la app necesita leer esta.
grant select (open_contribution) on public.missions to anon, authenticated;

insert into public.missions (code, type, title, description, center, radius_m, required_approved_contributions,
  individual_reward_usd, completion_bonus_usd, budget_authorized_usd, requires_on_site_evidence, requirements, status,
  open_contribution)
values ('HT-LIBRE', 'NEW_PLACE', 'Agregar un lugar',
  'Aporte libre: agrega un negocio o lugar que falta en el mapa. No tiene recompensa; se publica cuando el equipo lo aprueba.',
  extensions.st_setsrid(extensions.st_makepoint(-72.3350, 18.5392), 4326)::extensions.geography, null, 1,
  0, 0, 0, true, 'Estar en el lugar + foto del frente + nombre y categoría', 'ACTIVE', true)
on conflict (code) do nothing;

-- La misión libre no aparece en el mapa de misiones.
drop function if exists public.missions_nearby(double precision, double precision, double precision);
create function public.missions_nearby(lat double precision, lng double precision, radius_km double precision default 25)
returns table (
  id uuid, code text, type public.mission_type, title text, description text, commune text,
  lat double precision, lng double precision, radius_m integer, individual_reward_usd numeric, completion_bonus_usd numeric,
  required_approved_contributions integer, requirements text, end_at timestamptz, distance_m double precision,
  requires_on_site_evidence boolean
)
language sql stable set search_path = '' as $$
  select m.id, m.code, m.type, m.title, m.description, m.commune,
         extensions.st_y(m.center::extensions.geometry), extensions.st_x(m.center::extensions.geometry), m.radius_m,
         m.individual_reward_usd, m.completion_bonus_usd, m.required_approved_contributions, m.requirements, m.end_at,
         extensions.st_distance(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography),
         m.requires_on_site_evidence
  from public.missions m
  where m.status = 'ACTIVE'
    and not m.open_contribution
    and (m.end_at is null or m.end_at > now())
    and extensions.st_dwithin(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography, radius_km * 1000)
  order by 15;
$$;
grant execute on function public.missions_nearby(double precision, double precision, double precision) to anon, authenticated;

-- Límite anti-abuso: 30 aportes libres por persona cada 24 horas.
create or replace function public.limit_open_contributions() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.missions where id = new.mission_id and open_contribution)
     and (select count(*) from public.mission_contributions
           where user_id = new.user_id and mission_id = new.mission_id
             and created_at > now() - interval '24 hours') >= 30 then
    raise exception 'Alcanzaste el límite diario de aportes libres' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.limit_open_contributions() from public, anon, authenticated;
drop trigger if exists limit_open_contributions on public.mission_contributions;
create trigger limit_open_contributions before insert on public.mission_contributions
  for each row execute function public.limit_open_contributions();

-- Moderación: sin asiento de recompensa cuando el aporte no tiene pago (aporte libre o misión a 0).
create or replace function public.review_contribution(p_contribution_id uuid, p_decision public.contribution_status, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c public.mission_contributions;
  m public.missions;
  v_place_id uuid;
  v_approved int;
  v_reward numeric := 0;
  v_bonus numeric := 0;
begin
  if not (public.has_role('moderator') or public.has_role('admin')) then
    raise exception 'Solo moderadores pueden revisar aportes' using errcode = '42501';
  end if;
  if p_decision not in ('APPROVED', 'REJECTED', 'NEEDS_CHANGES') then
    raise exception 'Decisión no válida: %', p_decision;
  end if;
  if p_decision <> 'APPROVED' and coalesce(trim(p_reason), '') = '' then
    raise exception 'Indica el motivo del rechazo o de la corrección';
  end if;

  select * into c from public.mission_contributions where id = p_contribution_id for update;
  if not found then raise exception 'Aporte no encontrado'; end if;
  if c.user_id = auth.uid() then raise exception 'No puedes revisar tu propio aporte' using errcode = '42501'; end if;
  if c.status = 'APPROVED' then
    return jsonb_build_object('status', c.status, 'place_id', c.place_id, 'already', true);
  end if;

  select * into m from public.missions where id = c.mission_id;

  if p_decision = 'APPROVED' then
    -- La comuna y el departamento los asigna places_assign_area cuando hay límites cargados.
    insert into public.places (name, category, commune, department, address_reference, location, accuracy_m, source_contribution_id)
    values (c.name, c.category, m.commune, m.department, c.address_reference, c.location, c.accuracy_m, c.id)
    returning id into v_place_id;

    if m.individual_reward_usd > 0 then
      -- Recompensa por aporte: una sola vez gracias al índice único.
      insert into public.reward_events (user_id, contribution_id, mission_id, kind, amount_usd, status, created_by)
      values (c.user_id, c.id, m.id, 'CONTRIBUTION', m.individual_reward_usd, 'EARNED', auth.uid())
      on conflict do nothing;
      v_reward := m.individual_reward_usd;
    end if;

    update public.mission_contributions
       set status = 'APPROVED', place_id = v_place_id, review_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now()
     where id = c.id;

    -- Bono de misión al completar los aportes requeridos (solo si la misión lo define).
    if m.completion_bonus_usd > 0 then
      select count(*) into v_approved from public.mission_contributions
       where mission_id = m.id and user_id = c.user_id and status = 'APPROVED';
      if v_approved >= m.required_approved_contributions then
        insert into public.reward_events (user_id, mission_id, kind, amount_usd, status, reason, created_by)
        values (c.user_id, m.id, 'MISSION_BONUS', m.completion_bonus_usd, 'EARNED', 'Misión completada', auth.uid())
        on conflict do nothing;
        v_bonus := m.completion_bonus_usd;
      end if;
    end if;
  else
    update public.mission_contributions
       set status = p_decision, review_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now()
     where id = c.id;
  end if;

  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'review_contribution', c.id, jsonb_build_object('decision', p_decision, 'reason', p_reason));

  return jsonb_build_object('status', p_decision, 'place_id', v_place_id, 'reward_usd', v_reward, 'bonus_usd', v_bonus);
end;
$$;
revoke all on function public.review_contribution(uuid, public.contribution_status, text) from public, anon;
grant execute on function public.review_contribution(uuid, public.contribution_status, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Exportación del dataset (solo administradores con MFA)
-- ---------------------------------------------------------------------------
create or replace function public.admin_export_places(
  p_department_id bigint default null,
  p_commune_id bigint default null,
  p_category text default null
)
returns table (
  code text, name text, category text, department text, commune text, commune_code text,
  address_reference text, lat double precision, lng double precision, accuracy_m numeric,
  approved_at timestamptz, updated_at timestamptz
)
language plpgsql volatile security definer set search_path = '' as $$
declare
  n integer;
begin
  if not public.has_role('admin') then
    raise exception 'Solo administradores pueden exportar datos' using errcode = '42501';
  end if;

  return query
  select p.code, p.name, p.category, p.department, p.commune, a.code,
         p.address_reference,
         extensions.st_y(p.location::extensions.geometry), extensions.st_x(p.location::extensions.geometry),
         p.accuracy_m, mc.reviewed_at, p.updated_at
  from public.places p
  left join public.admin_areas a on a.id = p.commune_id
  left join public.mission_contributions mc on mc.id = p.source_contribution_id
  where p.visibility = 'PUBLIC'
    and (p_commune_id is null or p.commune_id = p_commune_id)
    and (p_department_id is null or a.parent_id = p_department_id)
    and (p_category is null or p.category = p_category)
  order by p.code;

  get diagnostics n = row_count;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'export_places', null, jsonb_build_object(
    'rows', n, 'department_id', p_department_id, 'commune_id', p_commune_id, 'category', p_category));
end;
$$;
revoke all on function public.admin_export_places(bigint, bigint, text) from public, anon;
grant execute on function public.admin_export_places(bigint, bigint, text) to authenticated;

notify pgrst, 'reload schema';
