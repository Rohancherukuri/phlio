"""
Anime for Phlio Stream, from AniList (https://anilist.co, GraphQL API at
https://graphql.anilist.co, no key needed).

AniList is a catalogue, not a video host: it provides titles, artwork,
synopses, scores, airing schedules, **official trailers** (YouTube /
Dailymotion) and **links to the official streaming services** that carry a
show (Crunchyroll, Netflix, official YouTube channels such as Muse Asia or
Ani-One, ...), including per-episode links for some shows. Phlio shows the
catalogue and trailers, and sends viewers to those official services to
watch: episodes are never re-hosted or scraped, which keeps the app on the
right side of copyright and of AniList's terms.

Why a backend proxy instead of calling AniList from the app:

* **Rate limits.** AniList allows roughly 30-90 requests per minute per IP.
  Charts are the same for everyone, so one cached copy serves all users
  (lists 30 min, details 6 h, search 10 min) and a 429 falls back to the last
  good copy instead of an error.
* **Fixed queries.** The app can only ask for the views below, never send
  arbitrary GraphQL, and adult titles are always excluded.
* **A stable, small JSON shape** for the app (``_media``), independent of
  AniList's schema.

Endpoints (signed-in users), under ``/api/v1/stream/anime``:

``GET /lists/{name}``   ``trending`` | ``season`` | ``popular`` | ``top`` | ``upcoming``
                        (query: ``page``, ``genre``)
``GET /search?q=``      title search
``GET /genres``         AniList's genre list
``GET /{id}``           full details: trailer, where to watch, episodes, recommendations
"""

from __future__ import annotations

import datetime as dt
import html
import logging
import re
import time
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query

from app.api.deps import get_container, get_current_user

log = logging.getLogger("phlio.anime")
router = APIRouter(prefix="/stream/anime", tags=["stream"])

ANILIST_URL = "https://graphql.anilist.co"
LIST_TTL, DETAIL_TTL, SEARCH_TTL = 30 * 60, 6 * 3600, 10 * 60

_CARD = """
  id idMal format status episodes duration averageScore popularity season seasonYear
  title { romaji english native }
  coverImage { extraLarge large color }
  bannerImage genres
  nextAiringEpisode { episode airingAt }
"""

_LIST_QUERY = """
query ($page: Int, $sort: [MediaSort], $season: MediaSeason, $seasonYear: Int,
       $status: MediaStatus, $genre: String, $search: String) {
  Page(page: $page, perPage: 24) {
    pageInfo { hasNextPage }
    media(type: ANIME, isAdult: false, sort: $sort, season: $season, seasonYear: $seasonYear,
          status: $status, genre: $genre, search: $search) { %s }
  }
}""" % _CARD

_DETAIL_QUERY = """
query ($id: Int) {
  Media(id: $id, type: ANIME) {
    %s
    isAdult
    description(asHtml: false)
    startDate { year month day }
    endDate { year month day }
    source
    studios(isMain: true) { nodes { name } }
    trailer { id site thumbnail }
    externalLinks { site url type language color icon isDisabled }
    streamingEpisodes { title thumbnail url site }
    recommendations(sort: [RATING_DESC], perPage: 10) {
      nodes { mediaRecommendation { %s isAdult } }
    }
  }
}""" % (_CARD, _CARD)

_GENRES_QUERY = "query { GenreCollection }"

_LISTS = {
    "trending": {"sort": ["TRENDING_DESC", "POPULARITY_DESC"]},
    "popular": {"sort": ["POPULARITY_DESC"]},
    "top": {"sort": ["SCORE_DESC"]},
    "upcoming": {"sort": ["POPULARITY_DESC"], "status": "NOT_YET_RELEASED"},
    "season": {"sort": ["POPULARITY_DESC"]},  # season/year filled in per request
}
_GENRE = re.compile(r"[A-Za-z\- ]{2,24}")
_TAGS = re.compile(r"<[^>]+>")


class _Cache:
    """Key -> (stored_at, value). Expired entries are kept as a stale fallback."""

    def __init__(self, size: int = 400) -> None:
        self.size = size
        self.items: dict[str, tuple[float, Any]] = {}

    def get(self, key: str, ttl: float, stale_ok: bool = False) -> Any | None:
        hit = self.items.get(key)
        if hit is None or (not stale_ok and time.monotonic() - hit[0] > ttl):
            return None
        return hit[1]

    def put(self, key: str, value: Any) -> None:
        self.items.pop(key, None)
        while len(self.items) >= self.size:
            self.items.pop(next(iter(self.items)))
        self.items[key] = (time.monotonic(), value)


