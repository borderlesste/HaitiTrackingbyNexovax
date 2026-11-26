-- Solo entornos de prueba. Los datos sintéticos se revierten al finalizar.
begin;

do $$
declare
  contributor uuid := gen_random_uuid();
  other_user uuid := gen_random_uuid();
  staff uuid := gen_random_uuid();
  mission uuid;
  organization uuid;
  project uuid;
  ticket uuid;
  previous_key uuid;
  evidence text := contributor::text || '/aporte.jpg';
  document text := contributor::text || '/org-docs/identidad.pdf';
  first_request uuid;
  retry_request uuid;
  retry_key uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role, email, phone, phone_confirmed_at)
  values (contributor, 'authenticated', 'authenticated', 'aporte-acl@example.test', '50937000001', now()),
         (other_user, 'authenticated', 'authenticated', 'otro-acl@example.test', null, null),
         (staff, 'authenticated', 'authenticated', 'staff-acl@example.test', null, null);
  insert into public.account_roles (user_id, role) values (staff, 'moderator');
  select id into strict mission from public.missions where code = 'MIS-DEL-0001';
  insert into public.mission_contributions
    (mission_id, user_id, idempotency_key, name, category, location, captured_at, photo_paths)
  values
    (mission, contributor, gen_random_uuid(), 'Comercio de prueba', 'Comercio',
     'SRID=4326;POINT(-72.297 18.5405)', now(), array[evidence, document]);
  insert into storage.objects (bucket_id, name) values ('evidence', evidence), ('evidence', document);
  insert into public.user_restrictions (user_id, reason) values (other_user, 'Prueba');
  insert into public.moncash_verifications (user_id, phone, phone_confirmation_at) values (contributor, '+50937000001', now());
  insert into public.reward_events (user_id, kind, amount_usd, status) values (contributor, 'ADJUSTMENT', 15, 'AVAILABLE');
  update public.platform_settings set value = jsonb_set(value, '{enabled}', 'true') where key = 'withdrawals';

  if has_function_privilege('anon', 'public.check_duplicates(float8,float8,text,float8)', 'EXECUTE')
    or has_column_privilege('anon', 'public.missions', 'budget_authorized_usd', 'SELECT')
    or has_column_privilege('authenticated', 'public.missions', 'budget_authorized_usd', 'SELECT')
    or has_column_privilege('authenticated', 'public.developer_api_keys', 'secret_hash', 'SELECT')
    or has_column_privilege('authenticated', 'public.mission_contributions', 'status', 'UPDATE')
    or has_column_privilege('authenticated', 'public.withdrawal_requests', 'status', 'UPDATE')
    or has_column_privilege('authenticated', 'public.support_tickets', 'priority', 'INSERT') then
    raise exception 'Permiso de cliente fuera de la lista autorizada';
  end if;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', contributor, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  if public.is_restricted(other_user)
    or exists (select 1 from public.mission_budgets)
    or not exists (select 1 from public.check_duplicates(18.5405, -72.297, 'Comercio') where source = 'pending') then
    raise exception 'El colaborador debe poder consultar solo sus aportes en revisión y el catálogo público';
  end if;
  if not exists (select 1 from public.missions_nearby(18.5405, -72.297) where id = mission) then
    raise exception 'El catálogo público debe seguir disponible';
  end if;
  begin
    perform public.check_duplicates(18.5405, -72.297, 'Comercio', 251);
    raise exception 'Se aceptó un radio fuera del límite';
  exception when invalid_parameter_value then null;
  end;

  organization := public.register_organization('Empresa prueba ACL', 'Salud', 'Representante de prueba');
  update public.organizations set contact_email = 'empresa-acl@example.test' where id = organization;
  if not found or has_column_privilege('authenticated', 'public.organizations', 'status', 'UPDATE') then
    raise exception 'La empresa debe poder editar el contacto sin cambiar su aprobación';
  end if;

  begin
    perform public.create_api_project('Proyecto sin consenso', 'Prueba', null);
    raise exception 'Se aceptó consentimiento NULL al crear el proyecto';
  exception when raise_exception then
    if sqlerrm <> 'Debes aceptar los términos de la API' then raise; end if;
  end;
  begin
    perform public.register_developer('Perfil sin consenso', 'Prueba', null);
    raise exception 'Se aceptó consentimiento NULL al registrar el perfil';
  exception when raise_exception then
    if sqlerrm <> 'Debes aceptar las condiciones de la API' then raise; end if;
  end;
  project := public.create_api_project('Proyecto de prueba', 'Prueba', true);
  perform public.create_api_key(project);
  select id into strict previous_key from public.developer_api_keys where project_id = project and revoked_at is null;
  perform public.rotate_api_key(previous_key);
  if (select count(*) from public.developer_api_keys where project_id = project and revoked_at is null) <> 1
    or not exists (select 1 from public.developer_api_keys where id = previous_key and revoked_at is not null) then
    raise exception 'La rotación debe dejar solo la nueva clave activa';
  end if;
  begin
    perform public.rotate_api_key(previous_key);
    raise exception 'Se aceptó rotar una clave revocada';
  exception when insufficient_privilege then null;
  end;

  insert into public.support_tickets (category, subject, message)
  values ('COMPANY', 'Soporte de prueba', 'Prueba de los valores definidos por el servidor') returning id into ticket;
  if not exists (
    select 1 from public.support_tickets
    where user_id = contributor and category = 'COMPANY' and priority = 'NORMAL' and code like 'SOP-%'
  ) then
    raise exception 'No se pudo abrir el ticket con los valores de servidor';
  end if;
  select id into first_request from public.request_withdrawal(5, retry_key);
  select id into retry_request from public.request_withdrawal(5, retry_key);
  if first_request is null or first_request is distinct from retry_request
    or (select count(*) from public.withdrawal_requests where user_id = contributor) <> 1 then
    raise exception 'El reintento de retiro debe devolver la solicitud original';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', other_user, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  if not public.is_restricted(other_user)
    or exists (select 1 from public.check_duplicates(18.5405, -72.297, 'Comercio') where source = 'pending')
    or exists (select 1 from public.support_tickets where user_id = contributor)
    or exists (select 1 from public.withdrawal_requests where user_id = contributor) then
    raise exception 'La segunda cuenta debe conservar su estado propio sin acceso a los registros ajenos';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', staff, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  if exists (select 1 from public.mission_budgets)
    or exists (select 1 from storage.objects where name in (evidence, document)) then
    raise exception 'La sesión de moderación AAL1 no debe ver presupuestos ni evidencia ajena';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', staff, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if not exists (select 1 from public.mission_budgets where id = mission)
    or not exists (select 1 from public.check_duplicates(18.5405, -72.297, 'Comercio') where source = 'pending')
    or not public.is_restricted(other_user)
    or not exists (select 1 from storage.objects where name = evidence)
    or exists (select 1 from storage.objects where name = document) then
    raise exception 'La moderación AAL2 debe ver evidencia del aporte sin acceso al documento de identidad';
  end if;
  perform public.admin_answer_ticket(ticket, 'RESOLVED', 'Mensaje de soporte sintético');
  if not exists (select 1 from public.support_tickets where id = ticket and admin_reply = 'Mensaje de soporte sintético')
    or not exists (select 1 from public.admin_actions where subject_id = ticket and action = 'answer_ticket' and not (details ? 'reply')) then
    raise exception 'La auditoría debe registrar la respuesta sin copiar su contenido';
  end if;
  execute 'reset role';

  if not exists (select 1 from storage.buckets where id = 'evidence' and not public
                 and file_size_limit <= 10485760 and allowed_mime_types = array['image/jpeg', 'image/png', 'application/pdf']) then
    raise exception 'El bucket de evidencias debe ser privado y limitar tamaño y tipo declarado';
  end if;
end $$;

rollback;

