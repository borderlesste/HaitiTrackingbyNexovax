-- Moderación: aprobar/rechazar aportes, publicar el lugar y asentar recompensas (idempotente).

-- Un bono de misión se paga una sola vez por persona y misión.
create unique index if not exists reward_events_once_bonus
  on public.reward_events (user_id, mission_id) where kind = 'MISSION_BONUS';

-- Bitácora de acciones administrativas (solo inserción; nadie la edita).
create table if not exists public.admin_actions (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users (id),
  action text not null,
  subject_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.admin_actions enable row level security;
create policy "admin lee bitácora" on public.admin_actions for select using (public.has_role('admin'));
grant select on public.admin_actions to authenticated;

create or replace function public.review_contribution(p_contribution_id uuid, p_decision public.contribution_status, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c public.mission_contributions;
  m public.missions;
  v_place_id uuid;
  v_approved int;
  v_reward numeric := 0;
  v_bonus numeric := 0;
begin
  if not (public.has_role('moderator') or public.has_role('admin')) then
    raise exception 'Solo moderadores pueden revisar aportes' using errcode = '42501';
  end if;
  if p_decision not in ('APPROVED', 'REJECTED', 'NEEDS_CHANGES') then
    raise exception 'Decisión no válida: %', p_decision;
  end if;
  if p_decision <> 'APPROVED' and coalesce(trim(p_reason), '') = '' then
    raise exception 'Indica el motivo del rechazo o de la corrección';
  end if;

  select * into c from public.mission_contributions where id = p_contribution_id for update;
  if not found then raise exception 'Aporte no encontrado'; end if;
  if c.user_id = auth.uid() then raise exception 'No puedes revisar tu propio aporte' using errcode = '42501'; end if;
  if c.status = 'APPROVED' then
    return jsonb_build_object('status', c.status, 'place_id', c.place_id, 'already', true);
  end if;

  select * into m from public.missions where id = c.mission_id;

  if p_decision = 'APPROVED' then
    insert into public.places (name, category, commune, department, address_reference, location, accuracy_m, source_contribution_id)
    values (c.name, c.category, m.commune, m.department, c.address_reference, c.location, c.accuracy_m, c.id)
    returning id into v_place_id;

    -- Recompensa por aporte: una sola vez gracias al índice único.
    insert into public.reward_events (user_id, contribution_id, mission_id, kind, amount_usd, status, created_by)
    values (c.user_id, c.id, m.id, 'CONTRIBUTION', m.individual_reward_usd, 'EARNED', auth.uid())
    on conflict do nothing;
    v_reward := m.individual_reward_usd;

    update public.mission_contributions
       set status = 'APPROVED', place_id = v_place_id, review_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now()
     where id = c.id;

    -- Bono de misión al completar los aportes requeridos (solo si la misión lo define).
    if m.completion_bonus_usd > 0 then
      select count(*) into v_approved from public.mission_contributions
       where mission_id = m.id and user_id = c.user_id and status = 'APPROVED';
      if v_approved >= m.required_approved_contributions then
        insert into public.reward_events (user_id, mission_id, kind, amount_usd, status, reason, created_by)
        values (c.user_id, m.id, 'MISSION_BONUS', m.completion_bonus_usd, 'EARNED', 'Misión completada', auth.uid())
        on conflict do nothing;
        v_bonus := m.completion_bonus_usd;
      end if;
    end if;
  else
    update public.mission_contributions
       set status = p_decision, review_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now()
     where id = c.id;
  end if;

  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'review_contribution', c.id, jsonb_build_object('decision', p_decision, 'reason', p_reason));

  return jsonb_build_object('status', p_decision, 'place_id', v_place_id, 'reward_usd', v_reward, 'bonus_usd', v_bonus);
end;
$$;

revoke all on function public.review_contribution(uuid, public.contribution_status, text) from public, anon;
grant execute on function public.review_contribution(uuid, public.contribution_status, text) to authenticated;

-- Cola de revisión con datos que el panel necesita (solo moderadores/admin ven filas, por RLS).
create or replace view public.review_queue with (security_invoker = true) as
select c.id, c.created_at, c.status, c.name, c.category, c.address_reference, c.notes, c.accuracy_m, c.captured_at,
       c.photo_paths, c.review_reason, c.user_id, p.full_name as author_name,
       m.id as mission_id, m.code as mission_code, m.title as mission_title, m.individual_reward_usd,
       extensions.st_y(c.location::extensions.geometry) as lat, extensions.st_x(c.location::extensions.geometry) as lng,
       extensions.st_distance(c.location, m.center) as distance_to_mission_m
from public.mission_contributions c
join public.missions m on m.id = c.mission_id
left join public.profiles p on p.id = c.user_id;
grant select on public.review_queue to authenticated;

-- Vista de misiones para el panel (incluye coordenadas legibles).
create or replace view public.missions_admin with (security_invoker = true) as
select m.*, extensions.st_y(m.center::extensions.geometry) as lat, extensions.st_x(m.center::extensions.geometry) as lng,
       (select count(*) from public.mission_contributions c where c.mission_id = m.id) as contributions_count,
       (select count(*) from public.mission_contributions c where c.mission_id = m.id and c.status = 'APPROVED') as approved_count
from public.missions m;
grant select on public.missions_admin to authenticated;

-- Moderadores pueden leer perfiles de autores (ya cubierto por la política de perfiles).
notify pgrst, 'reload schema';
