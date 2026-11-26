"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { Pause, Pencil, Play, Plus, Square, X } from "lucide-react";
import { useRoles } from "@/components/AuthGate";
import Modal from "@/components/ui/Modal";
import PageHead from "@/components/ui/PageHead";
import { fmtDate, getSetting, MISSION_STATUS_ES, supabase, usd } from "@/lib/supabase";

const Map = dynamic(() => import("@/components/Map"), { ssr: false });

export type Mission = {
  id: string;
  code: string;
  type: string;
  title: string;
  description: string;
  department: string | null;
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
  requires_on_site_evidence: boolean;
  requirements: string;
  start_at: string | null;
  end_at: string | null;
  created_at: string;
  contributions_count: number;
  approved_count: number;
};

export const TYPES: Record<string, string> = {
  NEW_PLACE: "Lugar nuevo",
  PRIORITY_PLACE: "Zona prioritaria",
  MAJOR_CORRECTION: "Corrección importante",
  INDEPENDENT_CHECK: "Verificación independiente",
  BATCH_ZONE: "Lote en zona (con bono)",
};
const FALLBACK_REWARDS: Record<string, number> = { NEW_PLACE: 0.25, PRIORITY_PLACE: 0.5, MAJOR_CORRECTION: 0.1, INDEPENDENT_CHECK: 0.05, BATCH_ZONE: 0.25 };
export const PAP = { lat: 18.5392, lng: -72.335 };
const DEPARTMENTS = ["Ouest", "Nord", "Nord-Est", "Nord-Ouest", "Artibonite", "Centre", "Sud", "Sud-Est", "Grand'Anse", "Nippes"];
const OPEN = ["DRAFT", "IN_REVIEW", "APPROVED", "SCHEDULED", "ACTIVE", "PAUSED"];

