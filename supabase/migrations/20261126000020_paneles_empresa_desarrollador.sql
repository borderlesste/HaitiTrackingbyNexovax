-- Paneles Empresa (pantallas 15–24) y Desarrollador (25–33) de la app.
-- Empresa: corregir registro rechazado, documentos de verificación, establecimientos propios con GPS y fotos.
-- Desarrollador: perfil y aceptación de condiciones API, rotar claves, prueba sin exponer la clave, editar proyectos.
-- Ambos: planes y facturas (el pago real se activa desde el panel administrativo; aquí solo se solicita).

-- ---------------------------------------------------------------------------
-- Empresa
-- ---------------------------------------------------------------------------
alter table public.organizations add column if not exists website text;
alter table public.organizations add column if not exists department text;

-- Corregir y reenviar los datos mientras la empresa no esté aprobada.
create or replace function public.update_organization_registration(
  p_org uuid, p_name text, p_sector text, p_representative text, p_legal_id text default null,
  p_phone text default null, p_email text default null, p_address text default null, p_commune text default null,
  p_website text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_org_member(p_org) then raise exception 'Empresa no encontrada' using errcode = '42501'; end if;
  if (select status from public.organizations where id = p_org) = 'APPROVED' then
    raise exception 'La empresa ya está verificada: edita solo los datos de contacto';
  end if;
  if coalesce(trim(p_name), '') = '' or coalesce(trim(p_representative), '') = '' then
    raise exception 'Nombre de la empresa y representante son obligatorios';
  end if;
  update public.organizations
     set name = trim(p_name), sector = p_sector, representative_name = trim(p_representative), legal_id = p_legal_id,
         contact_phone = p_phone, contact_email = p_email, address = p_address, commune = p_commune, website = p_website,
         status = 'PENDING', review_reason = null, reviewed_by = null, reviewed_at = null
   where id = p_org;
end;
$$;
revoke all on function public.update_organization_registration(uuid, text, text, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.update_organization_registration(uuid, text, text, text, text, text, text, text, text, text) to authenticated;
grant update (contact_phone, contact_email, address, website) on public.organizations to authenticated;

-- Documentos de verificación (archivos en el bucket privado "evidence", carpeta del usuario que los sube).
create table if not exists public.organization_documents (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  doc_type text not null check (doc_type in ('LEGAL_REGISTRATION', 'TAX_ID', 'REPRESENTATIVE_ID', 'PROOF_OF_ADDRESS', 'OTHER')),
  storage_path text not null,
  file_name text,
  status public.review_status not null default 'PENDING',
  review_reason text,
  uploaded_by uuid not null references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now()
);
alter table public.organization_documents enable row level security;
create policy "documentos: empresa y admin leen" on public.organization_documents for select
  using (public.is_org_member(org_id) or public.has_role('admin'));
create policy "documentos: empresa sube" on public.organization_documents for insert
  with check (public.is_org_member(org_id) and status = 'PENDING' and uploaded_by = auth.uid()
              and storage_path like auth.uid()::text || '/%');
grant select, insert on public.organization_documents to authenticated;

-- Establecimientos registrados por la empresa. Pasan por revisión; al aprobarse se publican en "places".
create table if not exists public.org_establishments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  category text not null,
  description text not null default '',
  address text,
  commune text,
  department text,
  phone text,
  opening_hours text,
  location extensions.geography (Point, 4326) not null,
  accuracy_m numeric,
  photo_paths text[] not null default '{}',
  status public.review_status not null default 'PENDING',
  review_reason text,
  place_id uuid references public.places (id),
  reviewed_by uuid references auth.users (id),
  reviewed_at timestamptz,
  created_by uuid not null references auth.users (id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.org_establishments enable row level security;
create policy "establecimientos: empresa y admin leen" on public.org_establishments for select
  using (public.is_org_member(org_id) or public.has_role('admin'));
grant select on public.org_establishments to authenticated;
-- Sin escritura directa: crear y editar pasa por save_establishment().

create or replace function public.save_establishment(
  p_id uuid, p_org uuid, p_name text, p_category text, p_lat double precision, p_lng double precision,
  p_accuracy_m numeric default null, p_description text default '', p_address text default null,
  p_commune text default null, p_phone text default null, p_opening_hours text default null,
  p_photo_paths text[] default '{}')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_org uuid;
begin
  if p_id is null then
    v_org := p_org;
  else
    select org_id into v_org from public.org_establishments where id = p_id;
  end if;
  if v_org is null or not public.is_org_member(v_org) then raise exception 'Empresa no encontrada' using errcode = '42501'; end if;
  if (select status from public.organizations where id = v_org) <> 'APPROVED' then
    raise exception 'Tu empresa debe estar verificada para registrar establecimientos';
  end if;
  if coalesce(trim(p_name), '') = '' or coalesce(trim(p_category), '') = '' then raise exception 'Nombre y categoría son obligatorios'; end if;
  if p_lat not between 17.9 and 20.2 or p_lng not between -74.6 and -71.5 then raise exception 'La ubicación debe estar en Haití'; end if;
  if exists (select 1 from unnest(coalesce(p_photo_paths, '{}')) ph where ph not like auth.uid()::text || '/%'
             and not exists (select 1 from public.org_establishments e where e.id = p_id and ph = any (e.photo_paths))) then
    raise exception 'Foto no válida';
  end if;
  if p_id is null then
    if (select count(*) from public.org_establishments where org_id = v_org) >= 50 then raise exception 'Límite de establecimientos alcanzado'; end if;
    insert into public.org_establishments (org_id, name, category, description, address, commune, phone, opening_hours, location, accuracy_m, photo_paths)
    values (v_org, trim(p_name), p_category, coalesce(p_description, ''), p_address, p_commune, p_phone, p_opening_hours,
            extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography, p_accuracy_m, coalesce(p_photo_paths, '{}'))
    returning id into v_id;
  else
    -- Cualquier cambio vuelve a revisión.
    update public.org_establishments
       set name = trim(p_name), category = p_category, description = coalesce(p_description, ''), address = p_address,
           commune = p_commune, phone = p_phone, opening_hours = p_opening_hours,
           location = extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography,
           accuracy_m = p_accuracy_m, photo_paths = coalesce(p_photo_paths, '{}'),
           status = 'PENDING', review_reason = null, reviewed_by = null, reviewed_at = null, updated_at = now()
     where id = p_id
    returning id into v_id;
  end if;
  return v_id;
end;
$$;
revoke all on function public.save_establishment(uuid, uuid, text, text, double precision, double precision, numeric, text, text, text, text, text, text[]) from public, anon;
grant execute on function public.save_establishment(uuid, uuid, text, text, double precision, double precision, numeric, text, text, text, text, text, text[]) to authenticated;

-- Revisión del administrador: al aprobar crea o actualiza el lugar público.
create or replace function public.review_establishment(p_id uuid, p_decision public.review_status, p_reason text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare e public.org_establishments; v_place uuid;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_decision = 'REJECTED' and coalesce(trim(p_reason), '') = '' then raise exception 'Indica el motivo'; end if;
  select * into e from public.org_establishments where id = p_id for update;
  if not found then raise exception 'Establecimiento no encontrado'; end if;
  if public.is_org_member(e.org_id) then raise exception 'No puedes revisar tu propia empresa' using errcode = '42501'; end if;
  v_place := e.place_id;
  if p_decision = 'APPROVED' then
    if v_place is null then
      insert into public.places (name, category, commune, department, address_reference, location, accuracy_m)
      values (e.name, e.category, e.commune, e.department, e.address, e.location, e.accuracy_m)
      returning id into v_place;
    else
      update public.places set name = e.name, category = e.category, commune = e.commune, address_reference = e.address,
             location = e.location, accuracy_m = e.accuracy_m, updated_at = now()
       where id = v_place;
    end if;
  end if;
  update public.org_establishments set status = p_decision, review_reason = p_reason, reviewed_by = auth.uid(),
         reviewed_at = now(), place_id = v_place where id = p_id;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'review_establishment', p_id, jsonb_build_object('decision', p_decision, 'reason', p_reason, 'place_id', v_place));
  return v_place;
end;
$$;
revoke all on function public.review_establishment(uuid, public.review_status, text) from public, anon;
grant execute on function public.review_establishment(uuid, public.review_status, text) to authenticated;

create or replace view public.org_establishments_view with (security_invoker = true) as
select e.id, e.org_id, o.name as org_name, e.name, e.category, e.description, e.address, e.commune, e.phone, e.opening_hours,
       extensions.st_y(e.location::extensions.geometry) as lat, extensions.st_x(e.location::extensions.geometry) as lng,
       e.accuracy_m, e.photo_paths, e.status, e.review_reason, e.place_id, p.code as place_code, e.created_at, e.updated_at
from public.org_establishments e join public.organizations o on o.id = e.org_id left join public.places p on p.id = e.place_id;
grant select on public.org_establishments_view to authenticated;

-- Fotos de establecimientos: los miembros de la empresa pueden ver las fotos de sus establecimientos.
create or replace function public.org_establishment_photo_paths(p_org uuid)
returns setof text language sql stable security definer set search_path = '' as $$
  select unnest(photo_paths) from public.org_establishments where org_id = p_org and public.is_org_member(p_org);
$$;
grant execute on function public.org_establishment_photo_paths(uuid) to authenticated;

-- Miembros autorizados: el dueño agrega usuarios existentes por teléfono o correo.
create or replace view public.organization_members_view with (security_invoker = false) as
select m.org_id, m.user_id, m.member_role, m.created_at, coalesce(nullif(p.full_name, ''), 'Usuario') as full_name,
       p.phone
from public.organization_members m left join public.profiles p on p.id = m.user_id
where public.is_org_member(m.org_id) or public.has_role('admin');
grant select on public.organization_members_view to authenticated;

create or replace function public.add_organization_member(p_org uuid, p_contact text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid; v_digits text;
begin
  if not exists (select 1 from public.organization_members where org_id = p_org and user_id = auth.uid() and member_role = 'owner') then
    raise exception 'Solo el dueño puede agregar usuarios' using errcode = '42501';
  end if;
  if (select count(*) from public.organization_members where org_id = p_org) >= 10 then raise exception 'Máximo 10 usuarios por empresa'; end if;
  v_digits := regexp_replace(coalesce(p_contact, ''), '\D', '', 'g');
  if length(v_digits) = 8 then v_digits := '509' || v_digits; end if;
  select id into v_user from auth.users
   where (position('@' in p_contact) > 0 and lower(email) = lower(trim(p_contact)))
      or (position('@' in p_contact) = 0 and phone = v_digits)
   limit 1;
  if v_user is null then raise exception 'No existe una cuenta con ese teléfono o correo. Pide que se registre primero.'; end if;
  insert into public.organization_members (org_id, user_id, member_role) values (p_org, v_user, 'member') on conflict do nothing;
  insert into public.account_roles (user_id, role) values (v_user, 'company') on conflict do nothing;
end;
$$;
create or replace function public.remove_organization_member(p_org uuid, p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.organization_members where org_id = p_org and user_id = auth.uid() and member_role = 'owner') then
    raise exception 'Solo el dueño puede quitar usuarios' using errcode = '42501';
  end if;
  if p_user = auth.uid() then raise exception 'No puedes quitarte a ti mismo'; end if;
  delete from public.organization_members where org_id = p_org and user_id = p_user and member_role = 'member';
end;
$$;
revoke all on function public.add_organization_member(uuid, text) from public, anon;
revoke all on function public.remove_organization_member(uuid, uuid) from public, anon;
grant execute on function public.add_organization_member(uuid, text) to authenticated;
grant execute on function public.remove_organization_member(uuid, uuid) to authenticated;

-- Solicitud de misión: tipo (registrar lugares nuevos o verificar existentes) y fechas deseadas.
alter table public.campaign_requests add column if not exists request_type text not null default 'COLLECT'
  check (request_type in ('COLLECT', 'VERIFY'));
alter table public.campaign_requests add column if not exists category text;
alter table public.campaign_requests add column if not exists desired_end date;

create or replace view public.campaign_requests_view with (security_invoker = true) as
select cr.id, cr.org_id, o.name as org_name, cr.title, cr.description, cr.commune, cr.radius_m, cr.target_places,
       cr.proposed_budget_usd, cr.status, cr.review_reason, cr.mission_id, cr.created_at,
       extensions.st_y(cr.center::extensions.geometry) as lat, extensions.st_x(cr.center::extensions.geometry) as lng,
       m.code as mission_code, m.status as mission_status,
       (select count(*) from public.mission_contributions mc where mc.mission_id = cr.mission_id and mc.status = 'APPROVED') as approved_places,
       cr.request_type, cr.category, cr.desired_end,
       (select count(*) from public.mission_contributions mc where mc.mission_id = cr.mission_id and mc.status = 'PENDING') as pending_places
from public.campaign_requests cr join public.organizations o on o.id = cr.org_id left join public.missions m on m.id = cr.mission_id;
grant select on public.campaign_requests_view to authenticated;

-- ---------------------------------------------------------------------------
-- Planes y facturación (empresa y desarrollador)
-- ---------------------------------------------------------------------------
create table if not exists public.billing_plans (
  code text primary key,
  audience text not null check (audience in ('company', 'developer')),
  name text not null,
  price_usd_month numeric(10, 2) not null default 0,
  daily_quota integer,
  features text[] not null default '{}',
  sort integer not null default 0,
  active boolean not null default true
);
alter table public.billing_plans enable row level security;
create policy "planes: todos leen" on public.billing_plans for select using (active or public.has_role('admin'));
grant select on public.billing_plans to anon, authenticated;

insert into public.billing_plans (code, audience, name, price_usd_month, daily_quota, features, sort) values
  ('company_free', 'company', 'Gratis', 0, null, array['Hasta 3 establecimientos', 'Ficha pública en el mapa', 'Solicitar misiones (pago por misión)'], 1),
  ('company_business', 'company', 'Negocio', 29, null, array['Hasta 25 establecimientos', '5 usuarios autorizados', 'Reportes de cobertura', 'Soporte prioritario'], 2),
  ('company_enterprise', 'company', 'Corporativo', 99, null, array['Hasta 50 establecimientos', '10 usuarios autorizados', 'Misiones de verificación periódicas', 'Gestor de cuenta'], 3),
  ('dev_free', 'developer', 'Gratis', 0, 1000, array['1.000 consultas al día', 'Entorno de pruebas', 'Soporte por correo'], 1),
  ('dev_starter', 'developer', 'Inicial', 19, 10000, array['10.000 consultas al día', 'Producción', 'Estadísticas de uso'], 2),
  ('dev_pro', 'developer', 'Profesional', 79, 100000, array['100.000 consultas al día', 'Producción', 'Soporte prioritario', 'Acuerdo de nivel de servicio'], 3)
on conflict (code) do nothing;

create table if not exists public.billing_subscriptions (
  id uuid primary key default gen_random_uuid(),
  audience text not null check (audience in ('company', 'developer')),
  org_id uuid references public.organizations (id) on delete cascade,
  owner_id uuid not null references auth.users (id) default auth.uid(),
  plan_code text not null references public.billing_plans (code),
  status text not null default 'REQUESTED' check (status in ('REQUESTED', 'ACTIVE', 'CANCELLED')),
  started_at timestamptz,
  created_at timestamptz not null default now(),
  check ((audience = 'company') = (org_id is not null))
);
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  number text not null unique,
  audience text not null check (audience in ('company', 'developer')),
  org_id uuid references public.organizations (id) on delete cascade,
  owner_id uuid references auth.users (id),
  plan_code text references public.billing_plans (code),
  description text not null default '',
  period_start date,
  period_end date,
  amount_usd numeric(12, 2) not null check (amount_usd >= 0),
  status text not null default 'PENDING' check (status in ('PENDING', 'PAID', 'VOID')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
alter table public.billing_subscriptions enable row level security;
alter table public.invoices enable row level security;
create policy "suscripciones: titular y admin leen" on public.billing_subscriptions for select
  using ((org_id is null and owner_id = auth.uid()) or (org_id is not null and public.is_org_member(org_id)) or public.has_role('admin'));
create policy "facturas: titular y admin leen" on public.invoices for select
  using ((org_id is null and owner_id = auth.uid()) or (org_id is not null and public.is_org_member(org_id)) or public.has_role('admin'));
grant select on public.billing_subscriptions, public.invoices to authenticated;

-- Solicitar un plan: queda REQUESTED hasta que el equipo confirme el pago y lo active desde el panel.
create or replace function public.request_plan(p_plan text, p_org uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare pl public.billing_plans; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sesión requerida' using errcode = '42501'; end if;
  select * into pl from public.billing_plans where code = p_plan and active;
  if not found then raise exception 'Plan no disponible'; end if;
  if pl.audience = 'company' then
    if p_org is null or not public.is_org_member(p_org) then raise exception 'Empresa no encontrada' using errcode = '42501'; end if;
  else
    p_org := null;
  end if;
  update public.billing_subscriptions set status = 'CANCELLED'
   where status = 'REQUESTED' and audience = pl.audience
     and ((p_org is null and org_id is null and owner_id = auth.uid()) or org_id = p_org);
  insert into public.billing_subscriptions (audience, org_id, owner_id, plan_code, status, started_at)
  values (pl.audience, p_org, auth.uid(), pl.code,
          case when pl.price_usd_month = 0 then 'ACTIVE' else 'REQUESTED' end,
          case when pl.price_usd_month = 0 then now() end)
  returning id into v_id;
  if pl.price_usd_month = 0 then
    update public.billing_subscriptions set status = 'CANCELLED'
     where id <> v_id and status = 'ACTIVE' and audience = pl.audience
       and ((p_org is null and org_id is null and owner_id = auth.uid()) or org_id = p_org);
  end if;
  return v_id;
end;
$$;
revoke all on function public.request_plan(text, uuid) from public, anon;
grant execute on function public.request_plan(text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Desarrollador
-- ---------------------------------------------------------------------------
create table if not exists public.developer_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade default auth.uid(),
  display_name text not null,
  company_name text,
  country text not null default 'Haití',
  website text,
  use_case text not null,
  terms_version text not null,
  terms_accepted_at timestamptz not null default now(),
  notify_quota boolean not null default true,
  notify_security boolean not null default true,
  notify_billing boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.developer_profiles enable row level security;
create policy "dev: propio y admin leen" on public.developer_profiles for select using (user_id = auth.uid() or public.has_role('admin'));
create policy "dev: propio actualiza" on public.developer_profiles for update using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select on public.developer_profiles to authenticated;
grant update (display_name, company_name, country, website, notify_quota, notify_security, notify_billing) on public.developer_profiles to authenticated;

create or replace function public.register_developer(p_display_name text, p_use_case text, p_accept_terms boolean,
  p_company text default null, p_country text default 'Haití', p_website text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sesión requerida' using errcode = '42501'; end if;
  if not p_accept_terms then raise exception 'Debes aceptar las condiciones de la API'; end if;
  if coalesce(trim(p_display_name), '') = '' or length(trim(coalesce(p_use_case, ''))) < 5 then
    raise exception 'Nombre y uso previsto son obligatorios';
  end if;
  insert into public.developer_profiles (user_id, display_name, company_name, country, website, use_case, terms_version)
  values (auth.uid(), trim(p_display_name), nullif(trim(p_company), ''), coalesce(nullif(trim(p_country), ''), 'Haití'),
          nullif(trim(p_website), ''), trim(p_use_case), 'api-terms-2026-11')
  on conflict (user_id) do update set display_name = excluded.display_name, company_name = excluded.company_name,
     country = excluded.country, website = excluded.website, use_case = excluded.use_case,
     terms_version = excluded.terms_version, terms_accepted_at = now();
  insert into public.account_roles (user_id, role) values (auth.uid(), 'developer') on conflict do nothing;
end;
$$;
revoke all on function public.register_developer(text, text, boolean, text, text, text) from public, anon;
grant execute on function public.register_developer(text, text, boolean, text, text, text) to authenticated;

create or replace function public.update_api_project(p_project uuid, p_name text, p_intended_use text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(trim(p_name), '') = '' then raise exception 'El nombre es obligatorio'; end if;
  update public.api_projects set name = trim(p_name), intended_use = coalesce(nullif(trim(p_intended_use), ''), intended_use)
   where id = p_project and owner_id = auth.uid();
  if not found then raise exception 'Proyecto no encontrado' using errcode = '42501'; end if;
end;
$$;
revoke all on function public.update_api_project(uuid, text, text) from public, anon;
grant execute on function public.update_api_project(uuid, text, text) to authenticated;

-- Rotar: crea una clave nueva (se muestra una sola vez) y revoca la anterior en la misma operación.
create or replace function public.rotate_api_key(p_key uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_project uuid; v_prefix text; v_secret text;
begin
  select k.project_id into v_project from public.developer_api_keys k join public.api_projects p on p.id = k.project_id
   where k.id = p_key and k.revoked_at is null and p.owner_id = auth.uid() and p.status = 'ACTIVE';
  if v_project is null then raise exception 'Clave no encontrada' using errcode = '42501'; end if;
  update public.developer_api_keys set revoked_at = now() where id = p_key;
  v_prefix := 'htk_' || encode(extensions.gen_random_bytes(4), 'hex');
  v_secret := v_prefix || '_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.developer_api_keys (project_id, prefix, secret_hash) values (v_project, v_prefix, encode(extensions.digest(v_secret, 'sha256'), 'hex'));
  return v_secret;
end;
$$;
revoke all on function public.rotate_api_key(uuid) from public, anon;
grant execute on function public.rotate_api_key(uuid) to authenticated;

-- Probar la API desde la app con la sesión del dueño: la clave secreta nunca entra en la app.
-- Cuenta en el consumo del proyecto igual que una consulta real.
create or replace function public.api_test_places_nearby(p_project uuid, p_lat double precision, p_lng double precision,
  p_radius_m double precision default 1000, p_limit integer default 20)
returns table (code text, name text, category text, commune text, lat double precision, lng double precision, distance_m double precision)
language plpgsql security definer set search_path = '' as $$
declare pr public.api_projects; used integer;
begin
  select * into pr from public.api_projects where id = p_project and owner_id = auth.uid();
  if not found then raise exception 'Proyecto no encontrado' using errcode = '42501'; end if;
  if pr.status <> 'ACTIVE' then raise exception 'Proyecto suspendido' using errcode = '42501'; end if;
  insert into public.api_usage (project_id, day, requests) values (pr.id, current_date, 1)
  on conflict (project_id, day) do update set requests = public.api_usage.requests + 1
  returning requests into used;
  if used > pr.daily_quota then raise exception 'Cuota diaria superada (% solicitudes)', pr.daily_quota using errcode = '53400'; end if;
  return query
  select p.code, p.name, p.category, p.commune,
         extensions.st_y(p.location::extensions.geometry), extensions.st_x(p.location::extensions.geometry),
         extensions.st_distance(p.location, extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography)
  from public.places p
  where p.visibility = 'PUBLIC'
    and extensions.st_dwithin(p.location, extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography, least(p_radius_m, 10000))
  order by 7
  limit least(greatest(p_limit, 1), 50);
end;
$$;
revoke all on function public.api_test_places_nearby(uuid, double precision, double precision, double precision, integer) from public, anon;
grant execute on function public.api_test_places_nearby(uuid, double precision, double precision, double precision, integer) to authenticated;

notify pgrst, 'reload schema';
