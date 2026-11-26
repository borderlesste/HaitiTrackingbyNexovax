-- Privilegios de clientes explícitos, incluso en proyectos con permisos por defecto amplios.
revoke update on public.organizations from public, anon, authenticated;
grant update (contact_phone, contact_email, address, website) on public.organizations to authenticated;

revoke update on public.profiles from public, anon, authenticated;
grant update (first_name, last_name, full_name, phone, department, commune, birth_date,
              preferred_language, collaborator_type, terms_accepted_at) on public.profiles to authenticated;

revoke update on public.developer_profiles from public, anon, authenticated;
grant update (display_name, company_name, country, website, notify_quota, notify_security, notify_billing)
  on public.developer_profiles to authenticated;

-- La ruta de evidencia debe pertenecer a la misma cuenta que registra el aporte.
alter policy "aportes propios: crear" on public.mission_contributions
  with check (user_id = (select auth.uid()) and status = 'SUBMITTED' and reviewed_by is null
    and not exists (
      select 1 from unnest(photo_paths) as photo(path)
      where path is null or (storage.foldername(path))[1] is distinct from (select auth.uid())::text
        or (storage.foldername(path))[2] = 'org-docs'
    ));

revoke all on public.developer_api_keys from public, anon, authenticated;
grant select (id, project_id, prefix, created_at, revoked_at, last_used_at)
  on public.developer_api_keys to authenticated;

revoke insert on public.support_tickets, public.mission_contributions, public.place_claims,
  public.campaign_requests, public.organization_documents from public, anon, authenticated;
grant insert (user_id, category, subject, message, related_id) on public.support_tickets to authenticated;
grant usage on sequence public.support_ticket_seq to authenticated;
grant insert (idempotency_key, mission_id, user_id, name, category, address_reference, notes,
              location, accuracy_m, captured_at, photo_paths) on public.mission_contributions to authenticated;
grant insert (org_id, place_id, evidence) on public.place_claims to authenticated;
grant insert (org_id, title, description, commune, center, radius_m, target_places,
              proposed_budget_usd, request_type, category, desired_end) on public.campaign_requests to authenticated;
grant insert (org_id, doc_type, storage_path, file_name, uploaded_by) on public.organization_documents to authenticated;

-- Las transiciones y las entradas de auditoría se crean juntas en sus RPC.
drop policy if exists "moderación revisa aportes" on public.mission_contributions;
drop policy if exists "admin procesa retiros" on public.withdrawal_requests;
revoke update on public.mission_contributions, public.withdrawal_requests from public, anon, authenticated;
revoke update (status, fee_usd, htg_rate, reference, rejection_reason, processed_at, processed_by)
  on public.withdrawal_requests from authenticated;
revoke insert, update, delete on public.admin_actions from public, anon, authenticated;

alter function public.is_restricted(uuid) security invoker;

-- RLS limita los aportes en revisión a su dueño y a personal con MFA.
create or replace function public.check_duplicates(lat double precision, lng double precision, place_name text, radius_m double precision default 60)
returns table (source text, code text, name text, category text, distance_m double precision, name_similarity real)
language plpgsql stable security invoker set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Sesión requerida' using errcode = '42501';
  end if;
  if not coalesce(lat between -90 and 90 and lng between -180 and 180
                  and radius_m > 0 and radius_m <= 250 and length(place_name) <= 250, false) then
    raise exception 'Parámetros de búsqueda no válidos' using errcode = '22023';
  end if;

  return query
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
  order by d.name_similarity desc, d.distance_m
  limit 10;
end;
$$;
revoke execute on function public.check_duplicates(double precision, double precision, text, double precision)
  from public, anon;

-- El catálogo abierto conserva los campos usados por la app. El presupuesto se lee en las vistas del panel.
revoke select on public.missions from public, anon, authenticated;
grant select (id, code, type, title, description, department, commune, area, center, radius_m,
              required_approved_contributions, individual_reward_usd, completion_bonus_usd, max_participants,
              requires_on_site_evidence, requirements, start_at, end_at, status, created_at, updated_at)
  on public.missions to anon, authenticated;

create or replace view public.missions_admin with (security_invoker = false, security_barrier = true) as
select m.*, extensions.st_y(m.center::extensions.geometry) as lat, extensions.st_x(m.center::extensions.geometry) as lng,
       (select count(*) from public.mission_contributions c where c.mission_id = m.id) as contributions_count,
       (select count(*) from public.mission_contributions c where c.mission_id = m.id and c.status = 'APPROVED') as approved_count
from public.missions m
where (select public.is_staff());

