"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { createContext, useContext, useEffect, useState, type FormEvent, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import {
  Banknote,
  BarChart3,
  ClipboardCheck,
  Code2,
  Download,
  FileClock,
  Headphones,
  LayoutDashboard,
  LogOut,
  Map as MapIcon,
  Megaphone,
  PiggyBank,
  Receipt,
  Settings,
  ShieldAlert,
  ShieldCheck,
  Store,
  Target,
  Users,
  Wallet,
  type LucideIcon,
} from "lucide-react";
import { getPanelAccess, supabase, type PanelAccess, type Role } from "@/lib/supabase";

const RolesContext = createContext<Role[]>([]);
export const useRoles = () => useContext(RolesContext);

export default function AuthGate({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [accessFor, setAccessFor] = useState<{ token: string; access: PanelAccess } | null>(null);

  useEffect(() => {
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setReady(true);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const token = session?.access_token;
  useEffect(() => {
    if (!token) return;
    let active = true;
    void getPanelAccess(token)
      .catch((): PanelAccess => ({ status: "error" }))
      .then((access) => {
        if (active) setAccessFor({ token, access });
      });
    return () => { active = false; };
  }, [token]);

  if (!ready) return <div className="center muted">Cargando…</div>;
  if (!session) return <Login />;
  const access = accessFor?.token === token ? accessFor?.access : undefined;
  if (!access) return <div className="center muted">Comprobando permisos…</div>;
  if (access.status === "verify") return <MfaVerify />;
  if (access.status === "enroll") return <MfaEnroll />;
  if (access.status !== "allowed") {
    return (
      <div className="center login-bg">
        <div className="card narrow">
          <h2>Sin acceso</h2>
          <p>{access.status === "error"
            ? "No pudimos comprobar tus permisos. Recarga la página o inicia sesión de nuevo."
            : "La cuenta no tiene rol de administrador ni de moderador."}</p>
          <button className="btn" onClick={() => supabase.auth.signOut()}>
            Cerrar sesión
          </button>
        </div>
      </div>
    );
  }
  return (
    <RolesContext.Provider value={access.roles}>
      <Shell email={session.user.email ?? ""} roles={access.roles}>
        {children}
      </Shell>
    </RolesContext.Provider>
  );
}

type NavItem = { href: string; label: string; icon: LucideIcon; adminOnly?: boolean };
const NAV: { title: string; items: NavItem[] }[] = [
  {
    title: "Operación",
    items: [
      { href: "/", label: "Dashboard", icon: LayoutDashboard },
      { href: "/aportes", label: "Revisar aportes", icon: ClipboardCheck },
      { href: "/fraude", label: "Duplicados y fraude", icon: ShieldAlert },
      { href: "/mapa", label: "Mapa operativo", icon: MapIcon },
      { href: "/misiones", label: "Misiones", icon: Target },
      { href: "/exportar", label: "Exportar datos", icon: Download, adminOnly: true },
    ],
  },
  {
    title: "Usuarios",
    items: [
      { href: "/colaboradores", label: "Colaboradores", icon: Users },
      { href: "/empresas", label: "Empresas", icon: Store },
      { href: "/campanas", label: "Solicitudes de misión", icon: Megaphone },
      { href: "/desarrolladores", label: "Desarrolladores", icon: Code2 },
      { href: "/soporte", label: "Soporte", icon: Headphones },
    ],
  },
  {
    title: "Finanzas",
    items: [
      { href: "/recompensas", label: "Tarifas y recompensas", icon: Wallet, adminOnly: true },
      { href: "/presupuestos", label: "Presupuestos", icon: PiggyBank },
      { href: "/retiros", label: "Retiros MonCash", icon: Banknote, adminOnly: true },
      { href: "/facturacion", label: "Facturación", icon: Receipt, adminOnly: true },
    ],
  },
  {
    title: "Sistema",
    items: [
      { href: "/configuracion", label: "Configuración", icon: Settings, adminOnly: true },
      { href: "/auditoria", label: "Auditoría", icon: FileClock },
    ],
  },
];

function Shell({ children, email, roles }: { children: ReactNode; email: string; roles: Role[] }) {
  const path = usePathname();
  const isAdmin = roles.includes("admin");
  const routeRequiresAdmin = NAV.some(({ items }) => items.some((item) => item.adminOnly && item.href === path));
  const [open, setOpen] = useState(false);
  return (
    <div className="shell">
      <aside className={`sidebar ${open ? "open" : ""}`}>
        <div className="brand">
          <span className="pin">●</span> HAITI TRACKING
          <div className="muted small">by Nexovax · Admin</div>
        </div>
        <nav onClick={() => setOpen(false)}>
          {NAV.map((g) => {
            const items = g.items.filter((i) => isAdmin || !i.adminOnly);
            if (items.length === 0) return null;
            return (
              <div key={g.title} className="navgroup">
                <div className="navtitle">{g.title}</div>
                {items.map((n) => {
                  const Icon = n.icon;
                  const active = n.href === "/" ? path === "/" : path.startsWith(n.href);
                  return (
                    <Link key={n.href} href={n.href} className={active ? "active" : ""}>
                      <Icon size={16} /> {n.label}
                    </Link>
                  );
                })}
              </div>
            );
          })}
        </nav>
        <div className="sidefoot">
          <div className="small">{email}</div>
          <div className="small muted">
            <ShieldCheck size={12} /> {roles.join(", ")}
          </div>
          <button className="btn ghost small" onClick={() => supabase.auth.signOut()}>
            <LogOut size={14} /> Salir
          </button>
        </div>
      </aside>
      <div className="main">
        <header className="mobilebar">
          <button className="btn small" onClick={() => setOpen((v) => !v)}>
            <BarChart3 size={14} /> Menú
          </button>
          <b>HAITI TRACKING · Admin</b>
        </header>
        <main className="content">
          {routeRequiresAdmin && !isAdmin ? <p>Esta sección requiere el rol de administrador.</p> : children}
        </main>
      </div>
    </div>
  );
}

function Login() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) setError("No se pudo iniciar sesión. Verifica tus credenciales o inténtalo más tarde.");
    } catch {
      setError("No se pudo iniciar sesión. Verifica tus credenciales o inténtalo más tarde.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="center login-bg">
      <form className="card narrow" onSubmit={submit}>
        <h1 className="brand-lg">
          <span className="pin">●</span> HAITI TRACKING
        </h1>
        <p className="muted">Panel administrativo privado. Acceso con contraseña y verificación en dos pasos.</p>
        <label>
          Correo
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="username" />
        </label>
        <label>
          Contraseña
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required autoComplete="current-password" />
        </label>
        {error && <p className="error">{error}</p>}
        <button className="btn primary" disabled={busy}>
          {busy ? "Entrando…" : "Entrar"}
        </button>
      </form>
    </div>
  );
}

function MfaVerify() {
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { data } = await supabase.auth.mfa.listFactors();
    const factor = data?.totp?.[0];
    if (!factor) {
      setBusy(false);
      return setError("No hay un autenticador registrado.");
    }
    const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code: code.trim() });
    setBusy(false);
    if (error) setError("Código incorrecto o caducado.");
  }

  return (
    <div className="center login-bg">
      <form className="card narrow" onSubmit={submit}>
        <h2>
          <ShieldCheck size={20} /> Verificación en dos pasos
        </h2>
        <p className="muted">Escribe el código de 6 dígitos de tu app autenticadora (Google Authenticator, Authy, 1Password…).</p>
        <input inputMode="numeric" pattern="[0-9]{6}" maxLength={6} value={code} onChange={(e) => setCode(e.target.value)} autoFocus required className="code" />
        {error && <p className="error">{error}</p>}
        <button className="btn primary" disabled={busy}>{busy ? "Verificando…" : "Verificar"}</button>
        <button type="button" className="btn" onClick={() => supabase.auth.signOut()}>Cancelar</button>
      </form>
    </div>
  );
}

