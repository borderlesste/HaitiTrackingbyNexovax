-- PRUEBA de perfiles Empresa y Desarrollador (se deshace al final, no deja datos).
do $$
declare
  emp uuid := gen_random_uuid(); adm uuid := gen_random_uuid(); dev uuid := gen_random_uuid();
  org uuid; pl uuid; cmp uuid; mis uuid; prj uuid; key text; kid uuid; r text := ''; n int;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
    (emp, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'emp@ejemplo.test', now(), now()),
    (adm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm@ejemplo.test', now(), now()),
    (dev, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dev@ejemplo.test', now(), now());
  insert into public.account_roles (user_id, role) values (adm, 'admin');
  insert into public.places (name, category, commune, location) values ('Farmacia Prueba', 'Farmacia', 'Delmas',
    extensions.st_setsrid(extensions.st_makepoint(-72.3035, 18.5466), 4326)::extensions.geography) returning id into pl;

  -- Empresa
  perform set_config('request.jwt.claims', json_build_object('sub', emp, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  org := public.register_organization('Farmacias Delmas SA', 'Salud', 'Marie Joseph');
  select count(*) into n from public.account_roles where user_id = emp and role = 'company';
  r := r || ' | 1 empresa registrada + rol company=' || n;
  begin
    insert into public.place_claims (org_id, place_id) values (org, pl);
    r := r || ' | 2 reclamar sin verificar=FALLO';
  exception when insufficient_privilege then r := r || ' | 2 sin verificar no reclama=OK';
  end;
  begin
    update public.organizations set status = 'APPROVED' where id = org;
    r := r || ' | 3 autoverificar=FALLO';
  exception when insufficient_privilege then r := r || ' | 3 no puede autoverificarse=OK';
  end;

  -- Admin verifica
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform public.review_organization(org, 'APPROVED');

  perform set_config('request.jwt.claims', json_build_object('sub', emp, 'role', 'authenticated')::text, true);
  insert into public.place_claims (org_id, place_id, evidence) values (org, pl, 'Patente comercial');
  insert into public.campaign_requests (org_id, title, commune, center, radius_m, target_places, proposed_budget_usd)
  values (org, 'Farmacias de Delmas', 'Delmas', extensions.st_setsrid(extensions.st_makepoint(-72.3035, 18.5466), 4326)::extensions.geography, 800, 20, 10)
  returning id into cmp;
  select count(*) into n from public.campaign_requests_view where org_id = org;
  r := r || ' | 4 reclamo + campaña creados, campaña visible=' || n;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  mis := public.review_campaign(cmp, 'APPROVED');
  select count(*) into n from public.missions_admin where id = mis and status = 'DRAFT' and max_participants = 20 and budget_authorized_usd = 5.00;
  r := r || ' | 5 campaña aprobada -> misión borrador=' || n;

  -- Desarrollador
  perform set_config('request.jwt.claims', json_build_object('sub', dev, 'role', 'authenticated')::text, true);
  begin
    perform public.create_api_project('App sin términos', 'pruebas', false);
    r := r || ' | 6 sin aceptar términos=FALLO';
  exception when others then r := r || ' | 6 exige términos=OK';
  end;
  prj := public.create_api_project('App Delivery', 'Buscar comercios cercanos', true);
  key := public.create_api_key(prj);
  execute 'reset role';
  select count(*) into n from public.developer_api_keys where project_id = prj and secret_hash <> key and secret_hash = encode(extensions.digest(key, 'sha256'), 'hex');
  execute 'set local role authenticated';
  r := r || ' | 7 clave creada, secreto no guardado en claro=' || n;
  select count(*) into n from public.api_places_nearby(key, 18.5466, -72.3035, 500);
  r := r || ' | 8 API devuelve lugares=' || n;
  select requests into n from public.api_usage where project_id = prj;
  r := r || ' | 9 consumo registrado=' || n;
  select id into kid from public.developer_api_keys where project_id = prj;
  begin
    perform secret_hash from public.developer_api_keys limit 1;
    r := r || ' | 9b dev lee hash=FALLO';
  exception when insufficient_privilege then r := r || ' | 9b hash no legible por la app=OK';
  end;
  perform public.revoke_api_key(kid);
  begin
    perform * from public.api_places_nearby(key, 18.5466, -72.3035, 500);
    r := r || ' | 10 clave revocada funciona=FALLO';
  exception when others then r := r || ' | 10 clave revocada rechazada=OK';
  end;
  begin
    perform * from public.api_places_nearby('htk_falsa_123', 18.5466, -72.3035, 500);
    r := r || ' | 11 clave falsa=FALLO';
  exception when others then r := r || ' | 11 clave falsa rechazada=OK';
  end;
  select count(*) into n from public.organizations;
  r := r || ' | 12 desarrollador no ve empresas ajenas (0)=' || n;

  raise exception 'RESULTADOS%', r;
end $$;
