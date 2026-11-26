"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { CheckCircle2, Download, Play, XCircle } from "lucide-react";
import Modal from "@/components/ui/Modal";
import PageHead from "@/components/ui/PageHead";
import { downloadCsv, fmtDate, getSetting, htg, supabase, usd } from "@/lib/supabase";

type W = {
  id: string;
  code: string;
  user_id: string;
  full_name: string | null;
  amount_usd: number;
  moncash_phone: string;
  verified_phone: string | null;
  phone_matches: boolean | null;
  status: string;
  fee_usd: number | null;
  htg_rate: number | null;
  reference: string | null;
  rejection_reason: string | null;
  created_at: string;
  processed_at: string | null;
};

const ES: Record<string, string> = { REQUESTED: "Solicitado", PROCESSING: "Autorizado", COMPLETED: "Pagado", REJECTED: "Rechazado" };

export default function WithdrawalsView() {
  const [rows, setRows] = useState<W[]>([]);
  const [filter, setFilter] = useState("open");
  const [acting, setActing] = useState<{ w: W; to: "COMPLETED" | "REJECTED" } | null>(null);
  const [cfg, setCfg] = useState({ enabled: false, min_usd: 5, max_usd: 50 });
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data, error } = await supabase.from("withdrawals_admin").select("*").order("created_at", { ascending: false }).limit(1000);
    setError(error?.message ?? null);
    setRows((data ?? []) as W[]);
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
    getSetting("withdrawals", { enabled: false, min_usd: 5, max_usd: 50 }).then(setCfg);
  }, [load]);

  const shown = rows.filter((r) => (filter === "open" ? ["REQUESTED", "PROCESSING"].includes(r.status) : filter === "all" || r.status === filter));
  const totals = useMemo(
    () => ({
      requested: rows.filter((r) => r.status === "REQUESTED").reduce((a, r) => a + Number(r.amount_usd), 0),
      processing: rows.filter((r) => r.status === "PROCESSING").reduce((a, r) => a + Number(r.amount_usd), 0),
      paid: rows.filter((r) => r.status === "COMPLETED").reduce((a, r) => a + Number(r.amount_usd), 0),
    }),
    [rows],
  );

  async function authorize(w: W) {
    const { error } = await supabase.rpc("admin_process_withdrawal", { p_id: w.id, p_status: "PROCESSING" });
    setError(error?.message ?? null);
    if (!error) setNotice(`${w.code} autorizado. Envía el pago por MonCash y luego márcalo como pagado.`);
    load();
  }

  return (
    <div className="page">
      <PageHead title="Retiros MonCash" subtitle="Solicitudes, autorizaciones, pagos y conciliación.">
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="open">Por atender</option>
          <option value="all">Todos</option>
          {Object.entries(ES).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>
        <button
          className="btn"
          onClick={() =>
            downloadCsv(
              `retiros-${new Date().toISOString().slice(0, 10)}.csv`,
              shown.map((r) => ({
                codigo: r.code,
                fecha: r.created_at,
                colaborador: r.full_name,
                monto_usd: r.amount_usd,
                moncash: r.moncash_phone,
                estado: ES[r.status],
                referencia: r.reference,
                tasa_htg: r.htg_rate,
                comision_usd: r.fee_usd,
                procesado: r.processed_at,
              })),
            )
          }
        >
          <Download size={14} /> Exportar CSV
        </button>
      </PageHead>

      {!cfg.enabled && (
        <p className="card small" style={{ background: "#fff8e6" }}>
          Los retiros están <b>desactivados</b> para los colaboradores (pendiente de la aprobación de MonCash). Se activan en Configuración. Límites
          actuales: {usd(cfg.min_usd)} – {usd(cfg.max_usd)}.
        </p>
      )}

      <div className="kpis">
        <div className="kpi"><div className="label">Solicitados</div><div className="value">{usd(totals.requested)}</div></div>
        <div className="kpi"><div className="label">Autorizados (por pagar)</div><div className="value">{usd(totals.processing)}</div></div>
        <div className="kpi"><div className="label">Pagados</div><div className="value">{usd(totals.paid)}</div></div>
      </div>

      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}

      {shown.length === 0 ? (
        <div className="empty">No hay retiros en este filtro.</div>
      ) : (
        <div className="scroll">
          <table className="table">
            <thead>
              <tr>
                <th>Código</th>
                <th>Colaborador</th>
                <th className="num">Monto</th>
                <th>MonCash</th>
                <th>Estado</th>
                <th>Conciliación</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {shown.map((r) => (
                <tr key={r.id}>
                  <td className="mono">
                    {r.code}
                    <div className="muted small">{fmtDate(r.created_at)}</div>
                  </td>
                  <td>{r.full_name || r.user_id.slice(0, 8)}</td>
                  <td className="num"><b>{usd(r.amount_usd)}</b></td>
                  <td className="mono">
                    {r.moncash_phone}
                    <div className="small">
                      {r.phone_matches ? <span className="ok">✓ verificado por SMS</span> : <span className="error">⚠ no coincide con el número verificado</span>}
                    </div>
                  </td>
                  <td><span className={`tag s-${r.status}`}>{ES[r.status] ?? r.status}</span></td>
                  <td className="small">
                    {r.reference && <div>Ref: <span className="mono">{r.reference}</span></div>}
                    {r.htg_rate && <div>{htg(Number(r.amount_usd) * Number(r.htg_rate))} (tasa {r.htg_rate})</div>}
                    {r.fee_usd !== null && <div>Comisión {usd(r.fee_usd)}</div>}
                    {r.rejection_reason && <div className="error">{r.rejection_reason}</div>}
                    {r.processed_at && <div className="muted">{fmtDate(r.processed_at)}</div>}
                  </td>
                  <td>
                    <div className="row gap">
                      {r.status === "REQUESTED" && (
                        <button className="btn small primary" onClick={() => authorize(r)}><Play size={12} /> Autorizar</button>
                      )}
                      {["REQUESTED", "PROCESSING"].includes(r.status) && (
                        <>
                          <button className="btn small" onClick={() => setActing({ w: r, to: "COMPLETED" })}><CheckCircle2 size={12} /> Pagado</button>
                          <button className="btn small danger" onClick={() => setActing({ w: r, to: "REJECTED" })}><XCircle size={12} /></button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {acting && (
        <Modal title={`${acting.to === "COMPLETED" ? "Registrar pago" : "Rechazar"} ${acting.w.code}`} onClose={() => setActing(null)}>
          <ProcessForm
            w={acting.w}
            to={acting.to}
            onDone={(msg) => {
              setActing(null);
              setNotice(msg);
              load();
            }}
          />
        </Modal>
      )}
    </div>
  );
}

function ProcessForm({ w, to, onDone }: { w: W; to: "COMPLETED" | "REJECTED"; onDone: (msg: string) => void }) {
  const [reference, setReference] = useState("");
  const [reason, setReason] = useState("");
  const [rate, setRate] = useState("");
  const [fee, setFee] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    const { error } = await supabase.rpc("admin_process_withdrawal", {
      p_id: w.id,
      p_status: to,
      p_reference: reference || null,
      p_reason: reason || null,
      p_htg_rate: rate ? Number(rate) : null,
      p_fee_usd: fee ? Number(fee) : null,
    });
    setBusy(false);
    if (error) setError(error.message);
    else onDone(to === "COMPLETED" ? `${w.code} marcado como pagado.` : `${w.code} rechazado; el saldo vuelve al colaborador.`);
  }

  return (
    <form className="form" onSubmit={submit}>
      <p>
        {w.full_name} · <b>{usd(w.amount_usd)}</b> · MonCash <span className="mono">{w.moncash_phone}</span>
      </p>
      {to === "COMPLETED" ? (
        <>
          <label>
            Referencia de la transacción MonCash
            <input value={reference} onChange={(e) => setReference(e.target.value)} required />
          </label>
          <div className="row gap">
            <label>
              Tasa HTG por USD
              <input type="number" step="0.0001" min="0" value={rate} onChange={(e) => setRate(e.target.value)} placeholder="132.5" />
            </label>
            <label>
              Comisión USD
              <input type="number" step="0.01" min="0" value={fee} onChange={(e) => setFee(e.target.value)} />
            </label>
          </div>
          {rate && <p className="small">Enviado: <b>{htg(Number(w.amount_usd) * Number(rate))}</b></p>}
          <p className="muted small">Solo marca como pagado después de confirmar el envío en MonCash.</p>
        </>
      ) : (
        <label>
          Motivo del rechazo (lo verá el colaborador)
          <textarea value={reason} onChange={(e) => setReason(e.target.value)} required rows={3} />
        </label>
      )}
      {error && <p className="error">{error}</p>}
      <button className={`btn ${to === "COMPLETED" ? "primary" : "danger"}`} disabled={busy}>
        {busy ? "Guardando…" : to === "COMPLETED" ? "Confirmar pago" : "Rechazar retiro"}
      </button>
    </form>
  );
}