function MfaEnroll() {
  const [factor, setFactor] = useState<{ id: string; qr: string; secret: string } | null>(null);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let active = true;
    void (async () => {
      // Limpia altas anteriores que no se terminaron de verificar.
      const { data: list, error: factorsError } = await supabase.auth.mfa.listFactors();
      if (factorsError) throw factorsError;
      for (const f of list?.all ?? []) {
        if (!active) return;
        if (f.status === "unverified" && f.factor_type === "totp" && f.friendly_name?.startsWith("Panel ")) {
          await supabase.auth.mfa.unenroll({ factorId: f.id });
        }
      }
      if (!active) return;
      const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: `Panel ${new Date().toISOString()}` });
      if (error || !data) throw error ?? new Error("No se pudo iniciar el registro.");
      if (active) setFactor({ id: data.id, qr: data.totp.qr_code, secret: data.totp.secret });
    })().catch(() => {
      if (active) setError("No se pudo configurar el autenticador. Contacta con el equipo de administración.");
    });
    return () => { active = false; };
  }, []);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!factor) return;
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code: code.trim() });
    setBusy(false);
    if (error) setError("Código incorrecto. Comprueba la hora del teléfono y vuelve a intentarlo.");
  }

  return (
    <div className="center login-bg">
      <form className="card narrow" onSubmit={submit}>
        <h2>
          <ShieldCheck size={20} /> Activa la verificación en dos pasos
        </h2>
        <p className="muted small">
          El panel maneja pagos y datos personales. Escanea el código QR con una app autenticadora y escribe el código de 6 dígitos.
        </p>
        {factor ? (
          <>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={factor.qr} alt="Código QR del autenticador" className="qr" />
            <p className="small muted">
              ¿No puedes escanear? Clave: <span className="mono">{factor.secret}</span>
            </p>
            <input inputMode="numeric" pattern="[0-9]{6}" maxLength={6} value={code} onChange={(e) => setCode(e.target.value)} required className="code" />
            <button className="btn primary" disabled={busy}>{busy ? "Verificando…" : "Activar y entrar"}</button>
          </>
        ) : (
          !error && <p className="muted">Preparando…</p>
        )}
        {error && <p className="error">{error}</p>}
        <button type="button" className="btn" onClick={() => supabase.auth.signOut()}>Cancelar</button>
      </form>
    </div>
  );
}
