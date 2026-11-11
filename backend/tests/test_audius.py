"""Audius proxy: allowlist, credentials, caching and stream redirects (no network)."""

from __future__ import annotations

import httpx
import pytest

from app.api.v1 import audius


@pytest.fixture
def upstream(monkeypatch):
    """Fake Audius: records requests and answers like the real API."""
    calls: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        path = request.url.path
        if path.endswith("/stream"):
            return httpx.Response(302, headers={"location": "https://creatornode.example/tracks/cidstream/abc"})
        if path.endswith("/tracks/trending"):
            return httpx.Response(200, json={"data": [{"id": "D7KyD", "title": "Song"}]})
        return httpx.Response(404, json={"error": "not found"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    monkeypatch.setattr(audius, "_http", client)
    monkeypatch.setattr(audius, "_responses", audius._TTLCache(50))
    monkeypatch.setattr(audius, "_streams", audius._TTLCache(50))
    return calls


async def test_trending_is_proxied_with_credentials_and_cached(client, auth_headers, upstream, settings):
    settings.audius_api_key = "pub-key"
    settings.audius_bearer_token = "secret-token"
    first = await client.get("/api/v1/music/audius/tracks/trending?time=week&genre=Electronic&evil=1",
                             headers=auth_headers)
    assert first.status_code == 200
    assert first.json()["data"][0]["id"] == "D7KyD"
    sent = upstream[0]
    assert sent.headers["authorization"] == "Bearer secret-token"
    assert sent.url.params["api_key"] == "pub-key" and sent.url.params["app_name"] == "Phlio"
    assert sent.url.params["genre"] == "Electronic" and "evil" not in sent.url.params
    again = await client.get("/api/v1/music/audius/tracks/trending?genre=Electronic&time=week", headers=auth_headers)
    assert again.headers["x-phlio-cache"] == "hit"
    assert len(upstream) == 1


async def test_reads_need_sign_in_and_allowlisted_paths(client, auth_headers, upstream):
    assert (await client.get("/api/v1/music/audius/tracks/trending")).status_code == 401
    for path in ("users/abc/favorites", "tracks/x/comments", "../../etc", "challenges"):
        assert (await client.get(f"/api/v1/music/audius/{path}", headers=auth_headers)).status_code == 404
    assert upstream == []


async def test_stream_redirects_to_content_node(client, upstream):
    r = await client.get("/api/v1/music/audius/stream/D7KyD", follow_redirects=False)
    assert r.status_code == 307
    assert r.headers["location"] == "https://creatornode.example/tracks/cidstream/abc"
    await client.get("/api/v1/music/audius/stream/D7KyD", follow_redirects=False)
    assert len(upstream) == 1  # resolved once, then cached
    assert (await client.get("/api/v1/music/audius/stream/bad-id!", follow_redirects=False)).status_code == 404
