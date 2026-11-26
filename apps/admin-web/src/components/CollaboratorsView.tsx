"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { Ban, Download, Gift, Unlock } from "lucide-react";
import { useRoles } from "@/components/AuthGate";
import Modal from "@/components/ui/Modal";
import PageHead from "@/components/ui/PageHead";
import { downloadCsv, fmtDate, supabase, usd } from "@/lib/supabase";

export type AdminUser = {
  id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  department: string | null;
  commune: string | null;
  created_at: string;
  last_sign_in_at: string | null;
  roles: string[];
  restricted: boolean;
  restriction_reason: string | null;
  moncash_phone: string | null;
  contributions: number;
  approved: number;
  rejected: number;
  needs_changes: number;
  pending: number;
  earned_usd: number;
  available_usd: number;
  withdrawn_usd: number;
};

export const ROLE_ES: Record<string, string> = {
  collaborator: "Colaborador",
  company: "Empresa",
  developer: "Desarrollador",
  admin: "Administrador",
  moderator: "Moderador",
};

/** Reputación 0–100: aprobados sobre revisados, con un mínimo de 5 revisiones para ser fiable. */
export function reputation(u: AdminUser): number | null {
  const reviewed = u.approved + u.rejected + u.needs_changes;
  if (reviewed === 0) return null;
  return Math.round(((u.approved + 0.5 * u.needs_changes) / reviewed) * 100);
}

export async function loadUsers(): Promise<{ users: AdminUser[]; error: string | null }> {
  const { data, error } = await supabase.rpc("admin_users");
  return { users: (data ?? []) as AdminUser[], error: error?.message ?? null };
}