export default function MissionsView() {
  const isAdmin = useRoles().includes("admin");
  const [missions, setMissions] = useState<Mission[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Mission | "new" | null>(null);
  const [filter, setFilter] = useState("open");
  const [q, setQ] = useState("");

  const load = useCallback(async () => {
    const { data, error } = await supabase.from("missions_admin").select("*").order("created_at", { ascending: false });
    if (error) setError(error.message);
    else setMissions((data ?? []) as Mission[]);
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  async function setStatus(m: Mission, status: string) {
    if (["COMPLETED", "CANCELLED"].includes(status) && !confirm(`¿${status === "COMPLETED" ? "Cerrar" : "Cancelar"} la misión ${m.code}? Dejará de aparecer en el mapa de los colaboradores.`)) return;
    const { error } = await supabase.from("missions").update({ status, updated_at: new Date().toISOString() }).eq("id", m.id);
    if (error) setError(error.message);
    load();
  }

  const shown = useMemo(() => {
    const t = q.trim().toLowerCase();
    return missions.filter(
      (m) =>
        (filter === "all" || (filter === "open" ? OPEN.includes(m.status) : m.status === filter)) &&
        (!t || `${m.code} ${m.title} ${m.commune ?? ""}`.toLowerCase().includes(t)),
    );
  }, [missions, filter, q]);

  return (
    <div className="page">
      <PageHead title="Misiones" subtitle="Las misiones activas aparecen en el mapa de los colaboradores.">
        <input placeholder="Buscar código, título o comuna" value={q} onChange={(e) => setQ(e.target.value)} />
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="open">Abiertas</option>
          <option value="all">Todas</option>
          {Object.entries(MISSION_STATUS_ES).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>
        {isAdmin && (
          <button className="btn primary" onClick={() => setEditing("new")}>
            <Plus size={14} /> Crear misión
          </button>
        )}
      </PageHead>
      {!isAdmin && <p className="muted">Solo un administrador puede crear, editar o pausar misiones.</p>}
      {error && <p className="error">{error}</p>}

      <Map
        center={PAP}
        zoom={11}
        height={320}
        points={shown.map((m) => ({
          lat: m.lat,
          lng: m.lng,
          label: `${m.code} · ${usd(m.individual_reward_usd)} · ${MISSION_STATUS_ES[m.status] ?? m.status}`,
          color: m.status === "ACTIVE" ? "#0d47c2" : "#999",
        }))}
        circles={shown.filter((m) => m.radius_m).map((m) => ({ lat: m.lat, lng: m.lng, radius: m.radius_m!, color: m.status === "ACTIVE" ? "#0d47c2" : "#999" }))}
      />

      <div className="scroll">
        <table className="table">
          <thead>
            <tr>
              <th>Código</th>
              <th>Misión</th>
              <th>Tipo</th>
              <th className="num">Recompensa</th>
              <th className="num">Aportes (aprob.)</th>
              <th className="num">Presupuesto</th>
              <th>Vigencia</th>
              <th>Estado</th>
              {isAdmin && <th></th>}
            </tr>
          </thead>
          <tbody>
            {shown.map((m) => (
              <tr key={m.id}>
                <td className="mono">{m.code}</td>
                <td>
                  {m.title}
                  <div className="muted small">
                    {[m.commune, m.department].filter(Boolean).join(", ") || "—"} · radio {m.radius_m ?? "—"} m
                    {!m.requires_on_site_evidence && " · sin presencia física"}
                  </div>
                </td>
                <td>{TYPES[m.type] ?? m.type}</td>
                <td className="num">
                  {usd(m.individual_reward_usd)}
                  {Number(m.completion_bonus_usd) > 0 && <div className="muted small">+ bono {usd(m.completion_bonus_usd)}</div>}
                </td>
                <td className="num">
                  {m.contributions_count} ({m.approved_count})
                  <div className="muted small">meta {m.required_approved_contributions}/persona</div>
                </td>
                <td className="num">{usd(m.budget_authorized_usd)}</td>
                <td className="small">{fmtDate(m.end_at, false)}</td>
                <td>
                  <span className={`tag m-${m.status}`}>{MISSION_STATUS_ES[m.status] ?? m.status}</span>
                </td>
                {isAdmin && (
                  <td>
                    <div className="row gap">
                      {OPEN.includes(m.status) && (
                        <button className="btn small" title="Editar" onClick={() => setEditing(m)}><Pencil size={12} /></button>
                      )}
                      {m.status === "ACTIVE" ? (
                        <button className="btn small" title="Pausar" onClick={() => setStatus(m, "PAUSED")}><Pause size={12} /> Pausar</button>
                      ) : ["DRAFT", "PAUSED", "APPROVED", "SCHEDULED", "IN_REVIEW"].includes(m.status) ? (
                        <button className="btn small primary" title="Activar" onClick={() => setStatus(m, "ACTIVE")}><Play size={12} /> Activar</button>
                      ) : null}
                      {["ACTIVE", "PAUSED"].includes(m.status) && (
                        <button className="btn small" title="Cerrar" onClick={() => setStatus(m, "COMPLETED")}><Square size={12} /> Cerrar</button>
                      )}
                      {["DRAFT", "IN_REVIEW", "APPROVED", "SCHEDULED"].includes(m.status) && (
                        <button className="btn small" title="Cancelar" onClick={() => setStatus(m, "CANCELLED")}><X size={12} /></button>
                      )}
                    </div>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
        {shown.length === 0 && <div className="empty">No hay misiones con este filtro.</div>}
      </div>

      {editing && (
        <Modal title={editing === "new" ? "Crear misión" : `Editar ${editing.code}`} onClose={() => setEditing(null)}>
          <MissionForm
            mission={editing === "new" ? null : editing}
            onSaved={() => {
              setEditing(null);
              load();
            }}
          />
        </Modal>
      )}
    </div>
  );
}

function MissionForm({ mission, onSaved }: { mission: Mission | null; onSaved: () => void }) {
  const [defaults, setDefaults] = useState<Record<string, number>>(FALLBACK_REWARDS);
  const [type, setType] = useState(mission?.type ?? "NEW_PLACE");
  const [code, setCode] = useState(mission?.code ?? "");
  const [title, setTitle] = useState(mission?.title ?? "");
  const [description, setDescription] = useState(mission?.description ?? "");
  const [requirements, setRequirements] = useState(mission?.requirements ?? "GPS + foto + datos del lugar");
  const [department, setDepartment] = useState(mission?.department ?? "Ouest");
  const [commune, setCommune] = useState(mission?.commune ?? "");
  const [point, setPoint] = useState(mission ? { lat: mission.lat, lng: mission.lng } : PAP);
  const [radius, setRadius] = useState(mission?.radius_m ?? 500);
  const [onSite, setOnSite] = useState(mission?.requires_on_site_evidence ?? true);
  const [reward, setReward] = useState(String(mission?.individual_reward_usd ?? FALLBACK_REWARDS.NEW_PLACE));
  const [bonus, setBonus] = useState(String(mission?.completion_bonus_usd ?? "0"));
  const [required, setRequired] = useState(mission?.required_approved_contributions ?? 1);
  const [maxParticipants, setMaxParticipants] = useState(mission?.max_participants ?? 50);
  const [start, setStart] = useState(() => (mission?.start_at ?? new Date().toISOString()).slice(0, 10));
  const [end, setEnd] = useState(() => (mission?.end_at ?? new Date(Date.now() + 30 * 86400000).toISOString()).slice(0, 10));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getSetting<{ defaults: Record<string, number> }>("rewards", { defaults: FALLBACK_REWARDS }).then((s) => {
      setDefaults(s.defaults);
      if (!mission) setReward(String(s.defaults.NEW_PLACE ?? FALLBACK_REWARDS.NEW_PLACE));
    });
  }, [mission]);

  // Exposición máxima = participantes × (aportes × recompensa + bono)
  const maxExposure = maxParticipants * (required * Number(reward || 0) + Number(bonus || 0));

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (end < start) return setError("La fecha de fin es anterior a la de inicio.");
    setBusy(true);
    setError(null);
    const row = {
      code: code.trim().toUpperCase(),
      type,
      title: title.trim(),
      description: description.trim(),
      requirements: requirements.trim() || "GPS + foto + datos del lugar",
      department: department || null,
      commune: commune.trim() || null,
      center: `SRID=4326;POINT(${point.lng} ${point.lat})`,
      radius_m: radius,
      requires_on_site_evidence: onSite,
      required_approved_contributions: required,
      individual_reward_usd: Number(reward).toFixed(2),
      completion_bonus_usd: Number(bonus || 0).toFixed(2),
      max_participants: maxParticipants,
      budget_authorized_usd: maxExposure.toFixed(2),
      start_at: new Date(start + "T00:00:00").toISOString(),
      end_at: new Date(end + "T23:59:59").toISOString(),
      updated_at: new Date().toISOString(),
    };
    const { error } = mission
      ? await supabase.from("missions").update(row).eq("id", mission.id)
      : await supabase.from("missions").insert({ ...row, status: "DRAFT", created_by: (await supabase.auth.getUser()).data.user?.id });
    setBusy(false);
    if (error) setError(error.message.includes("duplicate key") ? "Ya existe una misión con ese código." : error.message);
    else onSaved();
  }

  return (
    <form className="form" onSubmit={submit}>
      <div className="row gap">
        <label>
          Tipo
          <select
            value={type}
            onChange={(e) => {
              setType(e.target.value);
              setReward(String(defaults[e.target.value] ?? FALLBACK_REWARDS[e.target.value]));
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
      </div>
      <label>
        Objetivo (título)
        <input value={title} onChange={(e) => setTitle(e.target.value)} required placeholder="Registrar 5 comercios locales" />
      </label>
      <label>
        Descripción para el colaborador
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2} />
      </label>
      <label>
        Requisitos
        <input value={requirements} onChange={(e) => setRequirements(e.target.value)} />
      </label>
      <div className="row gap">
        <label>
          Departamento
          <select value={department} onChange={(e) => setDepartment(e.target.value)}>
            {DEPARTMENTS.map((d) => (
              <option key={d}>{d}</option>
            ))}
          </select>
        </label>
        <label>
          Comuna
          <input value={commune} onChange={(e) => setCommune(e.target.value)} placeholder="Delmas" />
        </label>
      </div>

      <p className="muted small">Zona GPS: haz clic en el mapa para ubicar el centro de la misión y ajusta el radio.</p>
      <Map center={point} zoom={14} points={[point]} circles={[{ ...point, radius }]} onPick={setPoint} height={260} />
      <div className="row gap">
        <label>
          Radio: {radius} m
          <input type="range" min={100} max={5000} step={50} value={radius} onChange={(e) => setRadius(Number(e.target.value))} />
        </label>
        <p className="muted small mono">{point.lat.toFixed(5)}, {point.lng.toFixed(5)}</p>
      </div>
      <label style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
        <input type="checkbox" checked={onSite} onChange={(e) => setOnSite(e.target.checked)} />
        Exigir presencia física dentro de la zona (GPS)
      </label>

      <div className="row gap">
        <label>
          Recompensa USD
          <input type="number" step="0.01" min="0" value={reward} onChange={(e) => setReward(e.target.value)} required />
        </label>
        <label>
          Bono al completar USD
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
      </div>
      <div className="row gap">
        <label>
          Inicio
          <input type="date" value={start} onChange={(e) => setStart(e.target.value)} />
        </label>
        <label>
          Fin
          <input type="date" value={end} onChange={(e) => setEnd(e.target.value)} />
        </label>
      </div>
      <p className="small">
        Presupuesto a autorizar (exposición máxima): <b>{usd(maxExposure)}</b>
        <span className="muted"> = {maxParticipants} × ({required} × {usd(reward)} + {usd(bonus || 0)})</span>
      </p>
      {error && <p className="error">{error}</p>}
      <button className="btn primary" disabled={busy}>
        {busy ? "Guardando…" : mission ? "Guardar cambios" : "Crear como borrador"}
      </button>
      {!mission && <p className="muted small">Se crea como borrador. Actívala desde la lista para publicarla en el mapa.</p>}
    </form>
  );
}
