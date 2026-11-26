"use client";

import { useEffect, useState } from "react";
import { Plus, Save, Trash2 } from "lucide-react";
import PageHead from "@/components/ui/PageHead";
import { fmtDate, getSetting, saveSetting, supabase, usd } from "@/lib/supabase";

type Plan = { name: string; price_usd: number; features?: string; daily_quota?: number };
type Plans = { company: Plan[]; developer: Plan[] };
type Campaign = { id: string; org_name: string; title: string; proposed_budget_usd: number; status: string; mission_code: string | null; created_at: string };

export default function BillingView() {
  const [plans, setPlans] = useState<Plans>({ company: [], developer: [] });
  const [campaigns, setCampaigns] = useState<Campaign[]>([]);
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    getSetting<Plans>("plans", { company: [], developer: [] }).then(setPlans);
    supabase
      .from("campaign_requests_view")
      .select("id, org_name, title, proposed_budget_usd, status, mission_code, created_at")
      .order("created_at", { ascending: false })
      .then(({ data }) => setCampaigns((data ?? []) as Campaign[]));
  }, []);

  async function save() {
    const e = await saveSetting("plans", plans);
    setErr(e);
    setMsg(e ? null : "Planes guardados.");
  }

  const approved = campaigns.filter((c) => c.status === "APPROVED");

  return (
    <div className="page">
      <PageHead title="Facturación" subtitle="Planes, suscripciones y ventas de misiones a empresas.">
        <button className="btn primary" onClick={save}><Save size={14} /> Guardar planes</button>
      </PageHead>
      <p className="card small" style={{ background: "#fff8e6" }}>
        El cobro en línea todavía no está conectado (falta elegir el procesador de pagos). Por ahora este módulo define el catálogo de planes y
        lleva el registro de lo que se debe facturar a cada empresa.
      </p>
      {msg && <p className="ok">{msg}</p>}
      {err && <p className="error">{err}</p>}

      <div className="grid2" style={{ margin: 0 }}>
        {(["company", "developer"] as const).map((kind) => (
          <div className="card" key={kind}>
            <div className="head">
              <h3 style={{ margin: 0 }}>Planes de {kind === "company" ? "empresa" : "desarrollador"}</h3>
              <button
                className="btn small"
                onClick={() => setPlans({ ...plans, [kind]: [...plans[kind], kind === "company" ? { name: "", price_usd: 0, features: "" } : { name: "", price_usd: 0, daily_quota: 1000 }] })}
              >
                <Plus size={12} /> Plan
              </button>
            </div>
            {plans[kind].map((p, i) => {
              const set = (patch: Partial<Plan>) => setPlans({ ...plans, [kind]: plans[kind].map((x, j) => (j === i ? { ...x, ...patch } : x)) });
              return (
                <div className="row gap" key={i} style={{ marginTop: 8, alignItems: "flex-end" }}>
                  <label>Nombre<input value={p.name} onChange={(e) => set({ name: e.target.value })} /></label>
                  <label style={{ maxWidth: 110 }}>USD/mes<input type="number" step="0.01" min="0" value={p.price_usd} onChange={(e) => set({ price_usd: Number(e.target.value) })} /></label>
                  {kind === "company" ? (
                    <label>Incluye<input value={p.features ?? ""} onChange={(e) => set({ features: e.target.value })} /></label>
                  ) : (
                    <label style={{ maxWidth: 130 }}>Consultas/día<input type="number" min="1" value={p.daily_quota ?? 1000} onChange={(e) => set({ daily_quota: Number(e.target.value) })} /></label>
                  )}
                  <button className="btn small" style={{ marginBottom: 8 }} onClick={() => setPlans({ ...plans, [kind]: plans[kind].filter((_, j) => j !== i) })}>
                    <Trash2 size={12} />
                  </button>
                </div>
              );
            })}
          </div>
        ))}
      </div>

      <h3>Misiones solicitadas por empresas</h3>
      <div className="kpis">
        <div className="kpi"><div className="label">Aprobadas (a facturar)</div><div className="value">{usd(approved.reduce((a, c) => a + Number(c.proposed_budget_usd), 0))}</div><div className="sub">{approved.length} solicitudes</div></div>
        <div className="kpi"><div className="label">En revisión</div><div className="value">{usd(campaigns.filter((c) => c.status === "PENDING").reduce((a, c) => a + Number(c.proposed_budget_usd), 0))}</div></div>
      </div>
      <div className="scroll">
        <table className="table">
          <thead>
            <tr><th>Fecha</th><th>Empresa</th><th>Solicitud</th><th>Misión</th><th className="num">Presupuesto</th><th>Estado</th></tr>
          </thead>
          <tbody>
            {campaigns.map((c) => (
              <tr key={c.id}>
                <td className="small">{fmtDate(c.created_at, false)}</td>
                <td>{c.org_name}</td>
                <td>{c.title}</td>
                <td className="mono">{c.mission_code ?? "—"}</td>
                <td className="num">{usd(c.proposed_budget_usd)}</td>
                <td><span className={`tag s-${c.status}`}>{c.status === "APPROVED" ? "Aprobada" : c.status === "REJECTED" ? "Rechazada" : "En revisión"}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
        {campaigns.length === 0 && <div className="empty">Sin solicitudes todavía.</div>}
      </div>
    </div>
  );
}
