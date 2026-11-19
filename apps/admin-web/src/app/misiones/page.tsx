"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useState, type FormEvent } from "react";
import { useRoles } from "@/components/AuthGate";
import { supabase, usd } from "@/lib/supabase";

const Map = dynamic(() => import("@/components/Map"), { ssr: false });

type Mission = {
  id: string;
  code: string;
  type: string;
  title: string;
  commune: string | null;
  status: string;
  lat: number;
  lng: number;
  radius_m: number | null;
  individual_reward_usd: number;
  completion_bonus_usd: number;
  required_approved_contributions: number;
  max_participants: number | null;
  budget_authorized_usd: number;
  end_at: string | null;
  contributions_count: number;
  approved_count: number;
};

const TYPES: Record<string, string> = {
  NEW_PLACE: "Lugar nuevo",
  PRIORITY_PLACE: "Zona prioritaria",
  MAJOR_CORRECTION: "Corrección importante",
  INDEPENDENT_CHECK: "Verificación independiente",
  BATCH_ZONE: "Lote en zona (con bono)",
};
const DEFAULT_REWARD: Record<string, string> = {
  NEW_PLACE: "0.25",
  PRIORITY_PLACE: "0.50",
  MAJOR_CORRECTION: "0.10",
  INDEPENDENT_CHECK: "0.05",
  BATCH_ZONE: "0.25",
};
const PAP = { lat: 18.5392, lng: -72.335 };

