import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";
import { createBillingHandler } from "../functions/billing-payments/handler.ts";
import { MoncashProvider } from "../functions/billing-payments/providers/moncash.ts";
import { StripeProvider, verifyStripeSignature } from "../functions/billing-payments/providers/stripe.ts";
import { decimal2, fromMinor, toMinor } from "../functions/billing-payments/providers/types.ts";

const base = "https://fixture.invalid";
const fnUrl = base + "/functions/v1/billing-payments";
const userAuth = "Bearer header.payload.sig";
const invoiceId = "0e226dcb-aba0-4168-90c8-6f7f09241960";
const paymentId = "4594bde3-b8ab-47df-87d7-66eb113285c0";
const whsec = "whsec_fixture";

function sign(body, t = Math.floor(Date.now() / 1000)) {
  return `t=${t},v1=${createHmac("sha256", whsec).update(`${t}.${body}`).digest("hex")}`;
}

function fixture({ start = { status: 200, body: { payment_id: paymentId, order_id: "2026112600000001", amount: "3814.00", currency: "HTG", invoice_number: "FAC-2026-000001", description: "Plan Negocio" } }, moncashPayment = null, payments = [] } = {}) {
  const calls = [];
  const http = async (url, options = {}) => {
    const u = new URL(url);
    const body = options.body ? (String(options.body).startsWith("{") ? JSON.parse(options.body) : String(options.body)) : null;
    calls.push({ host: u.host, path: u.pathname, body, headers: options.headers ?? {} });
    if (u.pathname === "/auth/v1/user") return Response.json({ id: "70c04811-2765-4446-b7ed-b067bc4a0235" });
    if (u.pathname === "/rest/v1/rpc/start_invoice_payment") return Response.json(start.body, { status: start.status });
    if (u.pathname === "/rest/v1/rpc/record_invoice_payment") return Response.json("paid");
    if (u.pathname.startsWith("/rest/v1/rpc/")) return new Response(null, { status: 204 });
    if (u.pathname === "/rest/v1/invoice_payments") return Response.json(payments);
    if (u.pathname === "/Api/oauth/token") return Response.json({ access_token: "mc-token", expires_in: 59 });
    if (u.pathname === "/Api/v1/CreatePayment") return Response.json({ payment_token: { token: "tok123" }, status: 202, mode: "sandbox" }, { status: 202 });
    if (u.pathname === "/Api/v1/RetrieveOrderPayment" || u.pathname === "/Api/v1/RetrieveTransactionPayment") {
      return moncashPayment ? Response.json({ payment: moncashPayment, status: 200 }) : Response.json({ status: 404 }, { status: 404 });
    }
    if (u.host === "api.stripe.com" && u.pathname === "/v1/checkout/sessions") return Response.json({ id: "cs_test_1", url: "https://checkout.stripe.com/c/pay/cs_test_1" });
    throw new Error("Unexpected " + url);
  };
  const handler = createBillingHandler({
    url: base, publicKey: "pk", serviceKey: "sb_secret_fixture", functionUrl: fnUrl,
    moncash: new MoncashProvider({ clientId: "id", clientSecret: "secret", live: false }, http),
    stripe: new StripeProvider({ secretKey: "sk_test_x", webhookSecret: whsec }, http),
    stripeWebhookSecret: whsec,
  }, http);
  const call = (path, { method = "POST", body, headers = { authorization: userAuth } } = {}) =>
    handler(new Request(fnUrl + path, { method, headers, body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body) }));
  return { calls, call };
}

test("importes exactos sin coma flotante", () => {
  assert.equal(decimal2(29), "29.00");
  assert.equal(decimal2("0.1"), "0.10");
  assert.equal(toMinor("19.99"), 1999);
  assert.equal(fromMinor(2900), "29.00");
  assert.throws(() => decimal2("1e3"));
  assert.throws(() => decimal2(-1));
});

test("checkout MonCash: importe de la base, token y URL del gateway sandbox", async () => {
  const { calls, call } = fixture();
  const res = await call("/checkout", { body: { invoice_id: invoiceId, provider: "moncash" } });
  assert.equal(res.status, 200);
  const out = await res.json();
  assert.equal(out.url, "https://sandbox.moncashbutton.digicelgroup.com/Moncash-middleware/Payment/Redirect?token=tok123");
  const start = calls.find((c) => c.path === "/rest/v1/rpc/start_invoice_payment");
  assert.equal(start.headers.authorization, userAuth, "inicia con la sesión del cliente");
  const create = calls.find((c) => c.path === "/Api/v1/CreatePayment");
  assert.deepEqual(create.body, { amount: 3814, orderId: "2026112600000001" });
  const attach = calls.find((c) => c.path === "/rest/v1/rpc/attach_payment_checkout");
  assert.equal(attach.headers.apikey, "sb_secret_fixture");
});

