"""
Audius music for Phlio Stream (https://docs.audius.co/api).

The app reaches Audius through these endpoints, not directly, so that:

* **The credentials stay on the server.** Audius issues an API key (public,
  identifies the app) and a bearer token (secret: never ship it in an APK)
  at https://api.audius.co/plans. Both are read from ``AUDIUS_API_KEY`` /
  ``AUDIUS_BEARER_TOKEN``; without them requests go out anonymously with
  ``app_name`` only, which Audius rate-limits more tightly.
* **Responses are cached.** Charts change slowly, and every user asking for
  "trending this week" would otherwise each spend from the plan's quota
  (free plan: 10 req/s, 500k/month). A small in-process TTL cache answers
  repeats instantly.
* **Only catalogue reads are possible.** Paths are matched against an
  allowlist and only known query parameters are forwarded, so the endpoint
  can't be used as an open proxy into the Audius API.

Endpoints (all under ``/api/v1/music/audius``):

``GET /{audius path}``
    A read from the allowlist below (signed-in users). The Audius JSON
    envelope ``{"data": ...}`` is returned unchanged.
``GET /stream/{track_id}``
    ``307`` redirect to the track's audio on an Audius content node. Public,
    because the audio player can't attach the session token; rate-limited
    per client IP. The resolved URL is cached for a few minutes.
"""

from __future__ import annotations

import logging
import re
import time
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse, RedirectResponse

from app.api.deps import get_container, get_current_user
from app.infrastructure.security.guard import client_ip

log = logging.getLogger("phlio.audius")
router = APIRouter(prefix="/music/audius", tags=["music"])

_ID = r"[A-Za-z0-9]{1,32}"
#: (path pattern, cache seconds). Anything else is a 404.
_ALLOWED: list[tuple[re.Pattern[str], int]] = [
    (re.compile(r"tracks/trending(/underground)?"), 600),
    (re.compile(r"tracks/search"), 120),
    (re.compile(rf"tracks/{_ID}"), 600),
    (re.compile(r"users/search"), 120),
    (re.compile(rf"users/{_ID}"), 600),
    (re.compile(rf"users/{_ID}/(tracks|related)"), 600),
    (re.compile(r"playlists/trending"), 600),
    (re.compile(rf"playlists/{_ID}(/tracks)?"), 600),
]
#: Query parameters passed through to Audius (values are length-capped).
_PARAMS = {"time", "genre", "limit", "offset", "query", "sort", "sort_method", "sort_direction"}
_TRACK_ID = re.compile(_ID)

_CACHE_MAX = 500
_STREAM_TTL = 300  # content-node URLs are signed and expire; keep them briefly


class _TTLCache:
    """Small LRU-ish cache: key -> (expires_at, value)."""

    def __init__(self, size: int) -> None:
        self.size = size
        self.items: dict[str, tuple[float, Any]] = {}

    def get(self, key: str) -> Any | None:
        hit = self.items.get(key)
        if hit is None:
            return None
        if hit[0] < time.monotonic():
            self.items.pop(key, None)
            return None
        return hit[1]

    def put(self, key: str, value: Any, ttl: float) -> None:
        if len(self.items) >= self.size:
            now = time.monotonic()
            self.items = {k: v for k, v in self.items.items() if v[0] > now}
            while len(self.items) >= self.size:
                self.items.pop(next(iter(self.items)))
        self.items[key] = (time.monotonic() + ttl, value)


_responses = _TTLCache(_CACHE_MAX)
_streams = _TTLCache(_CACHE_MAX)
_http: httpx.AsyncClient | None = None


def _client() -> httpx.AsyncClient:
    """One shared HTTP client (connection reuse to Audius)."""
    global _http
    if _http is None or _http.is_closed:
        _http = httpx.AsyncClient(timeout=httpx.Timeout(15, connect=8),
                                  headers={"User-Agent": "Phlio/1.0 (+https://phlio.app)"})
    return _http


def _auth(settings) -> tuple[dict[str, str], dict[str, str]]:
    """(headers, query) identifying Phlio to Audius."""
    headers: dict[str, str] = {}
    query = {"app_name": settings.audius_app_name}
    if settings.audius_bearer_token:
        headers["Authorization"] = f"Bearer {settings.audius_bearer_token}"
    if settings.audius_api_key:
        query["api_key"] = settings.audius_api_key
    return headers, query


