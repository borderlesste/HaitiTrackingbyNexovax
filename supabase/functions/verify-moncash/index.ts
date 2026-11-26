import { createMoncashHandler } from "./handler.ts";

function getApiKey(keySet: string, legacy: string): string {
  const keys = Deno.env.get(keySet);
  return (keys && JSON.parse(keys).default) || Deno.env.get(legacy) || "";
}

const url = Deno.env.get("SUPABASE_URL");
const publicKey = getApiKey("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
const serviceKey = getApiKey("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
if (!url || !publicKey || !serviceKey) throw new Error("Missing Supabase configuration");

Deno.serve(createMoncashHandler({ url, publicKey, serviceKey }));

