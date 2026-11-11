"""
"More like this" for Phlio Stream: similar songs (by lyrics and style),
search by lyrics, and similar movies / series / anime (by story).

Modelled on Searchly (github.com/AlbertSuarez/searchly): lyrics become
vectors and the nearest neighbours are the answer. Differences, and why:

* Searchly needs a pre-built index of ~150k songs scraped from AZLyrics.
  Phlio doesn't scrape lyrics sites; it builds a small index per request from
  playable Audius candidates (same genre charts, related artists, matching
  moods/tags) and fetches their lyrics from LRCLIB (open, community-run).
* Most independent Audius tracks have no published lyrics, so each song is
  also described by its style (genre, mood, tags, description). The score is
  ``0.6 * lyrics + 0.4 * style`` when both songs have lyrics, otherwise
  ``0.85 * style``, so lyric matches rank first and every result is playable.
* Each result says why it matched (shared words / tags), and for lyric
  matches a one-line snippet: lyrics themselves are not re-published here.

Endpoints (signed-in users), under ``/api/v1/stream/similar``:

``GET /songs?audius_id=`` or ``?title=&artist=``  similar playable songs
``GET /songs/by-lyrics?q=``                        songs whose lyrics match a
                                                   phrase or theme, with Audius
                                                   matches when available
``GET /titles/{ref}``                              movies/series/anime like this one
``GET /titles?q=``                                 titles whose story matches a description
"""

from __future__ import annotations

import asyncio
from collections import Counter
import logging
import time
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from app.api.deps import get_container, get_current_user
from app.api.v1.audius import audius_get
from app.domains.graph.service import key
from app.domains.stream.lyrics import lyrics_for, same_song, search_lyrics
from app.domains.stream.similarity import Document, TfidfIndex, best_line, tokens

log = logging.getLogger("phlio.similar")
router = APIRouter(prefix="/stream/similar", tags=["stream"])

_SONG_TTL = 30 * 60
_song_results: dict[str, tuple[float, dict[str, Any]]] = {}
_title_index: dict[str, Any] = {}


def _remember(store: dict, key_: str, value: Any, limit: int = 300) -> None:
    if len(store) >= limit:
        store.pop(next(iter(store)))
    store[key_] = (time.monotonic(), value)


# -- songs ---------------------------------------------------------------------------------

def _style_doc(track: dict[str, Any]) -> Document:
    """A song's style: genre and mood count most, then tags, title, description."""
    tags = [t.strip() for t in (track.get("tags") or "").split(",") if t.strip()]
    user = track.get("user") or {}
    return (Document(str(track.get("id")))
            .add_tags("genre", [track.get("genre")], 3)
            .add_tags("mood", [track.get("mood")], 3)
            .add_tags("tag", tags, 1.5)
            .add_text(" ".join(tags), 1)
            .add_text(track.get("title"), 1)
            .add_text(track.get("description"), 0.5)
            .add_tags("artist", [user.get("id")], 1))


def _playable(track: Any) -> bool:
    return isinstance(track, dict) and track.get("id") and track.get("is_streamable") is not False \
        and not track.get("is_delete") and not track.get("is_unlisted")


async def _data(settings, path: str, params: dict | None = None, ttl: float = 600) -> list[dict]:
    """Audius list endpoint -> list of track dicts; [] on any failure (best effort)."""
    try:
        body = await audius_get(settings, path, params, ttl)
    except HTTPException:
        return []
    data = body.get("data") if isinstance(body, dict) else None
    return [t for t in data if _playable(t)] if isinstance(data, list) else []


async def _candidates(settings, seed: dict[str, Any], seed_lyrics: str | None) -> list[dict]:
    """Playable songs worth comparing with ``seed``: same-genre charts, related
    artists' popular tracks, and searches for its mood, tags and lyric themes."""
    genre = seed.get("genre") or ""
    jobs = [
        _data(settings, "tracks/trending", {"time": "week", **({"genre": genre} if genre else {})}),
        _data(settings, "tracks/trending", {"time": "month", **({"genre": genre} if genre else {})}),
    ]
    queries = [seed.get("mood")] + [t.strip() for t in (seed.get("tags") or "").split(",")][:2]
    if seed_lyrics:
        top = [w for w, _ in Counter(tokens(seed_lyrics)).most_common(2)]
        queries += top
    for q in dict.fromkeys(q for q in queries if q):
        jobs.append(_data(settings, "tracks/search", {"query": q, "limit": "20"}, 1800))
    artist = (seed.get("user") or {}).get("id")
    related_ids: list[str] = []
    if artist:
        try:
            body = await audius_get(settings, f"users/{artist}/related", {"limit": "5"})
            related_ids = [u["id"] for u in (body.get("data") or []) if isinstance(u, dict) and u.get("id")][:5]
        except HTTPException:
            pass
    for rid in related_ids:
        jobs.append(_data(settings, f"users/{rid}/tracks", {"sort": "plays", "limit": "8"}))
    seen: dict[str, dict] = {}
    seed_user = (seed.get("user") or {}).get("name", "")
    for batch in await asyncio.gather(*jobs):
        for t in batch:
            tid = str(t["id"])
            if tid == str(seed.get("id")) or tid in seen:
                continue
            if same_song(seed.get("title", ""), seed_user, t.get("title", ""), (t.get("user") or {}).get("name", "")):
                continue
            seen[tid] = t
    return list(seen.values())


