// Interactive charts (Recharts). Rules: colour follows the platform, thin
// marks with rounded data-ends, a 2px surface gap between stacked fills,
// recessive grid, a hover tooltip on every chart, and a legend you can click
// to show/hide series (identity is never colour alone: names are in the legend
// and tooltip).
import clsx from "clsx";
import { useMemo, useState } from "react";
import {
  Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, Line, LineChart, Pie, PieChart,
  ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";
import { LABELS, color, compact, day, fmt, num } from "../lib/format";
import { Delta } from "./ui";

type Row = Record<string, any>;

function TipBox({ title, items }: { title: string; items: { name: string; value: string; color?: string }[] }) {
  return (
    <div className="min-w-[150px] rounded-xl border border-line bg-card px-3 py-2 shadow-xl backdrop-blur">
      <p className="mb-1.5 text-[11px] font-medium text-sub">{title}</p>
      {items.map((i) => (
        <div key={i.name} className="flex items-center justify-between gap-4 py-0.5 text-xs">
          <span className="flex items-center gap-1.5 text-sub">
            {i.color && <span className="h-2 w-2 rounded-sm" style={{ background: i.color }} />}
            {i.name}
          </span>
          <span className="font-semibold tabular-nums text-ink">{i.value}</span>
        </div>
      ))}
    </div>
  );
}

const axis = { tickLine: false, axisLine: false, tick: { fontSize: 11 } } as const;

export function Spark({ data, tone = "var(--ink)", kind }: { data: number[]; tone?: string; kind?: string }) {
  const rows = data.map((v, i) => ({ i, v }));
  const id = useMemo(() => "g" + Math.random().toString(36).slice(2, 8), []);
  return (
    <ResponsiveContainer width="100%" height={44}>
      <AreaChart data={rows} margin={{ top: 4, right: 0, bottom: 0, left: 0 }}>
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={tone} stopOpacity={0.25} />
            <stop offset="100%" stopColor={tone} stopOpacity={0} />
          </linearGradient>
        </defs>
        <Tooltip
          cursor={{ stroke: "var(--line)" }}
          content={({ active, payload }) =>
            active && payload?.length ? <TipBox title={`Day ${Number(payload[0].payload.i) + 1}`} items={[{ name: "Value", value: fmt(payload[0].value as number, kind) }]} /> : null
          }
        />
        <Area type="monotone" dataKey="v" stroke={tone} strokeWidth={2} fill={`url(#${id})`} dot={false} activeDot={{ r: 4, strokeWidth: 2, stroke: "var(--card)" }} isAnimationActive />
      </AreaChart>
    </ResponsiveContainer>
  );
}

export function KpiCard({ label, value, change, series, kind, hint }: { label: string; value: number; change?: number | null; series?: number[]; kind?: string; hint?: string }) {
  return (
    <div className="rise rounded-2xl border border-line bg-card p-4">
      <div className="flex items-center justify-between">
        <p className="text-xs font-medium text-sub">{label}</p>
        {change !== undefined && <Delta value={change} />}
      </div>
      <p className="mt-2 text-[26px] font-semibold leading-none tracking-tight tabular-nums">{fmt(value, kind)}</p>
      {hint && <p className="mt-1 text-[11px] text-faint">{hint}</p>}
      {series && series.length > 1 && (
        <div className="-mx-1 mt-2">
          <Spark data={series} kind={kind} />
        </div>
      )}
    </div>
  );
}

export function Legend({ keys, hidden, onToggle, labels = LABELS }: { keys: string[]; hidden: Set<string>; onToggle: (k: string) => void; labels?: Record<string, string> }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {keys.map((k) => (
        <button
          key={k}
          onClick={() => onToggle(k)}
          aria-pressed={!hidden.has(k)}
          className={clsx(
            "flex items-center gap-1.5 rounded-md border border-line px-2 py-1 text-[11px] font-medium transition",
            hidden.has(k) ? "text-faint line-through opacity-60" : "text-sub hover:text-ink",
          )}
        >
          <span className="h-2 w-2 rounded-sm" style={{ background: hidden.has(k) ? "var(--line)" : color(k) }} />
          {labels[k] ?? k}
        </button>
      ))}
    </div>
  );
}

