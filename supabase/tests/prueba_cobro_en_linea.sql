-- PRUEBA del cobro en línea de planes (se deshace al final, no deja datos).
do $$
declare
  emp uuid := gen_random_uuid(); otro uuid := gen_random_uuid(); adm uuid := gen_random_uuid(); dev uuid := gen_random_uuid();
  org uuid; sub uuid; inv public.invoices; p1 jsonb; p2 jsonb; v text; r text := ''; n int; prj uuid;
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
    (emp, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'emp-pago@ejemplo.test', now(), now()),
    (otro, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'otro-pago@ejemplo.test', now(), now()),
    (adm, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm-pago@ejemplo.test', now(), now()),
    (dev, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dev-pago@ejemplo.test', now(), now());
  insert into public.account_roles (user_id, role) values (adm, 'admin');
  update public.platform_settings set value = '{"usd_htg_rate": 131.5, "providers": {"moncash": true, "stripe": true}}' where key = 'payments';

  perform set_config('request.jwt.claims', json_build_object('sub', emp, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  org := public.register_organization('Pagos Delmas SA', 'Comercio', 'Marie Joseph');

  -- 1. Plan de pago genera suscripción REQUESTED y factura PENDING ligada
  sub := public.request_plan('company_business', org);
  select * into inv from public.invoices where subscription_id = sub;
  r := r || ' | 1 factura del plan=' || coalesce(inv.status || ' ' || inv.amount_usd, 'NINGUNA');

  -- 2. El cliente no puede marcar su factura como pagada
  begin
    update public.invoices set status = 'PAID' where id = inv.id;
    get diagnostics n = row_count;
    r := r || ' | 2 cliente marca pagada=' || case when n = 0 then 'OK(0 filas)' else 'FALLO' end;
  exception when insufficient_privilege then r := r || ' | 2 cliente no marca pagada=OK';
  end;

  -- 3. Importe MonCash en gourdes enteras: 29 × 131.5 = 3813.5 → 3814
  p1 := public.start_invoice_payment(inv.id, 'moncash');
  r := r || ' | 3 moncash=' || (p1 ->> 'amount') || ' ' || (p1 ->> 'currency');

  -- 4. Nuevo intento con Stripe vence el anterior
  p2 := public.start_invoice_payment(inv.id, 'stripe');
  select count(*) into n from public.invoice_payments where id = (p1 ->> 'payment_id')::uuid and status = 'EXPIRED';
  r := r || ' | 4 stripe=' || (p2 ->> 'amount') || ' ' || (p2 ->> 'currency') || ' anterior vencido=' || n;

  -- 5. El cliente no puede confirmar pagos
  begin
    perform public.record_invoice_payment('stripe', p2 ->> 'order_id', 'cs_test', 29.00, 'usd');
    r := r || ' | 5 cliente confirma=FALLO';
  exception when insufficient_privilege then r := r || ' | 5 cliente no confirma=OK';
  end;

  -- 6. Otra cuenta no puede pagar ni ver la factura ajena
  perform set_config('request.jwt.claims', json_build_object('sub', otro, 'role', 'authenticated')::text, true);
  begin
    perform public.start_invoice_payment(inv.id, 'stripe');
    r := r || ' | 6 ajeno paga=FALLO';
  exception when insufficient_privilege then
    select count(*) into n from public.invoice_payments;
    r := r || ' | 6 ajeno rechazado, ve pagos=' || n;
  end;

  -- Proveedor (clave de servicio)
  execute 'reset role';
  execute 'set local role service_role';

  -- 7. Monto distinto no paga
  v := public.record_invoice_payment('stripe', p2 ->> 'order_id', 'cs_test', 28.99, 'usd', null, 'evt_1');
  r := r || ' | 7 monto distinto=' || v;

  -- reintento limpio
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', emp, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  p2 := public.start_invoice_payment(inv.id, 'stripe');
  execute 'reset role';
  execute 'set local role service_role';

  -- 8. Confirmación correcta: factura pagada y plan activo
  v := public.record_invoice_payment('stripe', p2 ->> 'order_id', 'cs_test_2', 29.00, 'usd', 'cliente@ejemplo.test', 'evt_2');
  execute 'reset role';
  select count(*) into n from public.invoices i join public.billing_subscriptions s on s.id = i.subscription_id
   where i.id = inv.id and i.status = 'PAID' and s.status = 'ACTIVE';
  r := r || ' | 8 ' || v || ' factura+plan activos=' || n;

  -- 9. Evento repetido y confirmación repetida sin efecto
  execute 'set local role service_role';
  v := public.record_invoice_payment('stripe', p2 ->> 'order_id', 'cs_test_2', 29.00, 'usd', null, 'evt_2');
  r := r || ' | 9 mismo evento=' || v;
  v := public.record_invoice_payment('stripe', p2 ->> 'order_id', 'cs_test_2', 29.00, 'usd', null, 'evt_3');
  r := r || ' / otro evento=' || v;

  -- 10. Intento vencido que el proveedor cobra igual: queda para devolución
  v := public.record_invoice_payment('moncash', p1 ->> 'order_id', '12874820', (p1 ->> 'amount')::numeric, 'HTG', '50937007294', 'mc_1');
  r := r || ' | 10 cobro tardío=' || v;
  v := public.record_invoice_payment('moncash', '000', null, 1, 'HTG', null, 'mc_2');
  r := r || ' | 10b orden desconocida=' || v;
  execute 'reset role';

  -- 11. Factura pagada no admite nuevos intentos
  perform set_config('request.jwt.claims', json_build_object('sub', emp, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.start_invoice_payment(inv.id, 'stripe');
    r := r || ' | 11 pagar dos veces=FALLO';
  exception when others then r := r || ' | 11 ya pagada rechaza=OK';
  end;
  select count(*) into n from public.invoice_payments where invoice_id = inv.id;
  r := r || ' | 12 empresa ve sus intentos=' || n;

  -- 13. Cambiar de plan solicitado anula la factura pendiente anterior
  sub := public.request_plan('company_enterprise', org);
  sub := public.request_plan('company_business', org);
  select count(*) into n from public.invoices where org_id = org and status = 'VOID';
  r := r || ' | 13 facturas anuladas al cambiar=' || n;

  -- 14. Método desactivado
  execute 'reset role';
  update public.platform_settings set value = jsonb_set(value, '{providers,stripe}', 'false') where key = 'payments';
  execute 'set local role authenticated';
  select * into inv from public.invoices where subscription_id = sub;
  begin
    perform public.start_invoice_payment(inv.id, 'stripe');
    r := r || ' | 14 método apagado=FALLO';
  exception when others then r := r || ' | 14 método apagado rechazado=OK';
  end;

  -- 15. Desarrollador: pago en línea sube la cuota del proyecto
  perform set_config('request.jwt.claims', json_build_object('sub', dev, 'role', 'authenticated')::text, true);
  prj := public.create_api_project('App Pagos', 'pruebas', true);
  sub := public.request_plan('dev_starter');
  select * into inv from public.invoices where subscription_id = sub;
  p1 := public.start_invoice_payment(inv.id, 'moncash');
  execute 'reset role';
  execute 'set local role service_role';
  v := public.record_invoice_payment('moncash', p1 ->> 'order_id', '555', (p1 ->> 'amount')::numeric, 'HTG', '50937000000', 'mc_3');
  execute 'reset role';
  select daily_quota into n from public.api_projects where id = prj;
  r := r || ' | 15 ' || v || ' ' || (p1 ->> 'amount') || ' HTG cuota=' || n;

  -- 16. Admin: marcar pagada a mano activa el plan
  perform set_config('request.jwt.claims', json_build_object('sub', emp, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  sub := public.request_plan('company_enterprise', org);
  select * into inv from public.invoices where subscription_id = sub;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform public.admin_set_invoice_status(inv.id, 'PAID');
  select count(*) into n from public.billing_subscriptions where id = sub and status = 'ACTIVE';
  r := r || ' | 16 pagada a mano activa plan=' || n;
  select count(*) into n from public.invoice_payments_view where status = 'REFUND_DUE';
  r := r || ' | 17 admin ve devoluciones=' || n;
  execute 'reset role';

  raise exception 'RESULTADOS%', r;
end $$;
