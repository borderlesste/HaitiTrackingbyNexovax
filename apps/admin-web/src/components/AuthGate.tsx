"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { createContext, useContext, useEffect, useState, type FormEvent, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import { currentRoles, supabase, type Role } from "@/lib/supabase";

const RolesContext = createContext<Role[]>([]);
export const useRoles = () => useContext(RolesContext);

export default function AuthGate({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [rolesFor, setRolesFor] = useState<{ uid: string; roles: Role[] } | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setReady(true);
    });
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);

  const uid = session?.user.id;
  useEffect(() => {
    if (!uid) return;
    currentRoles().then((roles) => setRolesFor({ uid, roles }));
  }, [uid]);
  const roles = rolesFor && rolesFor.uid === uid ? rolesFor.roles : null;

  if (!ready) return <div className="center muted">Cargando…</div>;
  if (!session) return <Login />;
  if (roles === null) return <div className="center muted">Comprobando permisos…</div>;
  if (roles.length === 0) {
    return (
      <div className="center">
        <div className="card narrow">
          <h2>Sin acceso</h2>
          <p>
            La cuenta <b>{session.user.email}</b> no tiene rol de administrador ni de moderador.
          </p>
          <p className="muted small">ID de usuario: {session.user.id}</p>
          <button className="btn" onClick={() => supabase.auth.signOut()}>
            Cerrar sesión
          </button>
        </div>
      </div>
    );
  }

  return (
    <RolesContext.Provider value={roles}>
      <Shell email={session.user.email ?? ""} roles={roles}>
        {children}
      </Shell>
    </RolesContext.Provider>
  );
}

function Shell({ children, email, roles }: { children: ReactNode; email: string; roles: Role[] }) {
  const path = usePathname();
  const nav = [
    { href: "/", label: "Cola de revisión" },
    { href: "/misiones", label: "Misiones" },
  ];
  return (
    <div className="layout">
      <header className="topbar">
        <div className="brand">
          <span className="pin">●</span> HAITI TRACKING <span className="muted">· Admin</span>
        </div>
        <nav>
          {nav.map((n) => (
            <Link key={n.href} href={n.href} className={path === n.href ? "active" : ""}>
              {n.label}
            </Link>
          ))}
        </nav>
        <div className="user">
          <span className="muted small">
            {email} · {roles.join(", ")}
          </span>
          <button className="btn ghost" onClick={() => supabase.auth.signOut()}>
            Salir
          </button>
        </div>
      </header>
      <main className="content">{children}</main>
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
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) setError(error.message);
    setBusy(false);
  }

  return (
    <div className="center login-bg">
      <form className="card narrow" onSubmit={submit}>
        <h1 className="brand-lg">
          <span className="pin">●</span> HAITI TRACKING
        </h1>
        <p className="muted">Panel administrativo privado</p>
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
