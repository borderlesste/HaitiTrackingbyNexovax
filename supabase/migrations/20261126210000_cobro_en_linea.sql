-- Cobro en línea de facturas de planes (empresa y desarrollador).
-- Requiere 20261126000020_paneles_empresa_desarrollador.sql y 20261126100100_panel_admin_empresas.sql.
--
-- Flujo:
--   1. request_plan (plan de pago) crea la suscripción REQUESTED y su factura PENDING.
--   2. La app llama a la función Edge billing-payments/checkout, que usa start_invoice_payment
--      (con la sesión del cliente) y abre la página del proveedor (MonCash o Stripe).
--   3. El proveedor confirma (webhook firmado de Stripe, o consulta servidor a servidor a MonCash).
--      La función llama a record_invoice_payment con la clave de servicio: compara el monto exacto,
--      marca la factura PAID y activa la suscripción. Repetir la confirmación no tiene efecto.

-- ---------------------------------------------------------------------------
-- Ajustes (sin secretos: las credenciales viven en los secretos de la función Edge).
-- ---------------------------------------------------------------------------
insert into public.platform_settings (key, value)
values ('payments', '{"usd_htg_rate": 131, "providers": {"moncash": false, "stripe": false}}')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Factura ligada a la suscripción que la originó.
-- ---------------------------------------------------------------------------
alter table public.invoices add column if not exists subscription_id uuid references public.billing_subscriptions (id) on delete set null;
create index if not exists invoices_subscription_idx on public.invoices (subscription_id);

-- Los clientes solo leen; todo cambio pasa por RPC.
revoke insert, update, delete on public.invoices, public.billing_subscriptions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Intentos de pago
-- ---------------------------------------------------------------------------
create sequence if not exists public.payment_order_seq;

create table if not exists public.invoice_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices (id) on delete cascade,
  provider text not null check (provider in ('moncash', 'stripe')),
  -- CREATED: esperando al cliente · PAID: aplicado a la factura · FAILED/EXPIRED: sin cobro
  -- REFUND_DUE: el proveedor cobró pero la factura ya estaba pagada o anulada (devolver).
  status text not null default 'CREATED' check (status in ('CREATED', 'PAID', 'FAILED', 'EXPIRED', 'REFUND_DUE')),
  order_id text not null unique,
  amount numeric(12, 2) not null check (amount > 0),
  currency text not null check (currency in ('HTG', 'USD')),
  usd_htg_rate numeric(12, 4),
  provider_ref text,
  checkout_url text,
  payer text,
  error text,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  unique (provider, provider_ref)
);
create index if not exists invoice_payments_invoice_idx on public.invoice_payments (invoice_id, created_at desc);
create unique index if not exists invoice_payments_one_paid on public.invoice_payments (invoice_id) where status = 'PAID';

alter table public.invoice_payments enable row level security;
drop policy if exists "pagos: titular y admin leen" on public.invoice_payments;
create policy "pagos: titular y admin leen" on public.invoice_payments for select using (
  exists (
    select 1 from public.invoices i
    where i.id = invoice_id
      and ((i.org_id is null and i.owner_id = (select auth.uid()))
           or (i.org_id is not null and public.is_org_member(i.org_id))
           or public.has_role('admin'))
  )
);
revoke all on public.invoice_payments from public, anon, authenticated;
grant select (id, invoice_id, provider, status, order_id, amount, currency, usd_htg_rate, provider_ref, payer, error, created_at, paid_at)
  on public.invoice_payments to authenticated;

