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
