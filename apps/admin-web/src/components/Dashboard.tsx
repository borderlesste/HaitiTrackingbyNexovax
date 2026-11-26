"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import PageHead from "@/components/ui/PageHead";
import { fmtDate, supabase, usd } from "@/lib/supabase";

type Stats = {
  users: number;
  collaborators: number;
  companies: number;
  companies_pending: number;
  developers: number;
  missions_active: number;
  missions_total: number;
  places: number;
  contributions_pending: number;
  contributions_today: number;
  approved_7d: number;
  rejected_7d: number;
  rewards_earned_usd: number;
  rewards_available_usd: number;
  withdrawals_pending: number;
  withdrawals_pending_usd: number;
  withdrawals_paid_usd: number;
  budget_authorized_usd: number;
  tickets_open: number;
  campaigns_pending: number;
  api_requests_7d: number;
  daily: { day: string; submitted: number; approved: number }[];
};
type Action = { id: number; action: string; actor_name: string | null; created_at: string; details: Record<string, unknown> };

export const ACTION_ES: Record<string, string> = {
  review_contribution: "Revisó un aporte",
  review_organization: "Revisó una empresa",
  review_place_claim: "Revisó un reclamo de establecimiento",
  review_campaign: "Revisó una solicitud de misión",
  create_mission: "Creó una misión",
  edit_mission: "Editó una misión",
  mission_status: "Cambió el estado de una misión",
  update_setting: "Cambió la configuración",
  process_withdrawal: "Procesó un retiro",
  release_rewards: "Liberó recompensas",
  adjust_reward: "Ajustó un saldo",
  restrict_user: "Restringió un usuario",
  unrestrict_user: "Quitó una restricción",
  grant_role: "Concedió un rol",
  revoke_role: "Retiró un rol",
  answer_ticket: "Atendió un caso de soporte",
  update_api_project: "Cambió un proyecto API",
  review_establishment: "Revisó un establecimiento de empresa",
  review_org_document: "Revisó un documento de empresa",
  set_subscription: "Cambió un plan",
  create_invoice: "Emitió una factura",
  invoice_status: "Cambió el estado de una factura",
  export_places: "Exportó lugares del mapa",
};

export default function Dashboard() {
  const [s, setS] = useState<Stats | null>(null);
  const [actions, setActions] = useState<Action[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    supabase.rpc("admin_dashboard").then(({ data, error }) => {
      if (error) setError(error.message);
      else setS(data as Stats);
    });
    supabase
      .from("admin_actions_view")
      .select("id, action, actor_name, created_at, details")
      .order("created_at", { ascending: false })
      .limit(8)
      .then(({ data }) => setActions((data ?? []) as Action[]));
  }, []);

  if (error)
    return (
      <div className="page">
        <PageHead title="Dashboard" />
        <p className="error">{error}</p>
        <p className="muted small">Si dice que la función no existe, falta aplicar la migración del panel en Supabase.</p>
      </div>
    );
  if (!s) return <p className="muted">Cargando…</p>;

  const max = Math.max(1, ...s.daily.map((d) => Math.max(d.submitted, d.approved)));
  const reviewed = s.approved_7d + s.rejected_7d;

  return (
    <div className="page">
      <PageHead title="Dashboard general" subtitle="Actividad de la plataforma en tiempo real" />

      <div className="kpis">
        <Kpi href="/aportes" label="Aportes por revisar" value={s.contributions_pending} alert={s.contributions_pending > 0} sub={`${s.contributions_today} recibidos hoy`} />
        <Kpi href="/retiros" label="Retiros pendientes" value={s.withdrawals_pending} alert={s.withdrawals_pending > 0} sub={usd(s.withdrawals_pending_usd)} />
        <Kpi href="/soporte" label="Casos de soporte abiertos" value={s.tickets_open} alert={s.tickets_open > 0} />
        <Kpi href="/empresas" label="Empresas por verificar" value={s.companies_pending} alert={s.companies_pending > 0} sub={`${s.campaigns_pending} solicitudes de misión`} />
        <Kpi href="/misiones" label="Misiones activas" value={s.missions_active} sub={`${s.missions_total} en total`} />
        <Kpi href="/mapa" label="Lugares verificados" value={s.places} />
        <Kpi href="/colaboradores" label="Usuarios" value={s.users} sub={`${s.collaborators} colaboradores · ${s.companies} empresas · ${s.developers} desarrolladores`} />
        <Kpi
          label="Tasa de aprobación (7 días)"
          value={reviewed ? `${Math.round((s.approved_7d / reviewed) * 100)}%` : "—"}
          sub={`${s.approved_7d} aprobados · ${s.rejected_7d} rechazados`}
        />
        <Kpi href="/recompensas" label="Recompensas por liberar" value={usd(s.rewards_earned_usd)} sub={`${usd(s.rewards_available_usd)} ya retirables`} />
        <Kpi href="/retiros" label="Pagado por MonCash" value={usd(s.withdrawals_paid_usd)} />
        <Kpi href="/presupuestos" label="Presupuesto autorizado" value={usd(s.budget_authorized_usd)} sub="Misiones activas y pausadas" />
        <Kpi href="/desarrolladores" label="Consultas API (7 días)" value={s.api_requests_7d} />
      </div>

      <div className="grid2" style={{ margin: 0 }}>
        <div className="card">
          <div className="head">
            <h3 style={{ margin: 0 }}>Aportes últimos 14 días</h3>
            <div className="legend">
              <span><i style={{ background: "#b9c9ef" }} />Recibidos</span>
              <span><i style={{ background: "var(--green)" }} />Aprobados</span>
            </div>
          </div>
          <div className="bars">
            {s.daily.map((d) => (
              <div className="col" key={d.day} title={`${d.day}: ${d.submitted} recibidos, ${d.approved} aprobados`}>
                <div style={{ display: "flex", gap: 2, width: "100%", alignItems: "flex-end", flex: 1 }}>
                  <div className="b s" style={{ height: `${(d.submitted / max) * 100}%` }} />
                  <div className="b a" style={{ height: `${(d.approved / max) * 100}%` }} />
                </div>
                <span className="d">{d.day.slice(8)}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="card">
          <div className="head">
            <h3 style={{ margin: 0 }}>Actividad administrativa reciente</h3>
            <Link href="/auditoria" className="small" style={{ color: "var(--blue)" }}>Ver todo</Link>
          </div>
          {actions.length === 0 ? (
            <p className="muted small">Sin actividad todavía.</p>
          ) : (
            <table className="facts">
              <tbody>
                {actions.map((a) => (
                  <tr key={a.id}>
                    <td>{fmtDate(a.created_at)}</td>
                    <td>
                      <b>{a.actor_name || "Sistema"}</b> · {ACTION_ES[a.action] ?? a.action}
                      {typeof a.details?.code === "string" && <span className="muted"> {a.details.code}</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}

function Kpi({ label, value, sub, href, alert }: { label: string; value: number | string; sub?: string; href?: string; alert?: boolean }) {
  const body = (
    <>
      <div className="label">{label}</div>
      <div className={`value ${alert ? "alert" : ""}`}>{value}</div>
      {sub && <div className="sub">{sub}</div>}
    </>
  );
  return href ? (
    <Link href={href} className="kpi">
      {body}
    </Link>
  ) : (
    <div className="kpi">{body}</div>
  );
}
