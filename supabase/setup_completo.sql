-- Haiti Tracking by Nexovax - esquema inicial MVP (fase 1)
-- Colaboradores, misiones, aportes, lugares y libro de recompensas.
-- Montos en numeric (decimal exacto), nunca float.

create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------
create type public.app_role as enum ('collaborator', 'company', 'developer', 'admin', 'moderator');
create type public.mission_type as enum ('NEW_PLACE', 'PRIORITY_PLACE', 'MAJOR_CORRECTION', 'INDEPENDENT_CHECK', 'BATCH_ZONE');
create type public.mission_status as enum ('DRAFT', 'IN_REVIEW', 'APPROVED', 'SCHEDULED', 'ACTIVE', 'PAUSED', 'COMPLETED', 'EXPIRED', 'CANCELLED', 'ARCHIVED');
create type public.assignment_status as enum ('CLAIMED', 'IN_PROGRESS', 'SUBMITTED', 'ACCEPTED', 'REJECTED', 'NEEDS_CHANGES', 'EXPIRED', 'CANCELLED');
create type public.contribution_status as enum ('DRAFT', 'SUBMITTED', 'AUTO_CHECKED', 'HUMAN_REVIEW', 'APPROVED', 'REJECTED', 'NEEDS_CHANGES', 'APPEALED');
create type public.place_visibility as enum ('PUBLIC', 'RESTRICTED', 'PRIVATE');
create type public.reward_status as enum ('PENDING_REVIEW', 'EARNED', 'AVAILABLE', 'ON_HOLD', 'WITHDRAWAL_REQUESTED', 'PAID', 'REVERSED');

-- ---------------------------------------------------------------------------
-- Perfiles (1:1 con auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  phone text,
  department text,
  commune text,
  birth_date date,
  preferred_language text not null default 'ht' check (preferred_language in ('ht', 'fr', 'es', 'en')),
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.account_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.app_role not null,
  granted_at timestamptz not null default now(),
  primary key (user_id, role)
);

-- Al registrarse: crear perfil y rol colaborador por defecto.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), new.phone);
  insert into public.account_roles (user_id, role) values (new.id, 'collaborator');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.has_role(r public.app_role) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.account_roles where user_id = auth.uid() and role = r);
$$;

-- ---------------------------------------------------------------------------
-- Misiones
-- ---------------------------------------------------------------------------
create table public.missions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  type public.mission_type not null,
  title text not null,
  description text not null default '',
  department text,
  commune text,
  area extensions.geography (Polygon, 4326),
  center extensions.geography (Point, 4326) not null,
  radius_m integer check (radius_m > 0),
  required_approved_contributions integer not null default 1 check (required_approved_contributions > 0),
  individual_reward_usd numeric(10, 2) not null check (individual_reward_usd >= 0),
  completion_bonus_usd numeric(10, 2) not null default 0 check (completion_bonus_usd >= 0),
  max_participants integer check (max_participants > 0),
  budget_authorized_usd numeric(12, 2) not null default 0,
  requires_on_site_evidence boolean not null default true,
  requirements text not null default 'GPS + foto + datos del lugar',
  start_at timestamptz,
  end_at timestamptz,
  status public.mission_status not null default 'DRAFT',
  created_by uuid references auth.users (id),
  approved_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (approved_by is null or approved_by <> created_by)
);
create index missions_center_gix on public.missions using gist (center);
create index missions_status_idx on public.missions (status);

create table public.mission_assignments (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions (id),
  user_id uuid not null references auth.users (id),
  status public.assignment_status not null default 'CLAIMED',
  reward_rule_snapshot jsonb not null default '{}'::jsonb,
  claimed_at timestamptz not null default now(),
  expires_at timestamptz,
  unique (mission_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Lugares (catálogo aprobado)
-- ---------------------------------------------------------------------------
create sequence public.place_code_seq;

create table public.places (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default ('HT-NXV-' || lpad(nextval('public.place_code_seq')::text, 6, '0')),
  name text not null,
  category text not null,
  department text,
  commune text,
  address_reference text,
  location extensions.geography (Point, 4326) not null,
  accuracy_m numeric(8, 2),
  visibility public.place_visibility not null default 'PUBLIC',
  source_contribution_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index places_location_gix on public.places using gist (location);

-- ---------------------------------------------------------------------------
-- Aportes
-- ---------------------------------------------------------------------------
create table public.mission_contributions (
  id uuid primary key default gen_random_uuid(),
  idempotency_key uuid not null unique,
  mission_id uuid not null references public.missions (id),
  assignment_id uuid references public.mission_assignments (id),
  user_id uuid not null references auth.users (id) default auth.uid(),
  place_id uuid references public.places (id),
  name text not null,
  category text not null,
  address_reference text,
  notes text,
  location extensions.geography (Point, 4326) not null,
  accuracy_m numeric(8, 2),
  captured_at timestamptz not null,
  photo_paths text[] not null default '{}',
  status public.contribution_status not null default 'SUBMITTED',
  review_reason text,
  reviewed_by uuid references auth.users (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (reviewed_by is null or reviewed_by <> user_id)
);
create index mission_contributions_user_status_idx on public.mission_contributions (user_id, status, created_at desc);
create index mission_contributions_location_gix on public.mission_contributions using gist (location);

alter table public.places
  add constraint places_source_contribution_fk foreign key (source_contribution_id) references public.mission_contributions (id);

-- ---------------------------------------------------------------------------
-- Libro de recompensas (inmutable: correcciones con nuevos asientos)
-- ---------------------------------------------------------------------------
create table public.reward_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id),
  contribution_id uuid references public.mission_contributions (id),
  mission_id uuid references public.missions (id),
  kind text not null check (kind in ('CONTRIBUTION', 'MISSION_BONUS', 'WELCOME_BONUS', 'ADJUSTMENT')),
  amount_usd numeric(10, 2) not null,
  status public.reward_status not null default 'EARNED',
  reason text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);
-- Un aporte no se paga dos veces.
create unique index reward_events_once_per_contribution on public.reward_events (contribution_id) where kind = 'CONTRIBUTION';

create view public.my_reward_summary with (security_invoker = true) as
select
  user_id,
  coalesce(sum(amount_usd) filter (where status = 'PENDING_REVIEW'), 0) as pending_usd,
  coalesce(sum(amount_usd) filter (where status = 'EARNED'), 0) as earned_usd,
  coalesce(sum(amount_usd) filter (where status = 'AVAILABLE'), 0) as available_usd,
  coalesce(sum(amount_usd) filter (where status = 'ON_HOLD'), 0) as on_hold_usd
from public.reward_events
group by user_id;

-- ---------------------------------------------------------------------------
-- Funciones de la app
-- ---------------------------------------------------------------------------

-- Misiones activas cercanas (no exige GPS: la app puede pasar el centro del mapa).
create function public.missions_nearby(lat double precision, lng double precision, radius_km double precision default 25)
returns table (
  id uuid, code text, type public.mission_type, title text, description text, commune text,
  lat double precision, lng double precision, individual_reward_usd numeric, completion_bonus_usd numeric,
  required_approved_contributions integer, requirements text, end_at timestamptz, distance_m double precision
)
language sql stable set search_path = '' as $$
  select m.id, m.code, m.type, m.title, m.description, m.commune,
         extensions.st_y(m.center::extensions.geometry), extensions.st_x(m.center::extensions.geometry),
         m.individual_reward_usd, m.completion_bonus_usd, m.required_approved_contributions, m.requirements, m.end_at,
         extensions.st_distance(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography)
  from public.missions m
  where m.status = 'ACTIVE'
    and (m.end_at is null or m.end_at > now())
    and extensions.st_dwithin(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography, radius_km * 1000)
  order by 14;
$$;

-- Posibles duplicados: lugares a menos de N metros con nombre parecido o misma categoría.
create function public.check_duplicates(lat double precision, lng double precision, place_name text, radius_m double precision default 50)
returns table (id uuid, code text, name text, category text, distance_m double precision)
language sql stable security definer set search_path = '' as $$
  select p.id, p.code, p.name, p.category,
         extensions.st_distance(p.location, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography) as d
  from public.places p
  where p.visibility = 'PUBLIC'
    and extensions.st_dwithin(p.location, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography, radius_m)
  order by d
  limit 10;
$$;

-- ---------------------------------------------------------------------------
-- Seguridad a nivel de fila (RLS)
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.account_roles enable row level security;
alter table public.missions enable row level security;
alter table public.mission_assignments enable row level security;
alter table public.places enable row level security;
alter table public.mission_contributions enable row level security;
alter table public.reward_events enable row level security;

create policy "perfil propio: leer" on public.profiles for select using (id = auth.uid() or public.has_role('admin') or public.has_role('moderator'));
create policy "perfil propio: editar" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid() and verified = (select p.verified from public.profiles p where p.id = auth.uid()));

create policy "roles propios: leer" on public.account_roles for select using (user_id = auth.uid() or public.has_role('admin'));

create policy "misiones activas visibles" on public.missions for select using (status = 'ACTIVE' or public.has_role('admin') or public.has_role('moderator'));
create policy "admin gestiona misiones" on public.missions for all using (public.has_role('admin')) with check (public.has_role('admin'));

create policy "asignaciones propias: leer" on public.mission_assignments for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('moderator'));
create policy "asignaciones propias: crear" on public.mission_assignments for insert with check (user_id = auth.uid() and status = 'CLAIMED');

create policy "lugares públicos visibles" on public.places for select using (visibility = 'PUBLIC' or public.has_role('admin') or public.has_role('moderator'));
create policy "moderación gestiona lugares" on public.places for all using (public.has_role('admin') or public.has_role('moderator')) with check (public.has_role('admin') or public.has_role('moderator'));

