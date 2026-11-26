-- Pantallas del colaborador: corregir y reenviar aportes con "Requiere cambios" o "Rechazado".

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
  v_restricted boolean := false;
begin
  if v_uid is null then
    raise exception 'Sesión no iniciada';
  end if;
  -- Cuentas restringidas desde el panel (si esa función ya existe).
  if to_regprocedure('public.is_restricted(uuid)') is not null then
    execute 'select public.is_restricted($1)' into v_restricted using v_uid;
    if v_restricted then
      raise exception 'Tu cuenta está restringida. Contacta con soporte.' using errcode = '42501';
    end if;
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

-- La tabla de Ayuda y soporte (support_tickets) la crea 20261126100000_panel_admin.sql; la app la usa tal cual.
