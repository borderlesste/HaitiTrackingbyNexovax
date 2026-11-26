"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Ban } from "lucide-react";
import { useRoles } from "@/components/AuthGate";
import PageHead from "@/components/ui/PageHead";
import { fmtDate, supabase } from "@/lib/supabase";

type Row = {
  id: string;
  created_at: string;
  status: string;
  name: string;
  category: string;
  user_id: string;
  author_name: string | null;
  accuracy_m: number | null;
  mission_code: string;
  distance_to_mission_m: number;
  radius_m: number | null;
  near_places: number;
  near_contributions: number;
  user_last_hour: number;
  mocked_location: boolean;
  low_accuracy: boolean;
  outside_area: boolean;
  no_photo: boolean;
};

const STATUS_ES: Record<string, string> = {
  SUBMITTED: "Enviado",
  AUTO_CHECKED: "Revisado auto",
  HUMAN_REVIEW: "En revisión",
  APPROVED: "Aprobado",
  REJECTED: "Rechazado",
  NEEDS_CHANGES: "Requiere cambios",
};

/** Puntuación simple de riesgo: más alta = revisar primero. */
function score(r: Row) {
  return (
    (r.mocked_location ? 5 : 0) +
    (r.outside_area ? 3 : 0) +
    (r.near_places > 0 ? 3 : 0) +
    (r.near_contributions > 0 ? 2 : 0) +
    (r.user_last_hour >= 10 ? 2 : 0) +
    (r.low_accuracy ? 1 : 0) +
    (r.no_photo ? 1 : 0)
  );
}

export default function FraudView() {
  const isAdmin = useRoles().includes("admin");
  const [rows, setRows] = useState<Row[]>([]);
  const [scope, setScope] = useState<"pending" | "all">("pending");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    let q = supabase.from("contribution_flags").select("*").order("created_at", { ascending: false }).limit(500);
    if (scope === "pending") q = q.in("status", ["SUBMITTED", "AUTO_CHECKED", "HUMAN_REVIEW"]);
    const { data, error } = await q;
    setError(error?.message ?? null);
    setRows((data ?? []) as Row[]);
  }, [scope]);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  const flagged = useMemo(() => rows.filter((r) => score(r) > 0).sort((a, b) => score(b) - score(a)), [rows]);

  // Autores con varias señales: candidatos a restricción.
  const authors = useMemo(() => {
    const m = new Map<string, { id: string; name: string; count: number; score: number }>();
    for (const r of flagged) {
      const a = m.get(r.user_id) ?? { id: r.user_id, name: r.author_name || r.user_id.slice(0, 8), count: 0, score: 0 };
      a.count++;
      a.score += score(r);
      m.set(r.user_id, a);
    }
    return [...m.values()].filter((a) => a.count >= 2).sort((a, b) => b.score - a.score);
  }, [flagged]);

  async function restrict(userId: string, name: string) {
    const reason = prompt(`Motivo para restringir a ${name} (no podrá enviar aportes ni retirar):`);
    if (!reason) return;
    const { error } = await supabase.rpc("admin_set_restriction", { p_user: userId, p_restricted: true, p_reason: reason });
    setNotice(error ? null : `${name} quedó restringido.`);
    setError(error?.message ?? null);
  }

  return (
    <div className="page">
      <PageHead title="Duplicados y fraude" subtitle="Aportes con señales sospechosas, ordenados por riesgo.">
        <select value={scope} onChange={(e) => setScope(e.target.value as "pending" | "all")}>
          <option value="pending">Pendientes de revisión</option>
          <option value="all">Últimos 500 aportes</option>
        </select>
      </PageHead>
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}

      {authors.length > 0 && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Colaboradores con varias señales</h3>
          <table className="facts">
            <tbody>
              {authors.map((a) => (
                <tr key={a.id}>
                  <td>{a.name}</td>
                  <td>
                    {a.count} aportes señalados · riesgo {a.score}{" "}
                    {isAdmin && (
                      <button className="btn small danger" onClick={() => restrict(a.id, a.name)}>
                        <Ban size={12} /> Restringir
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {flagged.length === 0 ? (
        <div className="empty">No hay aportes con señales de riesgo. 👍</div>
      ) : (
        <div className="scroll">
          <table className="table">
            <thead>
              <tr>
                <th>Riesgo</th>
                <th>Aporte</th>
                <th>Autor</th>
                <th>Señales</th>
                <th>Estado</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {flagged.map((r) => (
                <tr key={r.id}>
                  <td><b className={score(r) >= 5 ? "error" : ""}>{score(r)}</b></td>
                  <td>
                    <b>{r.name}</b>
                    <div className="muted small">{r.category} · {r.mission_code} · {fmtDate(r.created_at)}</div>
                  </td>
                  <td>{r.author_name || r.user_id.slice(0, 8)}</td>
                  <td>
                    {r.mocked_location && <span className="flag">Ubicación simulada</span>}
                    {r.outside_area && <span className="flag">Fuera de zona ({Math.round(r.distance_to_mission_m)} m de {r.radius_m} m)</span>}
                    {r.near_places > 0 && <span className="flag">Duplica {r.near_places} lugar(es)</span>}
                    {r.near_contributions > 0 && <span className="flag mid">Parecido a {r.near_contributions} aporte(s)</span>}
                    {r.user_last_hour >= 10 && <span className="flag mid">{r.user_last_hour} envíos/hora</span>}
                    {r.low_accuracy && <span className="flag mid">GPS ±{Math.round(r.accuracy_m ?? 0)} m</span>}
                    {r.no_photo && <span className="flag mid">Sin foto</span>}
                  </td>
                  <td><span className={`tag s-${r.status}`}>{STATUS_ES[r.status] ?? r.status}</span></td>
                  <td>
                    <Link className="btn small primary" href={`/aportes?id=${r.id}`}>Revisar</Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
