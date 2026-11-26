"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useState } from "react";
import { ExternalLink } from "lucide-react";
import Modal from "@/components/ui/Modal";
import { fmtDate, supabase } from "@/lib/supabase";

const Map = dynamic(() => import("@/components/Map"), { ssr: false });

const ES: Record<string, string> = { PENDING: "En revisión", APPROVED: "Aprobado", REJECTED: "Rechazado" };
const DOC_ES: Record<string, string> = {
  LEGAL_REGISTRATION: "Registro legal (patente)",
  TAX_ID: "Identificación fiscal (NIF)",
  REPRESENTATIVE_ID: "Identidad del representante",
  PROOF_OF_ADDRESS: "Comprobante de domicilio",
  OTHER: "Otro",
};

type Doc = { id: string; org_name: string; doc_type: string; storage_path: string; file_name: string | null; status: string; review_reason: string | null; created_at: string };
type Est = {
  id: string;
  org_name: string;
  name: string;
  category: string;
  description: string;
  address: string | null;
  commune: string | null;
  phone: string | null;
  opening_hours: string | null;
  lat: number;
  lng: number;
  accuracy_m: number | null;
  photo_paths: string[];
  status: string;
  review_reason: string | null;
  place_code: string | null;
  updated_at: string;
};

async function openSigned(path: string) {
  const { data } = await supabase.storage.from("evidence").createSignedUrl(path, 300);
  if (data?.signedUrl) window.open(data.signedUrl, "_blank", "noopener");
}

function tag(status: string) {
  return <span className={`tag s-${status === "PENDING" ? "SUBMITTED" : status}`}>{ES[status] ?? status}</span>;
}