create policy "aportes propios: leer" on public.mission_contributions for select using (user_id = auth.uid() or public.has_role('admin') or public.has_role('moderator'));
create policy "aportes propios: crear" on public.mission_contributions for insert with check (user_id = auth.uid() and status = 'SUBMITTED' and reviewed_by is null);
create policy "moderación revisa aportes" on public.mission_contributions for update using (public.has_role('moderator') or public.has_role('admin')) with check (reviewed_by = auth.uid() and user_id <> auth.uid());

create policy "recompensas propias: leer" on public.reward_events for select using (user_id = auth.uid() or public.has_role('admin'));
-- Sin políticas de insert/update para usuarios: los asientos se crean solo desde el servidor.

-- ---------------------------------------------------------------------------
-- Almacenamiento privado de evidencias: cada usuario en su carpeta {uid}/...
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('evidence', 'evidence', false) on conflict (id) do nothing;

create policy "evidencias propias: subir" on storage.objects for insert
  with check (bucket_id = 'evidence' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "evidencias propias o moderación: leer" on storage.objects for select
  using (bucket_id = 'evidence' and ((storage.foldername(name))[1] = auth.uid()::text or public.has_role('moderator') or public.has_role('admin')));
-- Permisos para la app móvil (solo objetos de Haiti Tracking; las tablas del backend anterior no se exponen).
-- Nota: la tabla "contributions" ya existía (backend anterior), por eso la nuestra se llama mission_contributions.
grant usage on schema public to anon, authenticated;
grant usage on schema extensions to anon, authenticated;
grant usage on type public.app_role, public.mission_type, public.mission_status, public.assignment_status,
  public.contribution_status, public.place_visibility, public.reward_status to anon, authenticated;
grant select on public.missions, public.places to anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.account_roles, public.reward_events, public.my_reward_summary to authenticated;
grant select, insert on public.mission_assignments, public.mission_contributions to authenticated;
grant update on public.mission_contributions to authenticated;
grant insert, update, delete on public.missions, public.places to authenticated;
grant execute on function public.missions_nearby(double precision, double precision, double precision) to anon, authenticated;
grant execute on function public.check_duplicates(double precision, double precision, text, double precision) to authenticated;
grant execute on function public.has_role(public.app_role) to anon, authenticated;
grant usage on sequence public.place_code_seq to authenticated;
notify pgrst, 'reload schema';
-- Fase 3: aportes. La app necesita el radio de la misión y duplicados que incluyan aportes en revisión.

drop function if exists public.missions_nearby(double precision, double precision, double precision);
create function public.missions_nearby(lat double precision, lng double precision, radius_km double precision default 25)
returns table (
  id uuid, code text, type public.mission_type, title text, description text, commune text,
  lat double precision, lng double precision, radius_m integer, individual_reward_usd numeric, completion_bonus_usd numeric,
  required_approved_contributions integer, requirements text, end_at timestamptz, distance_m double precision
)
language sql stable set search_path = '' as $$
  select m.id, m.code, m.type, m.title, m.description, m.commune,
         extensions.st_y(m.center::extensions.geometry), extensions.st_x(m.center::extensions.geometry), m.radius_m,
         m.individual_reward_usd, m.completion_bonus_usd, m.required_approved_contributions, m.requirements, m.end_at,
         extensions.st_distance(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography)
  from public.missions m
  where m.status = 'ACTIVE'
    and (m.end_at is null or m.end_at > now())
    and extensions.st_dwithin(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography, radius_km * 1000)
  order by 15;
$$;
grant execute on function public.missions_nearby(double precision, double precision, double precision) to anon, authenticated;

-- Posibles duplicados: lugares aprobados + aportes pendientes de revisión (solo nombre y distancia, sin datos personales).
drop function if exists public.check_duplicates(double precision, double precision, text, double precision);
create function public.check_duplicates(lat double precision, lng double precision, place_name text, radius_m double precision default 60)
returns table (source text, code text, name text, category text, distance_m double precision, name_similarity real)
language sql stable security definer set search_path = '' as $$
  with pt as (select extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography as g)
  select * from (
    select 'place'::text, p.code, p.name, p.category,
           extensions.st_distance(p.location, pt.g), extensions.similarity(lower(p.name), lower(place_name))
    from public.places p, pt
    where p.visibility = 'PUBLIC' and extensions.st_dwithin(p.location, pt.g, radius_m)
    union all
    select 'pending'::text, null, c.name, c.category,
           extensions.st_distance(c.location, pt.g), extensions.similarity(lower(c.name), lower(place_name))
    from public.mission_contributions c, pt
    where c.status in ('SUBMITTED', 'AUTO_CHECKED', 'HUMAN_REVIEW')
      and extensions.st_dwithin(c.location, pt.g, radius_m)
  ) d (source, code, name, category, distance_m, name_similarity)
  order by name_similarity desc, distance_m
  limit 10;
$$;
grant execute on function public.check_duplicates(double precision, double precision, text, double precision) to authenticated;

notify pgrst, 'reload schema';
-- Moderación: aprobar/rechazar aportes, publicar el lugar y asentar recompensas (idempotente).

-- Un bono de misión se paga una sola vez por persona y misión.
create unique index if not exists reward_events_once_bonus
  on public.reward_events (user_id, mission_id) where kind = 'MISSION_BONUS';

-- Bitácora de acciones administrativas (solo inserción; nadie la edita).
create table if not exists public.admin_actions (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users (id),
  action text not null,
  subject_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.admin_actions enable row level security;
create policy "admin lee bitácora" on public.admin_actions for select using (public.has_role('admin'));
grant select on public.admin_actions to authenticated;

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
    insert into public.places (name, category, commune, department, address_reference, location, accuracy_m, source_contribution_id)
    values (c.name, c.category, m.commune, m.department, c.address_reference, c.location, c.accuracy_m, c.id)
    returning id into v_place_id;

    -- Recompensa por aporte: una sola vez gracias al índice único.
    insert into public.reward_events (user_id, contribution_id, mission_id, kind, amount_usd, status, created_by)
    values (c.user_id, c.id, m.id, 'CONTRIBUTION', m.individual_reward_usd, 'EARNED', auth.uid())
    on conflict do nothing;
    v_reward := m.individual_reward_usd;

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

-- Cola de revisión con datos que el panel necesita (solo moderadores/admin ven filas, por RLS).
create or replace view public.review_queue with (security_invoker = true) as
select c.id, c.created_at, c.status, c.name, c.category, c.address_reference, c.notes, c.accuracy_m, c.captured_at,
       c.photo_paths, c.review_reason, c.user_id, p.full_name as author_name,
       m.id as mission_id, m.code as mission_code, m.title as mission_title, m.individual_reward_usd,
       extensions.st_y(c.location::extensions.geometry) as lat, extensions.st_x(c.location::extensions.geometry) as lng,
       extensions.st_distance(c.location, m.center) as distance_to_mission_m
from public.mission_contributions c
join public.missions m on m.id = c.mission_id
left join public.profiles p on p.id = c.user_id;
grant select on public.review_queue to authenticated;

-- Vista de misiones para el panel (incluye coordenadas legibles).
create or replace view public.missions_admin with (security_invoker = true) as
select m.*, extensions.st_y(m.center::extensions.geometry) as lat, extensions.st_x(m.center::extensions.geometry) as lng,
       (select count(*) from public.mission_contributions c where c.mission_id = m.id) as contributions_count,
       (select count(*) from public.mission_contributions c where c.mission_id = m.id and c.status = 'APPROVED') as approved_count
from public.missions m;
grant select on public.missions_admin to authenticated;

-- Moderadores pueden leer perfiles de autores (ya cubierto por la política de perfiles).
notify pgrst, 'reload schema';
-- La app necesita saber si la misión exige presencia física (requires_on_site_evidence).
-- Las misiones sin presencia (p. ej. pruebas o sugerencias remotas) no comprueban el área GPS en la app.
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
    and (m.end_at is null or m.end_at > now())
    and extensions.st_dwithin(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography, radius_km * 1000)
  order by 15;
$$;
grant execute on function public.missions_nearby(double precision, double precision, double precision) to anon, authenticated;

-- Misión de PRUEBA en Delmas 33 (sin presencia física). Pausarla al terminar las pruebas.
insert into public.missions (code, type, title, description, commune, center, radius_m, required_approved_contributions,
  individual_reward_usd, completion_bonus_usd, max_participants, budget_authorized_usd, requires_on_site_evidence,
  requirements, start_at, end_at, status)
values ('MIS-DEL-TEST', 'NEW_PLACE', 'PRUEBA: comercio en Delmas 33',
  'Misión de prueba del equipo. Se puede enviar desde cualquier lugar.', 'Delmas',
  extensions.st_setsrid(extensions.st_makepoint(-72.3035, 18.5466), 4326)::extensions.geography, 600, 1,
  0.25, 0, 5, 1.25, false, 'Foto + datos del lugar (prueba sin GPS en sitio)', now(), now() + interval '14 days', 'ACTIVE')
on conflict (code) do nothing;

notify pgrst, 'reload schema';
-- Perfiles Empresa y Desarrollador (MVP).
-- Empresa: registrar organización (verificada por admin), reclamar establecimientos, solicitar campañas.
-- Desarrollador: proyectos API, claves (solo se guarda el hash), consumo diario y API pública de lugares.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Empresas
-- ---------------------------------------------------------------------------
create type public.review_status as enum ('PENDING', 'APPROVED', 'REJECTED');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_id text,
  sector text not null,
  contact_phone text,
  contact_email text,
  address text,
  commune text,
  representative_name text not null,
  status public.review_status not null default 'PENDING',
  review_reason text,
  reviewed_by uuid references auth.users (id),
  reviewed_at timestamptz,
  created_by uuid not null references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.organization_members (
  org_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  member_role text not null default 'owner' check (member_role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

create function public.is_org_member(p_org uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.organization_members where org_id = p_org and user_id = auth.uid());
$$;

create table public.place_claims (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  place_id uuid not null references public.places (id),
  evidence text,
  status public.review_status not null default 'PENDING',
  review_reason text,
  reviewed_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  unique (org_id, place_id)
);

create table public.campaign_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  title text not null,
  description text not null default '',
  commune text,
  center extensions.geography (Point, 4326) not null,
  radius_m integer not null check (radius_m between 100 and 5000),
  target_places integer not null check (target_places > 0),
  proposed_budget_usd numeric(12, 2) not null default 0 check (proposed_budget_usd >= 0),
  status public.review_status not null default 'PENDING',
  review_reason text,
  mission_id uuid references public.missions (id),
  reviewed_by uuid references auth.users (id),
  created_by uuid not null references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now()
);

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.place_claims enable row level security;
alter table public.campaign_requests enable row level security;

create policy "org: miembros y admin leen" on public.organizations for select
  using (public.is_org_member(id) or public.has_role('admin'));
create policy "org: miembros editan datos de contacto" on public.organizations for update
  using (public.is_org_member(id)) with check (public.is_org_member(id));
create policy "miembros: leer propios" on public.organization_members for select
  using (user_id = auth.uid() or public.has_role('admin'));
create policy "reclamos: empresa y admin leen" on public.place_claims for select
  using (public.is_org_member(org_id) or public.has_role('admin'));
create policy "reclamos: empresa verificada crea" on public.place_claims for insert
  with check (public.is_org_member(org_id) and status = 'PENDING'
              and exists (select 1 from public.organizations o where o.id = org_id and o.status = 'APPROVED'));
create policy "campañas: empresa y admin leen" on public.campaign_requests for select
  using (public.is_org_member(org_id) or public.has_role('admin'));
create policy "campañas: empresa verificada solicita" on public.campaign_requests for insert
  with check (public.is_org_member(org_id) and status = 'PENDING' and mission_id is null
              and exists (select 1 from public.organizations o where o.id = org_id and o.status = 'APPROVED'));

grant select on public.organizations to authenticated;
grant update (contact_phone, contact_email, address) on public.organizations to authenticated;
grant select on public.organization_members to authenticated;
grant select, insert on public.place_claims, public.campaign_requests to authenticated;
grant usage on type public.review_status to authenticated;

-- Registrar empresa: crea la organización (pendiente), al usuario como dueño y le da el rol company.
create function public.register_organization(
  p_name text, p_sector text, p_representative text, p_legal_id text default null,
  p_phone text default null, p_email text default null, p_address text default null, p_commune text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_org uuid;
begin
  if auth.uid() is null then raise exception 'Sesión requerida' using errcode = '42501'; end if;
  if coalesce(trim(p_name), '') = '' or coalesce(trim(p_representative), '') = '' then
    raise exception 'Nombre de la empresa y representante son obligatorios';
  end if;
  if (select count(*) from public.organization_members where user_id = auth.uid()) >= 3 then
    raise exception 'Límite de empresas por cuenta alcanzado';
  end if;
  insert into public.organizations (name, sector, representative_name, legal_id, contact_phone, contact_email, address, commune, created_by)
  values (trim(p_name), p_sector, trim(p_representative), p_legal_id, p_phone, p_email, p_address, p_commune, auth.uid())
  returning id into v_org;
  insert into public.organization_members (org_id, user_id, member_role) values (v_org, auth.uid(), 'owner');
  insert into public.account_roles (user_id, role) values (auth.uid(), 'company') on conflict do nothing;
  return v_org;
end;
$$;
revoke all on function public.register_organization(text, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.register_organization(text, text, text, text, text, text, text, text) to authenticated;

-- Revisiones del administrador (empresa, reclamo de establecimiento, campaña).
create function public.review_organization(p_org uuid, p_decision public.review_status, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_decision = 'REJECTED' and coalesce(trim(p_reason), '') = '' then raise exception 'Indica el motivo'; end if;
  if exists (select 1 from public.organization_members where org_id = p_org and user_id = auth.uid()) then
    raise exception 'No puedes verificar tu propia empresa' using errcode = '42501';
  end if;
  update public.organizations set status = p_decision, review_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now() where id = p_org;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'review_organization', p_org, jsonb_build_object('decision', p_decision, 'reason', p_reason));
end;
$$;

create function public.review_place_claim(p_claim uuid, p_decision public.review_status, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_decision = 'REJECTED' and coalesce(trim(p_reason), '') = '' then raise exception 'Indica el motivo'; end if;
  update public.place_claims set status = p_decision, review_reason = p_reason, reviewed_by = auth.uid() where id = p_claim;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'review_place_claim', p_claim, jsonb_build_object('decision', p_decision, 'reason', p_reason));
end;
$$;

-- Aprobar campaña: crea una misión en BORRADOR con los datos pedidos; el admin la revisa y activa después.
create function public.review_campaign(p_campaign uuid, p_decision public.review_status, p_reason text default null,
  p_reward_usd numeric default 0.25)
returns uuid language plpgsql security definer set search_path = '' as $$
declare c public.campaign_requests; v_mission uuid; v_code text;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_decision = 'REJECTED' and coalesce(trim(p_reason), '') = '' then raise exception 'Indica el motivo'; end if;
  select * into c from public.campaign_requests where id = p_campaign for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  if c.status <> 'PENDING' then raise exception 'La solicitud ya fue revisada'; end if;
  if p_decision = 'APPROVED' then
    v_code := 'CMP-' || upper(substr(replace(c.id::text, '-', ''), 1, 8));
    insert into public.missions (code, type, title, description, commune, center, radius_m, required_approved_contributions,
      individual_reward_usd, completion_bonus_usd, max_participants, budget_authorized_usd, status, created_by)
    values (v_code, 'NEW_PLACE', c.title, c.description, c.commune, c.center, c.radius_m, 1,
      p_reward_usd, 0, c.target_places, round(c.target_places * p_reward_usd, 2), 'DRAFT', auth.uid())
    returning id into v_mission;
  end if;
  update public.campaign_requests set status = p_decision, review_reason = p_reason, reviewed_by = auth.uid(), mission_id = v_mission where id = c.id;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'review_campaign', c.id, jsonb_build_object('decision', p_decision, 'reason', p_reason, 'mission_id', v_mission));
  return v_mission;
end;
$$;

revoke all on function public.review_organization(uuid, public.review_status, text) from public, anon;
revoke all on function public.review_place_claim(uuid, public.review_status, text) from public, anon;
revoke all on function public.review_campaign(uuid, public.review_status, text, numeric) from public, anon;
grant execute on function public.review_organization(uuid, public.review_status, text) to authenticated;
grant execute on function public.review_place_claim(uuid, public.review_status, text) to authenticated;
grant execute on function public.review_campaign(uuid, public.review_status, text, numeric) to authenticated;
grant execute on function public.is_org_member(uuid) to authenticated;

-- Vistas para la app y el panel (respetan RLS de quien consulta).
create view public.place_claims_view with (security_invoker = true) as
select pc.id, pc.org_id, o.name as org_name, pc.status, pc.evidence, pc.review_reason, pc.created_at,
       p.id as place_id, p.code as place_code, p.name as place_name, p.category as place_category, p.commune as place_commune
from public.place_claims pc join public.organizations o on o.id = pc.org_id join public.places p on p.id = pc.place_id;

create view public.campaign_requests_view with (security_invoker = true) as
select cr.id, cr.org_id, o.name as org_name, cr.title, cr.description, cr.commune, cr.radius_m, cr.target_places,
       cr.proposed_budget_usd, cr.status, cr.review_reason, cr.mission_id, cr.created_at,
       extensions.st_y(cr.center::extensions.geometry) as lat, extensions.st_x(cr.center::extensions.geometry) as lng,
       m.code as mission_code, m.status as mission_status,
       (select count(*) from public.mission_contributions mc where mc.mission_id = cr.mission_id and mc.status = 'APPROVED') as approved_places
from public.campaign_requests cr join public.organizations o on o.id = cr.org_id left join public.missions m on m.id = cr.mission_id;

grant select on public.place_claims_view, public.campaign_requests_view to authenticated;

-- ---------------------------------------------------------------------------
-- Desarrolladores
-- ---------------------------------------------------------------------------
create table public.api_projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) default auth.uid(),
  name text not null,
  environment text not null default 'test' check (environment in ('test', 'production')),
  intended_use text not null,
  daily_quota integer not null default 1000 check (daily_quota > 0),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'SUSPENDED')),
  terms_version text not null,
  created_at timestamptz not null default now()
);

