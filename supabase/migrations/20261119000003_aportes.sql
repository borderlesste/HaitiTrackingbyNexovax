-- Fase 3: aportes. La app necesita el radio de la misión y duplicados que incluyan aportes en revisión.

create extension if not exists pg_trgm with schema extensions;

drop function if exists public.missions_nearby(double precision, double precision, double precision);
create function public.missions_nearby(lat double precision, lng double precision, radius_km double precision default 25)
returns table (
  id uuid, code text, type public.mission_type, title text, description text, commune text,
  lat double precision, lng double precision, radius_m integer, individual_reward_usd numeric, completion_bonus_usd numeric,
  required_approved_contributions integer, requirements text, end_at timestamptz, distance_m double precision
)
language sql stable set search_path = '' as $$
  select m.id, m.code, m.type, m.title, m.description, m.commune,
         extensions.st_y(m.center::extensions.geometry), extensions.st_x(m.center::extensions.geometry), m.radius_m,
         m.individual_reward_usd, m.completion_bonus_usd, m.required_approved_contributions, m.requirements, m.end_at,
         extensions.st_distance(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography)
  from public.missions m
  where m.status = 'ACTIVE'
    and (m.end_at is null or m.end_at > now())
    and extensions.st_dwithin(m.center, extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography, radius_km * 1000)
  order by 15;
$$;
grant execute on function public.missions_nearby(double precision, double precision, double precision) to anon, authenticated;

-- Posibles duplicados: lugares aprobados + aportes pendientes de revisión (solo nombre y distancia, sin datos personales).
drop function if exists public.check_duplicates(double precision, double precision, text, double precision);
create function public.check_duplicates(lat double precision, lng double precision, place_name text, radius_m double precision default 60)
returns table (source text, code text, name text, category text, distance_m double precision, name_similarity real)
language sql stable security definer set search_path = '' as $$
  with pt as (select extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography as g)
  select * from (
    select 'place'::text, p.code, p.name, p.category,
           extensions.st_distance(p.location, pt.g), extensions.similarity(lower(p.name), lower(place_name))
    from public.places p, pt
    where p.visibility = 'PUBLIC' and extensions.st_dwithin(p.location, pt.g, radius_m)
    union all
    select 'pending'::text, null, c.name, c.category,
           extensions.st_distance(c.location, pt.g), extensions.similarity(lower(c.name), lower(place_name))
    from public.mission_contributions c, pt
    where c.status in ('SUBMITTED', 'AUTO_CHECKED', 'HUMAN_REVIEW')
      and extensions.st_dwithin(c.location, pt.g, radius_m)
  ) d (source, code, name, category, distance_m, name_similarity)
  order by name_similarity desc, distance_m
  limit 10;
$$;
grant execute on function public.check_duplicates(double precision, double precision, text, double precision) to authenticated;

notify pgrst, 'reload schema';
