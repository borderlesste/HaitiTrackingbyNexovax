"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useState } from "react";
import { supabase, usd } from "@/lib/supabase";

const Map = dynamic(() => import("@/components/Map"), { ssr: false });

type Item = {
  id: string;
  created_at: string;
  status: string;
  name: string;
  category: string;
  address_reference: string | null;
  notes: string | null;
  accuracy_m: number | null;
  captured_at: string;
  photo_paths: string[];
  review_reason: string | null;
  user_id: string;
  author_name: string | null;
  mission_code: string;
  mission_title: string;
  individual_reward_usd: number;
  lat: number;
  lng: number;
  distance_to_mission_m: number;
};

type Dup = { source: string; code: string | null; name: string; category: string; distance_m: number; name_similarity: number };

const PENDING = ["SUBMITTED", "AUTO_CHECKED", "HUMAN_REVIEW"];
const STATUS_ES: Record<string, string> = {
  SUBMITTED: "Enviado",
  AUTO_CHECKED: "Revisado auto",
  HUMAN_REVIEW: "En revisión",
  APPROVED: "Aprobado",
  REJECTED: "Rechazado",
  NEEDS_CHANGES: "Requiere cambios",
  APPEALED: "Apelado",
};

export default function ReviewQueuePage() {
  const [filter, setFilter] = useState<"pending" | "all">("pending");
  const [items, setItems] = useState<Item[]>([]);
  const [selected, setSelected] = useState<Item | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    let q = supabase.from("review_queue").select("*").order("created_at", { ascending: true }).limit(200);
    if (filter === "pending") q = q.in("status", PENDING);
    const { data, error } = await q;
    if (error) setError(error.message);
    else {
      setError(null);
      setItems((data ?? []) as Item[]);
    }
    setLoading(false);
  }, [filter]);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  return (
    <div className="split">
      <section className="list">
        <div className="row between">
          <h2>Cola de revisión</h2>
          <select value={filter} onChange={(e) => {
              setLoading(true);
              setFilter(e.target.value as "pending" | "all");
            }}>
            <option value="pending">Pendientes</option>
            <option value="all">Todos</option>
          </select>
        </div>
        {error && <p className="error">{error}</p>}
        {loading ? (
          <p className="muted">Cargando…</p>
        ) : items.length === 0 ? (
          <p className="muted">No hay aportes {filter === "pending" ? "pendientes" : ""}.</p>
        ) : (
          items.map((it) => (
            <button key={it.id} className={`item ${selected?.id === it.id ? "sel" : ""}`} onClick={() => setSelected(it)}>
              <div className="row between">
                <b>{it.name}</b>
                <span className={`tag s-${it.status}`}>{STATUS_ES[it.status] ?? it.status}</span>
              </div>
              <div className="muted small">
                {it.category} · {it.mission_code} · {new Date(it.created_at).toLocaleString("es")}
              </div>
            </button>
          ))
        )}
      </section>
      <section className="detail">
        {selected ? (
          <Detail
            key={selected.id}
            item={selected}
            onDone={async () => {
              setSelected(null);
              await load();
            }}
          />
        ) : (
          <p className="muted center">Selecciona un aporte para revisarlo.</p>
        )}
      </section>
    </div>
  );
}

