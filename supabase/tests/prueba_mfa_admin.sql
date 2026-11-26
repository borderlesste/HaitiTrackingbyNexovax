-- Ejecutar en una base aislada con todas las migraciones aplicadas.
begin;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_moderator uuid := gen_random_uuid();
  v_collaborator uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         id::text || '@ejemplo.test', now(), now()
  from unnest(array[v_admin, v_moderator, v_collaborator]) as u(id);
  insert into public.account_roles (user_id, role) values (v_admin, 'admin'), (v_moderator, 'moderator');

  execute 'set local role anon';
  if has_function_privilege('public.is_panel_staff()', 'execute') then
    raise exception 'El acceso al panel se debe consultar con sesión';
  end if;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_collaborator, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  if public.is_panel_staff() or not public.has_role('collaborator') or exists (
    select 1 from public.profiles where id = v_admin
  ) then
    raise exception 'La sesión de colaborador debe conservar sus permisos propios sin acceso al panel';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  if not public.is_panel_staff() or public.has_role('admin') then
    raise exception 'El administrador sin nivel de autenticación solo puede descubrir su acceso al panel';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  if public.has_role('admin') or exists (select 1 from public.profiles where id = v_collaborator) then
    raise exception 'La sesión administrativa AAL1 no debe tener acceso privilegiado a perfiles';
  end if;
  begin
    perform public.admin_dashboard();
    raise exception 'La sesión administrativa AAL1 no debe leer el tablero';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_set_role(v_collaborator, 'developer', true);
    raise exception 'La sesión administrativa AAL1 no debe cambiar roles';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if not public.has_role('admin') or not exists (select 1 from public.profiles where id = v_collaborator) then
    raise exception 'La sesión administrativa AAL2 debe poder leer perfiles';
  end if;
  perform public.admin_dashboard();
  perform public.admin_set_role(v_collaborator, 'developer', true);
  if not exists (select 1 from public.account_roles where user_id = v_collaborator and role = 'developer') then
    raise exception 'La sesión administrativa AAL2 debe poder asignar roles';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_moderator, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  if not public.is_panel_staff() or public.has_role('moderator') then
    raise exception 'La sesión de moderador AAL1 solo debe poder descubrir su acceso al panel';
  end if;
  begin
    perform public.admin_dashboard();
    raise exception 'La sesión de moderador AAL1 no debe leer el tablero';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_moderator, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if not public.has_role('moderator') or public.has_role('admin') then
    raise exception 'AAL2 debe conservar la diferencia entre moderación y administración';
  end if;
  perform public.admin_dashboard();
  begin
    perform public.admin_set_role(v_collaborator, 'developer', false);
    raise exception 'La sesión de moderador AAL2 no debe cambiar roles';
  exception when insufficient_privilege then null;
  end;
end $$;

rollback;
