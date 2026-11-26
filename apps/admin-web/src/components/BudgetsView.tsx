"use client";

import { useCallback, useEffect, useState } from "react";
import { useRoles } from "@/components/AuthGate";
import PageHead from "@/components/ui/PageHead";
import { MISSION_STATUS_ES, supabase, usd } from "@/lib/supabase";

type B = {
  id: string;
  code: string;
  title: string;
  status: string;
  budget_authorized_usd: number;
  individual_reward_usd: number;
  committed_usd: number;
  paid_usd: number;
  pending_exposure_usd: number;
};

export default function BudgetsView() {
  const isAdmin = useRoles().includes("admin");
  const [rows, setRows] = useState<B[]>([]);
  const [onlyOpen, setOnlyOpen] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data, error } = await supabase.from("mission_budgets").select("*").order("code");
    setError(error?.message ?? null);
    setRows((data ?? []) as B[]);
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  async function changeBudget(b: B) {
    const v = prompt(`Nuevo presupuesto autorizado para ${b.code} (USD):`, String(b.budget_authorized_usd));
    if (v === null) return;
    const n = Number(v);
    if (!Number.isFinite(n) || n < 0) return setError("Monto no válido");
    const { error } = await supabase.from("missions").update({ budget_authorized_usd: n.toFixed(2), updated_at: new Date().toISOString() }).eq("id", b.id);
    setError(error?.message ?? null);
    load();
  }

  const shown = rows.filter((r) => !onlyOpen || ["ACTIVE", "PAUSED", "DRAFT", "SCHEDULED", "APPROVED"].includes(r.status));
  const sum = (k: keyof B) => shown.reduce((a, r) => a + Number(r[k]), 0);

  return (
    <div className="page">
      <PageHead title="Presupuestos de misiones" subtitle="Reservado, comprometido en recompensas y riesgo de lo que está en revisión.">
        <label style={{ flexDirection: "row", alignItems: "center", gap: 6, margin: 0 }}>
          <input type="checkbox" checked={onlyOpen} onChange={(e) => setOnlyOpen(e.target.checked)} /> Solo misiones abiertas
        </label>
      </PageHead>
      {error && <p className="error">{error}</p>}
      <div className="kpis">
        <div className="kpi"><div className="label">Autorizado</div><div className="value">{usd(sum("budget_authorized_usd"))}</div></div>
        <div className="kpi"><div className="label">Comprometido (aprobado)</div><div className="value">{usd(sum("committed_usd"))}</div></div>
        <div className="kpi"><div className="label">En revisión (posible gasto)</div><div className="value">{usd(sum("pending_exposure_usd"))}</div></div>
        <div className="kpi"><div className="label">Disponible</div><div className="value">{usd(sum("budget_authorized_usd") - sum("committed_usd") - sum("pending_exposure_usd"))}</div></div>
      </div>
      <div className="scroll">
        <table className="table">
          <thead>
            <tr>
              <th>Misión</th>
              <th>Estado</th>
              <th className="num">Autorizado</th>
              <th className="num">Comprometido</th>
              <th className="num">En revisión</th>
              <th className="num">Disponible</th>
              <th>Uso</th>
              {isAdmin && <th></th>}
            </tr>
          </thead>
          <tbody>
            {shown.map((b) => {
              const used = Number(b.committed_usd) + Number(b.pending_exposure_usd);
              const pct = Number(b.budget_authorized_usd) > 0 ? (used / Number(b.budget_authorized_usd)) * 100 : used > 0 ? 100 : 0;
              return (
                <tr key={b.id}>
                  <td><span className="mono">{b.code}</span><div className="muted small">{b.title}</div></td>
                  <td><span className={`tag m-${b.status}`}>{MISSION_STATUS_ES[b.status] ?? b.status}</span></td>
                  <td className="num">{usd(b.budget_authorized_usd)}</td>
                  <td className="num">{usd(b.committed_usd)}</td>
                  <td className="num">{usd(b.pending_exposure_usd)}</td>
                  <td className="num"><b className={Number(b.budget_authorized_usd) - used < 0 ? "error" : ""}>{usd(Number(b.budget_authorized_usd) - used)}</b></td>
                  <td>
                    <div className="meter"><div className={pct > 100 ? "over" : ""} style={{ width: `${Math.min(100, pct)}%` }} /></div>
                    <div className="muted small">{Math.round(pct)}%{pct >= 90 && pct <= 100 && " · casi agotado"}{pct > 100 && " · excedido: pausa o amplía"}</div>
                  </td>
                  {isAdmin && <td><button className="btn small" onClick={() => changeBudget(b)}>Ajustar</button></td>}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
