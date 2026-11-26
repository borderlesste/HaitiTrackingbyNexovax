"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { Download, FilePlus2 } from "lucide-react";
import Modal from "@/components/ui/Modal";
import PageHead from "@/components/ui/PageHead";
import { downloadCsv, fmtDate, supabase, usd } from "@/lib/supabase";

type Plan = { code: string; audience: string; name: string; price_usd_month: number; daily_quota: number | null; features: string[]; sort: number; active: boolean };
type Sub = { id: string; audience: string; org_id: string | null; owner_id: string; plan_code: string; plan_name: string; price_usd_month: number; status: string; started_at: string | null; created_at: string; org_name: string | null; owner_name: string | null };
type Inv = { id: string; number: string; audience: string; org_name: string | null; owner_name: string | null; plan_name: string | null; description: string; period_start: string | null; period_end: string | null; amount_usd: number; status: string; created_at: string; paid_at: string | null };
type Campaign = { id: string; org_id: string; org_name: string; title: string; proposed_budget_usd: number; status: string; mission_code: string | null; created_at: string };

const SUB_ES: Record<string, string> = { REQUESTED: "Solicitado", ACTIVE: "Activo", CANCELLED: "Cancelado" };
const INV_ES: Record<string, string> = { PENDING: "Pendiente", PAID: "Pagada", VOID: "Anulada" };
const AUD_ES: Record<string, string> = { company: "Empresa", developer: "Desarrollador" };

export type InvoiceDraft = { audience: string; org_id: string | null; owner_id: string | null; plan_code: string | null; description: string; amount: number; who: string };

