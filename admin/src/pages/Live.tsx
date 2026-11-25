import { useQuery } from "@tanstack/react-query";
import { HBars, Legend, LiveArea, StackedDaily, useToggle } from "../components/charts";
import { Card, CardHead, Segmented, Skeleton } from "../components/ui";
import { api } from "../lib/api";
import { LABELS, ago, color, num } from "../lib/format";
import { usePanel } from "../lib/panel";
import { useState } from "react";

const KEYS = ["social", "dm", "rooms", "pay", "book", "shop", "stream", "news", "agent", "identity", "core"];

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="rounded-2xl border border-line bg-card p-4">
      <p className="text-xs font-medium text-sub">{label}</p>
      <p className="mt-2 text-[28px] font-semibold leading-none tabular-nums transition-all">{value}</p>
      {hint && <p className="mt-1.5 text-[11px] text-faint">{hint}</p>}
    </div>
  );
}

export default function LivePage() {
  const { live } = usePanel();
  const d = live.data;
  const { hidden, toggle } = useToggle();
  const [hours, setHours] = useState(24);
  const traffic = useQuery({
    queryKey: ["traffic", hours],
    queryFn: () => api<{ series: Record<string, any>[] }>(`/admin/traffic?hours=${hours}`),
    refetchInterval: 60_000,
  });
  const keys = KEYS.filter((k) => d?.series.some((s) => s[k]) || traffic.data?.series.some((s) => s[k]));

  return (
    <div className="space-y-5">
      <div className="flex items-center gap-2 text-xs text-sub">
        <span className={`h-2 w-2 rounded-full ${live.status === "live" ? "live-dot bg-good" : "bg-faint"}`} />
        {live.status === "live" ? "Streaming over WebSocket · every 2 s" : live.status === "polling" ? "WebSocket unavailable · polling every 5 s" : "Connecting…"}
      </div>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        {d ? (
          <>
            <Stat label="Online now" value={num(d.active_users)} hint="signed in, last 5 min" />
            <Stat label="Requests / min" value={num(d.requests_per_minute)} hint={`${num(d.requests_last_hour)} in the last hour`} />
            <Stat label="Events (24 h)" value={num(d.totals.events_24h)} />
            <Stat label="Total users" value={num(d.totals.users)} />
            <Stat label="p95 latency" value={`${num(d.p95_ms)} ms`} hint="last minute" />
            <Stat label="Error rate" value={`${(d.error_rate * 100).toFixed(1)}%`} hint="5xx, last minute" />
          </>
        ) : Array.from({ length: 6 }, (_, i) => <Skeleton key={i} className="h-[104px] rounded-2xl" />)}
      </div>

      <div className="grid gap-5 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHead title="Requests per minute" sub="Last 30 minutes, by platform. Click a legend item to hide it." />
          <div className="px-5 pt-3"><Legend keys={keys} hidden={hidden} onToggle={toggle} /></div>
          <div className="px-2 pb-4 pt-2">{d ? <LiveArea data={d.series.map((row) => Object.fromEntries([["t", row.t], ...keys.map((k) => [k, row[k] ?? 0])]))} keys={keys} hidden={hidden} /> : <Skeleton className="mx-3 h-[260px]" />}</div>
        </Card>
        <Card>
          <CardHead title="This minute" sub="Requests by platform." />
          <div className="p-5">
            {d ? <HBars items={d.by_platform.map((p) => ({ label: p.label, value: p.rpm }))} tone="var(--s-social)" /> : <Skeleton className="h-40" />}
          </div>
          <CardHead title="Recent events" sub="Forwarded to your analytics tools." />
          <ul className="space-y-1.5 px-5 pb-5 pt-3">
            {d?.feed.length ? d.feed.map((f, i) => (
              <li key={`${f.t}-${i}`} className="rise flex items-center gap-2 text-xs">
                <span className="h-2 w-2 shrink-0 rounded-sm" style={{ background: color(f.platform) }} />
                <code className="truncate text-ink">{f.event}</code>
                <span className="ml-auto shrink-0 text-faint">{ago(f.t)}</span>
              </li>
            )) : <li className="text-xs text-faint">No events yet.</li>}
          </ul>
        </Card>
      </div>

      <Card>
        <CardHead
          title="Traffic"
          sub="API requests per hour, by platform."
          right={<Segmented value={hours} onChange={setHours} options={[{ value: 24, label: "24 h" }, { value: 72, label: "3 d" }, { value: 168, label: "7 d" }]} />}
        />
        <div className="px-2 pb-4 pt-4">
          {traffic.data ? (
            <StackedDaily
              data={traffic.data.series.map((s) => ({ ...Object.fromEntries(keys.map((k) => [k, s[k] ?? 0])), date: new Date(s.t * 1000).toISOString() }))}
              keys={keys} hidden={hidden} labels={LABELS} height={240}
              xFormat={(d) => hours > 24 ? new Date(d).toLocaleDateString("en-IN", { day: "numeric", month: "short" }) : new Date(d).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })}
              tipFormat={(d) => new Date(d).toLocaleString("en-IN", { weekday: "short", hour: "2-digit", minute: "2-digit" })}
            />
          ) : <Skeleton className="mx-3 h-[240px]" />}
        </div>
      </Card>
    </div>
  );
}