-- Notificaciones recibidas de los proveedores (auditoría y deduplicación).
create table if not exists public.payment_events (
  provider text not null,
  event_id text not null,
  order_id text,
  result text,
  payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  primary key (provider, event_id)
);
alter table public.payment_events enable row level security;
revoke all on public.payment_events from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Activación de suscripción (compartida por el pago en línea y el panel).
-- ---------------------------------------------------------------------------
create or replace function public.activate_subscription_internal(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.billing_subscriptions; pl public.billing_plans;
begin
  select * into s from public.billing_subscriptions where id = p_id for update;
  if not found then raise exception 'Suscripción no encontrada'; end if;
  if s.status = 'ACTIVE' then return; end if;
  select * into pl from public.billing_plans where code = s.plan_code;
  update public.billing_subscriptions set status = 'CANCELLED'
   where id <> s.id and status = 'ACTIVE' and audience = s.audience
     and ((s.org_id is null and org_id is null and owner_id = s.owner_id) or (s.org_id is not null and org_id = s.org_id));
  update public.billing_subscriptions set status = 'ACTIVE', started_at = coalesce(started_at, now()) where id = s.id;
  if s.audience = 'developer' and pl.daily_quota is not null then
    update public.api_projects set daily_quota = pl.daily_quota where owner_id = s.owner_id;
  end if;
end;
$$;
revoke all on function public.activate_subscription_internal(uuid) from public, anon, authenticated;

create or replace function public.admin_set_subscription(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.billing_subscriptions;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_status not in ('ACTIVE', 'CANCELLED') then raise exception 'Estado no válido'; end if;
  select * into s from public.billing_subscriptions where id = p_id for update;
  if not found then raise exception 'Suscripción no encontrada'; end if;
  if s.owner_id = auth.uid() then raise exception 'No puedes activar tu propio plan' using errcode = '42501'; end if;
  if p_status = 'ACTIVE' then
    perform public.activate_subscription_internal(s.id);
  else
    update public.billing_subscriptions set status = 'CANCELLED' where id = s.id;
    update public.invoices set status = 'VOID' where subscription_id = s.id and status = 'PENDING';
  end if;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'set_subscription', s.id, jsonb_build_object('plan', s.plan_code, 'status', p_status));
end;
$$;
revoke all on function public.admin_set_subscription(uuid, text) from public, anon;
grant execute on function public.admin_set_subscription(uuid, text) to authenticated;

-- Marcar pagada a mano (transferencia o efectivo) también activa el plan de esa factura.
create or replace function public.admin_set_invoice_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_number text; v_sub uuid;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_status not in ('PAID', 'VOID') then raise exception 'Estado no válido'; end if;
  update public.invoices set status = p_status, paid_at = case when p_status = 'PAID' then now() end
   where id = p_id and status = 'PENDING'
  returning number, subscription_id into v_number, v_sub;
  if v_number is null then raise exception 'Solo se cambian facturas pendientes'; end if;
  update public.invoice_payments set status = 'EXPIRED' where invoice_id = p_id and status = 'CREATED';
  if p_status = 'PAID' and v_sub is not null then
    perform public.activate_subscription_internal(v_sub);
  end if;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'invoice_status', p_id, jsonb_build_object('code', v_number, 'status', p_status));
end;
$$;
revoke all on function public.admin_set_invoice_status(uuid, text) from public, anon;
grant execute on function public.admin_set_invoice_status(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Solicitar un plan: el gratuito se activa al momento; el de pago genera su factura para pagar en línea.
-- ---------------------------------------------------------------------------
create or replace function public.request_plan(p_plan text, p_org uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare pl public.billing_plans; v_id uuid; v_owner uuid := auth.uid();
begin
  if v_owner is null then raise exception 'Sesión requerida' using errcode = '42501'; end if;
  select * into pl from public.billing_plans where code = p_plan and active;
  if not found then raise exception 'Plan no disponible'; end if;
  if pl.audience = 'company' then
    if p_org is null or not public.is_org_member(p_org) then raise exception 'Empresa no encontrada' using errcode = '42501'; end if;
  else
    p_org := null;
  end if;

  -- Solicitudes anteriores sin pagar: se cancelan junto con su factura pendiente.
  with old as (
    update public.billing_subscriptions set status = 'CANCELLED'
     where status = 'REQUESTED' and audience = pl.audience
       and ((p_org is null and org_id is null and owner_id = v_owner) or org_id = p_org)
    returning id
  )
  update public.invoices set status = 'VOID' where subscription_id in (select id from old) and status = 'PENDING';

  insert into public.billing_subscriptions (audience, org_id, owner_id, plan_code, status, started_at)
  values (pl.audience, p_org, v_owner, pl.code,
          case when pl.price_usd_month = 0 then 'ACTIVE' else 'REQUESTED' end,
          case when pl.price_usd_month = 0 then now() end)
  returning id into v_id;

  if pl.price_usd_month = 0 then
    update public.billing_subscriptions set status = 'CANCELLED'
     where id <> v_id and status = 'ACTIVE' and audience = pl.audience
       and ((p_org is null and org_id is null and owner_id = v_owner) or org_id = p_org);
  else
    insert into public.invoices (number, audience, org_id, owner_id, plan_code, subscription_id, description,
                                 period_start, period_end, amount_usd)
    values ('FAC-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.invoice_number_seq')::text, 6, '0'),
            pl.audience, p_org, v_owner, pl.code, v_id, 'Plan ' || pl.name || ' – primer mes',
            current_date, (current_date + interval '1 month' - interval '1 day')::date, pl.price_usd_month);
  end if;
  return v_id;
