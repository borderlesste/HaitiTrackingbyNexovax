"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import { Gift, Save } from "lucide-react";
import PageHead from "@/components/ui/PageHead";
import { TYPES } from "@/components/MissionsView";
import { fmtDate, getSetting, saveSetting, supabase, usd } from "@/lib/supabase";

type RewardCfg = { hold_days: number; defaults: Record<string, number>; batch_bonus_usd: number };
type Ev = { id: string; user_id: string; kind: string; amount_usd: number; status: string; reason: string | null; created_at: string };

const DEFAULT: RewardCfg = {
  hold_days: 3,
  defaults: { NEW_PLACE: 0.25, PRIORITY_PLACE: 0.5, MAJOR_CORRECTION: 0.1, INDEPENDENT_CHECK: 0.05, BATCH_ZONE: 0.25 },
  batch_bonus_usd: 1,
};
const KIND_ES: Record<string, string> = { CONTRIBUTION: "Aporte", MISSION_BONUS: "Bono de misión", WELCOME_BONUS: "Bienvenida", ADJUSTMENT: "Ajuste" };
const STATUS_ES: Record<string, string> = { EARNED: "Por liberar", AVAILABLE: "Disponible", ON_HOLD: "Retenida", PAID: "Pagada", REVERSED: "Revertida", PENDING_REVIEW: "En revisión", WITHDRAWAL_REQUESTED: "En retiro" };

export default function RewardsView() {
  const [cfg, setCfg] = useState<RewardCfg>(DEFAULT);
  const [events, setEvents] = useState<Ev[]>([]);
  const [names, setNames] = useState<Record<string, string>>({});
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [c, e, u] = await Promise.all([
      getSetting<RewardCfg>("rewards", DEFAULT),
      supabase.from("reward_events").select("id, user_id, kind, amount_usd, status, reason, created_at").order("created_at", { ascending: false }).limit(100),
      supabase.rpc("admin_users"),
    ]);
    setCfg({ ...c, defaults: { ...DEFAULT.defaults, ...c.defaults } });
    setEvents((e.data ?? []) as Ev[]);
    setNames(Object.fromEntries(((u.data ?? []) as { id: string; full_name: string }[]).map((x) => [x.id, x.full_name])));
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  async function save(e: FormEvent) {
    e.preventDefault();
    const error = await saveSetting("rewards", cfg);
    setErr(error);
    setMsg(error ? null : "Tarifas guardadas. Se usarán como valores por defecto al crear misiones.");
  }

  async function releaseAll() {
    if (!confirm(`¿Liberar todas las recompensas con más de ${cfg.hold_days} días? Pasarán a saldo retirable.`)) return;
    const { data, error } = await supabase.rpc("admin_release_rewards", { p_user: null });
    setErr(error?.message ?? null);
    const r = data as { count: number; amount_usd: number } | null;
    setMsg(error ? null : `${r?.count ?? 0} recompensas liberadas (${usd(r?.amount_usd)}).`);
    load();
  }

  const pending = events.filter((e) => e.status === "EARNED").reduce((a, e) => a + Number(e.amount_usd), 0);

  return (
    <div className="page">
      <PageHead title="Tarifas y recompensas" subtitle="Pagos por tipo de misión, bonificaciones y liberación del saldo.">
        <button className="btn primary" onClick={releaseAll}><Gift size={14} /> Liberar recompensas</button>
      </PageHead>
      {msg && <p className="ok">{msg}</p>}
      {err && <p className="error">{err}</p>}

      <div className="grid2" style={{ margin: 0 }}>
        <form className="card form" onSubmit={save}>
          <h3 style={{ marginTop: 0 }}>Tarifas por defecto (USD por aporte aprobado)</h3>
          {Object.entries(TYPES).map(([k, v]) => (
            <label key={k} style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between" }}>
              {v}
              <input
                type="number"
                step="0.01"
                min="0"
                style={{ width: 110 }}
                value={cfg.defaults[k] ?? 0}
                onChange={(e) => setCfg({ ...cfg, defaults: { ...cfg.defaults, [k]: Number(e.target.value) } })}
              />
            </label>
          ))}
          <label style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between" }}>
            Bono por completar un lote (USD)
            <input type="number" step="0.01" min="0" style={{ width: 110 }} value={cfg.batch_bonus_usd} onChange={(e) => setCfg({ ...cfg, batch_bonus_usd: Number(e.target.value) })} />
          </label>
          <label style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between" }}>
            Días de retención antes de poder retirar
            <input type="number" min="0" max="60" style={{ width: 110 }} value={cfg.hold_days} onChange={(e) => setCfg({ ...cfg, hold_days: Number(e.target.value) })} />
          </label>
          <button className="btn primary"><Save size={14} /> Guardar tarifas</button>
          <p className="muted small">Cambiar las tarifas no modifica misiones ya creadas: cada misión guarda su propia recompensa.</p>
        </form>
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Cómo funciona</h3>
          <ol className="small" style={{ paddingLeft: 18, lineHeight: 1.6 }}>
            <li>Al aprobar un aporte se asienta la recompensa como <b>Por liberar</b>.</li>
            <li>Tras {cfg.hold_days} días sin incidencias, <b>Liberar recompensas</b> las pasa a <b>Disponible</b> (retirable).</li>
            <li>Los usuarios restringidos no se liberan.</li>
            <li>Bonificaciones o correcciones: desde la ficha del colaborador (ajuste manual, queda en la auditoría).</li>
          </ol>
          <p>Por liberar en los últimos 100 movimientos: <b>{usd(pending)}</b></p>
        </div>
      </div>

      <h3>Últimos movimientos del libro de recompensas</h3>
      <div className="scroll">
        <table className="table">
          <thead>
            <tr><th>Fecha</th><th>Colaborador</th><th>Concepto</th><th className="num">Monto</th><th>Estado</th></tr>
          </thead>
          <tbody>
            {events.map((e) => (
              <tr key={e.id}>
                <td className="small">{fmtDate(e.created_at)}</td>
                <td>{names[e.user_id] || e.user_id.slice(0, 8)}</td>
                <td>{KIND_ES[e.kind] ?? e.kind}{e.reason && <div className="muted small">{e.reason}</div>}</td>
                <td className="num">{usd(e.amount_usd)}</td>
                <td><span className="tag">{STATUS_ES[e.status] ?? e.status}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
        {events.length === 0 && <div className="empty">Todavía no hay recompensas.</div>}
      </div>
    </div>
  );
}