export default function MissionsPage() {
  const roles = useRoles();
  const isAdmin = roles.includes("admin");
  const [missions, setMissions] = useState<Mission[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);

  const load = useCallback(async () => {
    const { data, error } = await supabase.from("missions_admin").select("*").order("created_at", { ascending: false });
    if (error) setError(error.message);
    else setMissions((data ?? []) as Mission[]);
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  async function setStatus(m: Mission, status: string) {
    const { error } = await supabase.from("missions").update({ status, updated_at: new Date().toISOString() }).eq("id", m.id);
    if (error) alert(error.message);
    load();
  }

  return (
    <div className="page">
      <div className="row between">
        <h2>Misiones</h2>
        {isAdmin && (
          <button className="btn primary" onClick={() => setShowForm((v) => !v)}>
            {showForm ? "Cerrar" : "Nueva misión"}
          </button>
        )}
      </div>
      {!isAdmin && <p className="muted">Solo un administrador puede crear o pausar misiones.</p>}
      {showForm && (
        <NewMission
          onCreated={() => {
            setShowForm(false);
            load();
          }}
        />
      )}
      {error && <p className="error">{error}</p>}

      <Map
        center={PAP}
        zoom={12}
        height={320}
        points={missions.map((m) => ({
          lat: m.lat,
          lng: m.lng,
          label: `${m.code} · ${usd(m.individual_reward_usd)} · ${m.status}`,
          color: m.status === "ACTIVE" ? "#0d47c2" : "#999",
        }))}
      />

      <table className="table">
        <thead>
          <tr>
            <th>Código</th>
            <th>Misión</th>
            <th>Tipo</th>
            <th>Recompensa</th>
            <th>Aportes (aprob.)</th>
            <th>Presupuesto</th>
            <th>Estado</th>
            {isAdmin && <th></th>}
          </tr>
        </thead>
        <tbody>
          {missions.map((m) => (
            <tr key={m.id}>
              <td className="mono">{m.code}</td>
              <td>
                {m.title}
                <div className="muted small">{m.commune} · radio {m.radius_m ?? "—"} m</div>
              </td>
              <td>{TYPES[m.type] ?? m.type}</td>
              <td>
                {usd(m.individual_reward_usd)}
                {Number(m.completion_bonus_usd) > 0 && <div className="muted small">+ bono {usd(m.completion_bonus_usd)}</div>}
              </td>
              <td>
                {m.contributions_count} ({m.approved_count})
              </td>
              <td>{usd(m.budget_authorized_usd)}</td>
              <td>
                <span className={`tag m-${m.status}`}>{m.status}</span>
              </td>
              {isAdmin && (
                <td>
                  {m.status === "ACTIVE" ? (
                    <button className="btn small" onClick={() => setStatus(m, "PAUSED")}>Pausar</button>
                  ) : ["DRAFT", "PAUSED", "APPROVED", "SCHEDULED"].includes(m.status) ? (
                    <button className="btn small primary" onClick={() => setStatus(m, "ACTIVE")}>Activar</button>
                  ) : null}
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function NewMission({ onCreated }: { onCreated: () => void }) {
  const [type, setType] = useState("NEW_PLACE");
  const [code, setCode] = useState("");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [commune, setCommune] = useState("");
  const [point, setPoint] = useState(PAP);
  const [radius, setRadius] = useState(500);
  const [reward, setReward] = useState(DEFAULT_REWARD.NEW_PLACE);
  const [bonus, setBonus] = useState("0");
  const [required, setRequired] = useState(1);
  const [maxParticipants, setMaxParticipants] = useState(50);
  const [days, setDays] = useState(30);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Exposición máxima = participantes × (aportes × recompensa + bono)
  const maxExposure = maxParticipants * (required * Number(reward || 0) + Number(bonus || 0));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await supabase.from("missions").insert({
      code: code.trim().toUpperCase(),
      type,
      title: title.trim(),
      description: description.trim(),
      commune: commune.trim() || null,
      center: `SRID=4326;POINT(${point.lng} ${point.lat})`,
      radius_m: radius,
      required_approved_contributions: required,
      individual_reward_usd: reward,
      completion_bonus_usd: bonus || "0",
      max_participants: maxParticipants,
      budget_authorized_usd: maxExposure.toFixed(2),
      start_at: new Date().toISOString(),
      end_at: new Date(Date.now() + days * 86400000).toISOString(),
      status: "DRAFT",
      created_by: (await supabase.auth.getUser()).data.user?.id,
    });
    setBusy(false);
    if (error) setError(error.message);
    else onCreated();
  }

  return (
    <form className="card" onSubmit={submit}>
      <h3>Nueva misión (se crea como borrador)</h3>
      <div className="grid2">
        <div className="form">
          <label>
            Tipo
            <select
              value={type}
              onChange={(e) => {
                setType(e.target.value);
                setReward(DEFAULT_REWARD[e.target.value]);
                if (e.target.value === "BATCH_ZONE") {
                  setRequired(5);
                  setBonus("1.00");
                }
              }}
            >
              {Object.entries(TYPES).map(([k, v]) => (
                <option key={k} value={k}>{v}</option>
              ))}
            </select>
          </label>
          <label>
            Código
            <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="MIS-DEL-0003" required />
          </label>
          <label>
            Título
            <input value={title} onChange={(e) => setTitle(e.target.value)} required />
          </label>
          <label>
            Descripción para el colaborador
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2} />
          </label>
          <label>
            Comuna
            <input value={commune} onChange={(e) => setCommune(e.target.value)} placeholder="Delmas" />
          </label>
          <div className="row gap">
            <label>
              Recompensa USD
              <input type="number" step="0.01" min="0" value={reward} onChange={(e) => setReward(e.target.value)} required />
            </label>
            <label>
              Bono USD
              <input type="number" step="0.01" min="0" value={bonus} onChange={(e) => setBonus(e.target.value)} />
            </label>
          </div>
          <div className="row gap">
            <label>
              Aportes requeridos
              <input type="number" min={1} value={required} onChange={(e) => setRequired(Number(e.target.value))} />
            </label>
            <label>
              Máx. participantes
              <input type="number" min={1} value={maxParticipants} onChange={(e) => setMaxParticipants(Number(e.target.value))} />
            </label>
            <label>
              Días activa
              <input type="number" min={1} value={days} onChange={(e) => setDays(Number(e.target.value))} />
            </label>
          </div>
          <p className="muted small">
            Exposición máxima (presupuesto a autorizar): <b>{usd(maxExposure)}</b>
          </p>
        </div>
        <div>
          <p className="muted small">Haz clic en el mapa para ubicar el centro de la misión.</p>
          <Map center={point} zoom={14} points={[point]} circle={{ ...point, radius }} onPick={setPoint} height={300} />
          <label>
            Radio: {radius} m
            <input type="range" min={100} max={3000} step={50} value={radius} onChange={(e) => setRadius(Number(e.target.value))} />
          </label>
          <p className="muted small mono">
            {point.lat.toFixed(5)}, {point.lng.toFixed(5)}
          </p>
        </div>
      </div>
      {error && <p className="error">{error}</p>}
      <button className="btn primary" disabled={busy}>
        {busy ? "Guardando…" : "Crear borrador"}
      </button>
    </form>
  );
}