create table public.developer_api_keys (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.api_projects (id) on delete cascade,
  prefix text not null unique,
  secret_hash text not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  last_used_at timestamptz
);

create table public.api_usage (
  project_id uuid not null references public.api_projects (id) on delete cascade,
  day date not null,
  requests integer not null default 0,
  errors integer not null default 0,
  primary key (project_id, day)
);

alter table public.api_projects enable row level security;
alter table public.developer_api_keys enable row level security;
alter table public.api_usage enable row level security;

create policy "proyectos: dueño y admin leen" on public.api_projects for select using (owner_id = auth.uid() or public.has_role('admin'));
create policy "claves: dueño y admin leen" on public.developer_api_keys for select
  using (exists (select 1 from public.api_projects p where p.id = project_id and (p.owner_id = auth.uid() or public.has_role('admin'))));
create policy "consumo: dueño y admin leen" on public.api_usage for select
  using (exists (select 1 from public.api_projects p where p.id = project_id and (p.owner_id = auth.uid() or public.has_role('admin'))));
-- Sin políticas de escritura directa: todo pasa por funciones del servidor.
grant select on public.api_projects, public.api_usage to authenticated;
grant select (id, project_id, prefix, created_at, revoked_at, last_used_at) on public.developer_api_keys to authenticated;

