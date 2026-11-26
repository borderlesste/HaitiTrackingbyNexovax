-- Las filas históricas quedan disponibles para revisión y requieren una nueva comprobación.
alter table public.moncash_verifications add column phone_confirmation_at timestamptz;
alter table public.withdrawal_requests add column phone_proof_authorized_at timestamptz;

-- La API de cliente ya no puede registrar una verificación basándose en el método genérico otp.
revoke execute on function public.confirm_moncash_phone() from public, anon, authenticated, service_role;

create function public.record_moncash_phone(
  p_user_id uuid, p_session_id uuid, p_phone text, p_phone_confirmation_at timestamptz
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  -- Solo la función Edge puede atestiguar que GoTrue aceptó el código del teléfono.
  perform 1
  from auth.users u
  join auth.sessions s on s.user_id = u.id
  where u.id = p_user_id and s.id = p_session_id
    and s.created_at > now() - interval '5 minutes'
    and p_phone ~ '^\+509[0-9]{8}$'
    and u.phone in (p_phone, substring(p_phone from 2))
    and u.phone_confirmed_at = p_phone_confirmation_at
  for share of u, s;
  if not found then
    raise exception 'No se pudo confirmar el número MonCash' using errcode = '42501';
  end if;

  insert into public.moncash_verifications (user_id, phone, phone_confirmation_at)
  values (p_user_id, p_phone, p_phone_confirmation_at)
  on conflict (user_id) do update
      set phone = excluded.phone, phone_confirmation_at = excluded.phone_confirmation_at, verified_at = now();

  update public.profiles set phone = p_phone where id = p_user_id;
end;
$$;

revoke all on function public.record_moncash_phone(uuid, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.record_moncash_phone(uuid, uuid, text, timestamptz) to service_role;

create function public.has_current_moncash_phone(p_user_id uuid, p_phone text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.moncash_verifications v
    join auth.users u on u.id = v.user_id
    where v.user_id = p_user_id and v.phone = p_phone
      and (v.user_id = auth.uid() or public.has_role('admin'))
      and u.phone in (v.phone, substring(v.phone from 2))
      and u.phone_confirmed_at = v.phone_confirmation_at
  );
$$;
revoke execute on function public.has_current_moncash_phone(uuid, text) from public, anon;
grant execute on function public.has_current_moncash_phone(uuid, text) to authenticated;

create function public.my_moncash_phone() returns text
language sql stable security invoker set search_path = '' as $$
  select v.phone from public.moncash_verifications v
  where v.user_id = auth.uid() and public.has_current_moncash_phone(v.user_id, v.phone);
$$;
revoke execute on function public.my_moncash_phone() from public, anon;
grant execute on function public.my_moncash_phone() to authenticated;

create function public.require_moncash_phone_proof() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Un pago autorizado puede asentarse aunque el titular cambie el teléfono después.
  if tg_op = 'UPDATE' and old.status = 'PROCESSING' and new.status = 'COMPLETED'
     and old.phone_proof_authorized_at is not null then
    return new;
  end if;

  if new.method = 'MONCASH' and (tg_op = 'INSERT' or new.status in ('PROCESSING', 'COMPLETED')) then
    perform 1
    from public.moncash_verifications v
    join auth.users u on u.id = v.user_id
    where v.user_id = new.user_id and v.phone = new.moncash_phone
      and u.phone in (v.phone, substring(v.phone from 2))
      and u.phone_confirmed_at = v.phone_confirmation_at
    for share of u, v;
    if not found then
      raise exception 'Confirma nuevamente tu número MonCash' using errcode = '42501';
    end if;
    if new.status in ('PROCESSING', 'COMPLETED') then
      new.phone_proof_authorized_at := now();
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.require_moncash_phone_proof() from public, anon, authenticated;
create trigger require_moncash_phone_proof
before insert or update of status on public.withdrawal_requests
for each row execute function public.require_moncash_phone_proof();

create or replace view public.withdrawals_admin with (security_invoker = true) as
select w.id, w.code, w.user_id, w.amount_usd, w.method, w.moncash_phone, w.status, w.fee_usd,
       w.htg_rate, w.reference, w.rejection_reason, w.idempotency_key, w.created_at, w.processed_at, w.processed_by,
       coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as full_name,
       mv.phone as verified_phone, mv.verified_at as phone_verified_at,
       (w.phone_proof_authorized_at is not null or (mv.phone is not null and mv.phone = w.moncash_phone)) as phone_matches
from public.withdrawal_requests w
left join public.profiles p on p.id = w.user_id
left join public.moncash_verifications mv on mv.user_id = w.user_id and public.has_current_moncash_phone(w.user_id, mv.phone);

-- ImagePicker produce PNG cuando debe conservar transparencias.
update storage.buckets set allowed_mime_types = array['image/jpeg', 'image/png', 'application/pdf']
where id = 'evidence';

notify pgrst, 'reload schema';