@router.get("/songs")
async def similar_songs(audius_id: str | None = Query(None, pattern=r"^[A-Za-z0-9]{1,32}$"),
                        title: str | None = Query(None, max_length=200),
                        artist: str | None = Query(None, max_length=200),
                        genre: str | None = Query(None, max_length=40),
                        limit: int = Query(20, ge=1, le=40),
                        user=Depends(get_current_user), c=Depends(get_container)):
    """Playable songs similar to one song, by lyrics (when published) and style."""
    if not audius_id and not (title and artist):
        raise HTTPException(422, "Give audius_id, or title and artist.")
    cache_key = f"{audius_id or ''}|{(title or '').lower()}|{(artist or '').lower()}|{genre or ''}"
    hit = _song_results.get(cache_key)
    if hit and time.monotonic() - hit[0] < _SONG_TTL:
        return {**hit[1], "items": hit[1]["items"][:limit]}
    await c.cache.rate_limit(user.id, "similar-songs", 20)

    if audius_id:
        body = await audius_get(c.settings, f"tracks/{audius_id}")
        seed = body.get("data") if isinstance(body, dict) else None
        if not isinstance(seed, dict):
            raise HTTPException(404, "Song not found.")
    else:
        seed = {"id": "", "title": title, "user": {"name": artist}, "genre": genre or ""}
    seed_artist = (seed.get("user") or {}).get("name") or artist or ""
    seed_lyrics = await lyrics_for(c.settings.lrclib_url, seed.get("title") or "", seed_artist, seed.get("duration"))
    pool = await _candidates(c.settings, seed, seed_lyrics)
    if not pool:
        return {"seed": {"title": seed.get("title"), "artist": seed_artist, "has_lyrics": bool(seed_lyrics)},
                "items": []}

    seed_doc = _style_doc(seed)
    style_index = TfidfIndex([_style_doc(t) for t in pool])
    style = {d: (s, why) for d, s, why in style_index.nearest(seed_doc, k=len(pool), min_score=0.0)}

    lyric_scores: dict[str, tuple[float, list[str]]] = {}
    lyrics: dict[str, str] = {}
    if seed_lyrics:
        # Lyrics for the most promising candidates only (a free API, and time).
        shortlist = sorted(pool, key=lambda t: -style.get(str(t["id"]), (0, []))[0])[:40]

        async def fetch(t: dict) -> None:
            text = await lyrics_for(c.settings.lrclib_url, t.get("title") or "",
                                    (t.get("user") or {}).get("name") or "", t.get("duration"))
            if text:
                lyrics[str(t["id"])] = text

        try:
            await asyncio.wait_for(asyncio.gather(*(fetch(t) for t in shortlist)), timeout=8)
        except asyncio.TimeoutError:
            log.info("similar.lyrics_timeout fetched=%d", len(lyrics))
        if lyrics:
            lyric_index = TfidfIndex([Document("__seed__").add_text(seed_lyrics),
                                      *(Document(tid).add_text(text) for tid, text in lyrics.items())])
            lyric_scores = {d: (s, why) for d, s, why in lyric_index.nearest("__seed__", k=len(lyrics), min_score=0.0)}

    seed_terms = tokens(seed_lyrics) if seed_lyrics else []
    ranked = []
    for t in pool:
        tid = str(t["id"])
        s_score, s_why = style.get(tid, (0.0, []))
        if tid in lyric_scores:
            l_score, l_why = lyric_scores[tid]
            score, why, match = 0.6 * l_score + 0.4 * s_score, l_why, "lyrics"
        else:
            score, why, match = 0.85 * s_score, s_why, "style"
        if score <= 0:
            continue
        ranked.append((score, tid, why, match, t))
    ranked.sort(key=lambda r: r[0], reverse=True)
    result = {
        "seed": {"title": seed.get("title"), "artist": seed_artist, "has_lyrics": bool(seed_lyrics)},
        "items": [
            {"track": t, "similarity": round(score, 4), "because": why, "match": match,
             "snippet": best_line(lyrics.get(tid), why) if match == "lyrics" else None}
            for score, tid, why, match, t in ranked[:40]
        ],
    }
    _remember(_song_results, cache_key, result)
    return {**result, "items": result["items"][:limit]}


