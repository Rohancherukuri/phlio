"""AniList proxy: shaping, adult filtering, caching and rate-limit fallback (no network)."""

from __future__ import annotations

import datetime as dt
import json

import httpx
import pytest

from app.api.v1 import anime

CARD = {
    "id": 21, "format": "TV", "status": "RELEASING", "episodes": None, "duration": 24, "averageScore": 88,
    "popularity": 500000, "season": "FALL", "seasonYear": 1999,
    "title": {"romaji": "One Piece", "english": "ONE PIECE", "native": "ワンピース"},
    "coverImage": {"extraLarge": "https://img/c.jpg", "color": "#e4a15d"}, "bannerImage": "https://img/b.jpg",
    "genres": ["Action", "Adventure"], "nextAiringEpisode": {"episode": 1150, "airingAt": 1800000000},
}


@pytest.fixture
def anilist(monkeypatch):
    calls: list[dict] = []
    state = {"status": 200}

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        calls.append(body)
        if state["status"] == 429:
            return httpx.Response(429, headers={"retry-after": "60"})
        if "Media(id" in body["query"]:
            if body["variables"]["id"] == 666:
                return httpx.Response(200, json={"data": {"Media": {**CARD, "id": 666, "isAdult": True}}})
            return httpx.Response(200, json={"data": {"Media": {
                **CARD, "isAdult": False,
                "description": "Gol D. Roger<br><br>was known as the <i>Pirate King</i> &amp; more.",
                "startDate": {"year": 1999, "month": 10, "day": 20}, "source": "MANGA",
                "studios": {"nodes": [{"name": "Toei Animation"}]},
                "trailer": {"id": "abc123", "site": "youtube", "thumbnail": None},
                "externalLinks": [
                    {"site": "Crunchyroll", "url": "https://www.crunchyroll.com/series/x", "type": "STREAMING"},
                    {"site": "Twitter", "url": "https://twitter.com/x", "type": "SOCIAL"},
                    {"site": "Old", "url": "https://old.example", "type": "STREAMING", "isDisabled": True},
                    {"site": "Bad", "url": "javascript:alert(1)", "type": "STREAMING"},
                ],
                "streamingEpisodes": [{"title": "Episode 1", "url": "https://www.crunchyroll.com/ep1",
                                       "thumbnail": "https://img/e1.jpg", "site": "Crunchyroll"}],
                "recommendations": {"nodes": [{"mediaRecommendation": {**CARD, "id": 30, "isAdult": False}},
                                              {"mediaRecommendation": {**CARD, "id": 31, "isAdult": True}}]},
            }}})
        if "GenreCollection" in body["query"]:
            return httpx.Response(200, json={"data": {"GenreCollection": ["Action", "Hentai", "Romance"]}})
        return httpx.Response(200, json={"data": {"Page": {"pageInfo": {"hasNextPage": True}, "media": [CARD]}}})

    monkeypatch.setattr(anime, "_http", httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(anime, "_cache", anime._Cache())
    monkeypatch.setattr(anime, "_blocked_until", 0.0)
    return calls, state


async def test_trending_list_is_shaped_and_cached(client, auth_headers, anilist):
    calls, _ = anilist
    r = await client.get("/api/v1/stream/anime/lists/trending", headers=auth_headers)
    assert r.status_code == 200
    item = r.json()["items"][0]
    assert item["title"] == "ONE PIECE" and item["cover"] == "https://img/c.jpg"
    assert item["next_episode"] == {"episode": 1150, "airing_at": 1800000000}
    assert r.json()["has_more"] is True
    assert calls[0]["variables"]["sort"] == ["TRENDING_DESC", "POPULARITY_DESC"]
    assert "isAdult: false" in calls[0]["query"]
    await client.get("/api/v1/stream/anime/lists/trending", headers=auth_headers)
    assert len(calls) == 1


async def test_season_list_uses_current_season(client, auth_headers, anilist):
    calls, _ = anilist
    r = await client.get("/api/v1/stream/anime/lists/season", headers=auth_headers)
    season, year = anime._season()
    assert calls[0]["variables"]["season"] == season and calls[0]["variables"]["seasonYear"] == year
    assert r.json()["season"] == f"{season.title()} {year}"
    assert anime._season(dt.date(2026, 11, 11)) == ("FALL", 2026)
    assert anime._season(dt.date(2027, 1, 2)) == ("WINTER", 2027)


async def test_details_trailer_links_and_safety(client, auth_headers, anilist):
    r = await client.get("/api/v1/stream/anime/21", headers=auth_headers)
    d = r.json()
    assert d["description"].startswith("Gol D. Roger\n\nwas known as the Pirate King & more.")
    assert d["trailer"]["url"] == "https://www.youtube.com/watch?v=abc123"
    assert [link["site"] for link in d["where_to_watch"]] == ["Crunchyroll"]
    assert d["episodes_list"][0]["url"] == "https://www.crunchyroll.com/ep1"
    assert [rec["id"] for rec in d["recommendations"]] == [30]
    assert d["studios"] == ["Toei Animation"] and d["start_date"] == "1999-10-20"
    assert (await client.get("/api/v1/stream/anime/666", headers=auth_headers)).status_code == 404


async def test_genres_exclude_adult_and_auth_required(client, auth_headers, anilist):
    r = await client.get("/api/v1/stream/anime/genres", headers=auth_headers)
    assert r.json()["genres"] == ["Action", "Romance"]
    assert (await client.get("/api/v1/stream/anime/lists/top")).status_code == 401
    assert (await client.get("/api/v1/stream/anime/lists/nope", headers=auth_headers)).status_code == 404


async def test_rate_limit_serves_stale_copy_then_503(client, auth_headers, anilist, monkeypatch):
    calls, state = anilist
    assert (await client.get("/api/v1/stream/anime/search?q=one piece", headers=auth_headers)).status_code == 200
    monkeypatch.setattr(anime, "SEARCH_TTL", -1)  # force expiry
    state["status"] = 429
    stale = await client.get("/api/v1/stream/anime/search?q=one piece", headers=auth_headers)
    assert stale.status_code == 200 and stale.json()["items"][0]["id"] == 21
    fresh = await client.get("/api/v1/stream/anime/search?q=naruto", headers=auth_headers)
    assert fresh.status_code == 503
