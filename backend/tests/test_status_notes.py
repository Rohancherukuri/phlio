"""Notes above the inbox: post, visibility to followers / mutuals, likes, expiry."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio
SONG = {"title": "Midnight", "artist": "Kiara", "url": "/media/stream/midnight.mp3"}


async def login(client: AsyncClient, name: str) -> dict:
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


async def follow(client, headers, username):
    assert (await client.put(f"/api/v1/social/creators/{username}/follow", headers=headers)).status_code == 204


async def test_note_reaches_followers_and_likes(client: AsyncClient) -> None:
    kiara, neha = await login(client, "artbykiara"), await login(client, "neha")
    r = await client.post("/api/v1/social/notes", headers=kiara,
                          json={"text": "  studio   day ", "music": SONG,
                                "location": {"name": "Bandra", "lat": 19.06, "lng": 72.83}})
    assert r.status_code == 201, r.text
    assert r.json()["text"] == "studio day"

    assert (await client.get("/api/v1/social/notes", headers=neha)).json()["items"] == []
    await follow(client, neha, "artbykiara")
    items = (await client.get("/api/v1/social/notes", headers=neha)).json()["items"]
    assert [n["text"] for n in items] == ["studio day"]
    assert items[0]["music"]["title"] == "Midnight" and items[0]["like_count"] is None

    author = items[0]["author"]["id"]
    assert (await client.put(f"/api/v1/social/notes/{author}/like", headers=neha)).json() == {"liked": True}
    mine = (await client.get("/api/v1/social/notes", headers=kiara)).json()["mine"]
    assert mine["like_count"] == 1
    assert (await client.get("/api/v1/social/notes", headers=neha)).json()["items"][0]["liked_by_me"] is True

    assert (await client.delete("/api/v1/social/notes/mine", headers=kiara)).status_code == 204
    assert (await client.get("/api/v1/social/notes", headers=neha)).json()["items"] == []


async def test_mutuals_only_and_validation(client: AsyncClient) -> None:
    kiara, neha = await login(client, "artbykiara"), await login(client, "neha")
    await follow(client, neha, "artbykiara")
    await client.post("/api/v1/social/notes", headers=kiara, json={"text": "close friends", "audience": "mutuals"})
    assert (await client.get("/api/v1/social/notes", headers=neha)).json()["items"] == []
    await follow(client, kiara, "neha")
    assert len((await client.get("/api/v1/social/notes", headers=neha)).json()["items"]) == 1

    assert (await client.post("/api/v1/social/notes", headers=kiara, json={"text": " "})).status_code == 422
    assert (await client.post("/api/v1/social/notes", headers=kiara, json={"text": "x" * 61})).status_code == 422
    bad_gif = {"gif": {"url": "https://evil.example/a.gif"}}
    assert (await client.post("/api/v1/social/notes", headers=kiara, json=bad_gif)).status_code == 422
    bad_song = {"music": {**SONG, "url": "javascript:alert(1)"}}
    assert (await client.post("/api/v1/social/notes", headers=kiara, json=bad_song)).status_code == 422


async def test_expired_note_hidden(client: AsyncClient) -> None:
    import datetime as dt

    from app.api.v1 import status_notes

    kiara, neha = await login(client, "artbykiara"), await login(client, "neha")
    await follow(client, neha, "artbykiara")
    await client.post("/api/v1/social/notes", headers=kiara, json={"text": "old"})
    real = status_notes._now
    status_notes._now = lambda: real() + dt.timedelta(hours=25)
    try:
        body = (await client.get("/api/v1/social/notes", headers=neha)).json()
        assert body["items"] == []
    finally:
        status_notes._now = real
