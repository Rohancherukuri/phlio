"""Phlio notifications: DMs, rooms, comments, suggestions, read state."""

from __future__ import annotations

import asyncio
import io

import pytest
from httpx import AsyncClient
from PIL import Image

pytestmark = pytest.mark.asyncio


async def login(client: AsyncClient, name: str) -> dict:
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


async def feed(client, headers, **params):
    await asyncio.sleep(0.05)  # hooks notify in the background
    r = await client.get("/api/v1/notifications", headers=headers, params={"pulse": "false", **params})
    assert r.status_code == 200, r.text
    return r.json()


async def test_dm_notifications_group_and_read(client: AsyncClient, auth_headers: dict) -> None:
    neha = await login(client, "neha")
    await feed(client, neha)  # installs hooks
    for text in ("hey", "are you free?"):
        r = await client.post("/api/v1/messaging/peers/neha/messages", headers=auth_headers, json={"text": text})
        assert r.status_code == 201, r.text
    data = await feed(client, neha)
    dms = [n for n in data["items"] if n["platform"] == "dm"]
    assert len(dms) == 1 and dms[0]["count"] == 2 and dms[0]["body"] == "are you free?"
    assert dms[0]["actor"]["username"] == "arjun" and dms[0]["data"]["peer"] == "arjun"
    assert data["unread"] >= 1
    since = dms[0]["at"]
    assert (await feed(client, neha, since=since))["items"] == []
    assert (await client.post("/api/v1/notifications/read", headers=neha, json={"group": dms[0]["group"]})).status_code == 204
    after = await feed(client, neha)
    assert all(n["read"] for n in after["items"] if n["platform"] == "dm")
    # A new message after reading starts a fresh notification.
    await client.post("/api/v1/messaging/peers/neha/messages", headers=auth_headers, json={"text": "ping"})
    again = [n for n in (await feed(client, neha))["items"] if n["platform"] == "dm" and not n["read"]]
    assert len(again) == 1 and again[0]["count"] == 1
    # Your own messages never notify you.
    assert not [n for n in (await feed(client, auth_headers))["items"] if n["platform"] == "dm"]
    assert (await client.delete(f"/api/v1/notifications/{again[0]['id']}", headers=neha)).status_code == 204
    assert (await client.delete(f"/api/v1/notifications/{again[0]['id']}", headers=auth_headers)).status_code == 404


async def test_comment_and_mention_notifications(client: AsyncClient, auth_headers: dict) -> None:
    neha = await login(client, "neha")
    post = await client.post("/api/v1/social/posts", headers=neha, json={"text": "my new post"})
    assert post.status_code in (200, 201), post.text
    pid = post.json()["id"]
    r = await client.post(f"/api/v1/social/content/{pid}/comments", headers=auth_headers,
                          data={"text": "nice one @artbykiara"})
    assert r.status_code == 201, r.text
    mine = [n for n in (await feed(client, neha))["items"] if n["kind"] == "comment"]
    assert mine and mine[0]["platform"] == "social" and "nice one" in mine[0]["body"]
    assert mine[0]["data"]["path"].endswith(pid)
    kiara = await login(client, "artbykiara")
    tagged = [n for n in (await feed(client, kiara))["items"] if n["kind"] == "mention"]
    assert tagged and tagged[0]["actor"]["username"] == "arjun"
    reply = await client.post(f"/api/v1/social/content/{pid}/comments", headers=neha,
                              data={"text": "thanks!", "parent_id": r.json()["id"]})
    assert reply.status_code == 201, reply.text
    replies = [n for n in (await feed(client, auth_headers))["items"] if n["kind"] == "reply"]
    assert replies and "thanks!" in replies[0]["body"]


async def test_pulse_suggestions(client: AsyncClient, auth_headers: dict) -> None:
    from app.api.v1 import notifications as n
    from app.domains.graph.service import key
    c = client._transport.app.state.container  # type: ignore[attr-defined]
    me = (await client.get("/api/v1/auth/me", headers=auth_headers)).json()
    # A product in the bag → similar items.
    products = (await client.get("/api/v1/shop/products", headers=auth_headers)).json()["items"]
    assert products
    await client.put(f"/api/v1/shop/cart/{products[0]['id']}", headers=auth_headers, json={"quantity": 1})
    first = await client.get("/api/v1/notifications", headers=auth_headers)  # creates the state, no pulse yet
    assert first.status_code == 200
    made = []
    for _ in range(3):
        state = await c.graph.store.get(key("notification_state", me["id"]))
        state["last_pulse"] = "2000-01-01T00:00:00+00:00"
        await c.graph.store.put(state["id"], state)
        data = (await client.get("/api/v1/notifications", headers=auth_headers)).json()
        made = [x for x in data["items"] if x["platform"] in {"shop", "news", "stream"}]
    platforms = {x["platform"] for x in made}
    assert "shop" in platforms
    shop = next(x for x in made if x["platform"] == "shop")
    assert shop["kind"] == "similar_items" and shop["data"]["products"]
    assert all(p["id"] != products[0]["id"] for p in shop["data"]["products"])
    # Right after a pulse, polling doesn't make another.
    count = len(made)
    data = (await client.get("/api/v1/notifications", headers=auth_headers)).json()
    assert len([x for x in data["items"] if x["platform"] in {"shop", "news", "stream"}]) == count
    assert n.PULSE_GAP.total_seconds() >= 600


async def test_room_message_notifies_members(client: AsyncClient, auth_headers: dict) -> None:
    neha = await login(client, "neha")
    room = await client.post("/api/v1/rooms", headers=neha, json={"name": "Film club", "description": "Movies", "category": "gaming", "is_private": False})
    assert room.status_code == 201, room.text
    rid = room.json()["id"]
    assert (await client.post(f"/api/v1/rooms/{rid}/join", headers=auth_headers)).status_code == 200
    await feed(client, auth_headers)
    r = await client.post(f"/api/v1/rooms/{rid}/messages", headers=neha, json={"text": "Tonight 9pm?"})
    assert r.status_code == 201, r.text
    rooms = [n for n in (await feed(client, auth_headers))["items"] if n["platform"] == "rooms"]
    assert rooms and rooms[0]["title"] == "Film club" and rooms[0]["data"]["room_id"] == rid
    assert "Tonight 9pm?" in rooms[0]["body"]
    assert not [n for n in (await feed(client, neha))["items"] if n["platform"] == "rooms"]
