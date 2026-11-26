-- Aplicar el segundo factor a los privilegios de administración y moderación en la API y RLS.
create or replace function public.has_role(r public.app_role) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.account_roles
    where user_id = (select auth.uid()) and role = r
      and (r not in ('admin', 'moderator') or (select auth.jwt() ->> 'aal') = 'aal2')
  );
$$;

-- El panel puede iniciar la verificación consultando únicamente los roles de la cuenta actual.
create or replace function public.is_panel_staff() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from public.account_roles
    where user_id = (select auth.uid()) and role in ('admin', 'moderator')
  );
$$;
revoke all on function public.is_panel_staff() from public, anon;
grant execute on function public.is_panel_staff() to authenticated;

notify pgrst, 'reload schema';
