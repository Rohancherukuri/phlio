"""Similar songs / lyrics search / similar titles (Audius and LRCLIB mocked)."""

from __future__ import annotations

import httpx
import pytest

from app.api.v1 import audius, similar
from app.domains.stream import lyrics as lyrics_mod
from app.domains.stream.similarity import Document, TfidfIndex, best_line, tokens

RAIN = "Rain falls on the city tonight\nNeon lights and midnight rain\nI walk the empty city streets"
RAIN2 = "Midnight rain is falling on the city\nNeon streets, I walk alone in the rain"
SUN = "Sunshine on the beach, summer waves\nDancing in the sand all day"


def test_tokens_and_index():
    assert tokens("Oh yeah, the DREAMS we're chasing!") == ["dream", "chasing"]
    assert tokens("Город и дождь") == ["город", "дождь"]
    idx = TfidfIndex([Document("a").add_text(RAIN2), Document("b").add_text(SUN)])
    ranked = idx.nearest(Document("q").add_text(RAIN))
    assert ranked[0][0] == "a" and "rain" in ranked[0][2]
    assert best_line(RAIN2, ["neon", "street"]) == "Neon streets, I walk alone in the rain"


def track(tid, title, artist, genre="Electronic", mood="Melancholy", tags="night,city"):
    return {"id": tid, "title": title, "genre": genre, "mood": mood, "tags": tags, "duration": 200,
            "user": {"id": "u" + tid, "name": artist}, "is_streamable": True}


TRACKS = {
    "seed1": track("seed1", "City Rain", "Nova"),
    "aaa": track("aaa", "Midnight Rain", "Echo"),
    "bbb": track("bbb", "Summer Beach", "Sol", genre="Pop", mood="Upbeat", tags="summer"),
    "ccc": track("ccc", "Night Drive", "Vex", tags="night,drive"),
}
LYRICS = {("city rain", "nova"): RAIN, ("midnight rain", "echo"): RAIN2, ("summer beach", "sol"): SUN}


@pytest.fixture
def upstreams(monkeypatch):
    def audius_handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.endswith("/tracks/seed1"):
            return httpx.Response(200, json={"data": TRACKS["seed1"]})
        if path.endswith("/related"):
            return httpx.Response(200, json={"data": [{"id": "uccc"}]})
        if path.endswith("/users/uccc/tracks"):
            return httpx.Response(200, json={"data": [TRACKS["ccc"]]})
        if "tracks/search" in path:
            q = request.url.params.get("query", "").lower()
            hits = [t for t in TRACKS.values() if any(w in q for w in t["title"].lower().split())]
            return httpx.Response(200, json={"data": hits})
        if "tracks/trending" in path:
            return httpx.Response(200, json={"data": [TRACKS["aaa"], TRACKS["bbb"], TRACKS["seed1"]]})
        return httpx.Response(404, json={})

    def lrclib_handler(request: httpx.Request) -> httpx.Response:
        p = request.url.params
        if request.url.path == "/api/search" and p.get("q"):
            return httpx.Response(200, json=[
                {"id": 1, "trackName": "Midnight Rain", "artistName": "Echo", "albumName": "A", "duration": 200,
                 "plainLyrics": RAIN2, "instrumental": False},
                {"id": 2, "trackName": "Famous Sun", "artistName": "Star", "albumName": "B", "duration": 180,
                 "plainLyrics": SUN, "instrumental": False}])
        found = LYRICS.get((p.get("track_name", "").lower(), p.get("artist_name", "").lower()))
        if found is None:
            return httpx.Response(404, json={})
        return httpx.Response(200, json={"trackName": p["track_name"], "artistName": p["artist_name"],
                                         "plainLyrics": found, "instrumental": False})

    monkeypatch.setattr(audius, "_http", httpx.AsyncClient(transport=httpx.MockTransport(audius_handler)))
    monkeypatch.setattr(audius, "_responses", audius._TTLCache(200))
    monkeypatch.setattr(lyrics_mod, "_http",
                        httpx.AsyncClient(base_url="https://lrclib.net", transport=httpx.MockTransport(lrclib_handler)))
    monkeypatch.setattr(lyrics_mod, "_cache", {})
    monkeypatch.setattr(similar, "_song_results", {})


async def test_similar_songs_ranks_lyric_match_first(client, auth_headers, upstreams):
    r = await client.get("/api/v1/stream/similar/songs?audius_id=seed1", headers=auth_headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["seed"] == {"title": "City Rain", "artist": "Nova", "has_lyrics": True}
    ids = [i["track"]["id"] for i in body["items"]]
    assert ids[0] == "aaa" and "seed1" not in ids
    top = body["items"][0]
    assert top["match"] == "lyrics" and "rain" in top["because"] and top["snippet"]
    # Same genre/mood/tags is a match; unrelated pop with unrelated lyrics isn't.
    assert "ccc" in ids and ("bbb" not in ids or ids.index("ccc") < ids.index("bbb"))


async def test_lyrics_search_finds_audius_match(client, auth_headers, upstreams):
    r = await client.get("/api/v1/stream/similar/songs/by-lyrics?q=walking in the midnight rain", headers=auth_headers)
    items = r.json()["items"]
    assert items[0]["title"] == "Midnight Rain" and items[0]["audius"]["id"] == "aaa"
    assert items[0]["snippet"] and len(items[0]["snippet"]) <= 140
    assert all(i["audius"] is None for i in items[1:])


async def test_similar_titles(client, auth_headers, monkeypatch):
    from app.domains.graph.service import key
    from app.domains.stream import catalog

    container = client._transport.app.state.container
    rows = [
        dict(domain_ref="t-robots", title="Steel Dawn", kind="movie", category="Movies", genres=["Science fiction"],
             description="Robots and humans fight for a future city.", source_url="https://x"),
        dict(domain_ref="t-robots2", title="Machine Hearts", kind="movie", category="Movies",
             genres=["Science fiction"], description="An android in a future city learns to love.", source_url="https://x"),
        dict(domain_ref="t-cook", title="Kitchen Days", kind="series", category="TV Series", genres=["Comedy"],
             description="A family restaurant and its chaotic chefs.", source_url="https://x"),
    ]

    async def fake_ensure(c):
        for row in rows:
            if not await c.graph.store.get(key("platform_content", "stream", row["domain_ref"])):
                await catalog.save(c, row)

    monkeypatch.setattr(catalog, "ensure_catalog", fake_ensure)
    monkeypatch.setattr(similar, "_title_index", {})
    await fake_ensure(container)
    r = await client.get("/api/v1/stream/similar/titles/t-robots", headers=auth_headers)
    assert r.status_code == 200, r.text
    assert [i["ref"] for i in r.json()["items"]][:1] == ["t-robots2"]
    q = await client.get("/api/v1/stream/similar/titles?q=a robot story in the future", headers=auth_headers)
    assert [i["ref"] for i in q.json()["items"]][0] in {"t-robots", "t-robots2"}
    assert "t-cook" not in [i["ref"] for i in q.json()["items"]]


def test_placeholder_credentials_are_ignored():
    from app.config import Settings

    for placeholder in ("...", "<your key>", "changeme", "  "):
        assert Settings(_env_file=None, audius_bearer_token=placeholder).audius_bearer_token == ""
    assert Settings(_env_file=None, audius_api_key="abc123").audius_api_key == "abc123"