create function public.create_api_project(p_name text, p_intended_use text, p_accept_terms boolean, p_environment text default 'test')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sesión requerida' using errcode = '42501'; end if;
  if not p_accept_terms then raise exception 'Debes aceptar los términos de la API'; end if;
  if (select count(*) from public.api_projects where owner_id = auth.uid()) >= 5 then raise exception 'Máximo 5 proyectos por cuenta'; end if;
  insert into public.api_projects (owner_id, name, intended_use, environment, terms_version)
  values (auth.uid(), trim(p_name), trim(p_intended_use), p_environment, 'api-terms-2026-11') returning id into v_id;
  insert into public.account_roles (user_id, role) values (auth.uid(), 'developer') on conflict do nothing;
  return v_id;
end;
$$;

-- Genera una clave: devuelve el secreto UNA sola vez; en la base solo queda su hash SHA-256.
create function public.create_api_key(p_project uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_prefix text; v_secret text;
begin
  if not exists (select 1 from public.api_projects where id = p_project and owner_id = auth.uid() and status = 'ACTIVE') then
    raise exception 'Proyecto no encontrado' using errcode = '42501';
  end if;
  if (select count(*) from public.developer_api_keys where project_id = p_project and revoked_at is null) >= 3 then
    raise exception 'Máximo 3 claves activas por proyecto; revoca una antes';
  end if;
  v_prefix := 'htk_' || encode(extensions.gen_random_bytes(4), 'hex');
  v_secret := v_prefix || '_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.developer_api_keys (project_id, prefix, secret_hash) values (p_project, v_prefix, encode(extensions.digest(v_secret, 'sha256'), 'hex'));
  return v_secret;
end;
$$;

create function public.revoke_api_key(p_key uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.developer_api_keys k set revoked_at = now()
   where k.id = p_key and k.revoked_at is null
     and exists (select 1 from public.api_projects p where p.id = k.project_id and p.owner_id = auth.uid());
  if not found then raise exception 'Clave no encontrada' using errcode = '42501'; end if;
end;
$$;

-- API pública de lugares: la llama el backend del desarrollador con su clave secreta.
-- Solo devuelve lugares PUBLIC; aplica cuota diaria y registra el consumo.
create function public.api_places_nearby(p_api_key text, p_lat double precision, p_lng double precision,
  p_radius_m double precision default 1000, p_limit integer default 50)
returns table (code text, name text, category text, commune text, lat double precision, lng double precision, distance_m double precision)
language plpgsql security definer set search_path = '' as $$
declare k public.developer_api_keys; pr public.api_projects; used integer;
begin
  select * into k from public.developer_api_keys
   where prefix = split_part(p_api_key, '_', 1) || '_' || split_part(p_api_key, '_', 2)
     and secret_hash = encode(extensions.digest(p_api_key, 'sha256'), 'hex') and revoked_at is null;
  if not found then raise exception 'Clave API inválida o revocada' using errcode = '28000'; end if;
  select * into pr from public.api_projects where id = k.project_id;
  if pr.status <> 'ACTIVE' then raise exception 'Proyecto suspendido' using errcode = '42501'; end if;

  insert into public.api_usage (project_id, day, requests) values (pr.id, current_date, 1)
  on conflict (project_id, day) do update set requests = public.api_usage.requests + 1
  returning requests into used;
  if used > pr.daily_quota then raise exception 'Cuota diaria superada (% solicitudes)', pr.daily_quota using errcode = '53400'; end if;
  update public.developer_api_keys set last_used_at = now() where id = k.id;

  return query
  select p.code, p.name, p.category, p.commune,
         extensions.st_y(p.location::extensions.geometry), extensions.st_x(p.location::extensions.geometry),
         extensions.st_distance(p.location, extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography)
  from public.places p
  where p.visibility = 'PUBLIC'
    and extensions.st_dwithin(p.location, extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography, least(p_radius_m, 10000))
  order by 7
  limit least(greatest(p_limit, 1), 200);
end;
$$;

revoke all on function public.create_api_project(text, text, boolean, text) from public, anon;
revoke all on function public.create_api_key(uuid) from public, anon;
revoke all on function public.revoke_api_key(uuid) from public, anon;
grant execute on function public.create_api_project(text, text, boolean, text) to authenticated;
grant execute on function public.create_api_key(uuid) to authenticated;
grant execute on function public.revoke_api_key(uuid) to authenticated;
grant execute on function public.api_places_nearby(text, double precision, double precision, double precision, integer) to anon, authenticated;

notify pgrst, 'reload schema';
-- Datos de demostración (inventados). Solo para entornos de desarrollo.
insert into public.missions (code, type, title, description, commune, center, radius_m, required_approved_contributions,
  individual_reward_usd, completion_bonus_usd, max_participants, budget_authorized_usd, requirements, start_at, end_at, status)
values
  ('MIS-DEL-0001', 'BATCH_ZONE', 'Documentar cinco comercios públicos', 'Registra cinco comercios abiertos al público que no estén en el mapa.', 'Delmas',
   extensions.st_setsrid(extensions.st_makepoint(-72.2973, 18.5401), 4326)::extensions.geography, 800, 5, 0.25, 1.00, 30, 75.00,
   'GPS + foto + datos del lugar', now(), now() + interval '30 days', 'ACTIVE'),
  ('MIS-DEL-0002', 'NEW_PLACE', 'Registrar comercio faltante', 'Un comercio público que aún no aparece en el catálogo.', 'Delmas',
   extensions.st_setsrid(extensions.st_makepoint(-72.3050, 18.5470), 4326)::extensions.geography, 500, 1, 0.25, 0, 100, 25.00,
   'GPS + foto + datos del lugar', now(), now() + interval '30 days', 'ACTIVE'),
  ('MIS-PAP-0001', 'PRIORITY_PLACE', 'Zona prioritaria: centro de Port-au-Prince', 'Lugares públicos dentro de la zona prioritaria.', 'Port-au-Prince',
   extensions.st_setsrid(extensions.st_makepoint(-72.3388, 18.5425), 4326)::extensions.geography, 600, 1, 0.50, 0, 50, 25.00,
   'GPS + foto + datos del lugar', now(), now() + interval '30 days', 'ACTIVE'),
  ('MIS-PTV-0001', 'NEW_PLACE', 'Farmacias de Pétion-Ville', 'Registra farmacias abiertas al público.', 'Pétion-Ville',
   extensions.st_setsrid(extensions.st_makepoint(-72.2852, 18.5125), 4326)::extensions.geography, 700, 1, 0.25, 0, 50, 12.50,
   'GPS + foto + datos del lugar', now(), now() + interval '30 days', 'ACTIVE');


-- Registro por teléfono (SMS) con datos de perfil y solicitudes de retiro MonCash.
-- Los retiros se registran para pago MANUAL por el equipo; el interruptor
-- platform_settings.withdrawals.enabled empieza en false hasta tener la aprobación de MonCash.

-- ---------------------------------------------------------------------------
-- Perfil: datos del registro
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists first_name text,
  add column if not exists last_name text,
  add column if not exists collaborator_type text,
  add column if not exists terms_accepted_at timestamptz;

-- Al registrarse: copiar nombre y teléfono (auth guarda el teléfono sin "+").
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, first_name, last_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'first_name',
    new.raw_user_meta_data ->> 'last_name',
    case when coalesce(new.phone, '') = '' then null
         when new.phone like '+%' then new.phone
         else '+' || new.phone end
  );
  insert into public.account_roles (user_id, role) values (new.id, 'collaborator');
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Ajustes de la plataforma (lectura para usuarios, escritura solo admin)
-- ---------------------------------------------------------------------------
create table if not exists public.platform_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.platform_settings enable row level security;
create policy "ajustes: leer" on public.platform_settings for select to authenticated using (true);
create policy "ajustes: admin" on public.platform_settings for all using (public.has_role('admin')) with check (public.has_role('admin'));

insert into public.platform_settings (key, value)
values ('withdrawals', '{"enabled": false, "min_usd": 5, "max_usd": 50}')
on conflict (key) do nothing;

grant select on public.platform_settings to authenticated;
grant insert, update on public.platform_settings to authenticated; -- filtrado por la política de admin

-- ---------------------------------------------------------------------------
-- Solicitudes de retiro
-- ---------------------------------------------------------------------------
create sequence if not exists public.withdrawal_code_seq start 1001;

create table public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default ('HT-' || nextval('public.withdrawal_code_seq')::text),
  user_id uuid not null references auth.users (id),
  amount_usd numeric(10, 2) not null check (amount_usd > 0),
  method text not null default 'MONCASH' check (method in ('MONCASH')),
  moncash_phone text not null,
  status text not null default 'REQUESTED' check (status in ('REQUESTED', 'PROCESSING', 'COMPLETED', 'REJECTED')),
  fee_usd numeric(10, 2),
  htg_rate numeric(12, 4),
  reference text,
  rejection_reason text,
  idempotency_key uuid not null unique,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid references auth.users (id),
  check (processed_by is null or processed_by <> user_id)
);
create index withdrawal_requests_user_idx on public.withdrawal_requests (user_id, created_at desc);

alter table public.withdrawal_requests enable row level security;
create policy "retiros propios: leer" on public.withdrawal_requests for select
  using (user_id = auth.uid() or public.has_role('admin'));
-- Los usuarios solo crean retiros con request_withdrawal(); el admin los procesa.
create policy "admin procesa retiros" on public.withdrawal_requests for update
  using (public.has_role('admin')) with check (public.has_role('admin') and processed_by = auth.uid());

