// MonCash Business (Digicel), API REST "Moncash-middleware". Cobra en gourdes (HTG).
// El portal de MonCash no firma sus avisos: el pago se confirma siempre consultando
// RetrieveOrderPayment / RetrieveTransactionPayment con nuestras credenciales.
import { type Checkout, type CheckoutInput, type Confirmation, decimal2, type Fetch, type PaymentProvider } from "./types.ts";

export type MoncashConfig = { clientId: string; clientSecret: string; live: boolean };

type MoncashPayment = { reference?: string; transaction_id?: string | number; cost?: string | number; message?: string; payer?: string | number };

export function moncashHosts(live: boolean) {
  const host = live ? "https://moncashbutton.digicelgroup.com" : "https://sandbox.moncashbutton.digicelgroup.com";
  return { api: host + "/Api", gateway: host + "/Moncash-middleware" };
}

export class MoncashProvider implements PaymentProvider {
  readonly id = "moncash" as const;
  readonly currency = "HTG" as const;
  private token: { value: string; until: number } | null = null;
  private readonly hosts: { api: string; gateway: string };
  private readonly config: MoncashConfig;
  private readonly http: Fetch;
  private readonly now: () => number;

  constructor(config: MoncashConfig, http: Fetch = fetch, now = () => Date.now()) {
    this.config = config;
    this.http = http;
    this.now = now;
    this.hosts = moncashHosts(config.live);
  }

  private async accessToken(): Promise<string> {
    if (this.token && this.token.until > this.now()) return this.token.value;
    const res = await this.http(this.hosts.api + "/oauth/token", {
      method: "POST",
      headers: {
        accept: "application/json",
        authorization: "Basic " + btoa(`${this.config.clientId}:${this.config.clientSecret}`),
        "content-type": "application/x-www-form-urlencoded",
      },
      body: "scope=read,write&grant_type=client_credentials",
      redirect: "error",
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) throw new Error(`MonCash token ${res.status}`);
    const body = await res.json() as { access_token?: string; expires_in?: number };
    if (!body.access_token) throw new Error("MonCash token vacío");
    const seconds = Math.max(5, Number(body.expires_in ?? 59) - 5);
    this.token = { value: body.access_token, until: this.now() + seconds * 1000 };
    return body.access_token;
  }

  private async call(path: string, payload: Record<string, unknown>): Promise<Response> {
    return this.http(this.hosts.api + path, {
      method: "POST",
      headers: { accept: "application/json", authorization: "Bearer " + await this.accessToken(), "content-type": "application/json" },
      body: JSON.stringify(payload),
      redirect: "error",
      signal: AbortSignal.timeout(10000),
    });
  }

  async createCheckout(input: CheckoutInput): Promise<Checkout> {
    if (input.currency !== "HTG") throw new Error("MonCash solo cobra en HTG");
    const res = await this.call("/v1/CreatePayment", { amount: Number(decimal2(input.amount)), orderId: input.orderId });
    if (!res.ok) throw new Error(`MonCash CreatePayment ${res.status}`);
    const body = await res.json() as { payment_token?: { token?: string } };
    const token = body.payment_token?.token;
    if (!token) throw new Error("MonCash no devolvió token de pago");
    return { providerRef: null, url: `${this.hosts.gateway}/Payment/Redirect?token=${encodeURIComponent(token)}` };
  }

  private confirmation(payment: MoncashPayment | undefined, expectedOrder: string | null): Confirmation | null {
    if (!payment?.reference) return null;
    if (expectedOrder !== null && String(payment.reference) !== expectedOrder) return null;
    const ok = String(payment.message ?? "").toLowerCase() === "successful";
    return {
      orderId: String(payment.reference),
      status: ok ? "paid" : "failed",
      amount: decimal2(payment.cost),
      currency: "HTG",
      providerRef: payment.transaction_id != null ? String(payment.transaction_id) : null,
      payer: payment.payer != null ? String(payment.payer) : null,
    };
  }

  async lookup(attempt: { orderId: string }): Promise<Confirmation | null> {
    const res = await this.call("/v1/RetrieveOrderPayment", { orderId: attempt.orderId });
    if (res.status === 404 || res.status === 400) return null; // aún sin pagar
    if (!res.ok) throw new Error(`MonCash RetrieveOrderPayment ${res.status}`);
    return this.confirmation((await res.json() as { payment?: MoncashPayment }).payment, attempt.orderId);
  }

  /** Para la URL de retorno: MonCash envía transactionId, y la referencia es nuestro orderId. */
  async lookupTransaction(transactionId: string): Promise<Confirmation | null> {
    const res = await this.call("/v1/RetrieveTransactionPayment", { transactionId });
    if (res.status === 404 || res.status === 400) return null;
    if (!res.ok) throw new Error(`MonCash RetrieveTransactionPayment ${res.status}`);
    return this.confirmation((await res.json() as { payment?: MoncashPayment }).payment, null);
  }
}
