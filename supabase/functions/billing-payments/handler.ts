// Función Edge billing-payments: cobro en línea de facturas de planes.
//
//   POST /checkout         {invoice_id, provider}  (sesión del cliente) → {payment_id, url, amount, currency}
//   POST /verify           {payment_id}            (sesión del cliente) → {status}
//   POST /stripe/webhook   evento firmado de Stripe
//   GET  /stripe/return    página de regreso de Stripe Checkout
//   GET  /moncash/return   URL de retorno configurada en el portal MonCash Business (?transactionId=…)
//
// El importe y la moneda los fija la base de datos (start_invoice_payment). Una factura solo se marca
// pagada con la confirmación del proveedor consultada servidor a servidor o con un webhook firmado,
// y record_invoice_payment compara el monto exacto y es idempotente.
import type { MoncashProvider } from "./providers/moncash.ts";
import { sessionConfirmation, type StripeProvider, type StripeSession, verifyStripeSignature } from "./providers/stripe.ts";
import type { Confirmation, Fetch, PaymentProvider, ProviderId } from "./providers/types.ts";

export type BillingConfig = {
  url: string;
  publicKey: string;
  serviceKey: string;
  functionUrl: string;
  moncash?: MoncashProvider;
  stripe?: StripeProvider;
  stripeWebhookSecret?: string;
};

const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

function json(status: number, value: Record<string, unknown>) {
  return Response.json(value, { status, headers: { "cache-control": "no-store" } });
}

function page(status: number, text: string) {
  return new Response(text + "\n", { status, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
}

async function readBody(request: Request, limit: number): Promise<string> {
  const reader = request.body?.getReader();
  if (!reader) return "";
  const decoder = new TextDecoder();
  let length = 0;
  let body = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > limit) {
      await reader.cancel();
      throw new Error("too_large");
    }
    body += decoder.decode(value, { stream: true });
  }
  return body + decoder.decode();
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  const value = JSON.parse(await readBody(request, 2048) || "{}");
  return value && typeof value === "object" ? value : {};
}

