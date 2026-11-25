"""Admin analytics plumbing: live request telemetry and third-party forwarding.

`AdminMetrics` counts every API request by Phlio platform. The counts feed
the admin dashboard's live WebSocket stream and its traffic charts:

* in this process, a bounded window of the last hour (always on, so the
  dashboard works with Redis switched off and in tests), and
* in Redis, when it is enabled: hourly hashes per platform (35 days), a
  HyperLogLog of daily active users (40 days) and a sorted set of users seen
  in the last five minutes, so several workers add up to one picture.

`AnalyticsBridge` forwards product events to the analytics tools an admin
has switched on in the admin panel: Google Analytics 4 (Measurement
Protocol) and the open-source PostHog, Plausible, Umami and Matomo. Events
go out in the background and never slow down or fail a request. User ids
are pseudonymised (a keyed hash) before they leave the server, and no
request bodies, emails or names are ever sent.
"""

from __future__ import annotations

import asyncio
import collections
import datetime as dt
import hashlib
import hmac
import logging
import time
from typing import Any

import httpx
from redis.exceptions import RedisError

log = logging.getLogger("phlio.analytics")

PLATFORMS = {
    "social": "Social",
    "rooms": "Rooms",
    "pay": "Pay",
    "book": "Book",
    "shop": "Shop",
    "stream": "Stream",
    "news": "News",
    "agent": "Agent",
    "identity": "Accounts",
    "core": "Core",
}

# First path segment after /api/v1 → platform.
_SEGMENTS = {
    "social": "social", "stickers": "social", "fact-checks": "social", "memberships": "social",
    "blends": "social", "messaging": "social", "rooms": "rooms", "realtime": "rooms", "watch": "rooms",
    "pay": "pay", "book": "book", "places": "book", "explore": "book", "shop": "shop",
    "stream": "stream", "music": "stream", "playlists": "stream", "news": "news",
    "agent": "agent", "timeline": "agent", "activities": "agent", "fitness": "agent",
    "events": "agent", "activity": "agent", "auth": "identity", "users": "identity",
}


def platform_for(path: str, prefix: str = "/api/v1") -> str | None:
    """The platform an API path belongs to; None for paths that are not
    product traffic (admin, health, media, docs)."""
    if not path.startswith(prefix + "/"):
        return None
    segment = path[len(prefix) + 1 :].split("/", 1)[0]
    if segment in {"admin", "analytics"}:
        return None
    return _SEGMENTS.get(segment, "core")


def event_name(method: str, path: str, prefix: str = "/api/v1") -> str | None:
    """A stable, low-cardinality event name for a mutating request, e.g.
    POST /api/v1/social/posts/abc/like → "social_posts_like"."""
    platform = platform_for(path, prefix)
    if not platform or method in {"GET", "HEAD", "OPTIONS"}:
        return None
    parts = [p for p in path[len(prefix) + 1 :].split("/")[1:] if p]
    # Ids are long or contain digits; keep only the words.
    words = [p.replace("-", "_") for p in parts if p.replace("-", "").replace("_", "").isalpha() and len(p) <= 24]
    verb = {"POST": "create", "PUT": "update", "PATCH": "update", "DELETE": "delete"}.get(method, method.lower())
    tail = words[-2:] if words else []
    if tail and tail[-1] in {"like", "unlike", "follow", "unfollow", "react", "kudos", "join", "leave", "send",
                             "save", "share", "vote", "checkout", "book", "pay", "login", "signup", "register"}:
        verb = ""
    name = "_".join([platform, *tail, verb]).strip("_")
    return name[:40]


