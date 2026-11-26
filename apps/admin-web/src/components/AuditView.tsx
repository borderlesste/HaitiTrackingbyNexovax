"use client";

import { useCallback, useEffect, useState } from "react";
import { Download } from "lucide-react";
import { ACTION_ES } from "@/components/Dashboard";
import PageHead from "@/components/ui/PageHead";
import { downloadCsv, fmtDate, supabase } from "@/lib/supabase";

type A = { id: number; actor_id: string | null; actor_name: string | null; action: string; subject_id: string | null; details: Record<string, unknown>; created_at: string };

export default function AuditView() {
  const [rows, setRows] = useState<A[]>([]);
  const [action, setAction] = useState("all");
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    let q = supabase.from("admin_actions_view").select("*").order("created_at", { ascending: false }).limit(500);
    if (action !== "all") q = q.eq("action", action);
    const { data, error } = await q;
    setError(error?.message ?? null);
    setRows((data ?? []) as A[]);
  }, [action]);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  return (
    <div className="page">
      <PageHead title="Auditoría" subtitle="Historial inalterable de operaciones administrativas (nadie puede editarlo ni borrarlo desde el panel).">
        <select value={action} onChange={(e) => setAction(e.target.value)}>
          <option value="all">Todas las acciones</option>
          {Object.entries(ACTION_ES).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>
        <button className="btn" onClick={() => downloadCsv("auditoria.csv", rows.map((r) => ({ fecha: r.created_at, responsable: r.actor_name, accion: r.action, objeto: r.subject_id, detalles: r.details })))}>
          <Download size={14} /> CSV
        </button>
      </PageHead>
      {error && <p className="error">{error}</p>}
      <div className="scroll">
        <table className="table">
          <thead>
            <tr><th>Fecha</th><th>Responsable</th><th>Acción</th><th>Detalles</th></tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td className="small" style={{ whiteSpace: "nowrap" }}>{fmtDate(r.created_at)}</td>
                <td>{r.actor_name || (r.actor_id ? r.actor_id.slice(0, 8) : "Sistema")}</td>
                <td>{ACTION_ES[r.action] ?? r.action}</td>
                <td className="small mono" style={{ maxWidth: 520, wordBreak: "break-word" }}>
                  {Object.entries(r.details ?? {})
                    .filter(([, v]) => v !== null && v !== "")
                    .map(([k, v]) => `${k}: ${typeof v === "object" ? JSON.stringify(v) : v}`)
                    .join(" · ")}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {rows.length === 0 && <div className="empty">Sin registros.</div>}
      </div>
    </div>
  );
}
