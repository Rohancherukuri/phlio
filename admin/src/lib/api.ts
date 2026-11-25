// Phlio Admin API client. Admin tokens live in sessionStorage (cleared with
// the tab) and expire on the server after a few hours.

export const API_URL = (import.meta.env.VITE_API_URL as string | undefined)?.replace(/\/$/, "") ?? "";
const PREFIX = `${API_URL}/api/v1`;
const KEY = "phlio_admin_token";

export type Role = "owner" | "admin" | "analyst" | "viewer";
export interface Admin { id: string; email: string; name: string; role: Role; created_at: string; last_login?: string; disabled?: boolean }

export class ApiError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export const auth = {
  get token(): string | null {
    try { return sessionStorage.getItem(KEY); } catch { return null; }
  },
  set(token: string | null) {
    try { token ? sessionStorage.setItem(KEY, token) : sessionStorage.removeItem(KEY); } catch { /* private mode */ }
    window.dispatchEvent(new Event("phlio-auth"));
  },
};

export async function api<T = any>(path: string, init: RequestInit & { json?: unknown } = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (auth.token) headers.set("Authorization", `Bearer ${auth.token}`);
  let body = init.body;
  if (init.json !== undefined) { headers.set("Content-Type", "application/json"); body = JSON.stringify(init.json); }
  const res = await fetch(PREFIX + path, { ...init, headers, body });
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    if (res.status === 401 && auth.token && !path.startsWith("/admin/auth/")) auth.set(null);
    const msg = data?.error?.message ?? (typeof data?.detail === "string" ? data.detail : data?.detail?.[0]?.msg) ?? `Request failed (${res.status})`;
    throw new ApiError(res.status, msg);
  }
  return data as T;
}

export function liveUrl(): string {
  const base = API_URL || window.location.origin;
  return base.replace(/^http/, "ws") + "/api/v1/admin/live";
}

export const canManage = (role?: Role) => role === "owner" || role === "admin";