_cache = _Cache()
_http: httpx.AsyncClient | None = None
_blocked_until = 0.0  # AniList asked us to back off (429 Retry-After)


def _client() -> httpx.AsyncClient:
    global _http
    if _http is None or _http.is_closed:
        _http = httpx.AsyncClient(timeout=httpx.Timeout(15, connect=8),
                                  headers={"Content-Type": "application/json", "Accept": "application/json",
                                           "User-Agent": "Phlio/1.0 (+https://phlio.app)"})
    return _http


async def _query(key: str, ttl: float, query: str, variables: dict[str, Any],
                 url: str = ANILIST_URL) -> dict[str, Any]:
    """Runs one AniList query through the cache; stale data beats an error."""
    global _blocked_until
    fresh = _cache.get(key, ttl)
    if fresh is not None:
        return fresh
    if time.monotonic() >= _blocked_until:
        try:
            res = await _client().post(url, json={"query": query, "variables": variables})
            if res.status_code == 429:
                _blocked_until = time.monotonic() + float(res.headers.get("retry-after", "60") or 60)
                log.warning("anilist.rate_limited retry_after=%s", res.headers.get("retry-after"))
            elif res.status_code == 404:
                raise HTTPException(404, "Anime not found.")
            else:
                res.raise_for_status()
                body = res.json()
                if body.get("errors") and not body.get("data"):
                    raise HTTPException(404 if "Not Found" in str(body["errors"]) else 502,
                                        "Anime not found." if "Not Found" in str(body["errors"])
                                        else "AniList could not answer that.")
                data = body.get("data") or {}
                _cache.put(key, data)
                return data
        except httpx.HTTPError as exc:
            log.warning("anilist.request_failed %s", type(exc).__name__)
    stale = _cache.get(key, ttl, stale_ok=True)
    if stale is not None:
        return stale
    raise HTTPException(503, "Anime listings are busy right now. Try again in a minute.",
                        headers={"Retry-After": "30"})