export function useToggle() {
  const [hidden, setHidden] = useState<Set<string>>(new Set());
  const toggle = (k: string) =>
    setHidden((h) => {
      const n = new Set(h);
      n.has(k) ? n.delete(k) : n.add(k);
      return n;
    });
  return { hidden, toggle };
}

/** Daily events stacked by platform; click a bar to drill in. */
export function StackedDaily({ data, keys, hidden, onPick, height = 280, labels = LABELS, colorOf = color, xFormat = (d: string) => day(d), tipFormat = (d: string) => day(d, true) }: {
  data: Row[]; keys: string[]; hidden: Set<string>; onPick?: (date: string) => void; height?: number;
  labels?: Record<string, string>; colorOf?: (k: string) => string; xFormat?: (d: string) => string; tipFormat?: (d: string) => string;
}) {
  const shown = keys.filter((k) => !hidden.has(k));
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 8, right: 4, bottom: 0, left: -12 }} barCategoryGap="22%"
        onClick={(s: any) => s?.activeLabel && onPick?.(s.activeLabel)}>
        <CartesianGrid vertical={false} />
        <XAxis dataKey="date" {...axis} tickFormatter={xFormat} minTickGap={18} />
        <YAxis {...axis} tickFormatter={compact} allowDecimals={false} width={44} />
        <Tooltip
          content={({ active, payload, label }) =>
            active && payload?.length ? (
              <TipBox
                title={tipFormat(String(label))}
                items={[...payload].reverse().map((p) => ({ name: labels[String(p.dataKey)] ?? String(p.dataKey), value: num(p.value as number), color: colorOf(String(p.dataKey)) }))}
              />
            ) : null
          }
        />
        {shown.map((k, i) => (
          <Bar key={k} dataKey={k} stackId="a" fill={colorOf(k)} stroke="var(--card)" strokeWidth={2}
            radius={i === shown.length - 1 ? [4, 4, 0, 0] : 0} maxBarSize={28} cursor={onPick ? "pointer" : undefined} />
        ))}
      </BarChart>
    </ResponsiveContainer>
  );
}

/** One or two lines over time with a crosshair. */
export function Trend({ data, lines, height = 240 }: { data: Row[]; lines: { key: string; label: string; tone: string }[]; height?: number }) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <LineChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -12 }}>
        <CartesianGrid vertical={false} />
        <XAxis dataKey="date" {...axis} tickFormatter={(d) => day(d)} minTickGap={18} />
        <YAxis {...axis} tickFormatter={compact} allowDecimals={false} width={44} />
        <Tooltip
          cursor={{ stroke: "var(--faint)", strokeDasharray: "3 3" }}
          content={({ active, payload, label }) =>
            active && payload?.length ? (
              <TipBox title={day(String(label), true)} items={payload.map((p) => ({ name: lines.find((l) => l.key === p.dataKey)?.label ?? "", value: num(p.value as number), color: p.color }))} />
            ) : null
          }
        />
        {lines.map((l) => (
          <Line key={l.key} type="monotone" dataKey={l.key} stroke={l.tone} strokeWidth={2} dot={false}
            activeDot={{ r: 5, strokeWidth: 2, stroke: "var(--card)" }} />
        ))}
      </LineChart>
    </ResponsiveContainer>
  );
}

