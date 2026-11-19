import { createClient } from "@supabase/supabase-js";

// Clave publicable: segura en el navegador. Los permisos los imponen RLS y las funciones del servidor.
export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
);

export type Role = "admin" | "moderator";

export async function currentRoles(): Promise<Role[]> {
  const roles: Role[] = [];
  for (const r of ["admin", "moderator"] as Role[]) {
    const { data } = await supabase.rpc("has_role", { r });
    if (data === true) roles.push(r);
  }
  return roles;
}

export function usd(v: number | string | null | undefined): string {
  if (v === null || v === undefined) return "—";
  return `$${Number(v).toFixed(2)}`;
}
