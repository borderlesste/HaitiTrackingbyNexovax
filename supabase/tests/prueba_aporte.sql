-- PRUEBA de extremo a extremo de un aporte (ejecutar en el SQL Editor de Supabase).
-- Todo se deshace al final con una excepción: no queda nada guardado.
-- Resultado esperado (2026-11-19):
-- 1 perfil+rol creados=1 | 2 aporte enviado=1 | 3 reintento no duplica=OK | 4 no puede autoaprobarse=OK
-- 5 aprobar propio filas=0 OK | 6 duplicado detectado=1 | 7 places=0 | 8 subir foto propia=OK | 9 carpeta ajena bloqueada=OK
do $$
declare
  uid uuid := gen_random_uuid();
  mid uuid;
  k uuid := gen_random_uuid();
  r text := '';
  n int;
begin
  select id into mid from public.missions where code = 'MIS-DEL-0001';

  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values (uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'prueba@ejemplo.test', '{"full_name":"Prueba Delmas"}', now(), now());
  select count(*) into n from public.profiles p join public.account_roles a on a.user_id = p.id where p.id = uid and a.role = 'collaborator' and p.full_name = 'Prueba Delmas';
  r := r || ' | 1 perfil+rol creados=' || n;

  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.mission_contributions (idempotency_key, mission_id, name, category, address_reference, location, accuracy_m, captured_at, photo_paths)
  values (k, mid, 'Mini Market Delmas 33', 'Tienda / Mini Market', 'Frente a la estación', 'SRID=4326;POINT(-72.2970 18.5405)', 6, now(), array[uid::text || '/' || k::text || '.jpg']);
  select count(*) into n from public.mission_contributions where user_id = uid and status = 'SUBMITTED';
  r := r || ' | 2 aporte enviado=' || n;

  begin
    insert into public.mission_contributions (idempotency_key, mission_id, name, category, location, captured_at)
    values (k, mid, 'Reintento', 'Otro', 'SRID=4326;POINT(-72.2970 18.5405)', now());
    r := r || ' | 3 reintento duplicado=FALLO';
  exception when unique_violation then r := r || ' | 3 reintento no duplica=OK';
  end;

  begin
    insert into public.mission_contributions (idempotency_key, mission_id, name, category, location, captured_at, status)
    values (gen_random_uuid(), mid, 'Autoaprobado', 'Otro', 'SRID=4326;POINT(-72.2970 18.5405)', now(), 'APPROVED');
    r := r || ' | 4 autoaprobar=FALLO';
  exception when insufficient_privilege or check_violation then r := r || ' | 4 no puede autoaprobarse=OK';
  end;

  begin
    update public.mission_contributions set status = 'APPROVED' where user_id = uid;
    get diagnostics n = row_count;
    r := r || ' | 5 aprobar propio filas=' || n || case when n = 0 then ' OK' else ' FALLO' end;
  exception when others then r := r || ' | 5 aprobar propio bloqueado=OK';
  end;

  select count(*) into n from public.check_duplicates(18.54052, -72.29702, 'Minimarket Delmas 33') where source = 'pending';
  r := r || ' | 6 duplicado detectado=' || n;

  select count(*) into n from public.places;
  r := r || ' | 7 no publica lugar sin aprobar (places)=' || n;

  begin
    insert into storage.objects (bucket_id, name) values ('evidence', uid::text || '/foto.jpg');
    r := r || ' | 8 subir foto propia=OK';
  exception when others then r := r || ' | 8 subir foto propia=ERROR ' || sqlerrm;
  end;
  begin
    insert into storage.objects (bucket_id, name) values ('evidence', gen_random_uuid()::text || '/ajena.jpg');
    r := r || ' | 9 subir en carpeta ajena=FALLO';
  exception when others then r := r || ' | 9 carpeta ajena bloqueada=OK';
  end;

  raise exception 'RESULTADOS%', r;
end $$;
