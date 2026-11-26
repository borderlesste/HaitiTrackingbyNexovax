"use client";

import { useCallback, useEffect, useState } from "react";
import { useRoles } from "@/components/AuthGate";
import PageHead from "@/components/ui/PageHead";
import { fmtDate, supabase } from "@/lib/supabase";

type P = {
  id: string;
  name: string;
  owner_name: string | null;
  environment: string;
  intended_use: string;
  daily_quota: number;
  status: string;
  created_at: string;
  active_keys: number;
  last_used_at: string | null;
  requests_30d: number;
  errors_30d: number;
  requests_today: number;
};

export default function DevelopersView() {
  const isAdmin = useRoles().includes("admin");
  const [rows, setRows] = useState<P[]>([]);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data, error } = await supabase.from("api_projects_admin").select("*").order("created_at", { ascending: false });
    setError(error?.message ?? null);
    setRows((data ?? []) as P[]);
  }, []);

  useEffect(() => {
    Promise.resolve().then(load);
  }, [load]);

  async function update(p: P, status: string, quota: number) {
    const { error } = await supabase.rpc("admin_update_api_project", { p_project: p.id, p_status: status, p_daily_quota: quota });
    setError(error?.message ?? null);
    load();
  }

  return (
    <div className="page">
      <PageHead title="Gestión de desarrolladores" subtitle="Proyectos API, claves activas, cuotas y consumo. Las claves secretas nunca se muestran (solo se guarda su hash)." />
      {error && <p className="error">{error}</p>}
      {rows.length === 0 ? (
        <div className="empty">Todavía no hay proyectos API.</div>
      ) : (
        <div className="scroll">
          <table className="table">
            <thead>
              <tr>
                <th>Proyecto</th>
                <th>Desarrollador</th>
                <th>Entorno</th>
                <th className="num">Claves</th>
                <th className="num">Hoy / cuota</th>
                <th className="num">30 días</th>
                <th>Estado</th>
                {isAdmin && <th></th>}
              </tr>
            </thead>
            <tbody>
              {rows.map((p) => {
                const errRate = p.requests_30d ? Math.round((p.errors_30d / p.requests_30d) * 100) : 0;
                return (
                  <tr key={p.id}>
                    <td>
                      <b>{p.name}</b>
                      <div className="muted small">{p.intended_use}</div>
                    </td>
                    <td>{p.owner_name || "—"}<div className="muted small">desde {fmtDate(p.created_at, false)}</div></td>
                    <td>{p.environment === "production" ? "Producción" : "Pruebas"}</td>
                    <td className="num">{p.active_keys}<div className="muted small">uso: {fmtDate(p.last_used_at)}</div></td>
                    <td className="num">{p.requests_today} / {p.daily_quota}</td>
                    <td className="num">{p.requests_30d}<div className={`small ${errRate > 10 ? "error" : "muted"}`}>{errRate}% errores</div></td>
                    <td><span className={`tag s-${p.status}`}>{p.status === "ACTIVE" ? "Activo" : "Suspendido"}</span></td>
                    {isAdmin && (
                      <td>
                        <div className="row gap">
                          <button
                            className="btn small"
                            onClick={() => {
                              const v = prompt("Nueva cuota diaria de consultas:", String(p.daily_quota));
                              if (v && Number(v) > 0) update(p, p.status, Math.round(Number(v)));
                            }}
                          >
                            Cuota
                          </button>
                          {p.status === "ACTIVE" ? (
                            <button className="btn small danger" onClick={() => confirm(`¿Suspender ${p.name}? Sus claves dejarán de funcionar.`) && update(p, "SUSPENDED", p.daily_quota)}>Suspender</button>
                          ) : (
                            <button className="btn small primary" onClick={() => update(p, "ACTIVE", p.daily_quota)}>Reactivar</button>
                          )}
                        </div>
                      </td>
                    )}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