grant select on public.withdrawal_requests to authenticated;
grant update (status, fee_usd, htg_rate, reference, rejection_reason, processed_at, processed_by)
  on public.withdrawal_requests to authenticated;

-- Saldo retirable = recompensas disponibles − retiros no rechazados.
create or replace function public.withdrawable_usd(p_user uuid) returns numeric
language sql stable security definer set search_path = '' as $$
  select coalesce((select sum(amount_usd) from public.reward_events where user_id = p_user and status = 'AVAILABLE'), 0)
       - coalesce((select sum(amount_usd) from public.withdrawal_requests where user_id = p_user and status <> 'REJECTED'), 0);
$$;
revoke all on function public.withdrawable_usd(uuid) from public, anon, authenticated;

create or replace function public.my_withdrawable_usd() returns numeric
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then 0 else public.withdrawable_usd(auth.uid()) end;
$$;
revoke all on function public.my_withdrawable_usd() from public, anon;
grant execute on function public.my_withdrawable_usd() to authenticated;

-- Crea una solicitud de retiro al número MonCash verificado por SMS. Idempotente por p_idempotency_key.
create or replace function public.request_withdrawal(p_amount numeric, p_idempotency_key uuid)
returns public.withdrawal_requests
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_cfg jsonb;
  v_phone text;
  v_row public.withdrawal_requests;
begin
  if v_uid is null then
    raise exception 'Sesión no iniciada';
  end if;

  select * into v_row from public.withdrawal_requests where idempotency_key = p_idempotency_key and user_id = v_uid;
  if found then
    return v_row;
  end if;

  select value into v_cfg from public.platform_settings where key = 'withdrawals';
  if coalesce((v_cfg ->> 'enabled')::boolean, false) is not true then
    raise exception 'Los retiros todavía no están habilitados';
  end if;

  if p_amount is null or p_amount <> round(p_amount, 2) then
    raise exception 'Monto no válido';
  end if;
  if p_amount < (v_cfg ->> 'min_usd')::numeric or p_amount > (v_cfg ->> 'max_usd')::numeric then
    raise exception 'El monto debe estar entre % y % USD', v_cfg ->> 'min_usd', v_cfg ->> 'max_usd';
  end if;

  select phone into v_phone from auth.users where id = v_uid and phone_confirmed_at is not null;
  if coalesce(v_phone, '') = '' then
    raise exception 'Verifica tu número MonCash antes de retirar';
  end if;

  -- Un retiro a la vez por usuario: evita gastar el mismo saldo dos veces.
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  if public.withdrawable_usd(v_uid) < p_amount then
    raise exception 'Saldo disponible insuficiente';
  end if;

  insert into public.withdrawal_requests (user_id, amount_usd, moncash_phone, idempotency_key)
  values (v_uid, p_amount, case when v_phone like '+%' then v_phone else '+' || v_phone end, p_idempotency_key)
  returning * into v_row;
  return v_row;
end;
$$;
revoke all on function public.request_withdrawal(numeric, uuid) from public, anon;
grant execute on function public.request_withdrawal(numeric, uuid) to authenticated;

notify pgrst, 'reload schema';

-- ===== 20261126000002_verificacion_moncash.sql =====
-- Verificación del número MonCash separada del registro.
-- El registro ya no exige el código SMS (Supabase puede autoconfirmar el teléfono al crear la cuenta),
-- así que phone_confirmed_at deja de probar que la persona controla el número.
-- La prueba real es una sesión abierta con un código SMS (amr = 'otp'); solo entonces se guarda aquí.

create table if not exists public.moncash_verifications (
  user_id uuid primary key references auth.users (id) on delete cascade,
  phone text not null,
  verified_at timestamptz not null default now()
);

alter table public.moncash_verifications enable row level security;

drop policy if exists "ve su verificacion moncash" on public.moncash_verifications;
create policy "ve su verificacion moncash" on public.moncash_verifications
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "admin ve verificaciones moncash" on public.moncash_verifications;
create policy "admin ve verificaciones moncash" on public.moncash_verifications
  for select to authenticated using (public.has_role('admin'::public.app_role));

revoke insert, update, delete on public.moncash_verifications from anon, authenticated;

-- Se llama justo después de verificar el código SMS en la app.
create or replace function public.confirm_moncash_phone()
returns public.moncash_verifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_sid uuid;
  v_phone text;
  v_row public.moncash_verifications;
begin
  if v_uid is null then
    raise exception 'Sesión no iniciada';
  end if;

  v_sid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  if v_sid is null or not exists (
    select 1
    from auth.mfa_amr_claims c
    join auth.sessions s on s.id = c.session_id
    where c.session_id = v_sid
      and s.user_id = v_uid
      and c.authentication_method = 'otp'
      and greatest(c.created_at, c.updated_at) > now() - interval '15 minutes'
  ) then
    raise exception 'Primero confirma el código SMS';
  end if;

  select phone into v_phone from auth.users where id = v_uid and phone_confirmed_at is not null;
  if coalesce(v_phone, '') = '' then
    raise exception 'No hay un número confirmado en la cuenta';
  end if;
  v_phone := case when v_phone like '+%' then v_phone else '+' || v_phone end;

  insert into public.moncash_verifications (user_id, phone, verified_at)
  values (v_uid, v_phone, now())
  on conflict (user_id) do update set phone = excluded.phone, verified_at = excluded.verified_at
  returning * into v_row;

  update public.profiles set phone = v_phone where id = v_uid;
  return v_row;
end;
$$;

revoke all on function public.confirm_moncash_phone() from public, anon;
grant execute on function public.confirm_moncash_phone() to authenticated;

-- El retiro solo va al número verificado por SMS, y solo si sigue siendo el número de la cuenta.
create or replace function public.request_withdrawal(p_amount numeric, p_idempotency_key uuid)
returns public.withdrawal_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_cfg jsonb;
  v_phone text;
  v_row public.withdrawal_requests;
begin
  if v_uid is null then
    raise exception 'Sesión no iniciada';
  end if;

  select * into v_row from public.withdrawal_requests where idempotency_key = p_idempotency_key and user_id = v_uid;
  if found then
    return v_row;
  end if;

  select value into v_cfg from public.platform_settings where key = 'withdrawals';
  if coalesce((v_cfg ->> 'enabled')::boolean, false) is not true then
    raise exception 'Los retiros todavía no están habilitados';
  end if;

  if p_amount is null or p_amount <> round(p_amount, 2) then
    raise exception 'Monto no válido';
  end if;
  if p_amount < (v_cfg ->> 'min_usd')::numeric or p_amount > (v_cfg ->> 'max_usd')::numeric then
    raise exception 'El monto debe estar entre % y % USD', v_cfg ->> 'min_usd', v_cfg ->> 'max_usd';
  end if;

  select v.phone into v_phone
  from public.moncash_verifications v
  join auth.users u on u.id = v.user_id
  where v.user_id = v_uid
    and u.phone_confirmed_at is not null
    and v.phone = case when u.phone like '+%' then u.phone else '+' || u.phone end;
  if coalesce(v_phone, '') = '' then
    raise exception 'Verifica tu número MonCash antes de retirar';
  end if;

  -- Un retiro a la vez por usuario: evita gastar el mismo saldo dos veces.
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  if public.withdrawable_usd(v_uid) < p_amount then
    raise exception 'Saldo disponible insuficiente';
  end if;

  insert into public.withdrawal_requests (user_id, amount_usd, moncash_phone, idempotency_key)
  values (v_uid, p_amount, v_phone, p_idempotency_key)
  returning * into v_row;
  return v_row;
end;
$$;

-- ===== 20261126100000_panel_admin.sql =====
-- Panel administrativo web (módulos 34–50): lo que el panel necesita en la base de datos.
-- Restricciones de usuarios, gestión de roles, liberación de recompensas, procesamiento de retiros
-- MonCash, señales de fraude/duplicados, presupuestos, soporte, auditoría y tablero.
-- Todo lo que cambia dinero o permisos pasa por funciones security definer que comprueban el rol
-- y dejan constancia en admin_actions.

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- Auxiliar: ¿es admin o moderador?
-- ---------------------------------------------------------------------------
create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.has_role('admin'::public.app_role) or public.has_role('moderator'::public.app_role);
$$;
grant execute on function public.is_staff() to authenticated;

-- ---------------------------------------------------------------------------
-- Restricciones de usuarios (41)
-- Tabla aparte para que el usuario no pueda quitársela editando su perfil.
-- ---------------------------------------------------------------------------
create table if not exists public.user_restrictions (
  user_id uuid primary key references auth.users (id) on delete cascade,
  reason text not null,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);
alter table public.user_restrictions enable row level security;
drop policy if exists "restricción: propia o staff" on public.user_restrictions;
create policy "restricción: propia o staff" on public.user_restrictions for select to authenticated
  using (user_id = (select auth.uid()) or public.is_staff());
grant select on public.user_restrictions to authenticated;

create or replace function public.is_restricted(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_restrictions where user_id = p_user);
$$;
revoke all on function public.is_restricted(uuid) from public, anon;
grant execute on function public.is_restricted(uuid) to authenticated;

-- Un usuario restringido no envía aportes ni pide retiros.
create or replace function public.block_restricted_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if public.is_restricted(new.user_id) then
    raise exception 'Tu cuenta está restringida. Contacta con soporte.' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists block_restricted_contribution on public.mission_contributions;
create trigger block_restricted_contribution before insert on public.mission_contributions
  for each row execute function public.block_restricted_user();
drop trigger if exists block_restricted_withdrawal on public.withdrawal_requests;
create trigger block_restricted_withdrawal before insert on public.withdrawal_requests
  for each row execute function public.block_restricted_user();