create or replace view public.mission_budgets with (security_invoker = false, security_barrier = true) as
select m.id, m.code, m.title, m.status, m.budget_authorized_usd, m.individual_reward_usd, m.completion_bonus_usd,
       coalesce((select sum(e.amount_usd) from public.reward_events e where e.mission_id = m.id and e.status <> 'REVERSED' and (public.has_role('admin') or e.user_id = auth.uid())), 0) as committed_usd,
       coalesce((select sum(e.amount_usd) from public.reward_events e where e.mission_id = m.id and e.status = 'PAID' and (public.has_role('admin') or e.user_id = auth.uid())), 0) as paid_usd,
       (select count(*) from public.mission_contributions c
         where c.mission_id = m.id and c.status in ('SUBMITTED', 'AUTO_CHECKED', 'HUMAN_REVIEW'))::int * m.individual_reward_usd as pending_exposure_usd
from public.missions m
where (select public.is_staff());

revoke all on public.missions_admin, public.mission_budgets from public, anon;
grant select on public.missions_admin, public.mission_budgets to authenticated;

-- El moderador revisa evidencia de aportes. Los documentos de empresa quedan para sus dueños y administración.
alter policy "evidencias propias o moderación: leer" on storage.objects using (
  bucket_id = 'evidence' and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or (select public.has_role('admin'))
    or ((select public.has_role('moderator')) and (storage.foldername(name))[2] is distinct from 'org-docs' and exists (
      select 1 from public.mission_contributions c
      where c.user_id::text = (storage.foldername(storage.objects.name))[1]
        and storage.objects.name = any (c.photo_paths)
    ))
  )
);

update storage.buckets set public = false,
  file_size_limit = least(file_size_limit, 10485760),
  allowed_mime_types = array['image/jpeg', 'application/pdf']
where id = 'evidence';


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

  if p_idempotency_key is null then
    raise exception 'Falta el identificador de la solicitud' using errcode = '22023';
  end if;
  -- Serializar también los reintentos que llegan junto a la solicitud inicial.
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));

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

  if public.withdrawable_usd(v_uid) < p_amount then
    raise exception 'Saldo disponible insuficiente';
  end if;

  insert into public.withdrawal_requests (user_id, amount_usd, moncash_phone, idempotency_key)
  values (v_uid, p_amount, v_phone, p_idempotency_key)
  returning * into v_row;
  return v_row;
end;
$$;

-- La aceptación requiere consentimiento explícito. La emisión y la rotación comparten el bloqueo del proyecto.
create or replace function public.create_api_project(p_name text, p_intended_use text, p_accept_terms boolean, p_environment text default 'test')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sesión requerida' using errcode = '42501'; end if;
  if p_accept_terms is not true then raise exception 'Debes aceptar los términos de la API'; end if;
  if (select count(*) from public.api_projects where owner_id = auth.uid()) >= 5 then raise exception 'Máximo 5 proyectos por cuenta'; end if;
  insert into public.api_projects (owner_id, name, intended_use, environment, terms_version)
  values (auth.uid(), trim(p_name), trim(p_intended_use), p_environment, 'api-terms-2026-11') returning id into v_id;
  insert into public.account_roles (user_id, role) values (auth.uid(), 'developer') on conflict do nothing;
  return v_id;
end;
$$;

create or replace function public.register_developer(p_display_name text, p_use_case text, p_accept_terms boolean,
  p_company text default null, p_country text default 'Haití', p_website text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sesión requerida' using errcode = '42501'; end if;
  if p_accept_terms is not true then raise exception 'Debes aceptar las condiciones de la API'; end if;
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

create or replace function public.create_api_key(p_project uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_prefix text; v_secret text;
begin
  perform 1 from public.api_projects
  where id = p_project and owner_id = auth.uid() and status = 'ACTIVE' for no key update;
  if not found then
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

create or replace function public.rotate_api_key(p_key uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_project uuid; v_prefix text; v_secret text;
begin
  select k.project_id into v_project from public.developer_api_keys k join public.api_projects p on p.id = k.project_id
   where k.id = p_key and k.revoked_at is null and p.owner_id = auth.uid() and p.status = 'ACTIVE';
  if v_project is null then raise exception 'Clave no encontrada' using errcode = '42501'; end if;
  perform 1 from public.api_projects
  where id = v_project and owner_id = auth.uid() and status = 'ACTIVE' for no key update;
  if not found then raise exception 'Clave no encontrada' using errcode = '42501'; end if;

  update public.developer_api_keys set revoked_at = now()
  where id = p_key and revoked_at is null;
  if not found then raise exception 'Clave no encontrada' using errcode = '42501'; end if;
  v_prefix := 'htk_' || encode(extensions.gen_random_bytes(4), 'hex');
  v_secret := v_prefix || '_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.developer_api_keys (project_id, prefix, secret_hash) values (v_project, v_prefix, encode(extensions.digest(v_secret, 'sha256'), 'hex'));
  return v_secret;
end;
$$;

-- Conservar el evento de auditoría sin copiar mensajes, motivos, referencias ni valores de configuración.
create function public.redact_admin_action_details() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.details := new.details - array['reason', 'reply', 'reference', 'value'];
  return new;
end;
$$;
revoke execute on function public.redact_admin_action_details() from public, anon, authenticated;

create trigger redact_admin_action_details
before insert on public.admin_actions
for each row execute function public.redact_admin_action_details();

notify pgrst, 'reload schema';
