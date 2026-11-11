"""
Lyrics lookups from LRCLIB (https://lrclib.net, free, no key).

Used only as input to similarity (see ``similarity.py``) and for one-line
snippets explaining a match. Full lyrics are never re-served by these
endpoints. Results, including "not found", are cached in memory so repeated
similarity requests don't hit LRCLIB again.
"""

from __future__ import annotations

import asyncio
import logging
import re
import time
from typing import Any

import httpx

log = logging.getLogger("phlio.lyrics")

_TTL_FOUND, _TTL_MISSING = 7 * 86400, 86400
_cache: dict[str, tuple[float, str | None]] = {}
_CACHE_MAX = 5000
_http: httpx.AsyncClient | None = None
_sem = asyncio.Semaphore(6)  # be gentle with a free community service


def _client(base: str) -> httpx.AsyncClient:
    global _http
    if _http is None or _http.is_closed:
        _http = httpx.AsyncClient(base_url=base.rstrip("/"), timeout=httpx.Timeout(6, connect=4),
                                  headers={"User-Agent": "Phlio/1.0 (https://phlio.app; Phlio Stream)"})
    return _http


def _norm(text: str) -> str:
    """Title/artist normalised for matching: no brackets, 'feat.', punctuation or case."""
    text = re.sub(r"\(.*?\)|\[.*?\]", " ", text.lower())
    text = re.split(r"\s+(?:feat\.?|ft\.?|featuring)\s+", text)[0]
    return " ".join(re.sub(r"[^\w\s]", " ", text).split())


def same_song(title_a: str, artist_a: str, title_b: str, artist_b: str) -> bool:
    """Loose match of two (title, artist) pairs."""
    ta, tb, aa, ab = _norm(title_a), _norm(title_b), _norm(artist_a), _norm(artist_b)
    return bool(ta and tb and (ta == tb or ta in tb or tb in ta)
                and aa and ab and (aa == ab or aa in ab or ab in aa))


def _remember(key: str, lyrics: str | None) -> None:
    if len(_cache) >= _CACHE_MAX:
        for k in list(_cache)[: _CACHE_MAX // 10]:
            _cache.pop(k, None)
    _cache[key] = (time.monotonic(), lyrics)


async def lyrics_for(base: str, title: str, artist: str, duration: int | None = None) -> str | None:
    """Plain lyrics for a song, or None (unknown, instrumental or LRCLIB down)."""
    key = f"{_norm(title)}|{_norm(artist)}"
    hit = _cache.get(key)
    if hit and time.monotonic() - hit[0] < (_TTL_FOUND if hit[1] else _TTL_MISSING):
        return hit[1]
    params: dict[str, Any] = {"track_name": title, "artist_name": artist}
    if duration:
        params["duration"] = int(duration)
    lyrics: str | None = None
    try:
        async with _sem:
            res = await _client(base).get("/api/get", params=params)
            if res.status_code == 404:
                res = await _client(base).get("/api/search", params={"track_name": title, "artist_name": artist})
            if res.status_code == 200:
                body = res.json()
                rows = body if isinstance(body, list) else [body]
                for row in rows:
                    if (row.get("plainLyrics") and not row.get("instrumental")
                            and same_song(title, artist, row.get("trackName", ""), row.get("artistName", ""))):
                        lyrics = row["plainLyrics"]
                        break
    except (httpx.HTTPError, ValueError) as exc:
        log.info("lyrics.lookup_failed %s", type(exc).__name__)
        return None  # don't cache transient failures
    _remember(key, lyrics)
    return lyrics


async def search_lyrics(base: str, text: str) -> list[dict[str, Any]]:
    """LRCLIB full-text search over lyrics (and titles) for ``text``."""
    try:
        async with _sem:
            res = await _client(base).get("/api/search", params={"q": text})
        res.raise_for_status()
        rows = res.json()
    except (httpx.HTTPError, ValueError) as exc:
        log.warning("lyrics.search_failed %s", type(exc).__name__)
        return []
    out = []
    for row in rows if isinstance(rows, list) else []:
        if row.get("plainLyrics") and not row.get("instrumental"):
            _remember(f"{_norm(row.get('trackName', ''))}|{_norm(row.get('artistName', ''))}", row["plainLyrics"])
            out.append(row)
    return out