create or replace function public.admin_set_restriction(p_user uuid, p_restricted boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_user = auth.uid() then raise exception 'No puedes restringir tu propia cuenta'; end if;
  if p_restricted then
    if coalesce(trim(p_reason), '') = '' then raise exception 'Indica el motivo de la restricción'; end if;
    insert into public.user_restrictions (user_id, reason, created_by) values (p_user, trim(p_reason), auth.uid())
    on conflict (user_id) do update set reason = excluded.reason, created_by = excluded.created_by, created_at = now();
  else
    delete from public.user_restrictions where user_id = p_user;
  end if;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), case when p_restricted then 'restrict_user' else 'unrestrict_user' end, p_user,
          jsonb_build_object('reason', p_reason));
end;
$$;
revoke all on function public.admin_set_restriction(uuid, boolean, text) from public, anon;
grant execute on function public.admin_set_restriction(uuid, boolean, text) to authenticated;

-- Roles (49): conceder o retirar roles. Nadie se quita a sí mismo el rol de admin.
create or replace function public.admin_set_role(p_user uuid, p_role public.app_role, p_grant boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_user = auth.uid() and p_role = 'admin' and not p_grant then
    raise exception 'No puedes quitarte tu propio rol de administrador';
  end if;
  if p_grant then
    insert into public.account_roles (user_id, role) values (p_user, p_role) on conflict do nothing;
  else
    delete from public.account_roles where user_id = p_user and role = p_role;
  end if;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), case when p_grant then 'grant_role' else 'revoke_role' end, p_user, jsonb_build_object('role', p_role));
end;
$$;
revoke all on function public.admin_set_role(uuid, public.app_role, boolean) from public, anon;
grant execute on function public.admin_set_role(uuid, public.app_role, boolean) to authenticated;

-- Listado de usuarios con reputación y saldos (solo staff). Lee correo/teléfono de auth.users.
create or replace function public.admin_users()
returns table (
  id uuid, full_name text, email text, phone text, department text, commune text, created_at timestamptz,
  last_sign_in_at timestamptz, roles text[], restricted boolean, restriction_reason text, moncash_phone text,
  contributions integer, approved integer, rejected integer, needs_changes integer, pending integer,
  earned_usd numeric, available_usd numeric, withdrawn_usd numeric
)
language sql stable security definer set search_path = '' as $$
  select u.id,
         coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))),
         u.email::text, coalesce(p.phone, case when coalesce(u.phone, '') = '' then null else '+' || u.phone end),
         p.department, p.commune, u.created_at, u.last_sign_in_at,
         coalesce((select array_agg(r.role::text order by r.role) from public.account_roles r where r.user_id = u.id), '{}'),
         r.user_id is not null, r.reason, mv.phone,
         coalesce(c.total, 0)::int, coalesce(c.approved, 0)::int, coalesce(c.rejected, 0)::int,
         coalesce(c.needs_changes, 0)::int, coalesce(c.pending, 0)::int,
         coalesce(e.earned, 0), coalesce(e.available, 0), coalesce(w.withdrawn, 0)
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.user_restrictions r on r.user_id = u.id
  left join public.moncash_verifications mv on mv.user_id = u.id
  left join lateral (
    select count(*) as total,
           count(*) filter (where status = 'APPROVED') as approved,
           count(*) filter (where status = 'REJECTED') as rejected,
           count(*) filter (where status = 'NEEDS_CHANGES') as needs_changes,
           count(*) filter (where status in ('SUBMITTED', 'AUTO_CHECKED', 'HUMAN_REVIEW')) as pending
    from public.mission_contributions where user_id = u.id
  ) c on true
  left join lateral (
    select sum(amount_usd) filter (where status in ('EARNED', 'AVAILABLE', 'WITHDRAWAL_REQUESTED', 'PAID')) as earned,
           sum(amount_usd) filter (where status = 'AVAILABLE') as available
    from public.reward_events where user_id = u.id
  ) e on true
  left join lateral (
    select sum(amount_usd) filter (where status = 'COMPLETED') as withdrawn
    from public.withdrawal_requests where user_id = u.id
  ) w on true
  where public.is_staff()
  order by u.created_at desc;
$$;
revoke all on function public.admin_users() from public, anon;
grant execute on function public.admin_users() to authenticated;

-- ---------------------------------------------------------------------------
-- Recompensas (44): las recompensas nacen EARNED; el admin las libera a AVAILABLE
-- (saldo retirable) tras el periodo de retención configurado.
-- ---------------------------------------------------------------------------
insert into public.platform_settings (key, value) values
  ('rewards', '{"hold_days": 3, "defaults": {"NEW_PLACE": 0.25, "PRIORITY_PLACE": 0.50, "MAJOR_CORRECTION": 0.10, "INDEPENDENT_CHECK": 0.05, "BATCH_ZONE": 0.25}, "batch_bonus_usd": 1.00}'),
  ('general', '{"support_email": "", "support_phone": "", "languages": ["ht", "fr", "es", "en"], "default_language": "ht", "terms_url": "", "privacy_url": ""}'),
  ('plans', '{"company": [{"name": "Básico", "price_usd": 0, "features": "Ficha del establecimiento"}], "developer": [{"name": "Gratis", "price_usd": 0, "daily_quota": 1000}]}')
on conflict (key) do nothing;

create or replace function public.admin_release_rewards(p_user uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_days int; v_count int; v_sum numeric;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  select coalesce((value ->> 'hold_days')::int, 0) into v_days from public.platform_settings where key = 'rewards';
  with upd as (
    update public.reward_events e set status = 'AVAILABLE'
     where e.status = 'EARNED'
       and (p_user is null or e.user_id = p_user)
       and e.created_at <= now() - make_interval(days => coalesce(v_days, 0))
       and not public.is_restricted(e.user_id)
    returning e.amount_usd
  )
  select count(*), coalesce(sum(amount_usd), 0) into v_count, v_sum from upd;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'release_rewards', p_user, jsonb_build_object('count', v_count, 'amount_usd', v_sum, 'hold_days', v_days));
  return jsonb_build_object('count', v_count, 'amount_usd', v_sum);
end;
$$;
revoke all on function public.admin_release_rewards(uuid) from public, anon;
grant execute on function public.admin_release_rewards(uuid) to authenticated;

-- Ajuste manual (bonificación o corrección negativa): nuevo asiento, nunca se edita uno existente.
create or replace function public.admin_adjust_reward(p_user uuid, p_amount numeric, p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_user = auth.uid() then raise exception 'No puedes ajustar tu propio saldo'; end if;
  if p_amount is null or p_amount = 0 or p_amount <> round(p_amount, 2) or abs(p_amount) > 100 then
    raise exception 'Monto no válido (máx. 100 USD, 2 decimales)';
  end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Indica el motivo del ajuste'; end if;
  insert into public.reward_events (user_id, kind, amount_usd, status, reason, created_by)
  values (p_user, 'ADJUSTMENT', p_amount, 'EARNED', trim(p_reason), auth.uid())
  returning id into v_id;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'adjust_reward', p_user, jsonb_build_object('amount_usd', p_amount, 'reason', p_reason));
  return v_id;
end;
$$;
revoke all on function public.admin_adjust_reward(uuid, numeric, text) from public, anon;
grant execute on function public.admin_adjust_reward(uuid, numeric, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Retiros MonCash (46): REQUESTED → PROCESSING → COMPLETED, o REJECTED con motivo.
-- ---------------------------------------------------------------------------
create or replace function public.admin_process_withdrawal(
  p_id uuid, p_status text, p_reference text default null, p_reason text default null,
  p_htg_rate numeric default null, p_fee_usd numeric default null)
returns public.withdrawal_requests language plpgsql security definer set search_path = '' as $$
declare w public.withdrawal_requests;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  select * into w from public.withdrawal_requests where id = p_id for update;
  if not found then raise exception 'Retiro no encontrado'; end if;
  if w.user_id = auth.uid() then raise exception 'No puedes procesar tu propio retiro' using errcode = '42501'; end if;

  if p_status = 'PROCESSING' and w.status <> 'REQUESTED' then
    raise exception 'Solo se autorizan retiros en estado REQUESTED';
  elsif p_status = 'COMPLETED' and w.status not in ('REQUESTED', 'PROCESSING') then
    raise exception 'Este retiro ya está cerrado';
  elsif p_status = 'REJECTED' and w.status not in ('REQUESTED', 'PROCESSING') then
    raise exception 'Este retiro ya está cerrado';
  elsif p_status not in ('PROCESSING', 'COMPLETED', 'REJECTED') then
    raise exception 'Estado no válido';
  end if;
  if p_status = 'COMPLETED' and coalesce(trim(p_reference), '') = '' then
    raise exception 'Indica la referencia de la transacción MonCash';
  end if;
  if p_status = 'REJECTED' and coalesce(trim(p_reason), '') = '' then
    raise exception 'Indica el motivo del rechazo';
  end if;

  update public.withdrawal_requests
     set status = p_status,
         reference = coalesce(nullif(trim(p_reference), ''), reference),
         rejection_reason = case when p_status = 'REJECTED' then trim(p_reason) else rejection_reason end,
         htg_rate = coalesce(p_htg_rate, htg_rate),
         fee_usd = coalesce(p_fee_usd, fee_usd),
         processed_at = now(),
         processed_by = auth.uid()
   where id = p_id
  returning * into w;

  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'process_withdrawal', p_id,
          jsonb_build_object('code', w.code, 'status', p_status, 'amount_usd', w.amount_usd, 'reference', p_reference, 'reason', p_reason));
  return w;
end;
$$;
revoke all on function public.admin_process_withdrawal(uuid, text, text, text, numeric, numeric) from public, anon;
grant execute on function public.admin_process_withdrawal(uuid, text, text, text, numeric, numeric) to authenticated;

create or replace view public.withdrawals_admin with (security_invoker = true) as
select w.*, coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as full_name,
       mv.phone as verified_phone, mv.verified_at as phone_verified_at,
       (mv.phone is not null and mv.phone = w.moncash_phone) as phone_matches
