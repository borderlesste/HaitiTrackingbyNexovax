"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useState } from "react";
import { useRoles } from "@/components/AuthGate";
import { supabase, usd } from "@/lib/supabase";

const Map = dynamic(() => import("@/components/Map"), { ssr: false });

type Campaign = {
  id: string;
  org_name: string;
  title: string;
  description: string;
  commune: string | null;
  radius_m: number;
  target_places: number;
  proposed_budget_usd: number;
  status: string;
  review_reason: string | null;
  mission_code: string | null;
  mission_status: string | null;
  approved_places: number;
  request_type: string | null;
  category: string | null;
  desired_end: string | null;
  created_at: string;
  lat: number;
  lng: number;
};

const ES: Record<string, string> = { PENDING: "En revisión", APPROVED: "Aprobada", REJECTED: "Rechazada" };

export default function CampaignsView() {
  const isAdmin = useRoles().includes("admin");
  const [items, setItems] = useState<Campaign[]>([]);
  const [selected, setSelected] = useState<Campaign | null>(null);
  const [reward, setReward] = useState("0.25");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data, error } = await supabase.from("campaign_requests_view").select("*").order("created_at", { ascending: false });
    setError(error?.message ?? null);
    setItems((data ?? []) as Campaign[]);
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  async function decide(c: Campaign, decision: "APPROVED" | "REJECTED") {
    let reason: string | null = null;
    if (decision === "REJECTED") {
      reason = prompt("Motivo del rechazo (lo verá la empresa):");
      if (!reason) return;
    }
    const { data, error } = await supabase.rpc("review_campaign", {
      p_campaign: c.id,
      p_decision: decision,
      p_reason: reason,
      p_reward_usd: reward,
    });
    setError(error?.message ?? null);
    setNotice(error ? null : decision === "APPROVED" ? `Se creó una misión en borrador (${data}). Revísala y actívala en Misiones.` : "Solicitud rechazada.");
    setSelected(null);
    load();
  }

  if (!isAdmin) return <p className="muted">Solo un administrador puede aprobar campañas.</p>;

  const exposure = selected ? selected.target_places * Number(reward || 0) : 0;

  return (
    <div className="split">
      <section className="list">
        <h2>Misiones solicitadas por empresas</h2>
        {error && <p className="error">{error}</p>}
        {notice && <p className="ok small">{notice}</p>}
        {items.length === 0 && <p className="muted">Ninguna solicitud todavía.</p>}
        {items.map((c) => (
          <button key={c.id} className={`item ${selected?.id === c.id ? "sel" : ""}`} onClick={() => setSelected(c)}>
            <div className="row between">
              <b>{c.title}</b>
              <span className={`tag s-${c.status === "PENDING" ? "SUBMITTED" : c.status}`}>{ES[c.status]}</span>
            </div>
            <div className="muted small">
              {c.org_name} · {c.request_type === "VERIFY" ? "Verificar" : "Registrar"} · {c.commune ?? "—"} · {c.target_places} lugares
            </div>
          </button>
        ))}
      </section>
      <section className="detail">
        {selected ? (
          <div className="card">
            <h2>{selected.title}</h2>
            <p className="muted">{selected.org_name} · {new Date(selected.created_at).toLocaleString("es")}</p>
            <p>{selected.description || <span className="muted">Sin detalles.</span>}</p>
            <Map center={{ lat: selected.lat, lng: selected.lng }} zoom={14} circle={{ lat: selected.lat, lng: selected.lng, radius: selected.radius_m }} points={[{ lat: selected.lat, lng: selected.lng }]} />
            <table className="facts">
              <tbody>
                <tr><td>Tipo</td><td>{selected.request_type === "VERIFY" ? "Verificar ubicaciones existentes" : "Registrar lugares nuevos"}{selected.category && ` · ${selected.category}`}</td></tr>
                <tr><td>Fecha deseada de fin</td><td>{selected.desired_end ?? "—"}</td></tr>
                <tr><td>Comuna</td><td>{selected.commune ?? "—"}</td></tr>
                <tr><td>Radio</td><td>{selected.radius_m} m</td></tr>
                <tr><td>Lugares pedidos</td><td>{selected.target_places}</td></tr>
                <tr><td>Presupuesto propuesto por la empresa</td><td>{usd(selected.proposed_budget_usd)}</td></tr>
                {selected.mission_code && (
                  <tr><td>Misión</td><td className="mono">{selected.mission_code} · {selected.mission_status} · {selected.approved_places} aprobados</td></tr>
                )}
                {selected.review_reason && <tr><td>Motivo</td><td>{selected.review_reason}</td></tr>}
              </tbody>
            </table>
            {selected.status === "PENDING" && (
              <>
                <label>
                  Recompensa por lugar para los colaboradores (USD)
                  <input type="number" step="0.01" min="0" value={reward} onChange={(e) => setReward(e.target.value)} />
                </label>
                <p className="muted small">
                  Exposición máxima de la misión: <b>{usd(exposure)}</b>. Al aprobar se crea una misión en borrador; la revisas y la activas en Misiones.
                </p>
                <div className="row gap">
                  <button className="btn primary" onClick={() => decide(selected, "APPROVED")}>Aprobar y crear misión</button>
                  <button className="btn danger" onClick={() => decide(selected, "REJECTED")}>Rechazar</button>
                </div>
              </>
            )}
          </div>
        ) : (
          <p className="muted center">Selecciona una solicitud.</p>
        )}
      </section>
    </div>
  );
}
