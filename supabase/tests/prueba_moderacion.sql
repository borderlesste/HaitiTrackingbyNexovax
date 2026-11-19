-- PRUEBA de moderación (ejecutar en el SQL Editor; se deshace al final, no deja datos).
-- Nota: las secuencias no se deshacen; si places está vacía, reiniciar con:
--   select setval('public.place_code_seq', 1, false);
-- Resultado esperado (2026-11-19):
-- 1 colaborador no puede aprobar=OK | 2 cola visible para moderador=5 | 3 rechazo exige motivo=OK
-- 4 aprobar dos veces=true | 5 lugares publicados=5 | 6 asientos=6 total USD=2.25 | 7 bitácora=5
-- 8 saldo visto por colaborador=2.25 | 9 colaborador ve solo sus aportes=5
do $$
declare
  colab uuid := gen_random_uuid();
  modr uuid := gen_random_uuid();
  mid uuid; cid uuid; ids uuid[] := '{}'; i int; r text := ''; n int; s numeric; j jsonb;
begin
  select id into mid from public.missions where code = 'MIS-DEL-0001';
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
    (colab, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'colab@ejemplo.test', now(), now()),
    (modr,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mod@ejemplo.test', now(), now());
  insert into public.account_roles (user_id, role) values (modr, 'moderator');

  perform set_config('request.jwt.claims', json_build_object('sub', colab, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  for i in 1..5 loop
    insert into public.mission_contributions (idempotency_key, mission_id, name, category, location, captured_at)
    values (gen_random_uuid(), mid, 'Comercio ' || i, 'Otro', ('SRID=4326;POINT(-72.297' || i || ' 18.5401)')::extensions.geography, now()) returning id into cid;
    ids := ids || cid;
  end loop;
  begin
    perform public.review_contribution(ids[1], 'APPROVED');
    r := r || ' | 1 colaborador aprueba=FALLO';
  exception when insufficient_privilege then r := r || ' | 1 colaborador no puede aprobar=OK';
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', modr, 'role', 'authenticated')::text, true);
  select count(*) into n from public.review_queue;
  r := r || ' | 2 cola visible para moderador=' || n;
  begin
    perform public.review_contribution(ids[5], 'REJECTED', null);
    r := r || ' | 3 rechazo sin motivo=FALLO';
  exception when others then r := r || ' | 3 rechazo exige motivo=OK';
  end;
  for i in 1..5 loop perform public.review_contribution(ids[i], 'APPROVED'); end loop;
  j := public.review_contribution(ids[1], 'APPROVED');
  r := r || ' | 4 aprobar dos veces=' || coalesce(j->>'already', 'no');

  execute 'reset role';
  select count(*) into n from public.places where source_contribution_id = any(ids);
  r := r || ' | 5 lugares publicados=' || n;
  select count(*), sum(amount_usd) into n, s from public.reward_events where user_id = colab;
  r := r || ' | 6 asientos=' || n || ' total USD=' || s || ' (esperado 6 y 2.25)';
  select count(*) into n from public.admin_actions where actor_id = modr;
  r := r || ' | 7 bitácora=' || n;

  perform set_config('request.jwt.claims', json_build_object('sub', colab, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select earned_usd into s from public.my_reward_summary;
  r := r || ' | 8 saldo visto por colaborador=' || s;
  select count(*) into n from public.review_queue;
  r := r || ' | 9 colaborador ve solo sus aportes=' || n;

  raise exception 'RESULTADOS%', r;
end $$;