export default function CollaboratorsView() {
  const isAdmin = useRoles().includes("admin");
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [q, setQ] = useState("");
  const [role, setRole] = useState("collaborator");
  const [selected, setSelected] = useState<AdminUser | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const r = await loadUsers();
    setUsers(r.users);
    setError(r.error);
    setSelected((s) => (s ? r.users.find((u) => u.id === s.id) ?? null : null));
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  const shown = useMemo(() => {
    const t = q.trim().toLowerCase();
    return users.filter(
      (u) =>
        (role === "all" || (role === "restricted" ? u.restricted : u.roles.includes(role))) &&
        (!t || `${u.full_name} ${u.email ?? ""} ${u.phone ?? ""} ${u.commune ?? ""}`.toLowerCase().includes(t)),
    );
  }, [users, q, role]);

  return (
    <div className="page">
      <PageHead title="Gestión de colaboradores" subtitle="Usuarios, reputación, saldos y restricciones.">
        <input placeholder="Buscar nombre, teléfono, correo o comuna" value={q} onChange={(e) => setQ(e.target.value)} />
        <select value={role} onChange={(e) => setRole(e.target.value)}>
          <option value="all">Todos los usuarios</option>
          {Object.entries(ROLE_ES).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
          <option value="restricted">Restringidos</option>
        </select>
        <button
          className="btn"
          onClick={() =>
            downloadCsv(
              "usuarios.csv",
              shown.map((u) => ({ nombre: u.full_name, telefono: u.phone, correo: u.email, comuna: u.commune, roles: u.roles.join(" "), aportes: u.contributions, aprobados: u.approved, reputacion: reputation(u), ganado_usd: u.earned_usd, retirado_usd: u.withdrawn_usd, restringido: u.restricted })),
            )
          }
        >
          <Download size={14} /> CSV
        </button>
      </PageHead>
      {error && <p className="error">{error}</p>}

      <div className="scroll">
        <table className="table">
          <thead>
            <tr>
              <th>Usuario</th>
              <th>Zona</th>
              <th className="num">Aportes</th>
              <th className="num">Reputación</th>
              <th className="num">Ganado</th>
              <th className="num">Disponible</th>
              <th>Estado</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {shown.map((u) => {
              const rep = reputation(u);
              return (
                <tr key={u.id}>
                  <td>
                    <b>{u.full_name || "Sin nombre"}</b>
                    <div className="muted small">{u.phone ?? u.email ?? u.id.slice(0, 8)} · {u.roles.map((r) => ROLE_ES[r] ?? r).join(", ")}</div>
                  </td>
                  <td className="small">{[u.commune, u.department].filter(Boolean).join(", ") || "—"}</td>
                  <td className="num">
                    {u.contributions}
                    <div className="muted small">{u.approved} ✓ · {u.rejected} ✗ · {u.pending} ⏳</div>
                  </td>
                  <td className="num">{rep === null ? "—" : <b className={rep < 50 ? "error" : rep >= 80 ? "ok" : ""}>{rep}</b>}</td>
                  <td className="num">{usd(u.earned_usd)}</td>
                  <td className="num">{usd(u.available_usd)}</td>
                  <td>{u.restricted ? <span className="tag s-REJECTED">Restringido</span> : <span className="tag s-ACTIVE">Activo</span>}</td>
                  <td><button className="btn small" onClick={() => setSelected(u)}>Ver</button></td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {shown.length === 0 && <div className="empty">No hay usuarios con este filtro.</div>}
      </div>

      {selected && (
        <Modal title={selected.full_name || "Usuario"} onClose={() => setSelected(null)}>
          <UserDetail u={selected} isAdmin={isAdmin} onChanged={load} />
        </Modal>
      )}
    </div>
  );
}

function UserDetail({ u, isAdmin, onChanged }: { u: AdminUser; isAdmin: boolean; onChanged: () => void }) {
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const [reason, setReason] = useState("");

  async function run(p: PromiseLike<{ error: { message: string } | null }>, ok: string) {
    const { error } = await p;
    setErr(error?.message ?? null);
    setMsg(error ? null : ok);
    if (!error) onChanged();
  }

  async function restrict() {
    const r = prompt("Motivo de la restricción (no podrá enviar aportes ni retirar):");
    if (r) run(supabase.rpc("admin_set_restriction", { p_user: u.id, p_restricted: true, p_reason: r }), "Usuario restringido.");
  }

  async function adjust(e: FormEvent) {
    e.preventDefault();
    await run(supabase.rpc("admin_adjust_reward", { p_user: u.id, p_amount: Number(amount), p_reason: reason }), "Ajuste registrado (queda por liberar).");
    setAmount("");
    setReason("");
  }

  return (
    <div className="form">
      <table className="facts">
        <tbody>
          <tr><td>Teléfono</td><td>{u.phone ?? "—"}</td></tr>
          <tr><td>Correo</td><td>{u.email ?? "—"}</td></tr>
          <tr><td>MonCash verificado</td><td>{u.moncash_phone ?? "No"}</td></tr>
          <tr><td>Zona</td><td>{[u.commune, u.department].filter(Boolean).join(", ") || "—"}</td></tr>
          <tr><td>Registro · último acceso</td><td>{fmtDate(u.created_at, false)} · {fmtDate(u.last_sign_in_at)}</td></tr>
          <tr><td>Roles</td><td>{u.roles.map((r) => ROLE_ES[r] ?? r).join(", ")}</td></tr>
          <tr><td>Aportes</td><td>{u.contributions} · {u.approved} aprobados · {u.rejected} rechazados · {u.needs_changes} con cambios · {u.pending} pendientes</td></tr>
          <tr><td>Reputación</td><td>{reputation(u) ?? "—"}</td></tr>
          <tr><td>Saldos</td><td>Ganado {usd(u.earned_usd)} · disponible {usd(u.available_usd)} · retirado {usd(u.withdrawn_usd)}</td></tr>
          {u.restricted && <tr><td>Restricción</td><td className="error">{u.restriction_reason}</td></tr>}
        </tbody>
      </table>
      {msg && <p className="ok">{msg}</p>}
      {err && <p className="error">{err}</p>}
      {isAdmin && (
        <>
          <div className="row gap">
            {u.restricted ? (
              <button className="btn" onClick={() => run(supabase.rpc("admin_set_restriction", { p_user: u.id, p_restricted: false }), "Restricción retirada.")}>
                <Unlock size={14} /> Quitar restricción
              </button>
            ) : (
              <button className="btn danger" onClick={restrict}><Ban size={14} /> Restringir</button>
            )}
            <button className="btn" onClick={() => run(supabase.rpc("admin_release_rewards", { p_user: u.id }), "Recompensas liberadas según el periodo de retención.")}>
              <Gift size={14} /> Liberar sus recompensas
            </button>
          </div>
          <form onSubmit={adjust}>
            <h3>Ajuste o bonificación manual</h3>
            <div className="row gap">
              <label>
                Monto USD (negativo para corregir)
                <input type="number" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} required />
              </label>
              <label>
                Motivo
                <input value={reason} onChange={(e) => setReason(e.target.value)} required />
              </label>
            </div>
            <button className="btn">Registrar ajuste</button>
          </form>
        </>
      )}
    </div>
  );
}
