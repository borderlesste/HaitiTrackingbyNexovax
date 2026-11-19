-- Permisos para la app móvil (solo objetos de Haiti Tracking; las tablas del backend anterior no se exponen).
-- Nota: la tabla "contributions" ya existía (backend anterior), por eso la nuestra se llama mission_contributions.
grant usage on schema public to anon, authenticated;
grant usage on schema extensions to anon, authenticated;
grant usage on type public.app_role, public.mission_type, public.mission_status, public.assignment_status,
  public.contribution_status, public.place_visibility, public.reward_status to anon, authenticated;
grant select on public.missions, public.places to anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.account_roles, public.reward_events, public.my_reward_summary to authenticated;
grant select, insert on public.mission_assignments, public.mission_contributions to authenticated;
grant update on public.mission_contributions to authenticated;
grant insert, update, delete on public.missions, public.places to authenticated;
grant execute on function public.missions_nearby(double precision, double precision, double precision) to anon, authenticated;
grant execute on function public.check_duplicates(double precision, double precision, text, double precision) to authenticated;
grant execute on function public.has_role(public.app_role) to anon, authenticated;
grant usage on sequence public.place_code_seq to authenticated;
notify pgrst, 'reload schema';
