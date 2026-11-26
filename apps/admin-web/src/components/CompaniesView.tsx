"use client";

import { useCallback, useEffect, useState } from "react";
import { useRoles } from "@/components/AuthGate";
import { supabase } from "@/lib/supabase";
import { DocumentsSection, EstablishmentsSection } from "@/components/CompanyReviews";

type Org = {
  id: string;
  name: string;
  sector: string;
  legal_id: string | null;
  representative_name: string;
  contact_phone: string | null;
  contact_email: string | null;
  address: string | null;
  commune: string | null;
  status: string;
  review_reason: string | null;
  created_at: string;
};
type Claim = {
  id: string;
  org_name: string;
  status: string;
  evidence: string | null;
  place_code: string;
  place_name: string;
  place_category: string;
  created_at: string;
};

const ES: Record<string, string> = { PENDING: "En revisión", APPROVED: "Aprobado", REJECTED: "Rechazado" };

export default function CompaniesView() {
  const isAdmin = useRoles().includes("admin");
  const [orgs, setOrgs] = useState<Org[]>([]);
  const [claims, setClaims] = useState<Claim[]>([]);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [o, c] = await Promise.all([
      supabase.from("organizations").select("*").order("created_at", { ascending: false }),
      supabase.from("place_claims_view").select("*").order("created_at", { ascending: false }),
    ]);
    setError(o.error?.message ?? c.error?.message ?? null);
    setOrgs((o.data ?? []) as Org[]);
    setClaims((c.data ?? []) as Claim[]);
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  async function review(fn: "review_organization" | "review_place_claim", id: string, decision: "APPROVED" | "REJECTED") {
    let reason: string | null = null;
    if (decision === "REJECTED") {
      reason = prompt("Motivo del rechazo (lo verá la empresa):");
      if (!reason) return;
    }
    const args = fn === "review_organization" ? { p_org: id, p_decision: decision, p_reason: reason } : { p_claim: id, p_decision: decision, p_reason: reason };
    const { error } = await supabase.rpc(fn, args);
    setError(error?.message ?? null);
    load();
  }

  if (!isAdmin) return <p className="muted">Solo un administrador puede gestionar empresas.</p>;

  return (
    <div className="page">
      <h2>Empresas</h2>
      <p className="muted">Verificación de empresas, sus documentos y los establecimientos que registran.</p>
      {error && <p className="error">{error}</p>}
      <table className="table">
        <thead>
          <tr>
            <th>Empresa</th>
            <th>Representante y contacto</th>
            <th>Registro</th>
            <th>Estado</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {orgs.length === 0 && (
            <tr>
              <td colSpan={5} className="muted">Ninguna empresa registrada todavía.</td>
            </tr>
          )}
          {orgs.map((o) => (
            <tr key={o.id}>
              <td>
                <b>{o.name}</b>
                <div className="muted small">{o.sector} · {o.commune ?? "—"} · {o.address ?? ""}</div>
              </td>
              <td>
                {o.representative_name}
                <div className="muted small">{o.contact_phone ?? ""} {o.contact_email ?? ""}</div>
              </td>
              <td className="mono">{o.legal_id ?? "—"}</td>
              <td>
                <span className={`tag s-${o.status === "PENDING" ? "SUBMITTED" : o.status}`}>{ES[o.status]}</span>
                {o.review_reason && <div className="muted small">{o.review_reason}</div>}
              </td>
              <td>
                {o.status === "PENDING" && (
                  <div className="row gap">
                    <button className="btn small primary" onClick={() => review("review_organization", o.id, "APPROVED")}>Verificar</button>
                    <button className="btn small danger" onClick={() => review("review_organization", o.id, "REJECTED")}>Rechazar</button>
                  </div>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <DocumentsSection />
      <EstablishmentsSection />

      <h2>Reclamos de establecimientos</h2>
      <table className="table">
        <thead>
          <tr>
            <th>Lugar</th>
            <th>Empresa</th>
            <th>Prueba aportada</th>
            <th>Estado</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {claims.length === 0 && (
            <tr>
              <td colSpan={5} className="muted">Sin reclamos.</td>
            </tr>
          )}
          {claims.map((c) => (
            <tr key={c.id}>
              <td>
                <b>{c.place_name}</b>
                <div className="muted small mono">{c.place_code} · {c.place_category}</div>
              </td>
              <td>{c.org_name}</td>
              <td>{c.evidence ?? "—"}</td>
              <td><span className={`tag s-${c.status === "PENDING" ? "SUBMITTED" : c.status}`}>{ES[c.status]}</span></td>
              <td>
                {c.status === "PENDING" && (
                  <div className="row gap">
                    <button className="btn small primary" onClick={() => review("review_place_claim", c.id, "APPROVED")}>Aprobar</button>
                    <button className="btn small danger" onClick={() => review("review_place_claim", c.id, "REJECTED")}>Rechazar</button>
                  </div>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
