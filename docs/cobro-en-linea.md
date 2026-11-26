# Cobro en línea de planes

Las empresas y los desarrolladores pagan la factura de su plan desde **Planes y facturación** en la app.
Al confirmarse el cobro, la factura queda **Pagada** y el plan se **activa solo**. El panel admin muestra cada intento en **Facturación → Pagos en línea**.

## Procesador elegido

| Opción | ¿Sirve a una empresa en Haití? | Uso aquí |
| --- | --- | --- |
| **MonCash Business** (Digicel) | Sí. Es la billetera móvil que usan los clientes en Haití y cobra en gourdes (HTG). Tiene API REST con entorno sandbox. | **Principal** |
| **Stripe Checkout** | Solo si Nexovax tiene una entidad en un país admitido por Stripe (por ejemplo, una LLC en EE. UU.). Stripe no abre cuentas para empresas con sede en Haití. | Opcional, tarjetas en USD |
| PayPal | Las cuentas de Haití solo pueden **enviar** dinero, no recibirlo. | No |
| NatCash (Natcom), AZUL, CardNET | Posibles más adelante. | Se agregan implementando `PaymentProvider` |

El código está detrás de una interfaz (`supabase/functions/billing-payments/providers/types.ts`). Para sumar un procesador:
implementa `createCheckout` y `lookup`, regístralo en `index.ts` y añade su código al `check` de `invoice_payments.provider`.

## Cómo funciona

1. Elegir un plan de pago (`request_plan`) crea la suscripción **Solicitada** y su factura **Pendiente** del primer mes.
2. La app llama a `billing-payments/checkout`. La base de datos fija el importe (`start_invoice_payment`):
   USD para tarjeta; para MonCash, el monto en USD × la tasa de **Configuración**, redondeado a gourdes enteras. La tasa queda guardada en el intento.
3. El cliente paga en la página del procesador.
4. La confirmación llega por:
   - **Stripe**: webhook firmado (`Stripe-Signature`, HMAC-SHA256, 5 minutos de tolerancia).
   - **MonCash**: la URL de retorno trae `transactionId`. Como MonCash no firma sus avisos, la función **consulta** `RetrieveTransactionPayment` con nuestras credenciales antes de registrar nada.
   - **Verificar pago** en la app (al volver del navegador se hace solo): consulta al procesador por la orden.
5. `record_invoice_payment` (solo con la clave de servicio) compara **monto y moneda exactos**, marca la factura pagada y activa el plan.
   Es idempotente: el mismo evento o una confirmación repetida no cambian nada. Si el procesador cobra una factura que ya estaba pagada o anulada, el intento queda en **Devolver**.

Los pagos por transferencia o efectivo se siguen marcando a mano en **Facturación → Facturas → Pagada**, y eso también activa el plan.

## Puesta en marcha (sandbox)

1. **SQL**: pega `supabase/migrations/20261126210000_cobro_en_linea.sql` en el SQL Editor de Supabase.
2. **Secretos** de la función (Edge Functions → Secrets):
   - `MONCASH_CLIENT_ID`, `MONCASH_CLIENT_SECRET` (portal MonCash Business sandbox) y `MONCASH_MODE=sandbox`.
   - Opcional: `STRIPE_SECRET_KEY` (`sk_test_…`) y `STRIPE_WEBHOOK_SECRET` (`whsec_…`).
3. **Desplegar** sin verificación JWT en la puerta de enlace (los webhooks no traen sesión; `/checkout` y `/verify` validan la sesión ellos mismos):
   `supabase functions deploy billing-payments --no-verify-jwt`
4. **MonCash Business**: en el portal, la URL de retorno es
   `https://<proyecto>.supabase.co/functions/v1/billing-payments/moncash/return`
5. **Stripe** (si aplica): Developers → Webhooks → endpoint
   `https://<proyecto>.supabase.co/functions/v1/billing-payments/stripe/webhook` con los eventos
   `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed` y `checkout.session.expired`.
6. **Panel admin → Configuración → Cobro en línea de planes**: ajusta la tasa HTG por USD y activa MonCash (y Stripe si lo configuraste).
7. **App**: `flutter pub get` (se agregó `url_launcher`) y compila.

Para pasar a producción: credenciales live de MonCash con `MONCASH_MODE=live`, claves `sk_live_…` de Stripe y un webhook live.

## Pruebas

- `node --test supabase/tests/billing_payments.test.mjs`: función Edge (importes, firma de Stripe, consulta a MonCash).
- `supabase/tests/prueba_cobro_en_linea.sql` (lo ejecuta `run-local.sh`): permisos, importes, monto distinto, idempotencia, devoluciones y activación del plan.
