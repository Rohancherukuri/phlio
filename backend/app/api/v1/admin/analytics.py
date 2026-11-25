"""Admin analytics across every Phlio platform.

    GET /admin/overview?days=30            KPIs, per-platform totals and daily series
    GET /admin/platforms/{platform}?days=  one platform: metric series, actions, top content
    GET /admin/traffic?hours=24            API requests per hour per platform
    GET /admin/users?q=&offset=&limit=     app users (emails masked for viewers)
    GET /admin/live/snapshot               what the live stream sends, for polling
    WS  /admin/live                        live numbers every 2 s (send {"token"} first)

Sources: the domain tables in SurrealDB (posts, rooms, messages, bookings,
payments, Foxy chats, moments, Move, Fit …), the graph's activity edges
(likes, views, purchases … across platforms) and request telemetry (Redis
when enabled). Aggregates are cached in Redis for 30 seconds.
"""

from __future__ import annotations

import asyncio
import collections
import datetime as dt
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request, WebSocket, WebSocketDisconnect

from app.api.deps import get_container
from app.api.v1.admin.auth import admin_from_token, require
from app.infrastructure.analytics_bridge import PLATFORMS
from app.middleware.analytics import metrics_for

router = APIRouter(prefix="/admin", tags=["admin"])

PRODUCT = ["social", "dm", "rooms", "pay", "book", "shop", "stream", "news", "agent"]
COLORS = {"social": "#338ced", "dm": "#e76624", "rooms": "#00a888", "pay": "#d28e05", "book": "#e24d8b",
          "shop": "#0aac23", "stream": "#9887ef", "agent": "#eb6263", "news": "#9c9c9c"}

# id, platform, label, surreal table, memory repository attribute
DOMAIN = [
    ("posts", "social", "Posts", "post", ("social_repository", "_posts")),
    ("comments", "social", "Comments", "comment", ("social_repository", "_comments_by_post")),
    ("rooms", "rooms", "Rooms created", "room", ("rooms_repository", "_rooms")),
    ("room_messages", "rooms", "Room messages", "room_message", ("rooms_repository", "_messages_by_room")),
    ("bookings", "book", "Bookings", "booking", ("book_repository", "_bookings")),
    ("payments", "pay", "Payments", "pay_transaction", ("pay_repository", "_transactions_by_user")),
    ("agent_messages", "agent", "Foxy messages", "agent_message", ("agent_repository", "_messages")),
]
# id, platform, label, graph table
GRAPH = [
    ("moments", "social", "Moments", "social_moment"),
    ("shares", "social", "Shares", "share_event"),
    ("watch_parties", "rooms", "Watch parties", "watch_party"),
    ("carts", "shop", "Cart adds", "shop_cart"),
    ("parcels", "shop", "Parcels tracked", "shop_tracking"),
    ("move", "agent", "Move activities", "phlio_activity"),
    ("fit_days", "agent", "Fit days tracked", "fitness_day"),
    ("tasks", "agent", "Timeline tasks", "timeline_task"),
]


def _when(value) -> dt.datetime | None:
    if isinstance(value, dt.datetime):
        return value if value.tzinfo else value.replace(tzinfo=dt.UTC)
    if isinstance(value, str) and value:
        try:
            parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            try:
                parsed = dt.datetime.combine(dt.date.fromisoformat(value[:10]), dt.time(12))
            except ValueError:
                return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=dt.UTC)
    if isinstance(value, dt.date):
        return dt.datetime.combine(value, dt.time(12), dt.UTC)
    return None


def _stamp(row) -> dt.datetime | None:
    get = row.get if isinstance(row, dict) else lambda k: getattr(row, k, None)
    for field in ("created_at", "started_at", "updated_at", "date"):
        when = _when(get(field))
        if when:
            return when
    return None


def _flatten(value):
    items = value.values() if isinstance(value, dict) else value
    for item in items:
        if isinstance(item, (list, tuple, set)):
            yield from item
        else:
            yield item


async def _domain_rows(c, table: str, attr: tuple[str, str], since: dt.datetime) -> list[tuple[dt.datetime, dict]]:
    """(timestamp, row) for one domain table since `since`, from SurrealDB or
    the in-memory repositories (local dev and tests)."""
    db = getattr(c.graph.store, "db", None)
    out = []
    if db is not None:
        try:
            rows = await db.rows(f"SELECT * OMIT attachments, body_html FROM {table} WHERE created_at >= $since",
                                 {"since": since})
        except Exception:  # noqa: BLE001 — a missing table is just "no data yet"
            rows = []
        for row in rows:
            when = _stamp(row)
            if when:
                out.append((when, row))
        return out
    repo = getattr(c, attr[0], None)
    store = getattr(repo, attr[1], None) if repo else None
    for item in _flatten(store or {}):
        when = _stamp(item)
        if when and when >= since:
            row = {k: getattr(item, k, None) for k in ("type", "amount_minor_units", "author_id", "user_id", "sender_id")}
            out.append((when, row))
    return out


