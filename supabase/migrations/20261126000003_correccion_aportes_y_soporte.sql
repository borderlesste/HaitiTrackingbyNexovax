-- Pantallas del colaborador: corregir y reenviar aportes, y ayuda / soporte (incluye pedir borrar la cuenta).

-- 1) Corrección de aportes con "Requiere cambios" o "Rechazado".
alter table public.mission_contributions
  add column if not exists resubmit_count int not null default 0,
  add column if not exists previous_review_reason text;

create or replace function public.resubmit_contribution(
  p_id uuid,
  p_name text,
  p_category text,
  p_address_reference text,
  p_notes text,
  p_lat double precision default null,
  p_lng double precision default null,
  p_accuracy_m numeric default null,
  p_captured_at timestamptz default null,
  p_photo_paths text[] default null
)
returns public.mission_contributions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  c public.mission_contributions;
  p text;
begin
  if v_uid is null then
    raise exception 'Sesión no iniciada';
  end if;

  select * into c from public.mission_contributions where id = p_id for update;
  if not found or c.user_id <> v_uid then
    raise exception 'Aporte no encontrado';
  end if;
  if c.status not in ('NEEDS_CHANGES', 'REJECTED') then
    raise exception 'Este aporte no se puede corregir ahora';
  end if;
  if c.resubmit_count >= 3 then
    raise exception 'Ya corregiste este aporte 3 veces. Registra uno nuevo o escribe a soporte.';
  end if;
  if coalesce(length(trim(p_name)), 0) < 2 or coalesce(trim(p_category), '') = '' then
    raise exception 'Nombre y categoría son obligatorios';
  end if;
  if p_photo_paths is not null then
    if cardinality(p_photo_paths) = 0 then
      raise exception 'Hace falta al menos una foto';
    end if;
    foreach p in array p_photo_paths loop
      if p not like v_uid::text || '/%' then
        raise exception 'Foto no válida';
      end if;
    end loop;
  end if;
  if (p_lat is null) <> (p_lng is null) then
    raise exception 'Ubicación incompleta';
  end if;

  update public.mission_contributions set
    name = trim(p_name),
    category = trim(p_category),
    address_reference = nullif(trim(coalesce(p_address_reference, '')), ''),
    notes = nullif(trim(coalesce(p_notes, '')), ''),
    location = case when p_lat is null then location
                    else extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography end,
    accuracy_m = coalesce(p_accuracy_m, accuracy_m),
    captured_at = case when p_lat is null then captured_at else coalesce(p_captured_at, now()) end,
    photo_paths = coalesce(p_photo_paths, photo_paths),
    previous_review_reason = review_reason,
    review_reason = null,
    reviewed_by = null,
    reviewed_at = null,
    status = 'SUBMITTED',
    resubmit_count = resubmit_count + 1
  where id = p_id
  returning * into c;
  return c;
end;
$$;

revoke all on function public.resubmit_contribution(uuid, text, text, text, text, double precision, double precision, numeric, timestamptz, text[]) from public, anon;
grant execute on function public.resubmit_contribution(uuid, text, text, text, text, double precision, double precision, numeric, timestamptz, text[]) to authenticated;

-- 2) Ayuda y soporte: consultas, incidencias, reclamaciones y solicitudes de borrar la cuenta.
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('QUESTION', 'INCIDENT', 'CLAIM', 'ACCOUNT_DELETION')),
  subject text not null check (length(trim(subject)) between 3 and 120),
  message text not null check (length(trim(message)) between 5 and 2000),
  contribution_id uuid references public.mission_contributions (id) on delete set null,
  withdrawal_id uuid references public.withdrawal_requests (id) on delete set null,
  status text not null default 'OPEN' check (status in ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')),
  response text,
  responded_by uuid references auth.users (id),
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists support_tickets_user_idx on public.support_tickets (user_id, created_at desc);
create index if not exists support_tickets_open_idx on public.support_tickets (status, created_at) where status in ('OPEN', 'IN_PROGRESS');

alter table public.support_tickets enable row level security;

drop policy if exists "soporte: ver los propios" on public.support_tickets;
create policy "soporte: ver los propios" on public.support_tickets
  for select to authenticated
  using (user_id = (select auth.uid()) or public.has_role('admin'::public.app_role) or public.has_role('moderator'::public.app_role));

drop policy if exists "soporte: crear los propios" on public.support_tickets;
create policy "soporte: crear los propios" on public.support_tickets
  for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'OPEN' and response is null and responded_by is null);

drop policy if exists "soporte: el equipo responde" on public.support_tickets;
create policy "soporte: el equipo responde" on public.support_tickets
  for update to authenticated
  using (public.has_role('admin'::public.app_role) or public.has_role('moderator'::public.app_role))
  with check (public.has_role('admin'::public.app_role) or public.has_role('moderator'::public.app_role));

revoke delete on public.support_tickets from anon, authenticated;
revoke all on public.support_tickets from anon;
