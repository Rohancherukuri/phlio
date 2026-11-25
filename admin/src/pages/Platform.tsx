import { useQuery } from "@tanstack/react-query";
import { useParams } from "react-router-dom";
import { HBars, HourBars, KpiCard, Legend, StackedDaily, useToggle } from "../components/charts";
import { Card, CardHead, ErrorNote, Skeleton } from "../components/ui";
import { api } from "../lib/api";
import { color, num, verb } from "../lib/format";
import { usePanel } from "../lib/panel";

interface Detail {
  id: string; label: string; days: number;
  metrics: { id: string; label: string; value: number; change: number | null }[];
  series: Record<string, any>[];
  actions: { verb: string; count: number }[];
  top_content: { title: string; count: number }[];
  top_users: { id: string; username: string; name: string; avatar_url?: string; count: number }[];
  by_hour: { hour: number; count: number }[];
}

// Metrics inside one platform take categorical slots in a fixed order.
const SLOTS = ["social", "dm", "rooms", "pay", "book", "shop", "stream", "agent"];
const slot = (i: number) => `var(--s-${SLOTS[i % SLOTS.length]})`;

export default function PlatformPage() {
  const { platform = "social" } = useParams();
  const { days } = usePanel();
  const q = useQuery({
    queryKey: ["platform", platform, days],
    queryFn: () => api<Detail>(`/admin/platforms/${platform}?days=${days}`),
    refetchInterval: 60_000,
  });
  const { hidden, toggle } = useToggle();
  if (q.error) return <ErrorNote error={q.error} />;
  const d = q.data;
  const keys = d?.metrics.map((m) => m.id) ?? [];
  const labels = Object.fromEntries(d?.metrics.map((m) => [m.id, m.label]) ?? []);
  const colorOf = (k: string) => slot(keys.indexOf(k));
  const tone = color(platform);

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
        {d ? d.metrics.map((m) => (
          <KpiCard key={m.id} label={m.label} value={m.value} change={m.change} series={d.series.map((s) => s[m.id] ?? 0)} />
        )) : Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="h-[132px] rounded-2xl" />)}
      </div>

      <Card>
        <CardHead title="Daily breakdown" sub={`What happened on Phlio ${d?.label ?? ""}, day by day. Click a legend item to hide it.`} />
        <div className="px-5 pt-3">
          {d && <Legend keys={keys} hidden={hidden} onToggle={toggle} labels={labels} />}
        </div>
        <div className="px-2 pb-4 pt-2">
          {d ? <StackedDaily data={d.series} keys={keys} hidden={hidden} labels={labels} colorOf={colorOf} height={300} />
            : <Skeleton className="mx-3 h-[300px]" />}
        </div>
      </Card>

      <div className="grid gap-5 lg:grid-cols-3">
        <Card>
          <CardHead title="Actions" sub="Engagement on this platform." />
          <div className="p-5">{d ? <HBars items={d.actions.map((a) => ({ label: verb(a.verb), value: a.count }))} tone={tone} /> : <Skeleton className="h-40" />}</div>
        </Card>
        <Card>
          <CardHead title="Top content" sub="Most-engaged items." />
          <div className="p-5">{d ? <HBars items={d.top_content.map((t) => ({ label: t.title, value: t.count }))} tone={tone} /> : <Skeleton className="h-40" />}</div>
        </Card>
        <Card>
          <CardHead title="Most active people" sub="By actions in this period." />
          <ul className="space-y-1 p-3">
            {d?.top_users.length ? d.top_users.map((u) => (
              <li key={u.id} className="flex items-center gap-3 rounded-lg px-2 py-1.5 hover:bg-muted">
                {u.avatar_url && /^https?:/.test(u.avatar_url)
                  ? <img src={u.avatar_url} alt="" className="h-8 w-8 rounded-full object-cover" referrerPolicy="no-referrer" />
                  : <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted text-xs font-semibold">{u.name.slice(0, 1)}</div>}
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[13px] font-medium">{u.name}</p>
                  <p className="truncate text-[11px] text-faint">@{u.username}</p>
                </div>
                <span className="text-xs tabular-nums text-sub">{num(u.count)}</span>
              </li>
            )) : <p className="py-8 text-center text-sm text-faint">{d ? "Nobody yet." : "…"}</p>}
          </ul>
        </Card>
      </div>

      <Card>
        <CardHead title="When people are active" sub="Actions by hour of day (UTC)." />
        <div className="px-2 pb-4 pt-3">{d ? <HourBars data={d.by_hour} tone={tone} /> : <Skeleton className="mx-3 h-[180px]" />}</div>
      </Card>
    </div>
  );
}