def _dm_rows(c, since: dt.datetime) -> list[tuple[dt.datetime, dict]]:
    service = getattr(c, "messaging_service", None)
    if service is None:
        return []
    try:
        rows = service.db.execute("SELECT sender, created_at FROM messages WHERE created_at >= ?",
                                  (since.isoformat(),)).fetchall()
    except Exception:  # noqa: BLE001
        return []
    return [(w, {"user_id": r["sender"]}) for r in rows if (w := _when(r["created_at"]))]


async def _graph_rows(c, table: str, since: dt.datetime) -> list[tuple[dt.datetime, dict]]:
    out = []
    for row in await c.graph.store.rows(table):
        when = _stamp(row)
        if when and when >= since:
            out.append((when, row))
    return out


async def _edges(c, since: dt.datetime) -> list[tuple[dt.datetime, dict]]:
    """Activity edges (liked, viewed, purchased …) with their object's platform."""
    edges = [(w, e) for e in await c.graph.store.rows("activity") if (w := _when(e.get("created_at"))) and w >= since]
    ids = list({e["out"] for _, e in edges if str(e.get("out", "")).startswith("phlio_object:")})
    objects = {}
    for i in range(0, len(ids), 200):
        for obj in await c.graph.store.get_many(ids[i : i + 200]):
            objects[obj["id"]] = obj
    out = []
    for when, e in edges:
        obj = objects.get(e["out"])
        if obj:
            out.append((when, dict(e, platform=obj.get("platform"), title=obj.get("title"), owner=obj.get("owner"))))
    return out


class Window:
    def __init__(self, days: int):
        self.days = days
        self.end = dt.datetime.now(dt.UTC)
        self.start = self.end - dt.timedelta(days=days)
        self.prev = self.start - dt.timedelta(days=days)
        today = self.end.date()
        self.dates = [today - dt.timedelta(days=d) for d in range(days - 1, -1, -1)]

    def split(self, rows):
        now = [r for r in rows if r[0] >= self.start]
        return now, len(rows) - len(now)


def _pct(now: float, before: float) -> float | None:
    if before == 0:
        return None if now == 0 else 100.0
    return round((now - before) / before * 100, 1)


async def _collect(c, w: Window) -> dict[str, Any]:
    metrics: dict[str, dict] = {}
    for mid, platform, label, table, attr in DOMAIN:
        metrics[mid] = dict(platform=platform, label=label, rows=await _domain_rows(c, table, attr, w.prev))
    # A transfer is stored on both sides; count the sender's half only.
    metrics["payments"]["rows"] = [r for r in metrics["payments"]["rows"] if str(r[1].get("type", "send")).endswith("send")]
    metrics["dms"] = dict(platform="dm", label="Messages sent", rows=_dm_rows(c, w.prev))
    for mid, platform, label, table in GRAPH:
        metrics[mid] = dict(platform=platform, label=label, rows=await _graph_rows(c, table, w.prev))
    edges = await _edges(c, w.prev)
    by_platform_edges = collections.defaultdict(list)
    for row in edges:
        by_platform_edges[row[1].get("platform") or "core"].append(row)
    for platform in PRODUCT:
        if by_platform_edges.get(platform):
            metrics[f"{platform}_actions"] = dict(platform=platform, label="Engagement actions",
                                                  rows=by_platform_edges[platform])
    return {"metrics": metrics, "edges": edges}


def _series(rows, dates) -> list[int]:
    counts = collections.Counter(r[0].date() for r in rows)
    return [counts.get(d, 0) for d in dates]


async def _users(c, w: Window) -> dict[str, Any]:
    repo = c.identity_repository
    total = await repo.count_users()
    joined = await repo.signups_since(w.prev)
    now = [j for j in joined if j >= w.start]
    counts = collections.Counter(j.date() for j in now)
    return {"total": total, "new": len(now), "new_prev": len(joined) - len(now),
            "series": [counts.get(d, 0) for d in w.dates]}