export function createBillingHandler(config: BillingConfig, supabaseFetch: Fetch = fetch) {
  const base = config.url.replace(/\/$/, "");
  const providers: Partial<Record<ProviderId, PaymentProvider>> = { moncash: config.moncash, stripe: config.stripe };

  const supabase = (path: string, init: RequestInit) =>
    supabaseFetch(base + path, { ...init, redirect: "error", signal: AbortSignal.timeout(8000) });
  const serviceHeaders = {
    apikey: config.serviceKey,
    ...(config.serviceKey.startsWith("sb_secret_") ? {} : { authorization: "Bearer " + config.serviceKey }),
    "content-type": "application/json",
  };
  const userHeaders = (authorization: string) => ({ apikey: config.publicKey, authorization, "content-type": "application/json" });

  async function serviceRpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
    const res = await supabase("/rest/v1/rpc/" + name, { method: "POST", headers: serviceHeaders, body: JSON.stringify(args) });
    if (!res.ok) throw new Error(`rpc ${name} ${res.status}`);
    const text = await res.text();
    return (text ? JSON.parse(text) : null) as T;
  }

  async function sessionUser(request: Request): Promise<string | null> {
    const authorization = request.headers.get("authorization");
    if (!authorization?.match(/^Bearer [\w.-]+$/i)) return null;
    const res = await supabase("/auth/v1/user", { headers: userHeaders(authorization) });
    if (!res.ok) return null;
    const user = await res.json() as { id?: string; is_anonymous?: boolean };
    return user.id && uuid.test(user.id) && !user.is_anonymous ? authorization : null;
  }

  /** Aplica una confirmación del proveedor. Devuelve el resultado de record_invoice_payment. */
  async function apply(provider: ProviderId, c: Confirmation, eventId: string | null, payload: Record<string, unknown>) {
    if (c.status === "paid") {
      return await serviceRpc<string>("record_invoice_payment", {
        p_provider: provider, p_order_id: c.orderId, p_provider_ref: c.providerRef, p_amount: c.amount,
        p_currency: c.currency, p_payer: c.payer, p_event_id: eventId, p_payload: payload,
      });
    }
    if (c.status === "failed" || c.status === "expired") {
      await serviceRpc("fail_invoice_payment", {
        p_provider: provider, p_order_id: c.orderId, p_status: c.status === "failed" ? "FAILED" : "EXPIRED",
        p_error: c.status === "failed" ? "Rechazado por el proveedor" : "Venció sin pagar",
      });
    }
    return c.status;
  }

  async function checkout(request: Request) {
    const authorization = await sessionUser(request);
    if (!authorization) return json(401, { error: "session_required" });
    let body: Record<string, unknown>;
    try {
      body = await readJson(request);
    } catch {
      return json(400, { error: "invalid_input" });
    }
    const providerId = body.provider as ProviderId;
    const provider = providers[providerId];
    if (typeof body.invoice_id !== "string" || !uuid.test(body.invoice_id)) return json(400, { error: "invalid_input" });
    if (!provider) return json(400, { error: "provider_unavailable", message: "Este método de pago no está disponible." });

    const started = await supabase("/rest/v1/rpc/start_invoice_payment", {
      method: "POST",
      headers: userHeaders(authorization),
      body: JSON.stringify({ p_invoice: body.invoice_id, p_provider: providerId }),
    });
    if (!started.ok) {
      const err = await started.json().catch(() => ({})) as { message?: string };
      return json(started.status >= 500 ? 503 : 400, { error: "cannot_start", message: err.message ?? "No se pudo iniciar el pago." });
    }
    const p = await started.json() as { payment_id: string; order_id: string; amount: string; currency: "HTG" | "USD"; invoice_number: string; description: string };

    let url: string;
    try {
      const co = await provider.createCheckout({
        paymentId: p.payment_id, orderId: p.order_id, amount: p.amount, currency: p.currency,
        invoiceNumber: p.invoice_number, description: p.description, functionUrl: config.functionUrl,
      });
      url = co.url;
      await serviceRpc("attach_payment_checkout", { p_payment: p.payment_id, p_provider_ref: co.providerRef, p_url: co.url });
    } catch {
      await serviceRpc("fail_invoice_payment", { p_provider: providerId, p_order_id: p.order_id, p_status: "FAILED", p_error: "El proveedor no respondió" }).catch(() => {});
      return json(502, { error: "provider_error", message: "El procesador de pagos no respondió. Inténtalo de nuevo." });
    }
    return json(200, { payment_id: p.payment_id, url, amount: p.amount, currency: p.currency });
  }

  async function verify(request: Request) {
    const authorization = await sessionUser(request);
    if (!authorization) return json(401, { error: "session_required" });
    let body: Record<string, unknown>;
    try {
      body = await readJson(request);
    } catch {
      return json(400, { error: "invalid_input" });
    }
    if (typeof body.payment_id !== "string" || !uuid.test(body.payment_id)) return json(400, { error: "invalid_input" });
    // La lectura con la sesión del cliente respeta RLS: solo ve sus propios intentos.
    const read = () => supabase(`/rest/v1/invoice_payments?id=eq.${body.payment_id}&select=id,provider,order_id,provider_ref,status`, { headers: userHeaders(authorization) })
      .then((r) => r.ok ? r.json() as Promise<{ provider: ProviderId; order_id: string; provider_ref: string | null; status: string }[]> : []);
    const [pay] = await read();
    if (!pay) return json(404, { error: "not_found" });
    const provider = providers[pay.provider];
    if (provider && (pay.status === "CREATED" || pay.status === "EXPIRED")) {
      const c = await provider.lookup({ orderId: pay.order_id, providerRef: pay.provider_ref });
      if (c) await apply(pay.provider, c, null, { source: "verify" });
    }
    const [after] = await read();
    return json(200, { status: after?.status ?? pay.status });
  }

  async function stripeWebhook(request: Request) {
    if (!config.stripe || !config.stripeWebhookSecret) return json(404, { error: "not_configured" });
    let body: string;
    try {
      body = await readBody(request, 256 * 1024);
    } catch {
      return json(413, { error: "too_large" });
    }
    if (!await verifyStripeSignature(body, request.headers.get("stripe-signature"), config.stripeWebhookSecret)) {
      return json(400, { error: "bad_signature" });
    }
    const event = JSON.parse(body) as { id: string; type: string; data?: { object?: StripeSession } };
    const session = event.data?.object;
    const relevant = ["checkout.session.completed", "checkout.session.async_payment_succeeded", "checkout.session.async_payment_failed", "checkout.session.expired"];
    if (!session || !relevant.includes(event.type)) return json(200, { received: true });
    const c = sessionConfirmation(session, null);
    if (!c) return json(200, { received: true, ignored: true });
    if (event.type === "checkout.session.async_payment_failed") c.status = "failed";
    const result = await apply("stripe", c, event.id, { type: event.type, session: session.id, amount_total: session.amount_total, currency: session.currency });
    return json(200, { received: true, result });
  }

  async function stripeReturn(url: URL) {
    if (url.searchParams.has("cancelled")) return page(200, "Pago cancelado. Puedes volver a la aplicación Haiti Tracking.");
    const id = url.searchParams.get("session_id") ?? "";
    const session = config.stripe ? await config.stripe.lookupSession(id) : null;
    const c = session && sessionConfirmation(session, null);
    if (c) await apply("stripe", c, null, { source: "return" });
    return page(200, c?.status === "paid"
      ? "Pago recibido. Ya puedes volver a la aplicación Haiti Tracking."
      : "Estamos confirmando tu pago. Vuelve a la aplicación y pulsa «Verificar pago».");
  }

  async function moncashReturn(request: Request, url: URL) {
    if (!config.moncash) return json(404, { error: "not_configured" });
    let transactionId = url.searchParams.get("transactionId") ?? url.searchParams.get("transaction_id");
    if (!transactionId && request.method === "POST") {
      const raw = await readBody(request, 4096).catch(() => "");
      try {
        const obj = JSON.parse(raw) as Record<string, unknown>;
        transactionId = String(obj.transactionId ?? obj.transaction_id ?? "");
      } catch {
        transactionId = new URLSearchParams(raw).get("transactionId");
      }
    }
    if (!transactionId || !/^[0-9A-Za-z-]{1,40}$/.test(transactionId)) return page(400, "Falta la referencia de MonCash.");
    // El aviso no está firmado: solo sirve para saber qué consultar.
    const c = await config.moncash.lookupTransaction(transactionId);
    const result = c ? await apply("moncash", c, "txn:" + transactionId, { source: "return", transaction_id: transactionId }) : "pending";
    return page(200, result === "paid" || result === "already_paid" || result === "duplicate_event"
      ? "Pago MonCash recibido. Ya puedes volver a la aplicación Haiti Tracking."
      : "Estamos confirmando tu pago MonCash. Vuelve a la aplicación y pulsa «Verificar pago».");
  }

  return async (request: Request): Promise<Response> => {
    const url = new URL(request.url);
    const route = url.pathname.replace(/^.*?\/billing-payments/, "").replace(/\/$/, "");
    try {
      if (request.method === "POST" && route === "/checkout") return await checkout(request);
      if (request.method === "POST" && route === "/verify") return await verify(request);
      if (request.method === "POST" && route === "/stripe/webhook") return await stripeWebhook(request);
      if (request.method === "GET" && route === "/stripe/return") return await stripeReturn(url);
      if ((request.method === "GET" || request.method === "POST") && route === "/moncash/return") return await moncashReturn(request, url);
      return json(404, { error: "not_found" });
    } catch {
      // 5xx: Stripe reintenta el webhook; la app puede volver a verificar.
      return json(503, { error: "unavailable" });
    }
  };
}
