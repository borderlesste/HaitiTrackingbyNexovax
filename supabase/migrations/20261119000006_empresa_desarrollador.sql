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