async def _cached(c, name: str, build, ttl=30):
    cache_key = f"admin:{name}:{await c.graph.store.revision()}"
    hit = await c.cache.get(cache_key)
    if hit is not None:
        return hit
    value = await build()
    await c.cache.put(cache_key, value, ttl=ttl)
    return value


@router.get("/overview")
async def overview(request: Request, request_days: int = Query(30, alias="days", ge=1, le=90),
                   admin=Depends(require()), c=Depends(get_container)):
    async def build():
        w = Window(request_days)
        data = await _collect(c, w)
        users = await _users(c, w)
        metrics = data["metrics"]
        platforms = []
        all_now = all_prev = 0
        daily_total = [0] * len(w.dates)
        stacked = [{"date": d.isoformat()} for d in w.dates]
        for platform in PRODUCT:
            ms = [(mid, m) for mid, m in metrics.items() if m["platform"] == platform]
            rows = [r for _, m in ms for r in m["rows"]]
            now_rows, prev = w.split(rows)
            series = _series(now_rows, w.dates)
            for i, v in enumerate(series):
                daily_total[i] += v
                stacked[i][platform] = v
            all_now += len(now_rows)
            all_prev += prev
            platforms.append({
                "id": platform, "label": PLATFORMS[platform], "color": COLORS[platform],
                "events": len(now_rows), "change": _pct(len(now_rows), prev), "series": series,
                "metrics": [_metric(mid, m, w) for mid, m in ms],
            })
        pay_rows = w.split(metrics["payments"]["rows"])[0]
        volume = sum(int(r[1].get("amount_minor_units") or 0) for r in pay_rows) / 100
        active_days = await metrics_for(request.app).daily_active(min(request_days, 40))
        actors = {r[1].get("in") for r in data["edges"] if r[0].date() == w.end.date()}
        dau = max(active_days[-1]["active"] if active_days else 0, len(actors - {None}))
        mau_rows = {r[1].get("in") for r in data["edges"] if r[0] >= w.end - dt.timedelta(days=30)}
        verbs = collections.Counter(r[1].get("verb") for r in w.split(data["edges"])[0])
        return {
            "days": request_days,
            "generated_at": w.end.isoformat(),
            "kpis": [
                {"id": "users", "label": "Total users", "value": users["total"], "change": None,
                 "series": users["series"]},
                {"id": "new_users", "label": "New users", "value": users["new"],
                 "change": _pct(users["new"], users["new_prev"]), "series": users["series"]},
                {"id": "dau", "label": "Active today", "value": dau, "change": None,
                 "series": [d["active"] for d in active_days]},
                {"id": "events", "label": "Platform events", "value": all_now, "change": _pct(all_now, all_prev),
                 "series": daily_total},
                {"id": "volume", "label": "Pay volume", "value": volume, "format": "inr",
                 "change": None, "series": _amount_series(pay_rows, w.dates)},
                {"id": "mau", "label": "Engaged, 30 days", "value": len(mau_rows - {None}), "change": None},
            ],
            "platforms": platforms,
            "daily": [dict(s, users=u, active=a["active"] if a else 0) for s, u, a in
                      zip(stacked, users["series"], _align(active_days, w.dates))],
            "actions": [{"verb": v, "count": n} for v, n in verbs.most_common(12) if v],
        }

    return await _cached(c, f"overview:{request_days}", build)


def _align(active_days, dates):
    index = {d["date"]: d for d in active_days}
    return [index.get(d.isoformat()) for d in dates]


def _amount_series(rows, dates):
    totals = collections.Counter()
    for when, row in rows:
        totals[when.date()] += int(row.get("amount_minor_units") or 0) / 100
    return [round(totals.get(d, 0), 2) for d in dates]


def _metric(mid, m, w: Window) -> dict:
    now_rows, prev = w.split(m["rows"])
    return {"id": mid, "label": m["label"], "value": len(now_rows), "change": _pct(len(now_rows), prev)}


