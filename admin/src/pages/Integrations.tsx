import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, ExternalLink, XCircle } from "lucide-react";
import { useEffect, useState } from "react";
import { PhlioName } from "../components/brand";
import { Badge, Button, Card, ErrorNote, Field, Input, Skeleton } from "../components/ui";
import { api, canManage } from "../lib/api";
import { usePanel } from "../lib/panel";

interface Integration {
  id: string; label: string; open_source: boolean; docs: string; enabled: boolean;
  fields: Record<string, string>; secret_fields: string[]; updated_at?: string; updated_by?: string;
  sent: number; failed: number;
}

const FIELD_LABELS: Record<string, { label: string; placeholder?: string; hint?: string }> = {
  measurement_id: { label: "Measurement ID", placeholder: "G-XXXXXXXXXX" },
  api_secret: { label: "Measurement Protocol API secret", hint: "GA4 → Admin → Data streams → Measurement Protocol API secrets." },
  host: { label: "Host", placeholder: "https://analytics.example.com" },
  project_api_key: { label: "Project API key", placeholder: "phc_…", hint: "The public project key, not a personal API key." },
  domain: { label: "Site domain", placeholder: "phlio.app" },
  website_id: { label: "Website ID", placeholder: "UUID from Umami settings" },
  site_id: { label: "Site ID", placeholder: "1" },
  token_auth: { label: "Auth token (optional)", hint: "Only needed to send events with custom timestamps or IPs." },
};

const ABOUT: Record<string, string> = {
  ga4: "Server events via the Measurement Protocol, page views of this panel via gtag.",
  posthog: "Product analytics, funnels and session data. Self-host or PostHog Cloud.",
  plausible: "Lightweight, cookie-free web analytics. Self-host or plausible.io.",
  umami: "Simple, privacy-focused analytics you host yourself.",
  matomo: "Full analytics suite, self-hosted, cookies disabled here.",
};

function ProviderCard({ item, editable }: { item: Integration; editable: boolean }) {
  const qc = useQueryClient();
  const [form, setForm] = useState<Record<string, string>>(item.fields);
  const [enabled, setEnabled] = useState(item.enabled);
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null);
  useEffect(() => { setForm(item.fields); setEnabled(item.enabled); }, [item]);
  const dirty = enabled !== item.enabled || Object.keys(form).some((k) => form[k] !== item.fields[k]);

  const save = useMutation({
    mutationFn: () => api<Integration>(`/admin/integrations/${item.id}`, { method: "PUT", json: { ...form, enabled } }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["integrations"] }),
  });
  const test = useMutation({
    mutationFn: () => api<{ ok: boolean; message: string }>(`/admin/integrations/${item.id}/test`, { method: "POST" }),
    onSuccess: setResult,
    onError: (e: Error) => setResult({ ok: false, message: e.message }),
  });

  return (
    <Card className="flex flex-col p-5">
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="text-[15px] font-semibold">{item.label}</h3>
            {item.open_source && <Badge>Open source</Badge>}
            {item.enabled ? <Badge tone="good">On</Badge> : <Badge>Off</Badge>}
          </div>
          <p className="mt-1 text-xs text-sub">{ABOUT[item.id]}</p>
        </div>
        <label className="relative inline-flex cursor-pointer items-center">
          <input type="checkbox" className="peer sr-only" checked={enabled} disabled={!editable} onChange={(e) => setEnabled(e.target.checked)} aria-label={`Enable ${item.label}`} />
          <span className="h-5 w-9 rounded-full bg-line transition peer-checked:bg-[var(--good)]" />
          <span className="absolute left-0.5 top-0.5 h-4 w-4 rounded-full bg-white transition peer-checked:translate-x-4" />
        </label>
      </div>
      <div className="mt-4 space-y-3">
        {Object.keys(item.fields).map((k) => (
          <Field key={k} label={FIELD_LABELS[k]?.label ?? k} hint={FIELD_LABELS[k]?.hint}>
            <Input
              type={item.secret_fields.includes(k) ? "password" : "text"}
              value={form[k] ?? ""}
              placeholder={FIELD_LABELS[k]?.placeholder}
              disabled={!editable}
              autoComplete="off"
              onChange={(e) => setForm({ ...form, [k]: e.target.value })}
            />
          </Field>
        ))}
      </div>
      <ErrorNote error={save.error} />
      {result && (
        <p className={`mt-3 flex items-center gap-1.5 text-xs ${result.ok ? "text-good" : "text-bad"}`}>
          {result.ok ? <CheckCircle2 size={14} /> : <XCircle size={14} />} {result.message}
        </p>
      )}
      <div className="mt-auto flex flex-wrap items-center gap-2 pt-4">
        {editable && <Button disabled={!dirty || save.isPending} onClick={() => save.mutate()}>{save.isPending ? "Saving…" : "Save"}</Button>}
        {editable && <Button variant="outline" disabled={dirty || test.isPending || !item.updated_at} onClick={() => test.mutate()}>{test.isPending ? "Sending…" : "Send test event"}</Button>}
        <a href={item.docs} target="_blank" rel="noreferrer noopener" className="ml-auto flex items-center gap-1 text-xs text-sub hover:text-ink">Docs <ExternalLink size={12} /></a>
      </div>
      <p className="mt-3 text-[11px] text-faint">
        {item.sent || item.failed ? `${item.sent} sent · ${item.failed} failed since the server started` : "No events sent yet"}
        {item.updated_by ? ` · saved by ${item.updated_by}` : ""}
      </p>
    </Card>
  );
}

export default function IntegrationsPage() {
  const { admin } = usePanel();
  const q = useQuery({ queryKey: ["integrations"], queryFn: () => api<{ items: Integration[] }>("/admin/integrations") });
  return (
    <div className="space-y-5">
      <Card className="p-5">
        <h2 className="text-[15px] font-semibold">How it works</h2>
        <p className="mt-1.5 max-w-3xl text-sm text-sub">
          Every action people take in the <PhlioName size={14} className="align-[-2px] font-medium text-ink">app</PhlioName> (posting, liking, paying, booking, logging water …) is sent from the server to each
          tool you switch on, as a named event like <code className="text-ink">social_posts_like</code>. User ids are replaced with a
          keyed hash before they leave the server, and no names, emails or message text are ever sent. Public ids (never secrets) are
          also available to the app at <code className="text-ink">/api/v1/analytics/config</code> for client SDKs.
        </p>
        {!canManage(admin.role) && <p className="mt-3 text-xs text-faint">You can view integrations. Ask an admin to change them.</p>}
      </Card>
      <ErrorNote error={q.error} />
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {q.data ? q.data.items.map((i) => <ProviderCard key={i.id} item={i} editable={canManage(admin.role)} />)
          : Array.from({ length: 5 }, (_, i) => <Skeleton key={i} className="h-[340px] rounded-2xl" />)}
      </div>
    </div>
  );
}
