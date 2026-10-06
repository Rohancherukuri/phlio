"""Tests for the Activity feed and Sticker catalog endpoints."""

from __future__ import annotations

async def test_activity_requires_auth(client):
    response = await client.get("/api/v1/activity")
    assert response.status_code == 401


async def test_activity_returns_seeded_feed(client, auth_headers):
    response = await client.get("/api/v1/activity", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    kinds = {item["kind"] for item in body["items"]}
    assert {"book", "pay", "social", "agent"} <= kinds
    assert all(not item["is_read"] for item in body["items"])


async def test_mark_all_read(client, auth_headers):
    response = await client.post("/api/v1/activity/read-all", headers=auth_headers)
    assert response.status_code == 204

    feed = await client.get("/api/v1/activity", headers=auth_headers)
    assert all(item["is_read"] for item in feed.json()["items"])


async def test_sticker_catalog_public(client):
    # The catalog is public metadata so the app can fetch it pre-login.
    response = await client.get("/api/v1/stickers")
    assert response.status_code == 200


async def test_sticker_catalog(client, auth_headers):
    response = await client.get("/api/v1/stickers", headers=auth_headers)
    assert response.status_code == 200
    stickers = response.json()
    ids = {s["id"] for s in stickers}
    assert {"idle", "happy", "hello", "thinking", "sleepy"} <= ids
    assert all(s["pack"] == "foxy_classics" for s in stickers)