@router.get("/platforms/{platform}")
async def platform_detail(platform: str, days: int = Query(30, ge=1, le=90), admin=Depends(require()),
                          c=Depends(get_container)):
    if platform not in PRODUCT:
        raise HTTPException(404, "Unknown platform.")

    async def build():
        w = Window(days)
        data = await _collect(c, w)
        ms = [(mid, m) for mid, m in data["metrics"].items() if m["platform"] == platform]
        series = [{"date": d.isoformat()} for d in w.dates]
        metrics = []
        for mid, m in ms:
            now_rows, prev = w.split(m["rows"])
            for i, v in enumerate(_series(now_rows, w.dates)):
                series[i][mid] = v
            metrics.append({"id": mid, "label": m["label"], "value": len(now_rows), "change": _pct(len(now_rows), prev)})
        edges = [r for r in w.split(data["edges"])[0] if r[1].get("platform") == platform]
        verbs = collections.Counter(r[1].get("verb") for r in edges)
        top = collections.Counter((r[1].get("title") or "Untitled") for r in edges)
        actors = collections.Counter((r[1].get("in") or "").removeprefix("user:") for r in edges)
        people = {u.id: u for u in await c.identity_repository.get_many([a for a, _ in actors.most_common(8) if a])}
        hours = collections.Counter(r[0].hour for r in edges)
        return {
            "id": platform, "label": PLATFORMS[platform], "color": COLORS[platform], "days": days,
            "metrics": metrics, "series": series,
            "actions": [{"verb": v, "count": n} for v, n in verbs.most_common(10) if v],
            "top_content": [{"title": t, "count": n} for t, n in top.most_common(8)],
            "top_users": [{"id": a, "username": people[a].username, "name": people[a].full_name,
                           "avatar_url": people[a].avatar_url, "count": n}
                          for a, n in actors.most_common(8) if a in people],
            "by_hour": [{"hour": h, "count": hours.get(h, 0)} for h in range(24)],
        }

    return await _cached(c, f"platform:{platform}:{days}", build)


@router.get("/traffic")
async def traffic(request: Request, hours: int = Query(24, ge=1, le=24 * 14), admin=Depends(require())):
    rows = await metrics_for(request.app).hourly(hours)
    return {"hours": hours, "platforms": [{"id": p, "label": PLATFORMS[p]} for p in PLATFORMS], "series": rows}


def _mask(email: str | None) -> str | None:
    if not email or "@" not in email:
        return email
    name, domain = email.split("@", 1)
    return (name[:2] + "•••") + "@" + domain


@router.get("/users")
async def users(q: str = "", offset: int = Query(0, ge=0), limit: int = Query(25, ge=1, le=100),
                admin=Depends(require()), c=Depends(get_container)):
    repo = c.identity_repository
    if q.strip():
        found = await repo.search_users(q.strip(), limit=limit)
        total = len(found)
    else:
        found = await repo.list_users(offset, limit)
        total = await repo.count_users()
    full = admin["role"] in {"owner", "admin", "analyst"}
    return {
        "total": total, "offset": offset, "limit": limit,
        "items": [{
            "id": u.id, "username": u.username, "name": u.full_name,
            "email": u.email if full else _mask(u.email), "avatar_url": u.avatar_url,
            "created_at": u.created_at.isoformat() if u.created_at else None,
            "verified": u.is_verified, "creator": u.is_creator, "test": u.is_test_user, "country": u.country,
        } for u in found],
    }


async def _totals(c) -> dict:
    async def build():
        w = Window(1)
        data = await _collect(c, w)
        today = sum(len(w.split(m["rows"])[0]) for m in data["metrics"].values())
        return {"users": await c.identity_repository.count_users(), "events_24h": today}

    return await _cached(c, "totals", build, ttl=15)


async def snapshot(c, metrics) -> dict:
    live = await metrics.live()
    live["totals"] = await _totals(c)
    return {"type": "live", **live}


@router.get("/live/snapshot")
async def live_snapshot(request: Request, admin=Depends(require()), c=Depends(get_container)):
    return await snapshot(c, metrics_for(request.app))


@router.websocket("/live")
async def live(ws: WebSocket):
    """Streams live numbers. The first message must be {"token": "<admin token>"}
    (kept out of the URL so it never lands in access logs)."""
    await ws.accept()
    app = ws.app
    c = app.state.container
    try:
        hello = await asyncio.wait_for(ws.receive_json(), timeout=10)
        await admin_from_token(c, str((hello or {}).get("token", "")))
    except (asyncio.TimeoutError, HTTPException, ValueError, KeyError, TypeError):
        await ws.close(code=4401)
        return
    except WebSocketDisconnect:
        return
    metrics = metrics_for(app)
    interval = 2.0
    try:
        while True:
            await ws.send_json(await snapshot(c, metrics))
            try:
                message = await asyncio.wait_for(ws.receive_json(), timeout=interval)
                if isinstance(message, dict) and message.get("interval"):
                    interval = min(30.0, max(1.0, float(message["interval"])))
            except asyncio.TimeoutError:
                pass
    except (WebSocketDisconnect, RuntimeError):
        return