function Detail({ item, onDone }: { item: Item; onDone: () => void }) {
  const [photoUrl, setPhotoUrl] = useState<string | null>(null);
  const [dups, setDups] = useState<Dup[]>([]);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  useEffect(() => {
    const path = item.photo_paths?.[0];
    if (path) {
      supabase.storage
        .from("evidence")
        .createSignedUrl(path, 600)
        .then(({ data }) => setPhotoUrl(data?.signedUrl ?? null));
    }
    supabase
      .rpc("check_duplicates", { lat: item.lat, lng: item.lng, place_name: item.name })
      .then(({ data }) => setDups(((data ?? []) as Dup[]).filter((d) => !(d.source === "pending" && d.name === item.name && d.distance_m < 0.5))));
  }, [item]);

  async function decide(decision: "APPROVED" | "REJECTED" | "NEEDS_CHANGES") {
    if (decision !== "APPROVED" && !reason.trim()) {
      setMsg("Escribe el motivo para el colaborador.");
      return;
    }
    setBusy(true);
    setMsg(null);
    const { data, error } = await supabase.rpc("review_contribution", {
      p_contribution_id: item.id,
      p_decision: decision,
      p_reason: reason.trim() || null,
    });
    setBusy(false);
    if (error) {
      setMsg(error.message);
      return;
    }
    const r = data as { reward_usd?: number; bonus_usd?: number };
    if (decision === "APPROVED") {
      alert(`Aprobado. Recompensa: ${usd(r.reward_usd)}${r.bonus_usd ? ` + bono ${usd(r.bonus_usd)}` : ""}`);
    }
    onDone();
  }

  const pending = PENDING.includes(item.status);
  const lowAccuracy = (item.accuracy_m ?? 999) > 30;
  const mocked = item.notes?.includes("ubicación simulada");

  return (
    <div className="card">
      <div className="row between">
        <h2>{item.name}</h2>
        <span className={`tag s-${item.status}`}>{STATUS_ES[item.status] ?? item.status}</span>
      </div>
      <p className="muted">
        {item.category} · {item.mission_code} — {item.mission_title}
      </p>

      <div className="grid2">
        <div>
          {photoUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={photoUrl} alt="Evidencia" className="photo" />
          ) : (
            <div className="photo placeholder">Sin foto</div>
          )}
        </div>
        <Map
          center={{ lat: item.lat, lng: item.lng }}
          zoom={17}
          points={[
            { lat: item.lat, lng: item.lng, label: item.name },
          ]}
        />
      </div>

      <table className="facts">
        <tbody>
          <tr><td>Autor</td><td>{item.author_name || item.user_id.slice(0, 8)}</td></tr>
          <tr><td>Referencia</td><td>{item.address_reference || "—"}</td></tr>
          <tr><td>Notas</td><td>{item.notes || "—"}</td></tr>
          <tr><td>GPS</td><td>{item.lat.toFixed(5)}, {item.lng.toFixed(5)} · ±{Math.round(item.accuracy_m ?? 0)} m {lowAccuracy && <span className="warn">precisión baja</span>}</td></tr>
          <tr><td>Distancia al centro de la misión</td><td>{Math.round(item.distance_to_mission_m)} m</td></tr>
          <tr><td>Capturado</td><td>{new Date(item.captured_at).toLocaleString("es")}</td></tr>
          <tr><td>Recompensa si se aprueba</td><td><b>{usd(item.individual_reward_usd)}</b></td></tr>
          {item.review_reason && <tr><td>Motivo anterior</td><td>{item.review_reason}</td></tr>}
        </tbody>
      </table>

      {mocked && <p className="warn">⚠ El teléfono indicó ubicación simulada. Revisa con cuidado.</p>}

      <h3>Posibles duplicados cerca</h3>
      {dups.length === 0 ? (
        <p className="muted small">Ninguno en 60 m.</p>
      ) : (
        <ul className="dups">
          {dups.map((d, i) => (
            <li key={i}>
              <b>{d.name}</b> · {d.category} · a {Math.round(d.distance_m)} m · similitud {Math.round(d.name_similarity * 100)}%
              {d.source === "pending" ? " · en revisión" : d.code ? ` · ${d.code}` : ""}
            </li>
          ))}
        </ul>
      )}

      {pending && (
        <>
          <label>
            Motivo (obligatorio para rechazar o pedir cambios)
            <textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={2} />
          </label>
          {msg && <p className="error">{msg}</p>}
          <div className="row gap">
            <button className="btn primary" disabled={busy} onClick={() => decide("APPROVED")}>Aprobar</button>
            <button className="btn" disabled={busy} onClick={() => decide("NEEDS_CHANGES")}>Pedir cambios</button>
            <button className="btn danger" disabled={busy} onClick={() => decide("REJECTED")}>Rechazar</button>
          </div>
        </>
      )}
    </div>
  );
}