from public.withdrawal_requests w
left join public.profiles p on p.id = w.user_id
left join public.moncash_verifications mv on mv.user_id = w.user_id;
grant select on public.withdrawals_admin to authenticated;

-- ---------------------------------------------------------------------------
-- Duplicados y fraude (40): señales por aporte. Solo staff ve filas (RLS de los aportes).
-- ---------------------------------------------------------------------------
create or replace view public.contribution_flags with (security_invoker = true) as
select c.id, c.created_at, c.status, c.name, c.category, c.user_id, c.accuracy_m, c.notes,
       coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as author_name,
       m.code as mission_code, m.radius_m, m.requires_on_site_evidence,
       extensions.st_y(c.location::extensions.geometry) as lat, extensions.st_x(c.location::extensions.geometry) as lng,
       extensions.st_distance(c.location, m.center) as distance_to_mission_m,
       (select count(*) from public.places pl
         where pl.id is distinct from c.place_id
           and extensions.st_dwithin(pl.location, c.location, 60)
           and extensions.similarity(lower(pl.name), lower(c.name)) >= 0.4)::int as near_places,
       (select count(*) from public.mission_contributions o
         where o.id <> c.id and o.status not in ('REJECTED', 'DRAFT')
           and extensions.st_dwithin(o.location, c.location, 60)
           and extensions.similarity(lower(o.name), lower(c.name)) >= 0.4)::int as near_contributions,
       (select count(*) from public.mission_contributions o
         where o.user_id = c.user_id and o.created_at between c.created_at - interval '1 hour' and c.created_at)::int as user_last_hour,
       coalesce(c.notes ilike '%ubicación simulada%', false) as mocked_location,
       coalesce(c.accuracy_m, 999) > 30 as low_accuracy,
       (m.requires_on_site_evidence and m.radius_m is not null and extensions.st_distance(c.location, m.center) > m.radius_m) as outside_area,
       cardinality(c.photo_paths) = 0 as no_photo
from public.mission_contributions c
join public.missions m on m.id = c.mission_id
left join public.profiles p on p.id = c.user_id;
grant select on public.contribution_flags to authenticated;

-- ---------------------------------------------------------------------------
-- Presupuestos de misiones (45)
-- ---------------------------------------------------------------------------
create or replace view public.mission_budgets with (security_invoker = true) as
select m.id, m.code, m.title, m.status, m.budget_authorized_usd, m.individual_reward_usd, m.completion_bonus_usd,
       coalesce((select sum(e.amount_usd) from public.reward_events e where e.mission_id = m.id and e.status <> 'REVERSED'), 0) as committed_usd,
       coalesce((select sum(e.amount_usd) from public.reward_events e where e.mission_id = m.id and e.status = 'PAID'), 0) as paid_usd,
       (select count(*) from public.mission_contributions c
         where c.mission_id = m.id and c.status in ('SUBMITTED', 'AUTO_CHECKED', 'HUMAN_REVIEW'))::int * m.individual_reward_usd as pending_exposure_usd
from public.missions m;
grant select on public.mission_budgets to authenticated;

-- ---------------------------------------------------------------------------
-- Soporte y reclamaciones (48)
-- ---------------------------------------------------------------------------
create sequence if not exists public.support_ticket_seq start 1001;
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default ('SOP-' || nextval('public.support_ticket_seq')::text),
  user_id uuid not null references auth.users (id) default auth.uid(),
  category text not null default 'GENERAL' check (category in ('GENERAL', 'CONTRIBUTION', 'REWARD', 'WITHDRAWAL', 'ACCOUNT', 'COMPANY', 'API', 'COMPLAINT')),
  subject text not null check (length(subject) between 3 and 200),
  message text not null check (length(message) between 3 and 5000),
  related_id uuid,
  status text not null default 'OPEN' check (status in ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')),
  priority text not null default 'NORMAL' check (priority in ('LOW', 'NORMAL', 'HIGH')),
  admin_reply text,
  handled_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists support_tickets_status_idx on public.support_tickets (status, created_at desc);
create index if not exists support_tickets_user_idx on public.support_tickets (user_id, created_at desc);
alter table public.support_tickets enable row level security;
drop policy if exists "soporte: propio o staff lee" on public.support_tickets;
create policy "soporte: propio o staff lee" on public.support_tickets for select to authenticated
  using (user_id = (select auth.uid()) or public.is_staff());
drop policy if exists "soporte: usuario crea" on public.support_tickets;
create policy "soporte: usuario crea" on public.support_tickets for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'OPEN' and admin_reply is null and handled_by is null);
grant select, insert on public.support_tickets to authenticated;

create or replace function public.admin_answer_ticket(p_id uuid, p_status text, p_reply text default null, p_priority text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_staff() then raise exception 'Solo el equipo' using errcode = '42501'; end if;
  if p_status not in ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED') then raise exception 'Estado no válido'; end if;
  update public.support_tickets
     set status = p_status, admin_reply = coalesce(nullif(trim(p_reply), ''), admin_reply),
         priority = coalesce(p_priority, priority), handled_by = auth.uid(), updated_at = now()
   where id = p_id;
  if not found then raise exception 'Caso no encontrado'; end if;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'answer_ticket', p_id, jsonb_build_object('status', p_status, 'reply', p_reply));
end;
$$;
revoke all on function public.admin_answer_ticket(uuid, text, text, text) from public, anon;
grant execute on function public.admin_answer_ticket(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Desarrolladores (43): suspender/reactivar proyectos y cambiar cuota.
-- ---------------------------------------------------------------------------
create or replace function public.admin_update_api_project(p_project uuid, p_status text, p_daily_quota integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_status not in ('ACTIVE', 'SUSPENDED') then raise exception 'Estado no válido'; end if;
  if p_daily_quota is null or p_daily_quota < 1 then raise exception 'Cuota no válida'; end if;
  update public.api_projects set status = p_status, daily_quota = p_daily_quota where id = p_project;
  if not found then raise exception 'Proyecto no encontrado'; end if;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'update_api_project', p_project, jsonb_build_object('status', p_status, 'daily_quota', p_daily_quota));
end;
$$;
revoke all on function public.admin_update_api_project(uuid, text, integer) from public, anon;
grant execute on function public.admin_update_api_project(uuid, text, integer) to authenticated;

create or replace view public.api_projects_admin with (security_invoker = true) as
select pr.*, coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as owner_name,
       (select count(*) from public.developer_api_keys k where k.project_id = pr.id and k.revoked_at is null)::int as active_keys,
       (select max(k.last_used_at) from public.developer_api_keys k where k.project_id = pr.id) as last_used_at,
       coalesce((select sum(u.requests) from public.api_usage u where u.project_id = pr.id and u.day > current_date - 30), 0)::int as requests_30d,
       coalesce((select sum(u.errors) from public.api_usage u where u.project_id = pr.id and u.day > current_date - 30), 0)::int as errors_30d,
       coalesce((select u.requests from public.api_usage u where u.project_id = pr.id and u.day = current_date), 0)::int as requests_today
from public.api_projects pr
left join public.profiles p on p.id = pr.owner_id;
grant select on public.api_projects_admin to authenticated;

-- ---------------------------------------------------------------------------
-- Auditoría (50): registrar cambios de misiones y ajustes hechos directamente con la API.
-- ---------------------------------------------------------------------------
create or replace function public.log_admin_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'missions' then
    if tg_op = 'INSERT' then
      insert into public.admin_actions (actor_id, action, subject_id, details)
      values (auth.uid(), 'create_mission', new.id, jsonb_build_object('code', new.code, 'status', new.status));
    elsif new.status is distinct from old.status then
      insert into public.admin_actions (actor_id, action, subject_id, details)
      values (auth.uid(), 'mission_status', new.id, jsonb_build_object('code', new.code, 'from', old.status, 'to', new.status));
    else
      insert into public.admin_actions (actor_id, action, subject_id, details)
      values (auth.uid(), 'edit_mission', new.id, jsonb_build_object('code', new.code));
    end if;
  elsif tg_table_name = 'platform_settings' then
    insert into public.admin_actions (actor_id, action, subject_id, details)
    values (auth.uid(), 'update_setting', null, jsonb_build_object('key', new.key, 'value', new.value));
  end if;
  return new;
end;
$$;
drop trigger if exists audit_missions on public.missions;
create trigger audit_missions after insert or update on public.missions
  for each row execute function public.log_admin_change();
drop trigger if exists audit_settings on public.platform_settings;
create trigger audit_settings after insert or update on public.platform_settings
  for each row execute function public.log_admin_change();

-- Moderadores también leen la bitácora (solo lectura).
drop policy if exists "admin lee bitácora" on public.admin_actions;
create policy "admin lee bitácora" on public.admin_actions for select using (public.is_staff());

create or replace view public.admin_actions_view with (security_invoker = true) as
select a.*, coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as actor_name
from public.admin_actions a
left join public.profiles p on p.id = a.actor_id;
grant select on public.admin_actions_view to authenticated;

-- ---------------------------------------------------------------------------
-- Tablero (35)
-- ---------------------------------------------------------------------------
create or replace function public.admin_dashboard() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if not public.is_staff() then raise exception 'Solo el equipo' using errcode = '42501'; end if;
  select jsonb_build_object(
    'users', (select count(*) from auth.users),
    'collaborators', (select count(*) from public.account_roles where role = 'collaborator'),
    'companies', (select count(*) from public.organizations),
    'companies_pending', (select count(*) from public.organizations where status = 'PENDING'),
    'developers', (select count(distinct owner_id) from public.api_projects),
    'missions_active', (select count(*) from public.missions where status = 'ACTIVE'),
    'missions_total', (select count(*) from public.missions),
    'places', (select count(*) from public.places),
    'contributions_pending', (select count(*) from public.mission_contributions where status in ('SUBMITTED', 'AUTO_CHECKED', 'HUMAN_REVIEW')),
    'contributions_today', (select count(*) from public.mission_contributions where created_at >= date_trunc('day', now())),
    'approved_7d', (select count(*) from public.mission_contributions where status = 'APPROVED' and reviewed_at > now() - interval '7 days'),
    'rejected_7d', (select count(*) from public.mission_contributions where status = 'REJECTED' and reviewed_at > now() - interval '7 days'),
    'rewards_earned_usd', (select coalesce(sum(amount_usd), 0) from public.reward_events where status = 'EARNED'),
    'rewards_available_usd', (select coalesce(sum(amount_usd), 0) from public.reward_events where status = 'AVAILABLE'),
    'withdrawals_pending', (select count(*) from public.withdrawal_requests where status in ('REQUESTED', 'PROCESSING')),
    'withdrawals_pending_usd', (select coalesce(sum(amount_usd), 0) from public.withdrawal_requests where status in ('REQUESTED', 'PROCESSING')),
    'withdrawals_paid_usd', (select coalesce(sum(amount_usd), 0) from public.withdrawal_requests where status = 'COMPLETED'),
    'budget_authorized_usd', (select coalesce(sum(budget_authorized_usd), 0) from public.missions where status in ('ACTIVE', 'PAUSED')),
    'tickets_open', (select count(*) from public.support_tickets where status in ('OPEN', 'IN_PROGRESS')),
    'campaigns_pending', (select count(*) from public.campaign_requests where status = 'PENDING'),
    'api_requests_7d', (select coalesce(sum(requests), 0) from public.api_usage where day > current_date - 7),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', d::date, 'submitted', s, 'approved', a) order by d), '[]'::jsonb) from (
       select g.d,
              (select count(*) from public.mission_contributions c where c.created_at >= g.d and c.created_at < g.d + interval '1 day') as s,
              (select count(*) from public.mission_contributions c where c.status = 'APPROVED' and c.reviewed_at >= g.d and c.reviewed_at < g.d + interval '1 day') as a
       from generate_series(date_trunc('day', now()) - interval '13 days', date_trunc('day', now()), interval '1 day') g(d)) t)
  ) into r;
  return r;
