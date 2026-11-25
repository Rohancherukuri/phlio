import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Copy, Trash2 } from "lucide-react";
import { useState } from "react";
import { Badge, Button, Card, CardHead, ErrorNote, Field, Input, Skeleton } from "../components/ui";
import { api, type Admin, type Role } from "../lib/api";
import { ago } from "../lib/format";
import { usePanel } from "../lib/panel";

interface Invite { code: string; email?: string; role: Role; created_at: string; expires_at: string; created_by: string }
interface Team { members: Admin[]; invites: Invite[]; audit: { email: string; action: string; detail: Record<string, any>; created_at: string }[] }

const ROLES: { value: Role; label: string; about: string }[] = [
  { value: "viewer", label: "Viewer", about: "Dashboards; emails masked" },
  { value: "analyst", label: "Analyst", about: "Dashboards and full user list" },
  { value: "admin", label: "Admin", about: "Plus integrations and invites" },
];

export default function TeamPage() {
  const { admin } = usePanel();
  const qc = useQueryClient();
  const q = useQuery({ queryKey: ["team"], queryFn: () => api<Team>("/admin/team") });
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role>("viewer");
  const [copied, setCopied] = useState<string | null>(null);
  const refresh = () => qc.invalidateQueries({ queryKey: ["team"] });

  const invite = useMutation({
    mutationFn: () => api<Invite>("/admin/team/invites", { method: "POST", json: { email: email || null, role } }),
    onSuccess: () => { setEmail(""); refresh(); },
  });
  const revoke = useMutation({ mutationFn: (code: string) => api(`/admin/team/invites/${code}`, { method: "DELETE" }), onSuccess: refresh });
  const update = useMutation({
    mutationFn: ({ id, ...body }: { id: string; role?: Role; disabled?: boolean }) => api(`/admin/team/${id}`, { method: "PATCH", json: body }),
    onSuccess: refresh,
  });

  const link = (code: string) => `${window.location.origin}/signup?invite=${encodeURIComponent(code)}`;
  const copy = async (code: string) => {
    try { await navigator.clipboard.writeText(link(code)); setCopied(code); setTimeout(() => setCopied(null), 1500); } catch { /* ignore */ }
  };
  const owner = admin.role === "owner";

  return (
    <div className="grid gap-5 xl:grid-cols-3">
      <div className="space-y-5 xl:col-span-2">
        <Card>
          <CardHead title="Members" sub={owner ? "Change roles or turn off access." : "Only the owner can change roles."} />
          <ErrorNote error={update.error} />
          <ul className="divide-y divide-[var(--line)] p-2">
            {q.data ? q.data.members.map((m) => (
              <li key={m.id} className="flex flex-wrap items-center gap-3 px-3 py-3">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-muted text-sm font-semibold">{m.name.slice(0, 1)}</div>
                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-2 truncate text-sm font-medium">
                    {m.name} {m.id === admin.id && <Badge>You</Badge>} {m.disabled && <Badge tone="bad">Disabled</Badge>}
                  </p>
                  <p className="truncate text-xs text-faint">{m.email} · last sign-in {ago(m.last_login)}</p>
                </div>
                {owner && m.id !== admin.id ? (
                  <div className="flex items-center gap-2">
                    <select
                      value={m.role}
                      onChange={(e) => update.mutate({ id: m.id, role: e.target.value as Role })}
                      className="h-8 rounded-lg border border-line bg-bg px-2 text-xs text-ink"
                      aria-label={`Role for ${m.name}`}
                    >
                      {["owner", "admin", "analyst", "viewer"].map((r) => <option key={r} value={r}>{r}</option>)}
                    </select>
                    <Button variant={m.disabled ? "outline" : "danger"} className="h-8 text-xs" onClick={() => update.mutate({ id: m.id, disabled: !m.disabled })}>
                      {m.disabled ? "Turn on" : "Turn off"}
                    </Button>
                  </div>
                ) : <Badge tone={m.role === "owner" ? "brand" : "neutral"}>{m.role}</Badge>}
              </li>
            )) : <Skeleton className="m-3 h-32" />}
          </ul>
        </Card>
        <Card>
          <CardHead title="Activity log" sub="Sign-ins and changes in the admin panel." />
          <ul className="space-y-2 p-5 text-xs">
            {q.data?.audit.map((a, i) => (
              <li key={i} className="flex gap-3">
                <span className="w-24 shrink-0 text-faint">{ago(a.created_at)}</span>
                <span className="text-sub"><span className="text-ink">{a.email}</span> {a.action.replace(/_/g, " ")}
                  {a.detail?.provider ? ` · ${a.detail.provider}` : ""}{a.detail?.role ? ` · ${a.detail.role}` : ""}</span>
              </li>
            ))}
          </ul>
        </Card>
      </div>

      <div className="space-y-5">
        <Card className="p-5">
          <h3 className="text-[15px] font-semibold">Invite someone</h3>
          <p className="mt-1 text-xs text-sub">They get a link that works once, for 7 days.</p>
          <div className="mt-4 space-y-3">
            <Field label="Email (optional)" hint="Locks the invite to this address.">
              <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
            </Field>
            <div className="space-y-1.5">
              {ROLES.map((r) => (
                <label key={r.value} className={`flex cursor-pointer items-center gap-3 rounded-lg border px-3 py-2 ${role === r.value ? "border-sub" : "border-line"}`}>
                  <input type="radio" name="role" checked={role === r.value} onChange={() => setRole(r.value)} className="accent-[var(--brand)]" />
                  <span className="text-sm">{r.label}</span>
                  <span className="ml-auto text-[11px] text-faint">{r.about}</span>
                </label>
              ))}
            </div>
            <ErrorNote error={invite.error} />
            <Button className="w-full" disabled={invite.isPending} onClick={() => invite.mutate()}>Create invite</Button>
          </div>
        </Card>
        <Card>
          <CardHead title="Open invites" />
          <ul className="space-y-2 p-4">
            {q.data?.invites.length ? q.data.invites.map((i) => (
              <li key={i.code} className="rounded-lg border border-line p-3">
                <div className="flex items-center gap-2">
                  <Badge>{i.role}</Badge>
                  <span className="truncate text-xs text-sub">{i.email ?? "anyone with the link"}</span>
                </div>
                <div className="mt-2 flex items-center gap-1.5">
                  <Button variant="outline" className="h-7 flex-1 text-xs" onClick={() => copy(i.code)}><Copy size={12} /> {copied === i.code ? "Copied" : "Copy link"}</Button>
                  <Button variant="ghost" className="h-7 px-2" aria-label="Revoke invite" onClick={() => revoke.mutate(i.code)}><Trash2 size={13} /></Button>
                </div>
              </li>
            )) : <p className="py-4 text-center text-xs text-faint">No open invites.</p>}
          </ul>
        </Card>
      </div>
    </div>
  );
}