@router.get("/songs/by-lyrics")
async def songs_by_lyrics(q: str = Query(min_length=3, max_length=200), limit: int = Query(15, ge=1, le=20),
                          user=Depends(get_current_user), c=Depends(get_container)):
    """Songs whose lyrics match a phrase or theme ("rain on the city at midnight")."""
    if not tokens(q):
        raise HTTPException(422, "Describe the lyrics with a few meaningful words.")
    await c.cache.rate_limit(user.id, "lyrics-search", 20)
    rows = await search_lyrics(c.settings.lrclib_url, q)
    if not rows:
        return {"items": []}
    by_id = {str(r["id"]): r for r in rows if r.get("id") is not None}
    index = TfidfIndex(Document(i).add_text(r["plainLyrics"]).add_text(r.get("trackName"), 2) for i, r in by_id.items())
    ranked = index.nearest(Document("q").add_text(q), k=limit, min_score=0.0)
    sem = asyncio.Semaphore(4)

    async def on_audius(row: dict) -> dict | None:
        async with sem:
            matches = await _data(c.settings, "tracks/search",
                                  {"query": f"{row.get('artistName', '')} {row.get('trackName', '')}"[:120], "limit": "5"},
                                  3600)
        return next((t for t in matches if same_song(row.get("trackName", ""), row.get("artistName", ""),
                                                      t.get("title", ""), (t.get("user") or {}).get("name", ""))), None)

    rows_ranked = [(by_id[i], s, why) for i, s, why in ranked]
    playable = await asyncio.gather(*(on_audius(r) for r, _, _ in rows_ranked))
    return {"items": [
        {"title": r.get("trackName"), "artist": r.get("artistName"), "album": r.get("albumName"),
         "duration": r.get("duration"), "similarity": s, "because": why,
         "snippet": best_line(r.get("plainLyrics"), tokens(q)), "audius": track}
        for (r, s, why), track in zip(rows_ranked, playable)
    ]}


# -- movies, series, anime --------------------------------------------------------------------

async def _catalog_index(c) -> tuple[TfidfIndex, dict[str, dict]]:
    """TF-IDF index over the Stream catalogue (movies, series, anime); rebuilt
    whenever the catalogue changes (graph revision)."""
    from app.domains.stream.catalog import ensure_catalog
    await ensure_catalog(c)
    revision = await c.graph.store.revision()
    cached = _title_index.get("index")
    if cached and cached[0] == revision:
        return cached[1], cached[2]
    rows = await c.graph.store.rows("platform_content", {"platform": "stream"})
    titles = {r["domain_ref"]: r for r in rows
              if r.get("domain_ref") and r.get("category") not in ("Music", "Podcasts")
              and r.get("kind") not in ("music", "song", "podcast", "audio")
              and not (r.get("demo") and not r.get("source_url"))}
    docs = []
    for ref, r in titles.items():
        genres = r.get("genres") or []
        docs.append(Document(ref)
                    .add_text(r.get("title"), 2)
                    .add_text(r.get("description"), 1)
                    .add_text(" ".join(genres), 2)
                    .add_tags("genre", genres, 3)
                    .add_tags("category", [r.get("category")], 1.5)
                    .add_tags("by", [r.get("director"), r.get("studio")], 2)
                    .add_tags("lang", [r.get("language")], 0.5))
    index = TfidfIndex(docs)
    _title_index["index"] = (revision, index, titles)
    return index, titles


async def _present(c, user_id: str, ranked, titles) -> list[dict]:
    """Ranked refs -> the same item shape as /content/stream (opens like any title)."""
    from app.api.v1.content import presentation
    items = []
    for ref, score, why in ranked:
        row = titles.get(ref)
        try:
            obj = await c.graph.object_for(user_id, row.get("object_id") or key("phlio_object", "stream", ref))
        except HTTPException:
            continue
        items.append({**(await presentation(c, obj)), "similarity": score, "because": why})
    return items


@router.get("/titles/{ref}")
async def similar_titles(ref: str, limit: int = Query(12, ge=1, le=30),
                         user=Depends(get_current_user), c=Depends(get_container)):
    """Movies, series and anime most like ``ref`` (story, genres, studio/director)."""
    index, titles = await _catalog_index(c)
    if ref not in titles:
        raise HTTPException(404, "Title not found.")
    return {"items": await _present(c, user.id, index.nearest(ref, k=limit), titles)}


@router.get("/titles")
async def titles_by_story(q: str = Query(min_length=3, max_length=200), limit: int = Query(20, ge=1, le=40),
                          user=Depends(get_current_user), c=Depends(get_container)):
    """Titles whose synopsis matches a description ("robots in a future city")."""
    if not tokens(q):
        return {"items": []}
    index, titles = await _catalog_index(c)
    query = Document("q").add_text(q).add_tags("genre", [q], 3)
    return {"items": await _present(c, user.id, index.nearest(query, k=limit, min_score=0.05), titles)}