end;
$$;
revoke all on function public.admin_dashboard() from public, anon;
grant execute on function public.admin_dashboard() to authenticated;

-- Mapa operativo (38): lugares aprobados con coordenadas legibles para el panel.
create or replace view public.places_admin with (security_invoker = true) as
select pl.id, pl.code, pl.name, pl.category, pl.commune, pl.visibility, pl.created_at,
       extensions.st_y(pl.location::extensions.geometry) as lat, extensions.st_x(pl.location::extensions.geometry) as lng
from public.places pl;
grant select on public.places_admin to authenticated;

notify pgrst, 'reload schema';

-- ===== 20261126100100_panel_admin_empresas.sql =====
-- Panel administrativo: revisión de documentos de empresa, activación de planes y emisión de facturas.
-- Requiere 20261126000020_paneles_empresa_desarrollador.sql (tablas organization_documents, billing_*, invoices).

-- ---------------------------------------------------------------------------
-- Documentos de verificación de empresa
-- ---------------------------------------------------------------------------
create or replace function public.review_organization_document(p_id uuid, p_decision public.review_status, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_org uuid;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_decision = 'REJECTED' and coalesce(trim(p_reason), '') = '' then raise exception 'Indica el motivo'; end if;
  select org_id into v_org from public.organization_documents where id = p_id;
  if v_org is null then raise exception 'Documento no encontrado'; end if;
  if public.is_org_member(v_org) then raise exception 'No puedes revisar tu propia empresa' using errcode = '42501'; end if;
  update public.organization_documents set status = p_decision, review_reason = p_reason where id = p_id;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'review_org_document', p_id, jsonb_build_object('org_id', v_org, 'decision', p_decision, 'reason', p_reason));
end;
$$;
revoke all on function public.review_organization_document(uuid, public.review_status, text) from public, anon;
grant execute on function public.review_organization_document(uuid, public.review_status, text) to authenticated;

create or replace view public.organization_documents_view with (security_invoker = true) as
select d.*, o.name as org_name
from public.organization_documents d join public.organizations o on o.id = d.org_id;
grant select on public.organization_documents_view to authenticated;

-- ---------------------------------------------------------------------------
-- Suscripciones: el equipo confirma el pago y activa (o cancela) el plan.
-- Al activar un plan de desarrollador, la cuota diaria de sus proyectos pasa a la del plan.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_subscription(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.billing_subscriptions; pl public.billing_plans;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_status not in ('ACTIVE', 'CANCELLED') then raise exception 'Estado no válido'; end if;
  select * into s from public.billing_subscriptions where id = p_id for update;
  if not found then raise exception 'Suscripción no encontrada'; end if;
  if s.owner_id = auth.uid() then raise exception 'No puedes activar tu propio plan' using errcode = '42501'; end if;
  select * into pl from public.billing_plans where code = s.plan_code;

  if p_status = 'ACTIVE' then
    -- Un solo plan activo por titular.
    update public.billing_subscriptions set status = 'CANCELLED'
     where id <> s.id and status = 'ACTIVE' and audience = s.audience
       and ((s.org_id is null and org_id is null and owner_id = s.owner_id) or (s.org_id is not null and org_id = s.org_id));
    update public.billing_subscriptions set status = 'ACTIVE', started_at = coalesce(started_at, now()) where id = s.id;
    if s.audience = 'developer' and pl.daily_quota is not null then
      update public.api_projects set daily_quota = pl.daily_quota where owner_id = s.owner_id;
    end if;
  else
    update public.billing_subscriptions set status = 'CANCELLED' where id = s.id;
  end if;

  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'set_subscription', s.id, jsonb_build_object('plan', s.plan_code, 'status', p_status));
end;
$$;
revoke all on function public.admin_set_subscription(uuid, text) from public, anon;
grant execute on function public.admin_set_subscription(uuid, text) to authenticated;

create or replace view public.billing_subscriptions_view with (security_invoker = true) as
select s.*, pl.name as plan_name, pl.price_usd_month, pl.daily_quota, o.name as org_name,
       coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as owner_name
from public.billing_subscriptions s
join public.billing_plans pl on pl.code = s.plan_code
left join public.organizations o on o.id = s.org_id
left join public.profiles p on p.id = s.owner_id;
grant select on public.billing_subscriptions_view to authenticated;

-- ---------------------------------------------------------------------------
-- Facturas: numeración correlativa FAC-AAAA-000001.
-- ---------------------------------------------------------------------------
create sequence if not exists public.invoice_number_seq;

create or replace function public.admin_create_invoice(
  p_audience text, p_org uuid, p_owner uuid, p_plan text, p_description text,
  p_amount numeric, p_period_start date default null, p_period_end date default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_number text; v_owner uuid := p_owner;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_audience not in ('company', 'developer') then raise exception 'Tipo de cliente no válido'; end if;
  if p_amount is null or p_amount < 0 or p_amount <> round(p_amount, 2) then raise exception 'Monto no válido'; end if;
  if coalesce(trim(p_description), '') = '' then raise exception 'Indica el concepto'; end if;
  if p_audience = 'company' then
    if p_org is null then raise exception 'Elige la empresa'; end if;
    if v_owner is null then select created_by into v_owner from public.organizations where id = p_org; end if;
  elsif v_owner is null then
    raise exception 'Elige el desarrollador';
  end if;
  v_number := 'FAC-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.invoice_number_seq')::text, 6, '0');
  insert into public.invoices (number, audience, org_id, owner_id, plan_code, description, period_start, period_end, amount_usd)
  values (v_number, p_audience, case when p_audience = 'company' then p_org end, v_owner, p_plan, trim(p_description),
          p_period_start, p_period_end, p_amount);
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'create_invoice', null, jsonb_build_object('code', v_number, 'amount_usd', p_amount, 'org_id', p_org, 'owner_id', v_owner));
  return v_number;
end;
$$;
revoke all on function public.admin_create_invoice(text, uuid, uuid, text, text, numeric, date, date) from public, anon;
grant execute on function public.admin_create_invoice(text, uuid, uuid, text, text, numeric, date, date) to authenticated;

create or replace function public.admin_set_invoice_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_number text;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_status not in ('PAID', 'VOID') then raise exception 'Estado no válido'; end if;
  update public.invoices set status = p_status, paid_at = case when p_status = 'PAID' then now() end
   where id = p_id and status = 'PENDING'
  returning number into v_number;
  if v_number is null then raise exception 'Solo se cambian facturas pendientes'; end if;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'invoice_status', p_id, jsonb_build_object('code', v_number, 'status', p_status));
end;
$$;
revoke all on function public.admin_set_invoice_status(uuid, text) from public, anon;
grant execute on function public.admin_set_invoice_status(uuid, text) to authenticated;

create or replace view public.invoices_view with (security_invoker = true) as
select i.*, o.name as org_name, pl.name as plan_name,
       coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as owner_name
from public.invoices i
left join public.organizations o on o.id = i.org_id
left join public.billing_plans pl on pl.code = i.plan_code
left join public.profiles p on p.id = i.owner_id;
grant select on public.invoices_view to authenticated;

-- Planes: el admin puede ajustar precios y activar/desactivar desde el panel.
drop policy if exists "planes: admin gestiona" on public.billing_plans;
create policy "planes: admin gestiona" on public.billing_plans for update using (public.has_role('admin')) with check (public.has_role('admin'));
grant update (name, price_usd_month, daily_quota, features, active) on public.billing_plans to authenticated;

notify pgrst, 'reload schema';
