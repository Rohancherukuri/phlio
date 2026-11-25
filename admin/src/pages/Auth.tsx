import { useQuery } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Logo } from "../components/Layout";
import { Button, ErrorNote, Field, Input } from "../components/ui";
import { api, auth, type Admin } from "../lib/api";

interface Status { has_admins: boolean; signup: "bootstrap" | "invite"; code_required: boolean }
interface AuthOut { admin: Admin; tokens: { access_token: string } }

function Shell({ title, sub, children }: { title: string; sub: string; children: React.ReactNode }) {
  return (
    <div className="flex min-h-full items-center justify-center p-4">
      <div className="w-full max-w-[400px]">
        <div className="mb-8 flex justify-center"><Logo /></div>
        <div className="rounded-2xl border border-line bg-card p-6 sm:p-7">
          <h1 className="text-xl font-semibold">{title}</h1>
          <p className="mt-1 text-sm text-sub">{sub}</p>
          <div className="mt-6">{children}</div>
        </div>
        <p className="mt-6 text-center text-[11px] text-faint">Phlio Admin · for the Phlio team only</p>
      </div>
    </div>
  );
}

export function Login() {
  const nav = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const status = useQuery({ queryKey: ["auth-status"], queryFn: () => api<Status>("/admin/auth/status") });

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const out = await api<AuthOut>("/admin/auth/login", { method: "POST", json: { email, password } });
      auth.set(out.tokens.access_token);
      nav("/", { replace: true });
    } catch (err) { setError(err); } finally { setBusy(false); }
  }

  return (
    <Shell title="Sign in" sub="Analytics for every Phlio platform.">
      <form onSubmit={submit} className="space-y-4">
        <Field label="Email"><Input type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
        <Field label="Password"><Input type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} /></Field>
        <ErrorNote error={error} />
        <Button className="w-full" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</Button>
      </form>
      <p className="mt-5 text-center text-sm text-sub">
        {status.data && !status.data.has_admins ? "No admins yet — " : "Have an invite? "}
        <Link to="/signup" className="font-medium text-ink underline-offset-4 hover:underline">
          {status.data && !status.data.has_admins ? "create the owner account" : "Create your account"}
        </Link>
      </p>
    </Shell>
  );
}

export function Signup() {
  const nav = useNavigate();
  const params = new URLSearchParams(window.location.search);
  const [form, setForm] = useState({ name: "", email: "", password: "", code: params.get("invite") ?? "" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const status = useQuery({ queryKey: ["auth-status"], queryFn: () => api<Status>("/admin/auth/status") });
  const bootstrap = status.data?.signup === "bootstrap";
  const needsCode = !bootstrap || status.data?.code_required;
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm({ ...form, [k]: e.target.value });

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (form.password.length < 10) { setError(new Error("Use at least 10 characters for the password.")); return; }
    setBusy(true);
    setError(null);
    try {
      const out = await api<AuthOut>("/admin/auth/signup", { method: "POST", json: { ...form, code: form.code || null } });
      auth.set(out.tokens.access_token);
      nav("/", { replace: true });
    } catch (err) { setError(err); } finally { setBusy(false); }
  }

  return (
    <Shell
      title={bootstrap ? "Create the owner account" : "Join the admin team"}
      sub={bootstrap ? "The first account owns the panel and invites everyone else." : "Use the invite code an admin sent you."}
    >
      <form onSubmit={submit} className="space-y-4">
        <Field label="Name"><Input required autoComplete="name" value={form.name} onChange={set("name")} /></Field>
        <Field label="Email"><Input type="email" required autoComplete="email" value={form.email} onChange={set("email")} /></Field>
        <Field label="Password" hint="At least 10 characters.">
          <Input type="password" required autoComplete="new-password" value={form.password} onChange={set("password")} />
        </Field>
        {needsCode && (
          <Field label={bootstrap ? "Signup code" : "Invite code"} hint={bootstrap ? "The ADMIN_SIGNUP_CODE set on the server." : undefined}>
            <Input required value={form.code} onChange={set("code")} />
          </Field>
        )}
        <ErrorNote error={error} />
        <Button className="w-full" disabled={busy}>{busy ? "Creating…" : "Create account"}</Button>
      </form>
      <p className="mt-5 text-center text-sm text-sub">
        Already have an account? <Link to="/login" className="font-medium text-ink underline-offset-4 hover:underline">Sign in</Link>
      </p>
    </Shell>
  );
}
