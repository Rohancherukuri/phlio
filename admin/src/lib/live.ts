// Live numbers over the admin WebSocket, with automatic reconnect and a
// polling fallback (some proxies drop WebSockets).
import { useEffect, useRef, useState } from "react";
import { api, auth, liveUrl } from "./api";

export interface LiveSnapshot {
  type: "live";
  at: number;
  active_users: number;
  requests_per_minute: number;
  requests_last_hour: number;
  error_rate: number;
  p95_ms: number;
  by_platform: { platform: string; label: string; rpm: number }[];
  series: ({ t: number; total: number } & Record<string, number>)[];
  feed: { t: number; platform: string; event: string }[];
  totals: { users: number; events_24h: number };
}

export type LiveStatus = "connecting" | "live" | "polling" | "offline";

export function useLive(): { data: LiveSnapshot | null; status: LiveStatus } {
  const [data, setData] = useState<LiveSnapshot | null>(null);
  const [status, setStatus] = useState<LiveStatus>("connecting");
  const tries = useRef(0);

  useEffect(() => {
    let ws: WebSocket | null = null;
    let poll: number | undefined;
    let retry: number | undefined;
    let closed = false;

    const startPolling = () => {
      if (poll) return;
      setStatus("polling");
      const tick = () => api<LiveSnapshot>("/admin/live/snapshot").then(setData).catch(() => setStatus("offline"));
      tick();
      poll = window.setInterval(tick, 5000);
    };

    const connect = () => {
      if (closed || !auth.token) return;
      setStatus("connecting");
      try { ws = new WebSocket(liveUrl()); } catch { startPolling(); return; }
      ws.onopen = () => ws?.send(JSON.stringify({ token: auth.token }));
      ws.onmessage = (e) => {
        const msg = JSON.parse(e.data);
        if (msg.type === "live") {
          tries.current = 0;
          if (poll) { clearInterval(poll); poll = undefined; }
          setStatus("live");
          setData(msg);
        }
      };
      ws.onclose = (e) => {
        if (closed) return;
        if (e.code === 4401) { auth.set(null); return; }
        tries.current += 1;
        if (tries.current >= 3) startPolling();
        retry = window.setTimeout(connect, Math.min(15000, 1000 * 2 ** tries.current));
      };
    };

    connect();
    return () => {
      closed = true;
      ws?.close();
      clearInterval(poll);
      clearTimeout(retry);
    };
  }, []);

  return { data, status };
}
