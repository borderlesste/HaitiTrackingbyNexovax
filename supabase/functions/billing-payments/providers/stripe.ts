// Stripe Checkout (tarjetas en USD). Solo es posible si Nexovax tiene una entidad en un país
// admitido por Stripe (por ejemplo, una LLC en EE. UU.); Stripe no abre cuentas en Haití.
import { type Checkout, type CheckoutInput, type Confirmation, type Fetch, fromMinor, type PaymentProvider, toMinor } from "./types.ts";

export type StripeConfig = { secretKey: string; webhookSecret: string };

export type StripeSession = {
  id: string;
  url?: string | null;
  status?: string;
  payment_status?: string;
  amount_total?: number | null;
  currency?: string | null;
  client_reference_id?: string | null;
  metadata?: Record<string, string> | null;
  customer_details?: { email?: string | null } | null;
};

export class StripeProvider implements PaymentProvider {
  readonly id = "stripe" as const;
  readonly currency = "USD" as const;

  private readonly config: StripeConfig;
  private readonly http: Fetch;

  constructor(config: StripeConfig, http: Fetch = fetch) {
    this.config = config;
    this.http = http;
  }

  private request(path: string, init: RequestInit = {}): Promise<Response> {
    return this.http("https://api.stripe.com" + path, {
      ...init,
      headers: { authorization: "Bearer " + this.config.secretKey, ...(init.headers ?? {}) },
      redirect: "error",
      signal: AbortSignal.timeout(10000),
    });
  }

  async createCheckout(input: CheckoutInput): Promise<Checkout> {
    if (input.currency !== "USD") throw new Error("Stripe cobra estas facturas en USD");
    const form = new URLSearchParams({
      mode: "payment",
      client_reference_id: input.orderId,
      "metadata[order_id]": input.orderId,
      "metadata[payment_id]": input.paymentId,
      "payment_intent_data[metadata][order_id]": input.orderId,
      "line_items[0][quantity]": "1",
      "line_items[0][price_data][currency]": "usd",
      "line_items[0][price_data][unit_amount]": String(toMinor(input.amount)),
      "line_items[0][price_data][product_data][name]": `${input.invoiceNumber} · ${input.description}`.slice(0, 250),
      success_url: `${input.functionUrl}/stripe/return?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${input.functionUrl}/stripe/return?cancelled=1`,
      expires_at: String(Math.floor(Date.now() / 1000) + 60 * 60),
    });
    const res = await this.request("/v1/checkout/sessions", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", "idempotency-key": "checkout-" + input.orderId },
      body: form.toString(),
    });
    if (!res.ok) throw new Error(`Stripe checkout ${res.status}`);
    const session = await res.json() as StripeSession;
    if (!session.url) throw new Error("Stripe no devolvió URL de pago");
    return { providerRef: session.id, url: session.url };
  }

  async lookup(attempt: { orderId: string; providerRef: string | null }): Promise<Confirmation | null> {
    if (!attempt.providerRef) return null;
    const session = await this.lookupSession(attempt.providerRef);
    return session && sessionConfirmation(session, attempt.orderId);
  }

  async lookupSession(id: string): Promise<StripeSession | null> {
    if (!/^cs_[A-Za-z0-9_]+$/.test(id)) return null;
    const res = await this.request("/v1/checkout/sessions/" + id);
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`Stripe session ${res.status}`);
    return await res.json() as StripeSession;
  }
}

export function sessionConfirmation(session: StripeSession, expectedOrder: string | null): Confirmation | null {
  const orderId = session.metadata?.order_id ?? session.client_reference_id ?? null;
  if (!orderId || (expectedOrder !== null && orderId !== expectedOrder)) return null;
  if (session.currency?.toLowerCase() !== "usd" || typeof session.amount_total !== "number") return null;
  const status = session.payment_status === "paid" || session.payment_status === "no_payment_required"
    ? "paid"
    : session.status === "expired" ? "expired" : "pending";
  return {
    orderId,
    status,
    amount: fromMinor(session.amount_total),
    currency: "USD",
    providerRef: session.id,
    payer: session.customer_details?.email ?? null,
  };
}

const encoder = new TextEncoder();

/** Verifica la cabecera Stripe-Signature (HMAC-SHA256 de "t.cuerpo"), con 5 minutos de tolerancia. */
export async function verifyStripeSignature(body: string, header: string | null, secret: string, nowSeconds = Date.now() / 1000): Promise<boolean> {
  if (!header || !secret) return false;
  const parts = header.split(",").map((p) => p.split("=", 2) as [string, string]);
  const t = parts.find(([k]) => k === "t")?.[1];
  const signatures = parts.filter(([k]) => k === "v1").map(([, v]) => v);
  if (!t || !/^\d+$/.test(t) || signatures.length === 0) return false;
  if (Math.abs(nowSeconds - Number(t)) > 300) return false;
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(`${t}.${body}`)));
  const expected = Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
  return signatures.some((s) => constantTimeEqual(s, expected));
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