export default function BillingView() {
  const [tab, setTab] = useState<"subs" | "invoices" | "plans" | "missions">("subs");
  const [plans, setPlans] = useState<Plan[]>([]);
  const [subs, setSubs] = useState<Sub[]>([]);
  const [invoices, setInvoices] = useState<Inv[]>([]);
  const [campaigns, setCampaigns] = useState<Campaign[]>([]);
  const [draft, setDraft] = useState<InvoiceDraft | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [p, s, i, c] = await Promise.all([
      supabase.from("billing_plans").select("*").order("audience").order("sort"),
      supabase.from("billing_subscriptions_view").select("*").order("created_at", { ascending: false }),
      supabase.from("invoices_view").select("*").order("created_at", { ascending: false }).limit(500),
      supabase.from("campaign_requests_view").select("id, org_id, org_name, title, proposed_budget_usd, status, mission_code, created_at").order("created_at", { ascending: false }),
    ]);
    setErr(p.error?.message ?? s.error?.message ?? i.error?.message ?? null);
    setPlans((p.data ?? []) as Plan[]);
    setSubs((s.data ?? []) as Sub[]);
    setInvoices((i.data ?? []) as Inv[]);
    setCampaigns((c.data ?? []) as Campaign[]);
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  function done(error: { message: string } | null, ok: string) {
    setErr(error?.message ?? null);
    setMsg(error ? null : ok);
    load();
  }

  async function setSub(s: Sub, status: "ACTIVE" | "CANCELLED") {
    if (status === "ACTIVE" && Number(s.price_usd_month) > 0 && !confirm(`¿Confirmas que ${s.org_name ?? s.owner_name} pagó el plan ${s.plan_name} (${usd(s.price_usd_month)}/mes)?`)) return;
    const { error } = await supabase.rpc("admin_set_subscription", { p_id: s.id, p_status: status });
    done(error, status === "ACTIVE" ? `Plan ${s.plan_name} activado.` : "Plan cancelado.");
  }

  async function setInv(i: Inv, status: "PAID" | "VOID") {
    if (status === "VOID" && !confirm(`¿Anular la factura ${i.number}?`)) return;
    const { error } = await supabase.rpc("admin_set_invoice_status", { p_id: i.id, p_status: status });
    done(error, `${i.number} ${status === "PAID" ? "marcada como pagada" : "anulada"}.`);
  }

  async function savePlan(p: Plan, patch: Partial<Plan>) {
    const { error } = await supabase.from("billing_plans").update(patch).eq("code", p.code);
    done(error, `Plan ${p.name} actualizado.`);
  }

  const totals = useMemo(
    () => ({
      requested: subs.filter((s) => s.status === "REQUESTED").length,
      mrr: subs.filter((s) => s.status === "ACTIVE").reduce((a, s) => a + Number(s.price_usd_month), 0),
      pending: invoices.filter((i) => i.status === "PENDING").reduce((a, i) => a + Number(i.amount_usd), 0),
      paid: invoices.filter((i) => i.status === "PAID").reduce((a, i) => a + Number(i.amount_usd), 0),
    }),
    [subs, invoices],
  );

  return (
    <div className="page">
      <PageHead title="Facturación" subtitle="Planes, suscripciones y facturas de empresas y desarrolladores.">
        <button className="btn primary" onClick={() => setDraft({ audience: "company", org_id: null, owner_id: null, plan_code: null, description: "", amount: 0, who: "" })}>
          <FilePlus2 size={14} /> Nueva factura
        </button>
      </PageHead>
      <p className="card small" style={{ background: "#fff8e6" }}>
        El cobro en línea todavía no está conectado. El equipo confirma el pago (transferencia, MonCash o efectivo), activa el plan y marca la factura
        como pagada.
      </p>
      <div className="kpis">
        <div className="kpi"><div className="label">Planes por activar</div><div className={`value ${totals.requested ? "alert" : ""}`}>{totals.requested}</div></div>
        <div className="kpi"><div className="label">Ingresos mensuales activos</div><div className="value">{usd(totals.mrr)}</div></div>
        <div className="kpi"><div className="label">Facturas pendientes</div><div className="value">{usd(totals.pending)}</div></div>
        <div className="kpi"><div className="label">Cobrado</div><div className="value">{usd(totals.paid)}</div></div>
      </div>
      {msg && <p className="ok">{msg}</p>}
      {err && <p className="error">{err}</p>}

      <div className="tabs">
        {([["subs", "Suscripciones"], ["invoices", "Facturas"], ["missions", "Misiones de empresas"], ["plans", "Planes"]] as const).map(([k, v]) => (
          <button key={k} className={tab === k ? "on" : ""} onClick={() => setTab(k)}>{v}</button>
        ))}
      </div>

      {tab === "subs" && (
        <div className="scroll">
          <table className="table">
            <thead>
              <tr><th>Cliente</th><th>Plan</th><th className="num">Precio</th><th>Solicitado</th><th>Estado</th><th></th></tr>
            </thead>
            <tbody>
              {subs.map((s) => (
                <tr key={s.id}>
                  <td>{s.org_name ?? s.owner_name ?? "—"}<div className="muted small">{AUD_ES[s.audience]}</div></td>
                  <td>{s.plan_name}</td>
                  <td className="num">{usd(s.price_usd_month)}/mes</td>
                  <td className="small">{fmtDate(s.created_at)}{s.started_at && <div className="muted">activo desde {fmtDate(s.started_at, false)}</div>}</td>
                  <td><span className={`tag s-${s.status === "REQUESTED" ? "PENDING" : s.status === "CANCELLED" ? "CLOSED" : "ACTIVE"}`}>{SUB_ES[s.status]}</span></td>
                  <td>
                    <div className="row gap">
                      {s.status === "REQUESTED" && <button className="btn small primary" onClick={() => setSub(s, "ACTIVE")}>Activar</button>}
                      {s.status === "ACTIVE" && Number(s.price_usd_month) > 0 && (
                        <button
                          className="btn small"
                          onClick={() =>
                            setDraft({
                              audience: s.audience,
                              org_id: s.org_id,
                              owner_id: s.owner_id,
                              plan_code: s.plan_code,
                              description: `Plan ${s.plan_name} – ${new Date().toLocaleDateString("es", { month: "long", year: "numeric" })}`,
                              amount: Number(s.price_usd_month),
                              who: s.org_name ?? s.owner_name ?? "",
                            })
                          }
                        >
                          Facturar
                        </button>
                      )}
                      {s.status !== "CANCELLED" && <button className="btn small" onClick={() => confirm("¿Cancelar este plan?") && setSub(s, "CANCELLED")}>Cancelar</button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {subs.length === 0 && <div className="empty">Nadie ha solicitado un plan todavía.</div>}
        </div>
      )}

      {tab === "invoices" && (
        <div className="scroll">
          <div className="toolbar" style={{ marginBottom: 8 }}>
            <button className="btn small" onClick={() => downloadCsv("facturas.csv", invoices.map((i) => ({ numero: i.number, fecha: i.created_at, cliente: i.org_name ?? i.owner_name, concepto: i.description, monto_usd: i.amount_usd, estado: INV_ES[i.status], pagada: i.paid_at })))}>
              <Download size={12} /> CSV
            </button>
          </div>
          <table className="table">
            <thead>
              <tr><th>Número</th><th>Cliente</th><th>Concepto</th><th className="num">Monto</th><th>Estado</th><th></th></tr>
            </thead>
            <tbody>
              {invoices.map((i) => (
                <tr key={i.id}>
                  <td className="mono">{i.number}<div className="muted small">{fmtDate(i.created_at, false)}</div></td>
                  <td>{i.org_name ?? i.owner_name ?? "—"}<div className="muted small">{AUD_ES[i.audience]}</div></td>
                  <td>{i.description}{i.period_start && <div className="muted small">{i.period_start} → {i.period_end}</div>}</td>
                  <td className="num"><b>{usd(i.amount_usd)}</b></td>
                  <td><span className={`tag s-${i.status === "PAID" ? "COMPLETED" : i.status === "VOID" ? "CLOSED" : "PENDING"}`}>{INV_ES[i.status]}</span>{i.paid_at && <div className="muted small">{fmtDate(i.paid_at, false)}</div>}</td>
                  <td>
                    {i.status === "PENDING" && (
                      <div className="row gap">
                        <button className="btn small primary" onClick={() => setInv(i, "PAID")}>Pagada</button>
                        <button className="btn small" onClick={() => setInv(i, "VOID")}>Anular</button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {invoices.length === 0 && <div className="empty">Sin facturas todavía.</div>}
        </div>
      )}

      {tab === "missions" && (
        <div className="scroll">
          <table className="table">
            <thead>
              <tr><th>Fecha</th><th>Empresa</th><th>Solicitud</th><th>Misión</th><th className="num">Presupuesto</th><th>Estado</th><th></th></tr>
            </thead>
            <tbody>
              {campaigns.map((c) => (
                <tr key={c.id}>
                  <td className="small">{fmtDate(c.created_at, false)}</td>
                  <td>{c.org_name}</td>
                  <td>{c.title}</td>
                  <td className="mono">{c.mission_code ?? "—"}</td>
                  <td className="num">{usd(c.proposed_budget_usd)}</td>
                  <td><span className={`tag s-${c.status}`}>{c.status === "APPROVED" ? "Aprobada" : c.status === "REJECTED" ? "Rechazada" : "En revisión"}</span></td>
                  <td>
                    {c.status === "APPROVED" && (
                      <button
                        className="btn small"
                        onClick={() =>
                          setDraft({ audience: "company", org_id: c.org_id, owner_id: null, plan_code: null, description: `Misión ${c.mission_code ?? ""}: ${c.title}`.trim(), amount: Number(c.proposed_budget_usd), who: c.org_name })
                        }
                      >
                        Facturar
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {campaigns.length === 0 && <div className="empty">Sin solicitudes todavía.</div>}
        </div>
      )}

      {tab === "plans" && (
        <div className="scroll">
          <table className="table">
            <thead>
              <tr><th>Plan</th><th>Para</th><th className="num">USD/mes</th><th className="num">Consultas/día</th><th>Incluye</th><th>Visible</th></tr>
            </thead>
            <tbody>
              {plans.map((p) => (
                <tr key={p.code}>
                  <td><b>{p.name}</b><div className="muted small mono">{p.code}</div></td>
                  <td>{AUD_ES[p.audience]}</td>
                  <td className="num">
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      style={{ width: 90 }}
                      defaultValue={p.price_usd_month}
                      onBlur={(e) => Number(e.target.value) !== Number(p.price_usd_month) && savePlan(p, { price_usd_month: Number(e.target.value) })}
                    />
                  </td>
                  <td className="num">
                    {p.audience === "developer" ? (
                      <input
                        type="number"
                        min="1"
                        style={{ width: 100 }}
                        defaultValue={p.daily_quota ?? 0}
                        onBlur={(e) => Number(e.target.value) !== p.daily_quota && savePlan(p, { daily_quota: Number(e.target.value) })}
                      />
                    ) : (
                      "—"
                    )}
                  </td>
                  <td className="small">{p.features.join(" · ")}</td>
                  <td><input type="checkbox" checked={p.active} onChange={(e) => savePlan(p, { active: e.target.checked })} /></td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="muted small">Los cambios se guardan al salir de cada campo. Cambiar un precio no modifica facturas ya emitidas.</p>
        </div>
      )}

      {draft && (
        <Modal title="Nueva factura" onClose={() => setDraft(null)}>
          <InvoiceForm
            draft={draft}
            onDone={(n) => {
              setDraft(null);
              setTab("invoices");
              done(null, `Factura ${n} emitida.`);
            }}
          />
        </Modal>
      )}
    </div>
  );
}

function InvoiceForm({ draft, onDone }: { draft: InvoiceDraft; onDone: (number: string) => void }) {
  const [audience, setAudience] = useState(draft.audience);
  const [client, setClient] = useState(draft.org_id ?? draft.owner_id ?? "");
  const [clients, setClients] = useState<{ id: string; name: string; audience: string }[]>([]);
  const [description, setDescription] = useState(draft.description);
  const [amount, setAmount] = useState(String(draft.amount || ""));
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [error, setError] = useState<string | null>(null);
  const fixed = !!(draft.org_id || draft.owner_id);

  useEffect(() => {
    if (fixed) return;
    Promise.all([supabase.from("organizations").select("id, name").eq("status", "APPROVED"), supabase.from("developer_profiles").select("user_id, display_name")]).then(([o, d]) =>
      setClients([
        ...((o.data ?? []) as { id: string; name: string }[]).map((x) => ({ id: x.id, name: x.name, audience: "company" })),
        ...((d.data ?? []) as { user_id: string; display_name: string }[]).map((x) => ({ id: x.user_id, name: x.display_name, audience: "developer" })),
      ]),
    );
  }, [fixed]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    const isCompany = audience === "company";
    const { data, error } = await supabase.rpc("admin_create_invoice", {
      p_audience: audience,
      p_org: isCompany ? (draft.org_id ?? client) : null,
      p_owner: isCompany ? draft.owner_id : (draft.owner_id ?? client),
      p_plan: draft.plan_code,
      p_description: description,
      p_amount: Number(amount),
      p_period_start: start || null,
      p_period_end: end || null,
    });
    if (error) setError(error.message);
    else onDone(String(data));
  }

  return (
    <form className="form" onSubmit={submit}>
      {fixed ? (
        <p>Cliente: <b>{draft.who}</b> ({AUD_ES[audience]})</p>
      ) : (
        <div className="row gap">
          <label>
            Tipo
            <select value={audience} onChange={(e) => { setAudience(e.target.value); setClient(""); }}>
              <option value="company">Empresa</option>
              <option value="developer">Desarrollador</option>
            </select>
          </label>
          <label>
            Cliente
            <select value={client} onChange={(e) => setClient(e.target.value)} required>
              <option value="">Elegir…</option>
              {clients.filter((c) => c.audience === audience).map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </label>
        </div>
      )}
      <label>Concepto<input value={description} onChange={(e) => setDescription(e.target.value)} required /></label>
      <div className="row gap">
        <label>Monto USD<input type="number" step="0.01" min="0" value={amount} onChange={(e) => setAmount(e.target.value)} required /></label>
        <label>Periodo desde<input type="date" value={start} onChange={(e) => setStart(e.target.value)} /></label>
        <label>hasta<input type="date" value={end} onChange={(e) => setEnd(e.target.value)} /></label>
      </div>
      {error && <p className="error">{error}</p>}
      <button className="btn primary">Emitir factura</button>
      <p className="muted small">El número (FAC-AAAA-000001) se asigna automáticamente. El cliente la verá en su panel como pendiente.</p>
    </form>
  );
}