/** Share of events by platform; hover a slice to read it in the centre. */
export function Donut({ items, onPick }: { items: { id: string; label: string; value: number }[]; onPick?: (id: string) => void }) {
  const [hover, setHover] = useState<number | null>(null);
  const total = items.reduce((s, i) => s + i.value, 0);
  const shown = items.filter((i) => i.value > 0);
  const focus = hover != null ? shown[hover] : null;
  if (!total) return <p className="py-16 text-center text-sm text-faint">No events in this period yet.</p>;
  return (
    <div className="relative">
      <ResponsiveContainer width="100%" height={220}>
        <PieChart>
          <Pie data={shown} dataKey="value" nameKey="label" innerRadius={66} outerRadius={92} paddingAngle={1.5}
            stroke="var(--card)" strokeWidth={2} onMouseEnter={(_, i) => setHover(i)} onMouseLeave={() => setHover(null)}
            onClick={(d: any) => onPick?.(d.id)} cursor={onPick ? "pointer" : undefined}>
            {shown.map((i, n) => (
              <Cell key={i.id} fill={color(i.id)} opacity={hover == null || hover === n ? 1 : 0.35} />
            ))}
          </Pie>
        </PieChart>
      </ResponsiveContainer>
      <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-[22px] font-semibold tabular-nums">{num(focus ? focus.value : total)}</span>
        <span className="text-[11px] text-sub">
          {focus ? `${focus.label} · ${Math.round((focus.value / total) * 100)}%` : "events"}
        </span>
      </div>
    </div>
  );
}

export function HourBars({ data, tone }: { data: { hour: number; count: number }[]; tone: string }) {
  const max = Math.max(1, ...data.map((d) => d.count));
  return (
    <ResponsiveContainer width="100%" height={180}>
      <BarChart data={data} margin={{ top: 8, right: 0, bottom: 0, left: -20 }} barCategoryGap="18%">
        <XAxis dataKey="hour" {...axis} tickFormatter={(h) => (h % 6 === 0 ? `${h}:00` : "")} interval={0} />
        <YAxis {...axis} hide domain={[0, max]} />
        <Tooltip content={({ active, payload }) =>
          active && payload?.length ? <TipBox title={`${payload[0].payload.hour}:00 – ${payload[0].payload.hour + 1}:00 UTC`} items={[{ name: "Actions", value: num(payload[0].value as number), color: tone }]} /> : null} />
        <Bar dataKey="count" fill={tone} radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}

export function HBars({ items, tone }: { items: { label: string; value: number }[]; tone: string }) {
  const max = Math.max(1, ...items.map((i) => i.value));
  if (!items.length) return <p className="py-8 text-center text-sm text-faint">Nothing yet.</p>;
  return (
    <ul className="space-y-2.5">
      {items.map((i) => (
        <li key={i.label} className="group" title={`${i.label}: ${num(i.value)}`}>
          <div className="mb-1 flex justify-between text-xs">
            <span className="truncate text-sub group-hover:text-ink">{i.label}</span>
            <span className="tabular-nums text-ink">{num(i.value)}</span>
          </div>
          <div className="h-1.5 rounded-full bg-muted">
            <div className="h-1.5 rounded-full transition-all duration-500" style={{ width: `${(i.value / max) * 100}%`, background: tone }} />
          </div>
        </li>
      ))}
    </ul>
  );
}

export function LiveArea({ data, keys, hidden }: { data: Row[]; keys: string[]; hidden: Set<string> }) {
  const shown = keys.filter((k) => !hidden.has(k));
  return (
    <ResponsiveContainer width="100%" height={260}>
      <AreaChart data={data} margin={{ top: 8, right: 4, bottom: 0, left: -12 }}>
        <CartesianGrid vertical={false} />
        <XAxis dataKey="t" {...axis} tickFormatter={(t) => new Date(t * 1000).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })} minTickGap={30} />
        <YAxis {...axis} allowDecimals={false} width={44} />
        <Tooltip
          cursor={{ stroke: "var(--faint)", strokeDasharray: "3 3" }}
          content={({ active, payload, label }) =>
            active && payload?.length ? (
              <TipBox title={new Date(Number(label) * 1000).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })}
                items={[...payload].reverse().filter((p) => p.value).map((p) => ({ name: LABELS[String(p.dataKey)] ?? String(p.dataKey), value: num(p.value as number), color: color(String(p.dataKey)) }))} />
            ) : null
          }
        />
        {shown.map((k) => (
          <Area key={k} type="monotone" dataKey={k} stackId="1" stroke={color(k)} strokeWidth={1.5} fill={color(k)} fillOpacity={0.22}
            isAnimationActive={false} />
        ))}
      </AreaChart>
    </ResponsiveContainer>
  );
}
