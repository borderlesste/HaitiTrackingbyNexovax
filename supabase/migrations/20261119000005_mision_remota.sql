-- La app necesita saber si la misión exige presencia física (requires_on_site_evidence).
-- Las misiones sin presencia (p. ej. pruebas o sugerencias remotas) no comprueban el área GPS en la app.
drop function if exists public.missions_nearby(double precision, double precision, double precision);
create function public.missions_nearby(lat double precision, lng double precision, radius_km double precision default 25)
returns table (
  id uuid, code text, type public.mission_type, title text, description text, commune text,
  lat double precision, lng double precision, radius_m integer, individual_reward_usd numeric, completion_bonus_usd numeric,
  required_approved_contributions integer, requirements text, end_at timestamptz, distance_m double precision,
  requires_on_site_evidence boolean
)
language sql stable set search_path = '' as $$
  select m.id, m.code, m.type, m.title, m.description, m.commune,
         extensions.st_y(m.center::extensions.geometry), extensions.st_x(m.center::extensions.geometry), m.radius_m,
         m.individual_reward_usd, m.completion_bonus_usd, m.required_approved_contributions, m.requirements, m.end_at,
         extensions.st_distance(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography),
         m.requires_on_site_evidence
  from public.missions m
  where m.status = 'ACTIVE'
    and (m.end_at is null or m.end_at > now())
    and extensions.st_dwithin(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography, radius_km * 1000)
  order by 15;
$$;
grant execute on function public.missions_nearby(double precision, double precision, double precision) to anon, authenticated;

-- Misión de PRUEBA en Delmas 33 (sin presencia física). Pausarla al terminar las pruebas.
insert into public.missions (code, type, title, description, commune, center, radius_m, required_approved_contributions,
  individual_reward_usd, completion_bonus_usd, max_participants, budget_authorized_usd, requires_on_site_evidence,
  requirements, start_at, end_at, status)
values ('MIS-DEL-TEST', 'NEW_PLACE', 'PRUEBA: comercio en Delmas 33',
  'Misión de prueba del equipo. Se puede enviar desde cualquier lugar.', 'Delmas',
  extensions.st_setsrid(extensions.st_makepoint(-72.3035, 18.5466), 4326)::extensions.geography, 600, 1,
  0.25, 0, 5, 1.25, false, 'Foto + datos del lugar (prueba sin GPS en sitio)', now(), now() + interval '14 days', 'ACTIVE')
on conflict (code) do nothing;

notify pgrst, 'reload schema';
