import { createClient } from "@supabase/supabase-js";

// Clave publicable: segura en el navegador. Los permisos los imponen RLS y las funciones del servidor.
export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  { auth: { detectSessionInUrl: false } },
);

export type Role = "admin" | "moderator";

export type PanelAccess =
  | { status: "denied" | "verify" | "enroll" | "error" }
  | { status: "allowed"; roles: Role[] };

export async function getPanelAccess(token: string): Promise<PanelAccess> {
  const { data: assurance, error: assuranceError } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel(token);
  if (assuranceError || !assurance?.currentLevel) return { status: "error" };
  const authorization = `Bearer ${token}`;

  if (assurance.currentLevel !== "aal2") {
    const { data, error } = await supabase.rpc("is_panel_staff").setHeader("Authorization", authorization);
    if (error) return { status: "error" };
    if (data !== true) return { status: "denied" };
    return { status: assurance.nextLevel === "aal2" ? "verify" : "enroll" };
  }

  const roles: Role[] = [];
  for (const r of ["admin", "moderator"] as const) {
    const { data, error } = await supabase.rpc("has_role", { r }).setHeader("Authorization", authorization);
    if (error) return { status: "error" };
    if (data === true) roles.push(r);
  }
  return roles.length ? { status: "allowed", roles } : { status: "denied" };
}

export function usd(v: number | string | null | undefined): string {
  if (v === null || v === undefined) return "—";
  return `$${Number(v).toFixed(2)}`;
}

export function fmtDate(v: string | null | undefined, withTime = true): string {
  if (!v) return "—";
  const d = new Date(v);
  return withTime
    ? d.toLocaleString("es", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" })
    : d.toLocaleDateString("es", { day: "2-digit", month: "short", year: "numeric" });
}

export function htg(v: number | string | null | undefined): string {
  if (v === null || v === undefined) return "—";
  return `${Number(v).toLocaleString("es", { maximumFractionDigits: 0 })} HTG`;
}

/** Lee un ajuste de platform_settings (jsonb) con valor por defecto. */
export async function getSetting<T>(key: string, fallback: T): Promise<T> {
  const { data } = await supabase.from("platform_settings").select("value").eq("key", key).maybeSingle();
  return data ? ({ ...fallback, ...(data.value as object) } as T) : fallback;
}

export async function saveSetting(key: string, value: unknown): Promise<string | null> {
  const { error } = await supabase
    .from("platform_settings")
    .upsert({ key, value, updated_at: new Date().toISOString() }, { onConflict: "key" });
  return error?.message ?? null;
}

export function toCsv(rows: Record<string, unknown>[]): string {
  if (rows.length === 0) return "";
  const cols = Object.keys(rows[0]);
  const esc = (v: unknown) => {
    let s = v === null || v === undefined ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
    if (typeof v !== "number" && (/^[\t\r\n]/.test(s) || /^\s*[=+\-@＝＋－＠]/u.test(s))) s = `'${s}`;
    return /[",\r\n;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [cols.map(esc).join(","), ...rows.map((r) => cols.map((c) => esc(r[c])).join(","))].join("\n");
}

/** Descarga filas como CSV (conciliación, informes). */
export function downloadCsv(filename: string, rows: Record<string, unknown>[]) {
  if (rows.length === 0) return;
  const url = URL.createObjectURL(new Blob(["\ufeff" + toCsv(rows)], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export const MISSION_STATUS_ES: Record<string, string> = {
  DRAFT: "Borrador",
  IN_REVIEW: "En revisión",
  APPROVED: "Aprobada",
  SCHEDULED: "Programada",
  ACTIVE: "Activa",
  PAUSED: "Pausada",
  COMPLETED: "Cerrada",
  EXPIRED: "Vencida",
  CANCELLED: "Cancelada",
  ARCHIVED: "Archivada",
};
