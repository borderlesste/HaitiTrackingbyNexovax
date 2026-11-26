"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import PageHead from "@/components/ui/PageHead";
import { fmtDate, supabase } from "@/lib/supabase";

type T = {
  id: string;
  code: string;
  user_id: string;
  category: string;
  subject: string;
  message: string;
  status: string;
  priority: string;
  admin_reply: string | null;
  created_at: string;
  updated_at: string;
};

const STATUS_ES: Record<string, string> = { OPEN: "Abierto", IN_PROGRESS: "En curso", RESOLVED: "Resuelto", CLOSED: "Cerrado" };
const CAT_ES: Record<string, string> = {
  GENERAL: "Consulta",
  CONTRIBUTION: "Aporte",
  REWARD: "Recompensa",
  WITHDRAWAL: "Retiro",
  ACCOUNT: "Cuenta",
  COMPANY: "Empresa",
  API: "API",
  COMPLAINT: "Reclamación",
};

export default function SupportView() {
  const [rows, setRows] = useState<T[]>([]);
  const [names, setNames] = useState<Record<string, { name: string; phone: string | null }>>({});
  const [filter, setFilter] = useState("open");
  const [selected, setSelected] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    let q = supabase.from("support_tickets").select("*").order("created_at", { ascending: false }).limit(300);
    if (filter === "open") q = q.in("status", ["OPEN", "IN_PROGRESS"]);
    const [t, u] = await Promise.all([q, supabase.rpc("admin_users")]);
    setError(t.error?.message ?? null);
    setRows((t.data ?? []) as T[]);
    setNames(Object.fromEntries(((u.data ?? []) as { id: string; full_name: string; phone: string | null }[]).map((x) => [x.id, { name: x.full_name, phone: x.phone }])));
  }, [filter]);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  return (
    <div className="split">
      <section className="list">
        <PageHead title="Soporte y reclamaciones">
          <select value={filter} onChange={(e) => setFilter(e.target.value)}>
            <option value="open">Abiertos</option>
            <option value="all">Todos</option>
          </select>
        </PageHead>
        {error && <p className="error">{error}</p>}
        {rows.length === 0 && <div className="empty">No hay casos {filter === "open" ? "abiertos" : ""}.</div>}
        {rows.map((t) => (
          <button key={t.id} className={`item ${selected?.id === t.id ? "sel" : ""}`} onClick={() => setSelected(t)}>
            <div className="row between">
              <b>{t.subject}</b>
              <span className={`tag s-${t.status}`}>{STATUS_ES[t.status]}</span>
            </div>
            <div className="muted small">
              {t.code} · {CAT_ES[t.category] ?? t.category} · {names[t.user_id]?.name || "—"} · {fmtDate(t.created_at)}
              {t.priority === "HIGH" && <span className="flag" style={{ marginLeft: 6 }}>Prioridad alta</span>}
            </div>
          </button>
        ))}
      </section>
      <section>
        {selected ? (
          <Ticket
            key={selected.id}
            t={selected}
            who={names[selected.user_id]}
            onDone={() => {
              setSelected(null);
              load();
            }}
          />
        ) : (
          <p className="muted center">Selecciona un caso para responder.</p>
        )}
      </section>
    </div>
  );
}

function Ticket({ t, who, onDone }: { t: T; who?: { name: string; phone: string | null }; onDone: () => void }) {
  const [reply, setReply] = useState(t.admin_reply ?? "");
  const [status, setStatus] = useState(t.status === "OPEN" ? "RESOLVED" : t.status);
  const [priority, setPriority] = useState(t.priority);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    const { error } = await supabase.rpc("admin_answer_ticket", { p_id: t.id, p_status: status, p_reply: reply, p_priority: priority });
    if (error) setError(error.message);
    else onDone();
  }

  return (
    <form className="card form" onSubmit={submit}>
      <div className="row between">
        <h2>{t.subject}</h2>
        <span className="mono muted">{t.code}</span>
      </div>
      <p className="muted small">
        {CAT_ES[t.category] ?? t.category} · {who?.name || t.user_id.slice(0, 8)} {who?.phone && `· ${who.phone}`} · {fmtDate(t.created_at)}
      </p>
      <p style={{ whiteSpace: "pre-wrap" }}>{t.message}</p>
      <label>
        Respuesta al usuario
        <textarea value={reply} onChange={(e) => setReply(e.target.value)} rows={4} />
      </label>
      <div className="row gap">
        <label>
          Estado
          <select value={status} onChange={(e) => setStatus(e.target.value)}>
            {Object.entries(STATUS_ES).map(([k, v]) => (
              <option key={k} value={k}>{v}</option>
            ))}
          </select>
        </label>
        <label>
          Prioridad
          <select value={priority} onChange={(e) => setPriority(e.target.value)}>
            <option value="LOW">Baja</option>
            <option value="NORMAL">Normal</option>
            <option value="HIGH">Alta</option>
          </select>
        </label>
      </div>
      {error && <p className="error">{error}</p>}
      <button className="btn primary">Guardar</button>
    </form>
  );
}