def _season(today: dt.date | None = None) -> tuple[str, int]:
    """AniList season for a date: Winter = Jan-Mar, Spring, Summer, Fall = Oct-Dec."""
    today = today or dt.date.today()
    return ("WINTER", "SPRING", "SUMMER", "FALL")[(today.month - 1) // 3], today.year


def _text(raw: str | None) -> str:
    """AniList synopsis as plain text (it still carries <br>/<i> tags)."""
    if not raw:
        return ""
    text = _TAGS.sub("", raw.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n"))
    return re.sub(r"\n{3,}", "\n\n", html.unescape(text)).strip()


def _trailer(t: dict[str, Any] | None) -> dict[str, Any] | None:
    if not t or not t.get("id"):
        return None
    site, vid = (t.get("site") or "").lower(), t["id"]
    if site == "youtube":
        url = f"https://www.youtube.com/watch?v={vid}"
        thumb = t.get("thumbnail") or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
    elif site == "dailymotion":
        url, thumb = f"https://www.dailymotion.com/video/{vid}", t.get("thumbnail")
    else:
        return None
    return {"site": t.get("site"), "id": vid, "url": url, "thumbnail": thumb}


def _https(url: Any) -> str | None:
    return url if isinstance(url, str) and url.startswith("https://") else None


def _media(m: dict[str, Any]) -> dict[str, Any]:
    """The compact shape the app reads (see features/stream/anime/anime_api.dart)."""
    title = m.get("title") or {}
    cover = m.get("coverImage") or {}
    airing = m.get("nextAiringEpisode")
    return {
        "id": m.get("id"),
        "title": title.get("english") or title.get("romaji") or "Untitled",
        "romaji": title.get("romaji"),
        "native": title.get("native"),
        "cover": cover.get("extraLarge") or cover.get("large"),
        "color": cover.get("color"),
        "banner": m.get("bannerImage"),
        "format": m.get("format"),
        "status": m.get("status"),
        "episodes": m.get("episodes"),
        "duration": m.get("duration"),
        "score": m.get("averageScore"),
        "popularity": m.get("popularity"),
        "season": m.get("season"),
        "year": m.get("seasonYear"),
        "genres": m.get("genres") or [],
        "next_episode": {"episode": airing["episode"], "airing_at": airing["airingAt"]} if airing else None,
        "anilist_url": f"https://anilist.co/anime/{m.get('id')}",
    }


def _details(m: dict[str, Any]) -> dict[str, Any]:
    out = _media(m)
    links = [
        {"site": link.get("site"), "url": link["url"], "language": link.get("language"),
         "color": link.get("color"), "icon": _https(link.get("icon"))}
        for link in m.get("externalLinks") or []
        if link.get("type") == "STREAMING" and not link.get("isDisabled") and _https(link.get("url"))
    ]
    episodes = [
        {"title": e.get("title"), "thumbnail": _https(e.get("thumbnail")), "url": e["url"], "site": e.get("site")}
        for e in m.get("streamingEpisodes") or [] if _https(e.get("url"))
    ]
    recs = [
        _media(node["mediaRecommendation"])
        for node in ((m.get("recommendations") or {}).get("nodes") or [])
        if node.get("mediaRecommendation") and not node["mediaRecommendation"].get("isAdult")
    ]
    start = m.get("startDate") or {}
    out.update(
        description=_text(m.get("description")),
        source=m.get("source"),
        studios=[n["name"] for n in ((m.get("studios") or {}).get("nodes") or []) if n.get("name")],
        start_date=(f"{start['year']:04d}-{start.get('month') or 1:02d}-{start.get('day') or 1:02d}"
                    if start.get("year") else None),
        trailer=_trailer(m.get("trailer")),
        where_to_watch=links,
        episodes_list=episodes,
        recommendations=recs,
    )
    return out


@router.get("/lists/{name}")
async def anime_list(name: str, page: int = Query(1, ge=1, le=20), genre: str | None = None,
                     user=Depends(get_current_user), c=Depends(get_container)):
    """A chart: trending, this season, popular, top rated or upcoming."""
    if name not in _LISTS:
        raise HTTPException(404, "Unknown list.")
    if genre is not None and not _GENRE.fullmatch(genre):
        raise HTTPException(422, "Unknown genre.")
    variables: dict[str, Any] = {**_LISTS[name], "page": page}
    if name == "season":
        variables["season"], variables["seasonYear"] = _season()
    if genre:
        variables["genre"] = genre
    key = f"list:{name}:{page}:{genre or ''}:{variables.get('seasonYear', '')}{variables.get('season', '')}"
    data = await _query(key, LIST_TTL, _LIST_QUERY, variables, c.settings.anilist_endpoint)
    page_data = data.get("Page") or {}
    return {
        "items": [_media(m) for m in page_data.get("media") or []],
        "has_more": bool((page_data.get("pageInfo") or {}).get("hasNextPage")),
        "season": f"{variables['season'].title()} {variables['seasonYear']}" if name == "season" else None,
    }


@router.get("/search")
async def anime_search(q: str = Query(min_length=2, max_length=80), page: int = Query(1, ge=1, le=10),
                       user=Depends(get_current_user), c=Depends(get_container)):
    """Title search (English, romaji or native titles)."""
    await c.cache.rate_limit(user.id, "anime-search", 60)
    query = " ".join(q.split())
    data = await _query(f"search:{query.lower()}:{page}", SEARCH_TTL, _LIST_QUERY,
                        {"search": query, "page": page, "sort": ["SEARCH_MATCH", "POPULARITY_DESC"]},
                        c.settings.anilist_endpoint)
    page_data = data.get("Page") or {}
    return {"items": [_media(m) for m in page_data.get("media") or []],
            "has_more": bool((page_data.get("pageInfo") or {}).get("hasNextPage"))}


@router.get("/genres")
async def anime_genres(user=Depends(get_current_user), c=Depends(get_container)):
    """Genres AniList uses (Hentai is never offered)."""
    data = await _query("genres", DETAIL_TTL, _GENRES_QUERY, {}, c.settings.anilist_endpoint)
    return {"genres": [g for g in data.get("GenreCollection") or [] if g != "Hentai"]}


@router.get("/{anime_id}")
async def anime_details(anime_id: int, user=Depends(get_current_user), c=Depends(get_container)):
    """Everything for the detail page: trailer, where to watch, episodes, recommendations."""
    if not 0 < anime_id < 10_000_000:
        raise HTTPException(404, "Anime not found.")
    data = await _query(f"media:{anime_id}", DETAIL_TTL, _DETAIL_QUERY, {"id": anime_id},
                        c.settings.anilist_endpoint)
    media = data.get("Media")
    if not media or media.get("isAdult"):
        raise HTTPException(404, "Anime not found.")
    return _details(media)
