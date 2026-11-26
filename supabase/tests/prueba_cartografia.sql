-- PRUEBA de base cartográfica: límites, aporte libre y exportación (se deshace al final, no deja datos).
-- Resultado esperado: todos los puntos en OK, sin FALLO.
do $$
declare
  colab uuid := gen_random_uuid();
  modr uuid := gen_random_uuid();
  adm uuid := gen_random_uuid();
  libre uuid; cid uuid; n int; t text; r text := ''; j jsonb;
begin
  -- 1) Carga de límites (como en el SQL Editor) y enlace con el departamento.
  perform public.import_admin_areas(1::smallint, jsonb_build_array(jsonb_build_object(
    'type', 'Feature', 'properties', jsonb_build_object('shapeID', 'TEST-ADM1-OUEST', 'shapeName', 'Ouest'),
    'geometry', jsonb_build_object('type', 'Polygon', 'coordinates',
      '[[[-72.6,18.3],[-72.0,18.3],[-72.0,18.8],[-72.6,18.8],[-72.6,18.3]]]'::jsonb))), 'prueba', 'CC BY 4.0');
  perform public.import_admin_areas(2::smallint, jsonb_build_array(jsonb_build_object(
    'type', 'Feature', 'properties', jsonb_build_object('shapeID', 'TEST-ADM2-DELMAS', 'shapeName', 'Delmas'),
    'geometry', jsonb_build_object('type', 'MultiPolygon', 'coordinates',
      '[[[[-72.32,18.53],[-72.28,18.53],[-72.28,18.56],[-72.32,18.56],[-72.32,18.53]]]]'::jsonb))), 'prueba', 'CC BY 4.0');
  j := public.link_admin_areas();
  select p.name into t from public.admin_areas c join public.admin_areas p on p.id = c.parent_id where c.code = 'TEST-ADM2-DELMAS';
  r := r || ' | 1 comuna enlazada=' || case when t = 'Ouest' then 'OK' else 'FALLO ' || coalesce(t, 'null') end;

  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
    (colab, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'colab-carto@ejemplo.test', now(), now()),
    (modr,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mod-carto@ejemplo.test', now(), now()),
    (adm,   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm-carto@ejemplo.test', now(), now());
  insert into public.account_roles (user_id, role) values (modr, 'moderator'), (adm, 'admin');
  select id into libre from public.missions where code = 'HT-LIBRE' and open_contribution;
  r := r || ' | 2 misión libre=' || case when libre is null then 'FALLO' else 'OK' end;

  -- 3) Un colaborador no puede cargar límites ni exportar.
  perform set_config('request.jwt.claims', json_build_object('sub', colab, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.import_admin_areas(1::smallint, '[]'::jsonb);
    r := r || ' | 3 colaborador carga límites=FALLO';
  exception when insufficient_privilege then r := r || ' | 3 colaborador no carga límites=OK';
  end;

  -- 4) La misión libre no aparece en el mapa de misiones; el punto se ubica en su comuna.
  select count(*) into n from public.missions_nearby(18.5392, -72.3350, 50) m where m.code = 'HT-LIBRE';
  r := r || ' | 4 libre oculta del mapa=' || case when n = 0 then 'OK' else 'FALLO' end;
  select commune into t from public.admin_area_at(18.545, -72.30);
  r := r || ' | 5 comuna del punto=' || case when t = 'Delmas' then 'OK' else 'FALLO ' || coalesce(t, 'null') end;

  -- 6) Aporte libre: se envía sin misión real.
  insert into public.mission_contributions (idempotency_key, mission_id, name, category, location, captured_at)
  values (gen_random_uuid(), libre, 'Pharmacie Test Carto', 'Farmacia',
          'SRID=4326;POINT(-72.30 18.545)'::extensions.geography, now()) returning id into cid;

  -- 7) El moderador aprueba: lugar publicado con comuna y departamento, sin recompensa.
  perform set_config('request.jwt.claims', json_build_object('sub', modr, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  j := public.review_contribution(cid, 'APPROVED');
  begin
    perform * from public.admin_export_places();
    r := r || ' | 8 moderador exporta=FALLO';
  exception when insufficient_privilege then r := r || ' | 8 moderador no exporta=OK';
  end;

  -- 9) El administrador con MFA exporta y queda en la bitácora.
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  select count(*) into n from public.admin_export_places(null, (select id from public.admin_areas where code = 'TEST-ADM2-DELMAS'), 'Farmacia') e
   where e.name = 'Pharmacie Test Carto' and e.commune = 'Delmas' and e.department = 'Ouest' and e.commune_code = 'TEST-ADM2-DELMAS';
  r := r || ' | 9 exportación filtrada=' || case when n = 1 then 'OK' else 'FALLO ' || n end;

  execute 'reset role';
  select count(*) into n from public.places where source_contribution_id = cid and commune = 'Delmas' and department = 'Ouest' and commune_id is not null;
  r := r || ' | 10 lugar con comuna=' || case when n = 1 then 'OK' else 'FALLO' end;
  select count(*) into n from public.reward_events where user_id = colab;
  r := r || ' | 11 sin recompensa=' || case when n = 0 then 'OK' else 'FALLO ' || n end;
  select count(*) into n from public.admin_actions where actor_id = adm and action = 'export_places';
  r := r || ' | 12 exportación auditada=' || case when n = 1 then 'OK' else 'FALLO' end;

  -- 13) Límite diario de aportes libres.
  perform set_config('request.jwt.claims', json_build_object('sub', colab, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  for n in 1..29 loop
    insert into public.mission_contributions (idempotency_key, mission_id, name, category, location, captured_at)
    values (gen_random_uuid(), libre, 'Lugar ' || n, 'Otro', 'SRID=4326;POINT(-72.30 18.545)'::extensions.geography, now());
  end loop;
  begin
    insert into public.mission_contributions (idempotency_key, mission_id, name, category, location, captured_at)
    values (gen_random_uuid(), libre, 'Lugar 31', 'Otro', 'SRID=4326;POINT(-72.30 18.545)'::extensions.geography, now());
    r := r || ' | 13 límite diario=FALLO';
  exception when raise_exception then r := r || ' | 13 límite diario=OK';
  end;
  execute 'reset role';

  raise exception 'RESULTADOS%', r;
end;
$$;
