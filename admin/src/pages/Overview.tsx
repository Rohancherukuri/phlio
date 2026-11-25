import { useQuery } from "@tanstack/react-query";
import { ChevronRight, Table2 } from "lucide-react";
import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Donut, HBars, KpiCard, Legend, Spark, StackedDaily, Trend, useToggle } from "../components/charts";
import { PhlioName } from "../components/brand";
import { Card, CardHead, Delta, ErrorNote, Skeleton } from "../components/ui";
import { api } from "../lib/api";
import { LABELS, color, day, num, verb } from "../lib/format";
import { usePanel } from "../lib/panel";

export interface Overview {
  days: number;
  generated_at: string;
  kpis: { id: string; label: string; value: number; change: number | null; series?: number[]; format?: string }[];
  platforms: { id: string; label: string; events: number; change: number | null; series: number[]; metrics: { id: string; label: string; value: number; change: number | null }[] }[];
  daily: Record<string, any>[];
  actions: { verb: string; count: number }[];
}

export function useOverview(days: number) {
  return useQuery({ queryKey: ["overview", days], queryFn: () => api<Overview>(`/admin/overview?days=${days}`), refetchInterval: 60_000 });
}

export default function OverviewPage() {
  const { days } = usePanel();
  const q = useOverview(days);
  const nav = useNavigate();
  const { hidden, toggle } = useToggle();
  const [table, setTable] = useState(false);

  if (q.error) return <ErrorNote error={q.error} />;
  const o = q.data;
  const keys = o ? o.platforms.map((p) => p.id) : [];

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        {o ? o.kpis.map((k) => <KpiCard key={k.id} label={k.label} value={k.value} change={k.change} series={k.series} kind={k.format} />)
          : Array.from({ length: 6 }, (_, i) => <Skeleton key={i} className="h-[132px] rounded-2xl" />)}
      </div>

      <div className="grid gap-5 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHead
            title="Events by platform"
            sub={<>Daily activity across <PhlioName size={12} />, last {days} days. Click a legend item to hide it.</>}
            right={
              <button onClick={() => setTable(!table)} className="flex items-center gap-1.5 rounded-md border border-line px-2 py-1 text-[11px] text-sub hover:text-ink" aria-pressed={table}>
                <Table2 size={13} /> {table ? "Chart" : "Table"}
              </button>
            }
          />
          <div className="px-5 pt-3">{o && <Legend keys={keys} hidden={hidden} onToggle={toggle} />}</div>
          <div className="px-2 pb-4 pt-2">
            {!o ? <Skeleton className="mx-3 h-[280px]" /> : table ? (
              <div className="max-h-[300px] overflow-auto px-3">
                <table className="w-full text-xs">
                  <thead className="sticky top-0 bg-card text-faint">
                    <tr><th className="py-2 text-left font-medium">Day</th>{keys.map((k) => <th key={k} className="py-2 text-right font-medium">{LABELS[k]}</th>)}</tr>
                  </thead>
                  <tbody>
                    {[...o.daily].reverse().map((d) => (
                      <tr key={d.date} className="border-t border-line">
                        <td className="py-1.5 text-sub">{day(d.date, true)}</td>
                        {keys.map((k) => <td key={k} className="py-1.5 text-right tabular-nums">{num(d[k])}</td>)}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : <StackedDaily data={o.daily} keys={keys} hidden={hidden} />}
          </div>
        </Card>

        <Card>
          <CardHead title="Platform share" sub={<>Share of events across <PhlioName size={12}/>. Click a slice to open it.</>} />
          <div className="px-4 pb-2">
            {o ? <Donut items={o.platforms.map((p) => ({ id: p.id, label: p.label, value: p.events }))} onPick={(id) => nav(`/p/${id}?days=${days}`)} />
              : <Skeleton className="h-[220px]" />}
          </div>
          <div className="grid grid-cols-3 gap-x-3 gap-y-2 px-5 pb-5">
            {o?.platforms.map((p) => (
              <div key={p.id} className="flex items-center gap-1.5 text-[11px]">
                <span className="h-2 w-2 shrink-0 rounded-sm" style={{ background: color(p.id) }} />
                <span className="truncate text-sub">{p.label}</span>
              </div>
            ))}
          </div>
        </Card>
      </div>

      <div className="grid gap-5 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHead title="People" sub="New signups and signed-in daily actives." />
          <div className="px-2 pb-4 pt-3">
            {o ? <Trend data={o.daily} lines={[{ key: "active", label: "Daily active", tone: "var(--s-social)" }, { key: "users", label: "New users", tone: "var(--s-dm)" }]} />
              : <Skeleton className="mx-3 h-[240px]" />}
          </div>
          <div className="flex gap-4 px-5 pb-5 text-[11px] text-sub">
            <span className="flex items-center gap-1.5"><span className="h-0.5 w-4 rounded" style={{ background: "var(--s-social)" }} /> Daily active</span>
            <span className="flex items-center gap-1.5"><span className="h-0.5 w-4 rounded" style={{ background: "var(--s-dm)" }} /> New users</span>
          </div>
        </Card>
        <Card>
          <CardHead title="Top actions" sub="Likes, views, purchases … across platforms." />
          <div className="p-5">
            {o ? <HBars items={o.actions.map((a) => ({ label: verb(a.verb), value: a.count }))} tone="var(--s-stream)" /> : <Skeleton className="h-[200px]" />}
          </div>
        </Card>
      </div>

      <div>
        <h2 className="mb-3 text-[15px] font-semibold">Platforms</h2>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {o ? o.platforms.map((p) => (
            <Link key={p.id} to={`/p/${p.id}?days=${days}`} className="rise group rounded-2xl border border-line bg-card p-4 transition hover:border-faint">
              <div className="flex items-center gap-2">
                <PhlioName size={17} className="text-sm font-medium">{p.label}</PhlioName>
                <span className="h-2 w-2 shrink-0 rounded-sm" style={{ background: color(p.id) }} aria-hidden />
                <ChevronRight size={15} className="ml-auto text-faint transition group-hover:translate-x-0.5 group-hover:text-ink" />
              </div>
              <div className="mt-3 flex items-end justify-between gap-3">
                <div>
                  <p className="text-2xl font-semibold tabular-nums">{num(p.events)}</p>
                  <p className="text-[11px] text-faint">events · {days} d</p>
                </div>
                <Delta value={p.change} />
              </div>
              <div className="-mx-1 mt-2"><Spark data={p.series} tone={color(p.id)} /></div>
              <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 border-t border-line pt-2.5">
                {p.metrics.slice(0, 3).map((m) => (
                  <span key={m.id} className="text-[11px] text-sub">{m.label} <span className="font-medium tabular-nums text-ink">{num(m.value)}</span></span>
                ))}
              </div>
            </Link>
          )) : Array.from({ length: 9 }, (_, i) => <Skeleton key={i} className="h-[190px] rounded-2xl" />)}
        </div>
      </div>
      {o && <p className="text-[11px] text-faint">Updated {new Date(o.generated_at).toLocaleTimeString("en-IN")} · refreshes every minute</p>}
    </div>
  );
}