end;
$$;
revoke all on function public.request_plan(text, uuid) from public, anon;
grant execute on function public.request_plan(text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Iniciar un pago (lo llama la función Edge con la sesión del cliente).
-- El importe se fija aquí: USD para Stripe; HTG en gourdes enteras para MonCash, con la tasa guardada.
-- ---------------------------------------------------------------------------
create or replace function public.start_invoice_payment(p_invoice uuid, p_provider text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  inv public.invoices; cfg jsonb; v_rate numeric; v_amount numeric(12, 2); v_currency text; v_order text; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sesión requerida' using errcode = '42501'; end if;
  if p_provider not in ('moncash', 'stripe') then raise exception 'Método de pago no válido'; end if;
  select value into cfg from public.platform_settings where key = 'payments';
  if not coalesce((cfg -> 'providers' ->> p_provider)::boolean, false) then
    raise exception 'Este método de pago no está disponible';
  end if;

  select * into inv from public.invoices where id = p_invoice for update;
  if not found or not ((inv.org_id is null and inv.owner_id = auth.uid()) or (inv.org_id is not null and public.is_org_member(inv.org_id))) then
    raise exception 'Factura no encontrada' using errcode = '42501';
  end if;
  if inv.status <> 'PENDING' then raise exception 'Esta factura ya no está pendiente'; end if;
  if inv.amount_usd <= 0 then raise exception 'Esta factura no requiere pago'; end if;
  if (select count(*) from public.invoice_payments where invoice_id = inv.id and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Demasiados intentos. Espera unos minutos.';
  end if;

  if p_provider = 'moncash' then
    v_rate := (cfg ->> 'usd_htg_rate')::numeric;
    if v_rate is null or v_rate <= 0 then raise exception 'Tasa de cambio no configurada'; end if;
    v_amount := round(inv.amount_usd * v_rate, 0);
    v_currency := 'HTG';
  else
    v_amount := inv.amount_usd;
    v_currency := 'USD';
  end if;

  -- Los intentos anteriores quedan vencidos; si el proveedor los confirma igual, se registran como REFUND_DUE.
  update public.invoice_payments set status = 'EXPIRED' where invoice_id = inv.id and status = 'CREATED';

  v_order := to_char(now(), 'YYYYMMDD') || lpad(nextval('public.payment_order_seq')::text, 8, '0');
  insert into public.invoice_payments (invoice_id, provider, order_id, amount, currency, usd_htg_rate, created_by)
  values (inv.id, p_provider, v_order, v_amount, v_currency, v_rate, auth.uid())
  returning id into v_id;

  return jsonb_build_object('payment_id', v_id, 'order_id', v_order, 'amount', v_amount::text,
                            'currency', v_currency, 'invoice_number', inv.number, 'description', inv.description);
end;
$$;
revoke all on function public.start_invoice_payment(uuid, text) from public, anon;
grant execute on function public.start_invoice_payment(uuid, text) to authenticated;

-- Guarda la referencia y la URL de pago devueltas por el proveedor (solo la función Edge).
create or replace function public.attach_payment_checkout(p_payment uuid, p_provider_ref text, p_url text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.invoice_payments set provider_ref = coalesce(p_provider_ref, provider_ref), checkout_url = p_url
   where id = p_payment and status = 'CREATED';
end;
$$;
revoke all on function public.attach_payment_checkout(uuid, text, text) from public, anon, authenticated;
grant execute on function public.attach_payment_checkout(uuid, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- Confirmación del proveedor (solo la función Edge, con la clave de servicio). Idempotente.
-- Devuelve: paid | already_paid | refund_due | amount_mismatch | unknown_order | duplicate_event
-- ---------------------------------------------------------------------------
create or replace function public.record_invoice_payment(
  p_provider text, p_order_id text, p_provider_ref text, p_amount numeric, p_currency text,
  p_payer text default null, p_event_id text default null, p_payload jsonb default '{}'::jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare pay public.invoice_payments; inv public.invoices; v_result text; v_rows int;
begin
  if p_event_id is not null then
    insert into public.payment_events (provider, event_id, order_id, payload)
    values (p_provider, p_event_id, p_order_id, coalesce(p_payload, '{}'::jsonb))
    on conflict do nothing;
    get diagnostics v_rows = row_count;
    if v_rows = 0 then return 'duplicate_event'; end if;
  end if;

  select * into pay from public.invoice_payments where order_id = p_order_id and provider = p_provider for update;
  if not found then
    v_result := 'unknown_order';
  elsif pay.status in ('PAID', 'REFUND_DUE') then
    v_result := 'already_paid';
  elsif p_amount is distinct from pay.amount or upper(p_currency) is distinct from pay.currency then
    update public.invoice_payments
       set status = 'FAILED', error = format('Monto recibido %s %s, esperado %s %s', p_amount, upper(p_currency), pay.amount, pay.currency)
     where id = pay.id;
    v_result := 'amount_mismatch';
  else
    select * into inv from public.invoices where id = pay.invoice_id for update;
    if inv.status = 'PENDING' then
      update public.invoices set status = 'PAID', paid_at = now() where id = inv.id;
      update public.invoice_payments set status = 'PAID', paid_at = now(), provider_ref = coalesce(p_provider_ref, provider_ref),
             payer = p_payer, error = null
       where id = pay.id;
      update public.invoice_payments set status = 'EXPIRED' where invoice_id = inv.id and status = 'CREATED' and id <> pay.id;
      if inv.subscription_id is not null then
        perform public.activate_subscription_internal(inv.subscription_id);
      end if;
      v_result := 'paid';
    else
      update public.invoice_payments set status = 'REFUND_DUE', paid_at = now(), provider_ref = coalesce(p_provider_ref, provider_ref),
             payer = p_payer, error = 'La factura ya estaba ' || case inv.status when 'PAID' then 'pagada' else 'anulada' end
       where id = pay.id;
      v_result := 'refund_due';
    end if;
  end if;

  if p_event_id is not null then
    update public.payment_events set result = v_result where provider = p_provider and event_id = p_event_id;
  end if;
  return v_result;
end;
$$;
revoke all on function public.record_invoice_payment(text, text, text, numeric, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.record_invoice_payment(text, text, text, numeric, text, text, text, jsonb) to service_role;

-- Pago rechazado o vencido en el proveedor.
create or replace function public.fail_invoice_payment(p_provider text, p_order_id text, p_status text, p_error text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_status not in ('FAILED', 'EXPIRED') then raise exception 'Estado no válido'; end if;
  update public.invoice_payments set status = p_status, error = p_error
   where order_id = p_order_id and provider = p_provider and status = 'CREATED';
end;
$$;
revoke all on function public.fail_invoice_payment(text, text, text, text) from public, anon, authenticated;
grant execute on function public.fail_invoice_payment(text, text, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- Vistas del panel
-- ---------------------------------------------------------------------------
drop view if exists public.invoices_view;
create view public.invoices_view with (security_invoker = true) as
select i.*, o.name as org_name, pl.name as plan_name,
       coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as owner_name,
       lp.provider as last_payment_provider, lp.status as last_payment_status
from public.invoices i
left join public.organizations o on o.id = i.org_id
left join public.billing_plans pl on pl.code = i.plan_code
left join public.profiles p on p.id = i.owner_id
left join lateral (
  select ip.provider, ip.status from public.invoice_payments ip where ip.invoice_id = i.id order by ip.created_at desc limit 1
) lp on true;
revoke all on public.invoices_view from public, anon;
grant select on public.invoices_view to authenticated;

create or replace view public.invoice_payments_view with (security_invoker = true) as
select ip.id, ip.invoice_id, ip.provider, ip.status, ip.order_id, ip.amount, ip.currency, ip.usd_htg_rate,
       ip.provider_ref, ip.payer, ip.error, ip.created_at, ip.paid_at,
       i.number as invoice_number, i.amount_usd, i.audience, o.name as org_name,
       coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as owner_name
from public.invoice_payments ip
join public.invoices i on i.id = ip.invoice_id
left join public.organizations o on o.id = i.org_id
left join public.profiles p on p.id = i.owner_id;
revoke all on public.invoice_payments_view from public, anon;
grant select on public.invoice_payments_view to authenticated;

notify pgrst, 'reload schema';
