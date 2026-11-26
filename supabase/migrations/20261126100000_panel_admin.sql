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
