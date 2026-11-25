import clsx from "clsx";
import { ArrowDownRight, ArrowUpRight, Minus } from "lucide-react";
import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from "react";

export function Card({ className, children, ...rest }: { className?: string; children: ReactNode } & React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={clsx("rounded-2xl border border-line bg-card", className)} {...rest}>
      {children}
    </div>
  );
}

export function CardHead({ title, sub, right }: { title: ReactNode; sub?: ReactNode; right?: ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-3 px-5 pt-5">
      <div className="min-w-0">
        <h3 className="text-[15px] font-semibold text-ink">{title}</h3>
        {sub && <p className="mt-0.5 text-xs text-sub">{sub}</p>}
      </div>
      {right}
    </div>
  );
}

export function Button({ variant = "primary", className, ...rest }: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: "primary" | "ghost" | "outline" | "danger" }) {
  return (
    <button
      className={clsx(
        "inline-flex h-9 items-center justify-center gap-2 rounded-lg px-3.5 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-50",
        variant === "primary" && "bg-ink text-bg hover:opacity-90",
        variant === "outline" && "border border-line bg-card text-ink hover:bg-muted",
        variant === "ghost" && "text-sub hover:bg-muted hover:text-ink",
        variant === "danger" && "border border-line text-bad hover:bg-muted",
        className,
      )}
      {...rest}
    />
  );
}

export function Input({ className, ...rest }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={clsx(
        "h-10 w-full rounded-lg border border-line bg-bg px-3 text-sm text-ink outline-none transition placeholder:text-faint focus:border-sub",
        className,
      )}
      {...rest}
    />
  );
}

export function Field({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-xs font-medium text-sub">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-[11px] text-faint">{hint}</span>}
    </label>
  );
}

export function Badge({ children, tone = "neutral" }: { children: ReactNode; tone?: "neutral" | "good" | "bad" | "brand" }) {
  return (
    <span
      className={clsx(
        "inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[11px] font-medium",
        tone === "neutral" && "bg-muted text-sub",
        tone === "good" && "tint-good text-good",
        tone === "bad" && "tint-bad text-bad",
        tone === "brand" && "tint-brand text-brand",
      )}
    >
      {children}
    </span>
  );
}

/** Change vs the previous period, with an icon so it never relies on colour. */
export function Delta({ value }: { value: number | null | undefined }) {
  if (value == null) return null;
  const Icon = value > 0 ? ArrowUpRight : value < 0 ? ArrowDownRight : Minus;
  return (
    <Badge tone={value > 0 ? "good" : value < 0 ? "bad" : "neutral"}>
      <Icon size={12} strokeWidth={2.4} />
      {value > 0 ? "+" : ""}
      {value}%
    </Badge>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={clsx("animate-pulse rounded-lg bg-muted", className)} />;
}

export function Segmented<T extends string | number>({ value, options, onChange }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void }) {
  return (
    <div className="inline-flex rounded-lg border border-line bg-card p-0.5" role="tablist">
      {options.map((o) => (
        <button
          key={String(o.value)}
          role="tab"
          aria-selected={o.value === value}
          onClick={() => onChange(o.value)}
          className={clsx(
            "h-7 rounded-md px-2.5 text-xs font-medium transition",
            o.value === value ? "bg-muted text-ink" : "text-sub hover:text-ink",
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function ErrorNote({ error }: { error: unknown }) {
  if (!error) return null;
  return <p className="rounded-lg tint-bad border border-line px-3 py-2 text-sm text-bad">{(error as Error).message}</p>;
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="flex h-full min-h-[120px] items-center justify-center text-sm text-faint">{children}</div>;
}
