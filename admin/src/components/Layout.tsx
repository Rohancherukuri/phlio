import clsx from "clsx";
import {
  LayoutDashboard, LogOut, Menu, Moon, PlugZap, Radio, Sun, Users, UsersRound, X,
} from "lucide-react";
import { useEffect, useState, type ReactNode } from "react";
import { NavLink, Outlet, useLocation, useSearchParams } from "react-router-dom";
import { auth, canManage, type Admin } from "../lib/api";
import { trackPage } from "../lib/analytics";
import { LABELS, PLATFORMS, color } from "../lib/format";
import { useLive } from "../lib/live";
import { PhlioMark, PhlioName } from "./brand";
import { Segmented } from "./ui";

export function Logo({ small, size = 32 }: { small?: boolean; size?: number }) {
  return (
    <div className="flex items-center gap-2.5">
      <PhlioMark size={size} />
      {!small && (
        <div className="leading-tight">
          <p className="text-[15px] font-semibold">Phlio</p>
          <p className="text-[11px] text-faint">Admin</p>
        </div>
      )}
    </div>
  );
}

function Item({ to, icon, children, dot, onClick }: { to: string; icon?: ReactNode; children: ReactNode; dot?: string; onClick?: () => void }) {
  return (
    <NavLink
      to={to}
      end
      onClick={onClick}
      className={({ isActive }) =>
        clsx(
          "flex h-9 items-center gap-2.5 rounded-lg px-2.5 text-[13px] font-medium transition",
          isActive ? "bg-muted text-ink" : "text-sub hover:bg-muted hover:text-ink",
        )
      }
    >
      {icon}
      {dot && <span className="ml-1 mr-0.5 h-2 w-2 rounded-sm" style={{ background: dot }} />}
      {children}
    </NavLink>
  );
}

const TITLES: Record<string, string> = {
  "/": "Overview", "/live": "Live", "/users": "Users", "/integrations": "Integrations", "/team": "Team",
};

function useTheme() {
  const [theme, setTheme] = useState<"dark" | "light">(() => {
    try { return (localStorage.getItem("phlio_admin_theme") as "dark" | "light") || "dark"; } catch { return "dark"; }
  });
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try { localStorage.setItem("phlio_admin_theme", theme); } catch { /* ignore */ }
  }, [theme]);
  return [theme, () => setTheme((t) => (t === "dark" ? "light" : "dark"))] as const;
}

export function Layout({ admin }: { admin: Admin }) {
  const [open, setOpen] = useState(false);
  const [theme, flip] = useTheme();
  const loc = useLocation();
  const [params, setParams] = useSearchParams();
  const days = Number(params.get("days") || 30);
  const live = useLive();
  const platform = loc.pathname.startsWith("/p/") ? loc.pathname.slice(3) : null;
  const title = platform ? `Phlio ${LABELS[platform] ?? platform}` : TITLES[loc.pathname] ?? "Phlio Admin";
  const showRange = loc.pathname === "/" || !!platform;

  useEffect(() => {
    document.title = `${title} · Phlio Admin`;
    trackPage(loc.pathname, title);
  }, [loc.pathname, title]);

  const close = () => setOpen(false);
  const nav = (
    <nav className="flex h-full flex-col gap-6 overflow-y-auto px-3 py-5">
      <div className="px-1.5"><Logo /></div>
      <div className="space-y-0.5">
        <p className="px-2.5 pb-1 text-[11px] font-medium uppercase tracking-wider text-faint">Dashboard</p>
        <Item to="/" icon={<LayoutDashboard size={16} />} onClick={close}>Overview</Item>
        <Item to="/live" icon={<Radio size={16} />} onClick={close}>Live</Item>
        <Item to="/users" icon={<Users size={16} />} onClick={close}>Users</Item>
      </div>
      <div className="space-y-0.5">
        <p className="px-2.5 pb-1 text-[11px] font-medium uppercase tracking-wider text-faint">Platforms</p>
        {PLATFORMS.map((p) => (
          <Item key={p} to={`/p/${p}${days !== 30 ? `?days=${days}` : ""}`} dot={color(p)} onClick={close}>{LABELS[p]}</Item>
        ))}
      </div>
      <div className="space-y-0.5">
        <p className="px-2.5 pb-1 text-[11px] font-medium uppercase tracking-wider text-faint">Settings</p>
        <Item to="/integrations" icon={<PlugZap size={16} />} onClick={close}>Integrations</Item>
        {canManage(admin.role) && <Item to="/team" icon={<UsersRound size={16} />} onClick={close}>Team</Item>}
      </div>
      <div className="mt-auto rounded-xl border border-line p-3">
        <p className="truncate text-[13px] font-medium">{admin.name}</p>
        <p className="truncate text-[11px] text-faint">{admin.email} · {admin.role}</p>
        <button onClick={() => auth.set(null)} className="mt-2.5 flex items-center gap-1.5 text-xs text-sub hover:text-ink">
          <LogOut size={13} /> Sign out
        </button>
      </div>
    </nav>
  );

  return (
    <div className="flex min-h-full">
      <aside className="sticky top-0 hidden h-screen w-60 shrink-0 border-r border-line bg-bg lg:block">{nav}</aside>
      {open && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <div className="absolute inset-0 bg-black/60" onClick={close} />
          <aside className="absolute inset-y-0 left-0 w-64 border-r border-line bg-bg">
            <button className="absolute right-3 top-4 text-sub" onClick={close} aria-label="Close menu"><X size={18} /></button>
            {nav}
          </aside>
        </div>
      )}
      <div className="min-w-0 flex-1">
        <header className="sticky top-0 z-30 flex h-14 items-center gap-3 border-b border-line bg-bg px-4 sm:px-6">
          <button className="text-sub lg:hidden" onClick={() => setOpen(true)} aria-label="Open menu"><Menu size={20} /></button>
          <h1 className="min-w-0 text-[15px] font-semibold">
            {platform ? <PhlioName size={18}>{LABELS[platform] ?? platform}</PhlioName> : title}
          </h1>
          <div className="ml-auto flex items-center gap-2">
            {showRange && (
              <div className="hidden sm:block">
                <Segmented value={days} onChange={(d) => setParams((p) => { p.set("days", String(d)); return p; })}
                  options={[{ value: 7, label: "7D" }, { value: 30, label: "30D" }, { value: 90, label: "90D" }]} />
              </div>
            )}
            <NavLink to="/live" className="flex h-8 items-center gap-2 rounded-lg border border-line px-2.5 text-xs text-sub hover:text-ink">
              <span className={clsx("h-2 w-2 rounded-full", live.status === "live" ? "live-dot bg-good" : live.status === "polling" ? "bg-brand" : "bg-faint")} />
              <span className="tabular-nums">{live.data ? `${live.data.active_users} online` : live.status}</span>
            </NavLink>
            <button onClick={flip} className="flex h-8 w-8 items-center justify-center rounded-lg border border-line text-sub hover:text-ink" aria-label="Toggle theme">
              {theme === "dark" ? <Sun size={15} /> : <Moon size={15} />}
            </button>
          </div>
        </header>
        {showRange && (
          <div className="px-4 pt-4 sm:hidden">
            <Segmented value={days} onChange={(d) => setParams((p) => { p.set("days", String(d)); return p; })}
              options={[{ value: 7, label: "7D" }, { value: 30, label: "30D" }, { value: 90, label: "90D" }]} />
          </div>
        )}
        <main className="mx-auto max-w-[1400px] p-4 sm:p-6">
          <Outlet context={{ admin, days, live }} />
        </main>
      </div>
    </div>
  );
}

