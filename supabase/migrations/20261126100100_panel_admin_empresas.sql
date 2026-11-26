-- Panel administrativo: revisión de documentos de empresa, activación de planes y emisión de facturas.
-- Requiere 20261126000020_paneles_empresa_desarrollador.sql (tablas organization_documents, billing_*, invoices).

-- ---------------------------------------------------------------------------
-- Documentos de verificación de empresa
-- ---------------------------------------------------------------------------
create or replace function public.review_organization_document(p_id uuid, p_decision public.review_status, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_org uuid;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_decision = 'REJECTED' and coalesce(trim(p_reason), '') = '' then raise exception 'Indica el motivo'; end if;
  select org_id into v_org from public.organization_documents where id = p_id;
  if v_org is null then raise exception 'Documento no encontrado'; end if;
  if public.is_org_member(v_org) then raise exception 'No puedes revisar tu propia empresa' using errcode = '42501'; end if;
  update public.organization_documents set status = p_decision, review_reason = p_reason where id = p_id;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'review_org_document', p_id, jsonb_build_object('org_id', v_org, 'decision', p_decision, 'reason', p_reason));
end;
$$;
revoke all on function public.review_organization_document(uuid, public.review_status, text) from public, anon;
grant execute on function public.review_organization_document(uuid, public.review_status, text) to authenticated;

create or replace view public.organization_documents_view with (security_invoker = true) as
select d.*, o.name as org_name
from public.organization_documents d join public.organizations o on o.id = d.org_id;
grant select on public.organization_documents_view to authenticated;

-- ---------------------------------------------------------------------------
-- Suscripciones: el equipo confirma el pago y activa (o cancela) el plan.
-- Al activar un plan de desarrollador, la cuota diaria de sus proyectos pasa a la del plan.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_subscription(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.billing_subscriptions; pl public.billing_plans;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_status not in ('ACTIVE', 'CANCELLED') then raise exception 'Estado no válido'; end if;
  select * into s from public.billing_subscriptions where id = p_id for update;
  if not found then raise exception 'Suscripción no encontrada'; end if;
  if s.owner_id = auth.uid() then raise exception 'No puedes activar tu propio plan' using errcode = '42501'; end if;
  select * into pl from public.billing_plans where code = s.plan_code;

  if p_status = 'ACTIVE' then
    -- Un solo plan activo por titular.
    update public.billing_subscriptions set status = 'CANCELLED'
     where id <> s.id and status = 'ACTIVE' and audience = s.audience
       and ((s.org_id is null and org_id is null and owner_id = s.owner_id) or (s.org_id is not null and org_id = s.org_id));
    update public.billing_subscriptions set status = 'ACTIVE', started_at = coalesce(started_at, now()) where id = s.id;
    if s.audience = 'developer' and pl.daily_quota is not null then
      update public.api_projects set daily_quota = pl.daily_quota where owner_id = s.owner_id;
    end if;
  else
    update public.billing_subscriptions set status = 'CANCELLED' where id = s.id;
  end if;

  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'set_subscription', s.id, jsonb_build_object('plan', s.plan_code, 'status', p_status));
end;
$$;
revoke all on function public.admin_set_subscription(uuid, text) from public, anon;
grant execute on function public.admin_set_subscription(uuid, text) to authenticated;

create or replace view public.billing_subscriptions_view with (security_invoker = true) as
select s.*, pl.name as plan_name, pl.price_usd_month, pl.daily_quota, o.name as org_name,
       coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as owner_name
from public.billing_subscriptions s
join public.billing_plans pl on pl.code = s.plan_code
left join public.organizations o on o.id = s.org_id
left join public.profiles p on p.id = s.owner_id;
grant select on public.billing_subscriptions_view to authenticated;

-- ---------------------------------------------------------------------------
-- Facturas: numeración correlativa FAC-AAAA-000001.
-- ---------------------------------------------------------------------------
create sequence if not exists public.invoice_number_seq;

create or replace function public.admin_create_invoice(
  p_audience text, p_org uuid, p_owner uuid, p_plan text, p_description text,
  p_amount numeric, p_period_start date default null, p_period_end date default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_number text; v_owner uuid := p_owner;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_audience not in ('company', 'developer') then raise exception 'Tipo de cliente no válido'; end if;
  if p_amount is null or p_amount < 0 or p_amount <> round(p_amount, 2) then raise exception 'Monto no válido'; end if;
  if coalesce(trim(p_description), '') = '' then raise exception 'Indica el concepto'; end if;
  if p_audience = 'company' then
    if p_org is null then raise exception 'Elige la empresa'; end if;
    if v_owner is null then select created_by into v_owner from public.organizations where id = p_org; end if;
  elsif v_owner is null then
    raise exception 'Elige el desarrollador';
  end if;
  v_number := 'FAC-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.invoice_number_seq')::text, 6, '0');
  insert into public.invoices (number, audience, org_id, owner_id, plan_code, description, period_start, period_end, amount_usd)
  values (v_number, p_audience, case when p_audience = 'company' then p_org end, v_owner, p_plan, trim(p_description),
          p_period_start, p_period_end, p_amount);
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'create_invoice', null, jsonb_build_object('code', v_number, 'amount_usd', p_amount, 'org_id', p_org, 'owner_id', v_owner));
  return v_number;
end;
$$;
revoke all on function public.admin_create_invoice(text, uuid, uuid, text, text, numeric, date, date) from public, anon;
grant execute on function public.admin_create_invoice(text, uuid, uuid, text, text, numeric, date, date) to authenticated;

create or replace function public.admin_set_invoice_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_number text;
begin
  if not public.has_role('admin') then raise exception 'Solo administradores' using errcode = '42501'; end if;
  if p_status not in ('PAID', 'VOID') then raise exception 'Estado no válido'; end if;
  update public.invoices set status = p_status, paid_at = case when p_status = 'PAID' then now() end
   where id = p_id and status = 'PENDING'
  returning number into v_number;
  if v_number is null then raise exception 'Solo se cambian facturas pendientes'; end if;
  insert into public.admin_actions (actor_id, action, subject_id, details)
  values (auth.uid(), 'invoice_status', p_id, jsonb_build_object('code', v_number, 'status', p_status));
end;
$$;
revoke all on function public.admin_set_invoice_status(uuid, text) from public, anon;
grant execute on function public.admin_set_invoice_status(uuid, text) to authenticated;

create or replace view public.invoices_view with (security_invoker = true) as
select i.*, o.name as org_name, pl.name as plan_name,
       coalesce(nullif(p.full_name, ''), trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))) as owner_name
from public.invoices i
left join public.organizations o on o.id = i.org_id
left join public.billing_plans pl on pl.code = i.plan_code
left join public.profiles p on p.id = i.owner_id;
grant select on public.invoices_view to authenticated;

-- Planes: el admin puede ajustar precios y activar/desactivar desde el panel.
drop policy if exists "planes: admin gestiona" on public.billing_plans;
create policy "planes: admin gestiona" on public.billing_plans for update using (public.has_role('admin')) with check (public.has_role('admin'));
grant update (name, price_usd_month, daily_quota, features, active) on public.billing_plans to authenticated;

notify pgrst, 'reload schema';