export function DocumentsSection() {
  const [docs, setDocs] = useState<Doc[]>([]);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data, error } = await supabase.from("organization_documents_view").select("*").order("created_at", { ascending: false });
    setError(error?.message ?? null);
    setDocs((data ?? []) as Doc[]);
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  async function review(d: Doc, decision: "APPROVED" | "REJECTED") {
    let reason: string | null = null;
    if (decision === "REJECTED") {
      reason = prompt("Motivo del rechazo (lo verá la empresa):");
      if (!reason) return;
    }
    const { error } = await supabase.rpc("review_organization_document", { p_id: d.id, p_decision: decision, p_reason: reason });
    setError(error?.message ?? null);
    load();
  }

  return (
    <>
      <h2>Documentos de verificación</h2>
      {error && <p className="error">{error}</p>}
      <table className="table">
        <thead>
          <tr><th>Empresa</th><th>Documento</th><th>Enviado</th><th>Estado</th><th></th></tr>
        </thead>
        <tbody>
          {docs.length === 0 && (
            <tr><td colSpan={5} className="muted">Sin documentos.</td></tr>
          )}
          {docs.map((d) => (
            <tr key={d.id}>
              <td>{d.org_name}</td>
              <td>
                {DOC_ES[d.doc_type] ?? d.doc_type}
                <div>
                  <button className="btn small" onClick={() => openSigned(d.storage_path)}>
                    <ExternalLink size={12} /> {d.file_name || "Ver archivo"}
                  </button>
                </div>
              </td>
              <td className="small">{fmtDate(d.created_at)}</td>
              <td>{tag(d.status)}{d.review_reason && <div className="muted small">{d.review_reason}</div>}</td>
              <td>
                {d.status === "PENDING" && (
                  <div className="row gap">
                    <button className="btn small primary" onClick={() => review(d, "APPROVED")}>Aceptar</button>
                    <button className="btn small danger" onClick={() => review(d, "REJECTED")}>Rechazar</button>
                  </div>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}

export function EstablishmentsSection() {
  const [rows, setRows] = useState<Est[]>([]);
  const [filter, setFilter] = useState("PENDING");
  const [selected, setSelected] = useState<Est | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    let q = supabase.from("org_establishments_view").select("*").order("updated_at", { ascending: false });
    if (filter !== "all") q = q.eq("status", filter);
    const { data, error } = await q;
    setError(error?.message ?? null);
    setRows((data ?? []) as Est[]);
  }, [filter]);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  return (
    <>
      <div className="head">
        <h2>Establecimientos registrados por empresas</h2>
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="PENDING">Por revisar</option>
          <option value="APPROVED">Aprobados</option>
          <option value="REJECTED">Rechazados</option>
          <option value="all">Todos</option>
        </select>
      </div>
      {error && <p className="error">{error}</p>}
      <table className="table">
        <thead>
          <tr><th>Establecimiento</th><th>Empresa</th><th>Dirección</th><th>Estado</th><th></th></tr>
        </thead>
        <tbody>
          {rows.length === 0 && (
            <tr><td colSpan={5} className="muted">Nada en este filtro.</td></tr>
          )}
          {rows.map((e) => (
            <tr key={e.id}>
              <td><b>{e.name}</b><div className="muted small">{e.category}{e.place_code && ` · ${e.place_code}`}</div></td>
              <td>{e.org_name}</td>
              <td className="small">{[e.address, e.commune].filter(Boolean).join(", ") || "—"}</td>
              <td>{tag(e.status)}</td>
              <td><button className="btn small" onClick={() => setSelected(e)}>Revisar</button></td>
            </tr>
          ))}
        </tbody>
      </table>
      {selected && (
        <Modal title={selected.name} onClose={() => setSelected(null)}>
          <EstablishmentDetail
            e={selected}
            onDone={() => {
              setSelected(null);
              load();
            }}
          />
        </Modal>
      )}
    </>
  );
}

function EstablishmentDetail({ e, onDone }: { e: Est; onDone: () => void }) {
  const [photos, setPhotos] = useState<string[]>([]);
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (e.photo_paths?.length)
      supabase.storage
        .from("evidence")
        .createSignedUrls(e.photo_paths, 600)
        .then(({ data }) => setPhotos((data ?? []).map((d) => d.signedUrl).filter((u): u is string => !!u)));
  }, [e]);

  async function decide(decision: "APPROVED" | "REJECTED") {
    if (decision === "REJECTED" && !reason.trim()) return setError("Escribe el motivo para la empresa.");
    const { error } = await supabase.rpc("review_establishment", { p_id: e.id, p_decision: decision, p_reason: reason.trim() || null });
    if (error) setError(error.message);
    else onDone();
  }

  return (
    <div className="form">
      <p className="muted">{e.org_name} · {e.category} · actualizado {fmtDate(e.updated_at)}</p>
      <div className="row gap" style={{ flexWrap: "wrap" }}>
        {photos.map((u, i) => (
          <a key={i} href={u} target="_blank" rel="noreferrer">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={u} alt={`Foto ${i + 1}`} style={{ width: 140, height: 100, objectFit: "cover", borderRadius: 8 }} />
          </a>
        ))}
        {photos.length === 0 && <span className="muted small">Sin fotos.</span>}
      </div>
      <Map center={{ lat: e.lat, lng: e.lng }} zoom={17} points={[{ lat: e.lat, lng: e.lng, label: e.name }]} height={220} />
      <table className="facts">
        <tbody>
          <tr><td>Descripción</td><td>{e.description || "—"}</td></tr>
          <tr><td>Dirección</td><td>{[e.address, e.commune].filter(Boolean).join(", ") || "—"}</td></tr>
          <tr><td>Teléfono · horario</td><td>{e.phone ?? "—"} · {e.opening_hours ?? "—"}</td></tr>
          <tr><td>GPS</td><td className="mono">{e.lat.toFixed(5)}, {e.lng.toFixed(5)} {e.accuracy_m && `±${Math.round(e.accuracy_m)} m`}</td></tr>
          {e.review_reason && <tr><td>Motivo anterior</td><td>{e.review_reason}</td></tr>}
        </tbody>
      </table>
      <p className="muted small">Al aprobar se publica (o actualiza) como lugar verificado en el mapa.</p>
      <label>
        Motivo (obligatorio para rechazar)
        <textarea value={reason} onChange={(ev) => setReason(ev.target.value)} rows={2} />
      </label>
      {error && <p className="error">{error}</p>}
      <div className="row gap">
        <button className="btn primary" onClick={() => decide("APPROVED")}>Aprobar y publicar</button>
        <button className="btn danger" onClick={() => decide("REJECTED")}>Rechazar</button>
      </div>
    </div>
  );
}
