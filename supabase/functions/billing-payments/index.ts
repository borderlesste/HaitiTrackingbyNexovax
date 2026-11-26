import { createBillingHandler } from "./handler.ts";
import { MoncashProvider } from "./providers/moncash.ts";
import { StripeProvider } from "./providers/stripe.ts";

// Desplegar con verify_jwt desactivado (los webhooks no traen sesión); /checkout y /verify validan la sesión.
// Secretos: MONCASH_CLIENT_ID, MONCASH_CLIENT_SECRET, MONCASH_MODE (sandbox|live),
//           STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET. Un proveedor sin secretos queda apagado.

function getApiKey(keySet: string, legacy: string): string {
  const keys = Deno.env.get(keySet);
  return (keys && JSON.parse(keys).default) || Deno.env.get(legacy) || "";
}

const url = Deno.env.get("SUPABASE_URL");
const publicKey = getApiKey("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
const serviceKey = getApiKey("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
if (!url || !publicKey || !serviceKey) throw new Error("Missing Supabase configuration");

const env = (name: string) => Deno.env.get(name)?.trim() ?? "";
const moncashId = env("MONCASH_CLIENT_ID");
const moncashSecret = env("MONCASH_CLIENT_SECRET");
const stripeKey = env("STRIPE_SECRET_KEY");

Deno.serve(createBillingHandler({
  url,
  publicKey,
  serviceKey,
  functionUrl: env("BILLING_FUNCTION_URL") || url.replace(/\/$/, "") + "/functions/v1/billing-payments",
  moncash: moncashId && moncashSecret
    ? new MoncashProvider({ clientId: moncashId, clientSecret: moncashSecret, live: env("MONCASH_MODE") === "live" })
    : undefined,
  stripe: stripeKey ? new StripeProvider({ secretKey: stripeKey, webhookSecret: env("STRIPE_WEBHOOK_SECRET") }) : undefined,
  stripeWebhookSecret: env("STRIPE_WEBHOOK_SECRET") || undefined,
}));
