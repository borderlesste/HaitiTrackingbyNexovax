-- Verificación MonCash con cuentas y sesiones sintéticas.
begin;

do $$
declare
  owner_id uuid := gen_random_uuid();
  staff_id uuid := gen_random_uuid();
  valid_session uuid := gen_random_uuid();
  foreign_session uuid := gen_random_uuid();
  expired_session uuid := gen_random_uuid();
  withdrawal_key uuid := gen_random_uuid();
  withdrawal_id uuid;
  pending_id uuid;
  confirmed_at timestamptz := now();
  number_e164 text := '+50937110001';
begin
  insert into auth.users (id, aud, role, email, phone, phone_confirmed_at)
  values (owner_id, 'authenticated', 'authenticated', 'owner@example.test', substring(number_e164 from 2), confirmed_at),
         (staff_id, 'authenticated', 'authenticated', 'staff@example.test', null, null);
  insert into auth.sessions (id, user_id, created_at)
  values (valid_session, owner_id, now()), (foreign_session, staff_id, now()),
         (expired_session, owner_id, now() - interval '10 minutes');
  insert into public.account_roles (user_id, role) values (staff_id, 'admin');
  insert into public.moncash_verifications (user_id, phone) values (owner_id, number_e164);
  insert into public.reward_events (user_id, kind, amount_usd, status) values (owner_id, 'ADJUSTMENT', 10, 'AVAILABLE');
  update public.platform_settings set value = jsonb_set(value, '{enabled}', 'true') where key = 'withdrawals';

  if has_function_privilege('authenticated', 'public.confirm_moncash_phone()', 'EXECUTE')
    or has_function_privilege('anon', 'public.record_moncash_phone(uuid,uuid,text,timestamptz)', 'EXECUTE')
    or has_function_privilege('authenticated', 'public.record_moncash_phone(uuid,uuid,text,timestamptz)', 'EXECUTE') then
    raise exception 'Los clientes no deben poder registrar prueba telefónica';
  end if;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', owner_id, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  begin
    perform public.request_withdrawal(5, withdrawal_key);
    raise exception 'Una verificación histórica no debe autorizar el retiro';
  exception when insufficient_privilege then
    if sqlerrm <> 'Confirma nuevamente tu número MonCash' then raise; end if;
  end;

  execute 'reset role';
  execute 'set local role service_role';
  begin
    perform public.record_moncash_phone(owner_id, foreign_session, number_e164, confirmed_at);
    raise exception 'La sesión debe pertenecer a la cuenta';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.record_moncash_phone(owner_id, expired_session, number_e164, confirmed_at);
    raise exception 'La sesión debe ser reciente';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.record_moncash_phone(owner_id, valid_session, '+50937110002', confirmed_at);
    raise exception 'La sesión debe coincidir con el número vigente de la cuenta';
  exception when insufficient_privilege then null;
  end;
  perform public.record_moncash_phone(owner_id, valid_session, number_e164, confirmed_at);

  execute 'reset role';
  execute 'set local role authenticated';
  select id into strict withdrawal_id from public.request_withdrawal(5, withdrawal_key);
  if public.my_moncash_phone() is distinct from number_e164
    or (public.request_withdrawal(5, withdrawal_key)).id is distinct from withdrawal_id then
    raise exception 'El retiro verificado debe preservar su idempotencia';
  end if;
  select id into strict pending_id from public.request_withdrawal(5, gen_random_uuid());

  perform set_config('request.jwt.claims', jsonb_build_object('sub', staff_id, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if (public.admin_process_withdrawal(withdrawal_id, 'PROCESSING')).status is distinct from 'PROCESSING' then
    raise exception 'El administrador debe poder procesar la solicitud verificada';
  end if;
  execute 'reset role';
  update auth.users set phone_confirmed_at = confirmed_at + interval '1 second' where id = owner_id;
  execute 'set local role authenticated';
  if not (select phone_matches from public.withdrawals_admin where id = withdrawal_id)
    or (select phone_matches from public.withdrawals_admin where id = pending_id) then
    raise exception 'El panel debe distinguir la autorización previa de la verificación vencida';
  end if;
  if (public.admin_process_withdrawal(withdrawal_id, 'COMPLETED', 'referencia-de-prueba')).status is distinct from 'COMPLETED' then
    raise exception 'Debe poder registrarse el pago ya autorizado';
  end if;
  begin
    perform public.admin_process_withdrawal(pending_id, 'PROCESSING');
    raise exception 'La confirmación anterior no permite autorizar otra solicitud';
  exception when insufficient_privilege then
    if sqlerrm <> 'Confirma nuevamente tu número MonCash' then raise; end if;
  end;
  if (public.admin_process_withdrawal(pending_id, 'REJECTED', p_reason => 'Confirmación vencida')).status is distinct from 'REJECTED' then
    raise exception 'El equipo debe poder rechazar la solicitud e inutilizar la reserva';
  end if;
  execute 'reset role';
end $$;

rollback;

