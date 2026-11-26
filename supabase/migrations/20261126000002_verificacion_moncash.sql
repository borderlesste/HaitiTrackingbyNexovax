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