class AdminMetrics:
    WINDOW = 3600  # seconds kept in memory
    ACTIVE = 300  # "active now" = seen in the last five minutes

    def __init__(self, cache=None) -> None:
        self.cache = cache
        self.events: collections.deque = collections.deque(maxlen=100_000)
        self.started = time.time()
        self._tasks: set[asyncio.Task] = set()

    @property
    def _redis(self):
        return getattr(self.cache, "redis", None)

    def _k(self, name: str) -> str:
        return f"{getattr(self.cache, 'prefix', 'phlio:')}admin:{name}"

    def record(self, platform: str, status: int, ms: float, user_id: str | None, event: str | None = None) -> None:
        now = time.time()
        self.events.append((now, platform, user_id, status, ms, event))
        if self._redis:
            task = asyncio.create_task(self._persist(now, platform, user_id, status))
            self._tasks.add(task)
            task.add_done_callback(self._tasks.discard)

    async def _persist(self, now: float, platform: str, user_id: str | None, status: int) -> None:
        stamp = dt.datetime.fromtimestamp(now, dt.UTC)
        hour, day = self._k("req:" + stamp.strftime("%Y%m%d%H")), stamp.strftime("%Y%m%d")
        try:
            async with self._redis.pipeline(transaction=False) as pipe:
                pipe.hincrby(hour, platform, 1).expire(hour, 35 * 86400)
                if status >= 500:
                    pipe.hincrby(hour, "_errors", 1)
                if user_id:
                    pipe.pfadd(self._k("dau:" + day), user_id).expire(self._k("dau:" + day), 40 * 86400)
                    pipe.pfadd(self._k(f"pau:{platform}:{day}"), user_id).expire(self._k(f"pau:{platform}:{day}"), 40 * 86400)
                    pipe.zadd(self._k("active"), {user_id: now}).zremrangebyscore(self._k("active"), 0, now - self.ACTIVE)
                await pipe.execute()
        except RedisError:
            pass

    def _recent(self, seconds: int):
        cutoff = time.time() - seconds
        return [e for e in self.events if e[0] >= cutoff]

    async def live(self) -> dict[str, Any]:
        """The numbers the dashboard streams every couple of seconds."""
        now = time.time()
        hour = self._recent(self.WINDOW)
        minute = [e for e in hour if e[0] >= now - 60]
        active = {e[2] for e in hour if e[2] and e[0] >= now - self.ACTIVE}
        active_count = len(active)
        if self._redis:
            try:
                await self._redis.zremrangebyscore(self._k("active"), 0, now - self.ACTIVE)
                active_count = max(active_count, int(await self._redis.zcard(self._k("active"))))
            except RedisError:
                pass
        # Requests per minute over the last 30 minutes, per platform.
        start = int(now // 60) - 29
        buckets = [{"t": (start + i) * 60, "total": 0} for i in range(30)]
        for e in hour:
            i = int(e[0] // 60) - start
            if 0 <= i < 30:
                buckets[i]["total"] += 1
                buckets[i][e[1]] = buckets[i].get(e[1], 0) + 1
        by_platform = collections.Counter(e[1] for e in minute)
        latencies = sorted(e[4] for e in minute)
        p95 = latencies[int(len(latencies) * 0.95) - 1] if latencies else 0
        errors = sum(1 for e in minute if e[3] >= 500)
        feed = [
            {"t": e[0], "platform": e[1], "event": e[5]}
            for e in list(self.events)[-200:][::-1]
            if e[5]
        ][:12]
        return {
            "at": now,
            "active_users": active_count,
            "requests_per_minute": len(minute),
            "requests_last_hour": len(hour),
            "error_rate": round(errors / len(minute), 4) if minute else 0,
            "p95_ms": round(p95, 1),
            "by_platform": [{"platform": p, "label": PLATFORMS.get(p, p), "rpm": n} for p, n in by_platform.most_common()],
            "series": buckets,
            "feed": feed,
            "uptime_s": int(now - self.started),
        }

    async def hourly(self, hours: int = 24) -> list[dict[str, Any]]:
        """Requests per hour per platform (Redis when enabled, else this process)."""
        now = dt.datetime.now(dt.UTC).replace(minute=0, second=0, microsecond=0)
        slots = [now - dt.timedelta(hours=h) for h in range(hours - 1, -1, -1)]
        out = [{"t": int(s.timestamp()), "total": 0} for s in slots]
        if self._redis:
            try:
                async with self._redis.pipeline(transaction=False) as pipe:
                    for s in slots:
                        pipe.hgetall(self._k("req:" + s.strftime("%Y%m%d%H")))
                    results = await pipe.execute()
                for row, data in zip(out, results):
                    for p, n in (data or {}).items():
                        if p != "_errors":
                            row[p] = int(n)
                            row["total"] += int(n)
                return out
            except RedisError:
                pass
        first = slots[0].timestamp()
        for e in self.events:
            i = int((e[0] - first) // 3600)
            if 0 <= i < hours:
                out[i]["total"] += 1
                out[i][e[1]] = out[i].get(e[1], 0) + 1
        return out

    async def daily_active(self, days: int) -> list[dict[str, Any]]:
        """Distinct signed-in users per day (Redis HyperLogLog; this process otherwise)."""
        today = dt.datetime.now(dt.UTC).date()
        dates = [today - dt.timedelta(days=d) for d in range(days - 1, -1, -1)]
        if self._redis:
            try:
                async with self._redis.pipeline(transaction=False) as pipe:
                    for d in dates:
                        pipe.pfcount(self._k("dau:" + d.strftime("%Y%m%d")))
                    counts = await pipe.execute()
                return [{"date": d.isoformat(), "active": int(n)} for d, n in zip(dates, counts)]
            except RedisError:
                pass
        seen: dict[str, set] = collections.defaultdict(set)
        for e in self.events:
            if e[2]:
                seen[dt.datetime.fromtimestamp(e[0], dt.UTC).date().isoformat()].add(e[2])
        return [{"date": d.isoformat(), "active": len(seen.get(d.isoformat(), ()))} for d in dates]


# --- Third-party analytics -----------------------------------------------

PROVIDERS: dict[str, dict[str, Any]] = {
    "ga4": {
        "label": "Google Analytics 4",
        "open_source": False,
        "fields": {"measurement_id": False, "api_secret": True},
        "public": ["measurement_id"],
        "docs": "https://developers.google.com/analytics/devguides/collection/protocol/ga4",
    },
    "posthog": {
        "label": "PostHog",
        "open_source": True,
        "fields": {"host": False, "project_api_key": False},
        "public": ["host", "project_api_key"],
        "docs": "https://posthog.com/docs/api/capture",
    },
    "plausible": {
        "label": "Plausible",
        "open_source": True,
        "fields": {"host": False, "domain": False},
        "public": ["host", "domain"],
        "docs": "https://plausible.io/docs/events-api",
    },
    "umami": {
        "label": "Umami",
        "open_source": True,
        "fields": {"host": False, "website_id": False},
        "public": ["host", "website_id"],
        "docs": "https://umami.is/docs/api/sending-stats",
    },
    "matomo": {
        "label": "Matomo",
        "open_source": True,
        "fields": {"host": False, "site_id": False, "token_auth": True},
        "public": ["host", "site_id"],
        "docs": "https://developer.matomo.org/api-reference/tracking-api",
    },
}

DEFAULT_HOSTS = {"posthog": "https://us.i.posthog.com", "plausible": "https://plausible.io"}
_UA = "Phlio-Server/1.0 (+server-side analytics)"


def _host(cfg: dict, provider: str) -> str:
    return (cfg.get("host") or DEFAULT_HOSTS.get(provider, "")).rstrip("/")


def build_request(provider: str, cfg: dict, event: str, client_id: str, props: dict, *, debug=False):
    """(method, url, kwargs) for one event to one provider, or None when the
    provider is missing a required field."""
    props = {k: v for k, v in props.items() if isinstance(v, (str, int, float, bool))}
    page = props.get("path", "/app")
    if provider == "ga4":
        if not (cfg.get("measurement_id") and cfg.get("api_secret")):
            return None
        url = "https://www.google-analytics.com/" + ("debug/mp/collect" if debug else "mp/collect")
        return "POST", url, {
            "params": {"measurement_id": cfg["measurement_id"], "api_secret": cfg["api_secret"]},
            "json": {"client_id": client_id, "user_id": client_id,
                     "events": [{"name": event[:40], "params": {**props, "engagement_time_msec": 1}}]},
        }
    if provider == "posthog":
        if not cfg.get("project_api_key"):
            return None
        return "POST", _host(cfg, provider) + "/capture/", {
            "json": {"api_key": cfg["project_api_key"], "event": event, "distinct_id": client_id,
                     "properties": {**props, "$lib": "phlio-server"}},
        }
    if provider == "plausible":
        if not cfg.get("domain"):
            return None
        return "POST", _host(cfg, provider) + "/api/event", {
            "headers": {"User-Agent": _UA, "Content-Type": "application/json"},
            "json": {"name": event, "domain": cfg["domain"], "url": f"app://{cfg['domain']}{page}", "props": props},
        }
    if provider == "umami":
        if not (cfg.get("host") and cfg.get("website_id")):
            return None
        return "POST", _host(cfg, provider) + "/api/send", {
            "headers": {"User-Agent": _UA},
            "json": {"type": "event", "payload": {"website": cfg["website_id"], "name": event, "url": page,
                                                  "hostname": "phlio.app", "data": props}},
        }
    if provider == "matomo":
        if not (cfg.get("host") and cfg.get("site_id")):
            return None
        category, _, action = event.partition("_")
        params = {"idsite": cfg["site_id"], "rec": 1, "apiv": 1, "uid": client_id, "url": f"app://phlio{page}",
                  "e_c": category, "e_a": action or event, "send_image": 0}
        if cfg.get("token_auth"):
            params["token_auth"] = cfg["token_auth"]
        return "POST", _host(cfg, provider) + "/matomo.php", {"data": params, "headers": {"User-Agent": _UA}}
    return None


class AnalyticsBridge:
    """Forwards events to the providers switched on in the admin panel."""

    REFRESH = 30  # seconds between config reloads

    def __init__(self, secret: str) -> None:
        self._secret = secret.encode()
        self._configs: dict[str, dict] = {}
        self._loaded = 0.0
        self._client: httpx.AsyncClient | None = None
        self._tasks: set[asyncio.Task] = set()
        self.sent = collections.Counter()
        self.failed = collections.Counter()

    def pseudonym(self, user_id: str | None) -> str:
        if not user_id:
            return "anonymous"
        return hmac.new(self._secret, user_id.encode(), hashlib.sha256).hexdigest()[:32]

    def set_configs(self, configs: dict[str, dict]) -> None:
        self._configs = {p: c for p, c in configs.items() if c.get("enabled")}
        self._loaded = time.time()

    async def refresh(self, store) -> None:
        if time.time() - self._loaded < self.REFRESH:
            return
        self._loaded = time.time()
        try:
            rows = await store.rows("admin_integration")
        except Exception:  # noqa: BLE001 — analytics must never break requests
            return
        self.set_configs({r["provider"]: r for r in rows if r.get("provider")})

    @property
    def enabled(self) -> list[str]:
        return list(self._configs)

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=4)
        return self._client

    async def send(self, provider: str, cfg: dict, event: str, client_id: str, props: dict, *, debug=False):
        built = build_request(provider, cfg, event, client_id, props, debug=debug)
        if not built:
            return None
        method, url, kwargs = built
        response = await self._http().request(method, url, **kwargs)
        return response

    def track(self, event: str, user_id: str | None, props: dict | None = None) -> None:
        if not self._configs:
            return
        client_id = self.pseudonym(user_id)
        for provider, cfg in self._configs.items():
            task = asyncio.create_task(self._safe_send(provider, cfg, event, client_id, props or {}))
            self._tasks.add(task)
            task.add_done_callback(self._tasks.discard)

    async def _safe_send(self, provider, cfg, event, client_id, props):
        try:
            response = await self.send(provider, cfg, event, client_id, props)
            if response is not None and response.status_code < 400:
                self.sent[provider] += 1
            else:
                self.failed[provider] += 1
        except (httpx.HTTPError, OSError) as error:
            self.failed[provider] += 1
            log.debug("analytics %s failed: %s", provider, error)

    async def close(self) -> None:
        if self._client:
            await self._client.aclose()
