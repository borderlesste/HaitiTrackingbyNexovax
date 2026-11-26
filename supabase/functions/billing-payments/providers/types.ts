// Interfaz común de procesadores de pago. Para agregar uno (NatCash, PayPal, AZUL…):
// implementa PaymentProvider, regístralo en index.ts y añade su código al check de la migración.

export type ProviderId = "moncash" | "stripe";
export type Currency = "HTG" | "USD";

export type CheckoutInput = {
  paymentId: string;
  orderId: string;
  /** Importe exacto en texto decimal ("29.00"), tal como lo fijó la base de datos. */
  amount: string;
  currency: Currency;
  invoiceNumber: string;
  description: string;
  /** URL pública de esta función, para las páginas de retorno del proveedor. */
  functionUrl: string;
};

export type Checkout = { providerRef: string | null; url: string };

/** Lo que el proveedor confirma, consultado servidor a servidor (nunca lo que dice el navegador). */
export type Confirmation = {
  orderId: string;
  status: "paid" | "pending" | "failed" | "expired";
  amount: string;
  currency: Currency;
  providerRef: string | null;
  payer: string | null;
};

export interface PaymentProvider {
  readonly id: ProviderId;
  readonly currency: Currency;
  createCheckout(input: CheckoutInput): Promise<Checkout>;
  /** Consulta el estado de un intento. Devuelve null si el proveedor aún no lo conoce. */
  lookup(attempt: { orderId: string; providerRef: string | null }): Promise<Confirmation | null>;
}

export type Fetch = typeof fetch;

/** "29" | 29 | "29.5" → "29.50". Rechaza valores no decimales. */
export function decimal2(value: unknown): string {
  const text = typeof value === "number" ? String(value) : typeof value === "string" ? value.trim() : "";
  const m = /^(\d{1,10})(?:\.(\d{1,2}))?$/.exec(text);
  if (!m) throw new Error("Importe no válido");
  return `${BigInt(m[1])}.${(m[2] ?? "").padEnd(2, "0")}`;
}

/** "29.00" → 2900 (unidades menores, sin coma flotante). */
export function toMinor(amount: string): number {
  const [units, cents] = decimal2(amount).split(".");
  return Number(BigInt(units) * 100n + BigInt(cents));
}

/** 2900 → "29.00". */
export function fromMinor(minor: number): string {
  if (!Number.isSafeInteger(minor) || minor < 0) throw new Error("Importe no válido");
  return `${Math.trunc(minor / 100)}.${String(minor % 100).padStart(2, "0")}`;
}