test("checkout sin sesión o con datos no válidos", async () => {
  const { call } = fixture();
  assert.equal((await call("/checkout", { body: { invoice_id: invoiceId, provider: "moncash" }, headers: {} })).status, 401);
  assert.equal((await call("/checkout", { body: { invoice_id: "x", provider: "moncash" } })).status, 400);
  assert.equal((await call("/checkout", { body: { invoice_id: invoiceId, provider: "paypal" } })).status, 400);
});

test("checkout Stripe: centavos exactos e idempotencia por orden", async () => {
  const { calls, call } = fixture({ start: { status: 200, body: { payment_id: paymentId, order_id: "2026112600000002", amount: "29.00", currency: "USD", invoice_number: "FAC-2026-000001", description: "Plan Negocio" } } });
  const res = await call("/checkout", { body: { invoice_id: invoiceId, provider: "stripe" } });
  assert.equal(res.status, 200);
  const create = calls.find((c) => c.host === "api.stripe.com");
  const form = new URLSearchParams(create.body);
  assert.equal(form.get("line_items[0][price_data][unit_amount]"), "2900");
  assert.equal(form.get("metadata[order_id]"), "2026112600000002");
  assert.equal(create.headers["idempotency-key"], "checkout-2026112600000002");
});

test("checkout rechazado por la base devuelve su mensaje", async () => {
  const { call } = fixture({ start: { status: 400, body: { message: "Esta factura ya no está pendiente" } } });
  const res = await call("/checkout", { body: { invoice_id: invoiceId, provider: "moncash" } });
  assert.equal(res.status, 400);
  assert.equal((await res.json()).message, "Esta factura ya no está pendiente");
});

test("webhook Stripe: firma obligatoria y monto en decimal", async () => {
  const event = JSON.stringify({ id: "evt_1", type: "checkout.session.completed", data: { object: { id: "cs_test_1", payment_status: "paid", amount_total: 2900, currency: "usd", metadata: { order_id: "2026112600000002" } } } });
  const { calls, call } = fixture();
  assert.equal((await call("/stripe/webhook", { body: event, headers: { "stripe-signature": "t=1,v1=00" } })).status, 400);
  assert.equal((await call("/stripe/webhook", { body: event, headers: { "stripe-signature": sign(event, Math.floor(Date.now() / 1000) - 3600) } })).status, 400);
  const ok = await call("/stripe/webhook", { body: event, headers: { "stripe-signature": sign(event) } });
  assert.equal(ok.status, 200);
  const record = calls.find((c) => c.path === "/rest/v1/rpc/record_invoice_payment");
  assert.equal(record.body.p_amount, "29.00");
  assert.equal(record.body.p_currency, "USD");
  assert.equal(record.body.p_event_id, "evt_1");
  assert.equal(record.body.p_order_id, "2026112600000002");
});

test("retorno MonCash consulta la transacción antes de registrar", async () => {
  const { calls, call } = fixture({ moncashPayment: { reference: "2026112600000001", transaction_id: "12874820", cost: 3814, message: "successful", payer: "50937007294" } });
  const res = await call("/moncash/return?transactionId=12874820", { method: "GET", headers: {} });
  assert.equal(res.status, 200);
  assert.match(await res.text(), /recibido/);
  assert.ok(calls.some((c) => c.path === "/Api/v1/RetrieveTransactionPayment" && c.body.transactionId === "12874820"));
  const record = calls.find((c) => c.path === "/rest/v1/rpc/record_invoice_payment");
  assert.equal(record.body.p_amount, "3814.00");
  assert.equal(record.body.p_event_id, "txn:12874820");
});

test("retorno MonCash sin pago confirmado no registra", async () => {
  const { calls, call } = fixture();
  const res = await call("/moncash/return?transactionId=999", { method: "GET", headers: {} });
  assert.match(await res.text(), /confirmando/);
  assert.ok(!calls.some((c) => c.path === "/rest/v1/rpc/record_invoice_payment"));
});

test("verificar consulta al proveedor con la orden del intento", async () => {
  const { calls, call } = fixture({
    payments: [{ provider: "moncash", order_id: "2026112600000001", provider_ref: null, status: "CREATED" }],
    moncashPayment: { reference: "2026112600000001", transaction_id: "1", cost: "3814", message: "successful", payer: "509" },
  });
  const res = await call("/verify", { body: { payment_id: paymentId } });
  assert.equal(res.status, 200);
  assert.ok(calls.some((c) => c.path === "/Api/v1/RetrieveOrderPayment" && c.body.orderId === "2026112600000001"));
  assert.ok(calls.some((c) => c.path === "/rest/v1/rpc/record_invoice_payment"));
});

test("firma Stripe acepta varias v1", async () => {
  const body = "{}";
  const t = Math.floor(Date.now() / 1000);
  const good = createHmac("sha256", whsec).update(`${t}.${body}`).digest("hex");
  assert.equal(await verifyStripeSignature(body, `t=${t},v1=${"0".repeat(64)},v1=${good}`, whsec), true);
  assert.equal(await verifyStripeSignature(body, `t=${t},v1=${good}`, "otro"), false);
});