def _hosts(settings) -> list[str]:
    return [h.rstrip("/") for h in (settings.audius_api_url, settings.audius_fallback_url) if h]


@router.get("/stream/{track_id}")
async def stream(track_id: str, request: Request, c=Depends(get_container)):
    """Redirects the audio player to the track's audio file."""
    if not _TRACK_ID.fullmatch(track_id):
        raise HTTPException(404, "Unknown track.")
    await c.cache.rate_limit(client_ip(request) or "?", "audius-stream", 240)
    cached = _streams.get(track_id)
    if cached:
        return RedirectResponse(cached, status_code=307)
    headers, query = _auth(c.settings)
    last_error = "unavailable"
    for host in _hosts(c.settings):
        try:
            res = await _client().get(f"{host}/tracks/{track_id}/stream", headers=headers,
                                      params={**query, "no_redirect": "true"}, follow_redirects=False)
        except httpx.HTTPError as exc:
            last_error = type(exc).__name__
            continue
        target: str | None = None
        if res.status_code in (301, 302, 303, 307, 308):
            target = res.headers.get("location")
        elif res.status_code == 200 and "json" in res.headers.get("content-type", ""):
            data = res.json().get("data")
            target = data if isinstance(data, str) else None
        elif res.status_code in (403, 404):
            raise HTTPException(404, "This track can't be streamed.")
        else:
            last_error = f"HTTP {res.status_code}"
        if target and target.startswith("https://"):
            _streams.put(track_id, target, _STREAM_TTL)
            return RedirectResponse(target, status_code=307)
    log.warning("audius.stream_failed track=%s reason=%s", track_id, last_error)
    raise HTTPException(502, "Audius is not reachable right now.")


async def audius_get(settings, path: str, params: dict[str, str] | None = None, ttl: float = 600) -> Any:
    """One cached Audius read (``{"data": ...}`` body). Also used by similarity search.

    Raises HTTPException: 404 when Audius has no such item, 503/502 when
    Audius is busy, rejects the credentials, or can't be reached.
    """
    params = {k: str(v)[:200] for k, v in sorted((params or {}).items())}
    key = path + "?" + "&".join(f"{k}={v}" for k, v in params.items())
    cached = _responses.get(key)
    if cached is not None:
        return cached
    headers, query = _auth(settings)
    last: str = "unavailable"
    for host in _hosts(settings):
        try:
            res = await _client().get(f"{host}/{path}", headers=headers, params={**query, **params})
        except httpx.HTTPError as exc:
            last = type(exc).__name__
            continue
        if res.status_code == 404:
            raise HTTPException(404, "Not found on Audius.")
        if res.status_code == 429:
            raise HTTPException(503, "Audius is busy. Try again in a moment.", headers={"Retry-After": "10"})
        if res.status_code in (401, 403):
            log.error("audius.auth_rejected status=%s: check AUDIUS_API_KEY / AUDIUS_BEARER_TOKEN", res.status_code)
            raise HTTPException(503, "Phlio Stream can't reach Audius right now.")
        if res.status_code >= 500:
            last = f"HTTP {res.status_code}"
            continue
        try:
            body = res.json()
        except ValueError:
            last = "bad JSON"
            continue
        _responses.put(key, body, ttl)
        return body
    log.warning("audius.read_failed path=%s reason=%s", path, last)
    raise HTTPException(502, "Audius is not reachable right now.")


@router.get("/{path:path}")
async def read(path: str, request: Request, user=Depends(get_current_user), c=Depends(get_container)):
    """A cached, allowlisted Audius catalogue read."""
    path = path.strip("/")
    ttl = next((ttl for pattern, ttl in _ALLOWED if pattern.fullmatch(path)), None)
    if ttl is None:
        raise HTTPException(404, "Not found.")
    params = {k: v for k, v in request.query_params.items() if k in _PARAMS}
    key = path + "?" + "&".join(f"{k}={v[:200]}" for k, v in sorted(params.items()))
    body, state = _responses.get(key), "hit"
    if body is None:
        await c.cache.rate_limit(user.id, "audius", 120)
        body, state = await audius_get(c.settings, path, params, ttl), "miss"
    return JSONResponse(body, headers={"X-Phlio-Cache": state, "Cache-Control": "private, max-age=60"})
