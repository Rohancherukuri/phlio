export const PLATFORMS = ["social", "dm", "rooms", "pay", "book", "shop", "stream", "news", "agent"] as const;
export type Platform = (typeof PLATFORMS)[number];

export const LABELS: Record<string, string> = {
  social: "Social", dm: "Messages", rooms: "Rooms", pay: "Pay", book: "Book", shop: "Shop",
  stream: "Stream", news: "News", agent: "Agent", identity: "Accounts", core: "Core", other: "Other",
};

/** Colour follows the platform, never its rank. */
export const color = (p: string) => `var(--s-${PLATFORMS.includes(p as Platform) ? p : "other"})`;

const nf = new Intl.NumberFormat("en-IN");
const cf = new Intl.NumberFormat("en-IN", { notation: "compact", maximumFractionDigits: 1 });

export function num(v: number | null | undefined): string {
  if (v == null) return "–";
  return Math.abs(v) >= 100_000 ? cf.format(v) : nf.format(Math.round(v * 10) / 10);
}
export const compact = (v: number) => cf.format(v);
export const inr = (v: number) =>
  "₹" + (v >= 100_000 ? cf.format(v) : new Intl.NumberFormat("en-IN", { maximumFractionDigits: 0 }).format(v));

export const fmt = (v: number, kind?: string) => (kind === "inr" ? inr(v) : num(v));

export function day(iso: string, long = false): string {
  const d = new Date(iso.length <= 10 ? iso + "T12:00:00" : iso);
  return d.toLocaleDateString("en-IN", long ? { weekday: "short", day: "numeric", month: "short" } : { day: "numeric", month: "short" });
}
export const clock = (t: number) => new Date(t * 1000).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" });

export function ago(iso?: string | number | null): string {
  if (!iso) return "never";
  const t = typeof iso === "number" ? iso * 1000 : new Date(iso).getTime();
  const s = Math.max(0, (Date.now() - t) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  return `${Math.floor(s / 86400)} d ago`;
}

export const verb = (v: string) => v.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
