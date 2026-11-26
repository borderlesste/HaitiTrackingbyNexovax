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
