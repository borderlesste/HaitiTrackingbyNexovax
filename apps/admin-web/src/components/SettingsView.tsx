"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import { Save, UserPlus, X } from "lucide-react";
import { loadUsers, ROLE_ES, type AdminUser } from "@/components/CollaboratorsView";
import PageHead from "@/components/ui/PageHead";
import { getSetting, saveSetting, supabase, usd } from "@/lib/supabase";

type General = { support_email: string; support_phone: string; languages: string[]; default_language: string; terms_url: string; privacy_url: string };
type Withdrawals = { enabled: boolean; min_usd: number; max_usd: number };

const LANGS: Record<string, string> = { ht: "Kreyòl", fr: "Français", es: "Español", en: "English" };
const GENERAL: General = { support_email: "", support_phone: "", languages: ["ht", "fr", "es", "en"], default_language: "ht", terms_url: "", privacy_url: "" };

export default function SettingsView() {
  const [general, setGeneral] = useState<General>(GENERAL);
  const [wd, setWd] = useState<Withdrawals>({ enabled: false, min_usd: 5, max_usd: 50 });
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [search, setSearch] = useState("");
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  const loadTeam = useCallback(async () => {
    const r = await loadUsers();
    setUsers(r.users);
  }, []);

  useEffect(() => {
    getSetting<General>("general", GENERAL).then(setGeneral);
    getSetting<Withdrawals>("withdrawals", { enabled: false, min_usd: 5, max_usd: 50 }).then(setWd);
    Promise.resolve().then(loadTeam);
  }, [loadTeam]);

  function done(e: string | null, ok: string) {
    setErr(e);
    setMsg(e ? null : ok);
  }

  async function saveGeneral(e: FormEvent) {
    e.preventDefault();
    done(await saveSetting("general", general), "Datos generales guardados.");
  }

  async function saveWd(e: FormEvent) {
    e.preventDefault();
    if (wd.min_usd <= 0 || wd.max_usd < wd.min_usd) return done("El mínimo debe ser mayor que 0 y el máximo mayor o igual al mínimo.", "");
    if (wd.enabled && !confirm("¿Activar los retiros para todos los colaboradores? Hazlo solo con la aprobación de MonCash y fondos disponibles.")) return;
    done(await saveSetting("withdrawals", wd), "Política de retiros guardada.");
  }

  async function setRole(u: AdminUser, role: string, grant: boolean) {
    const { error } = await supabase.rpc("admin_set_role", { p_user: u.id, p_role: role, p_grant: grant });
    done(error?.message ?? null, `${grant ? "Rol concedido" : "Rol retirado"}: ${ROLE_ES[role]} · ${u.full_name}`);
    loadTeam();
  }

  const team = users.filter((u) => u.roles.includes("admin") || u.roles.includes("moderator"));
  const t = search.trim().toLowerCase();
  const candidates = t.length >= 3 ? users.filter((u) => `${u.full_name} ${u.email ?? ""} ${u.phone ?? ""}`.toLowerCase().includes(t)).slice(0, 6) : [];

  return (
    <div className="page">
      <PageHead title="Configuración general" subtitle="Contactos, idiomas, permisos del equipo y políticas." />
      {msg && <p className="ok">{msg}</p>}
      {err && <p className="error">{err}</p>}

      <div className="grid2" style={{ margin: 0 }}>
        <form className="card form" onSubmit={saveGeneral}>
          <h3 style={{ marginTop: 0 }}>Contacto y políticas</h3>
          <label>Correo de soporte<input type="email" value={general.support_email} onChange={(e) => setGeneral({ ...general, support_email: e.target.value })} /></label>
          <label>Teléfono / WhatsApp de soporte<input value={general.support_phone} onChange={(e) => setGeneral({ ...general, support_phone: e.target.value })} placeholder="+509 …" /></label>
          <label>Enlace a términos y condiciones<input type="url" value={general.terms_url} onChange={(e) => setGeneral({ ...general, terms_url: e.target.value })} /></label>
          <label>Enlace a la política de privacidad<input type="url" value={general.privacy_url} onChange={(e) => setGeneral({ ...general, privacy_url: e.target.value })} /></label>
          <div>
            <div style={{ fontWeight: 500, marginBottom: 4 }}>Idiomas de la app</div>
            <div className="row gap">
              {Object.entries(LANGS).map(([k, v]) => (
                <label key={k} style={{ flexDirection: "row", alignItems: "center", gap: 4, flex: "none" }}>
                  <input
                    type="checkbox"
                    checked={general.languages.includes(k)}
                    onChange={(e) => setGeneral({ ...general, languages: e.target.checked ? [...general.languages, k] : general.languages.filter((l) => l !== k) })}
                  />
                  {v}
                </label>
              ))}
            </div>
          </div>
          <label>
            Idioma por defecto
            <select value={general.default_language} onChange={(e) => setGeneral({ ...general, default_language: e.target.value })}>
              {general.languages.map((l) => (
                <option key={l} value={l}>{LANGS[l]}</option>
              ))}
            </select>
          </label>
          <button className="btn primary"><Save size={14} /> Guardar</button>
        </form>

        <form className="card form" onSubmit={saveWd}>
          <h3 style={{ marginTop: 0 }}>Retiros MonCash</h3>
          <label style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
            <input type="checkbox" checked={wd.enabled} onChange={(e) => setWd({ ...wd, enabled: e.target.checked })} />
            Retiros activados para los colaboradores
          </label>
          <div className="row gap">
            <label>Mínimo USD<input type="number" step="0.01" min="0.01" value={wd.min_usd} onChange={(e) => setWd({ ...wd, min_usd: Number(e.target.value) })} /></label>
            <label>Máximo USD<input type="number" step="0.01" min="0.01" value={wd.max_usd} onChange={(e) => setWd({ ...wd, max_usd: Number(e.target.value) })} /></label>
          </div>
          <p className="muted small">
            Ahora: {wd.enabled ? "activados" : "desactivados"}, entre {usd(wd.min_usd)} y {usd(wd.max_usd)} por solicitud. Solo se paga al número MonCash verificado por SMS.
          </p>
          <button className="btn primary"><Save size={14} /> Guardar política</button>
        </form>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Equipo y permisos</h3>
        <p className="muted small">
          <b>Administrador</b>: todo, incluidos pagos y configuración. <b>Moderador</b>: revisar aportes, fraude, soporte y consultar. Nadie puede revisar
          sus propios aportes ni procesar sus propios retiros.
        </p>
        <table className="facts">
          <tbody>
            {team.map((u) => (
              <tr key={u.id}>
                <td>{u.full_name || u.email || u.phone}<div className="muted small">{u.email ?? u.phone}</div></td>
                <td>
                  {(["admin", "moderator"] as const).map((r) =>
                    u.roles.includes(r) ? (
                      <button key={r} className="btn small" style={{ marginRight: 6 }} onClick={() => confirm(`¿Quitar el rol ${ROLE_ES[r]} a ${u.full_name}?`) && setRole(u, r, false)}>
                        {ROLE_ES[r]} <X size={10} />
                      </button>
                    ) : (
                      <button key={r} className="btn small" style={{ marginRight: 6, opacity: 0.6 }} onClick={() => setRole(u, r, true)}>
                        + {ROLE_ES[r]}
                      </button>
                    ),
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <label style={{ marginTop: 12 }}>
          Añadir al equipo (busca por nombre, teléfono o correo)
          <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Escribe al menos 3 letras" />
        </label>
        {candidates.map((u) => (
          <div key={u.id} className="row between" style={{ padding: "4px 0" }}>
            <span>{u.full_name || "Sin nombre"} <span className="muted small">{u.phone ?? u.email}</span></span>
            <span className="row gap">
              <button className="btn small" onClick={() => setRole(u, "moderator", true)}><UserPlus size={12} /> Moderador</button>
              <button className="btn small" onClick={() => confirm(`¿Dar acceso total de administrador a ${u.full_name}?`) && setRole(u, "admin", true)}><UserPlus size={12} /> Admin</button>
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
