"""Blend, watch together, and Discord-style replies / pins in Rooms."""

from __future__ import annotations

import asyncio

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def login(client, name):
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


async def post(client, headers, text):
    r = await client.post("/api/v1/social/posts", headers=headers, json={"text": text})
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


async def like(client, headers, pid):
    r = await client.put(f"/api/v1/content/social/{pid}/like", headers=headers)
    assert r.status_code == 200, r.text


async def test_blend_invite_accept_and_feed(client: AsyncClient, auth_headers: dict) -> None:
    neha = await login(client, "neha")
    kiara = await login(client, "artbykiara")
    p_neha = await post(client, kiara, "sunset hike #travel")
    p_mine = await post(client, kiara, "ramen night #food")
    p_both = await post(client, kiara, "mountain lake #travel")
    await like(client, neha, p_neha)
    await like(client, auth_headers, p_mine)
    await like(client, neha, p_both)
    await like(client, auth_headers, p_both)

    r = await client.post("/api/v1/blends", headers=auth_headers, json={"username": "neha"})
    assert r.status_code == 201, r.text
    blend = r.json()
    assert blend["status"] == "pending" and blend["invited_by_me"] and blend["partner"]["username"] == "neha"
    # Same pair → same Blend; the inviter can't accept for them.
    assert (await client.post("/api/v1/blends", headers=auth_headers, json={"username": "neha"})).json()["id"] == blend["id"]
    assert (await client.post(f"/api/v1/blends/{blend['id']}/accept", headers=auth_headers)).status_code == 422
    # The invite is a DM card.
    dm = (await client.get("/api/v1/messaging/peers/arjun/messages", headers=neha)).json()
    items = dm["items"] if isinstance(dm, dict) else dm
    assert any(f"phlio-blend:{blend['id']}" in (m.get("text") or "") for m in items)

    r = await client.post(f"/api/v1/blends/{blend['id']}/accept", headers=neha)
    assert r.json()["status"] == "active"
    feed = (await client.get(f"/api/v1/blends/{blend['id']}", headers=auth_headers)).json()
    reasons = {i["ref"]: i["reason"] for i in feed["items"]}
    assert reasons[p_both] == "You both liked"
    assert reasons[p_neha].startswith("Liked by")
    assert reasons[p_mine] == "You liked"
    assert feed["items"][0]["ref"] == p_both
    only_clips = (await client.get(f"/api/v1/blends/{blend['id']}", headers=auth_headers, params={"kind": "clip"})).json()
    assert all(i["object_type"] == "social.clip" for i in only_clips["items"])
    assert len((await client.get("/api/v1/blends", headers=neha)).json()["items"]) == 1
    assert (await client.delete(f"/api/v1/blends/{blend['id']}", headers=neha)).status_code == 204
    assert (await client.get("/api/v1/blends", headers=auth_headers)).json()["items"] == []


async def test_watch_together_in_a_dm(client: AsyncClient, auth_headers: dict) -> None:
    neha = await login(client, "neha")
    pid = await post(client, auth_headers, "watch this with me")
    assert (await client.get("/api/v1/watch/dm/neha", headers=auth_headers)).json() == {"party": None}
    r = await client.post("/api/v1/watch/dm/neha/start", headers=auth_headers, json={"platform": "social", "ref": pid})
    assert r.status_code == 200, r.text
    party = r.json()["party"]
    assert party["item"]["ref"] == pid and party["kind"] == "dm"
    # Neha sees the same party from her side of the DM, and a card in the chat.
    theirs = (await client.get("/api/v1/watch/dm/arjun", headers=neha)).json()["party"]
    assert theirs["id"] == party["id"]
    r = await client.post("/api/v1/watch/dm/arjun/control", headers=neha, json={"action": "seek", "position_ms": 42000})
    assert r.json()["party"]["position_ms"] >= 42000
    r = await client.post("/api/v1/watch/dm/arjun/control", headers=neha, json={"action": "pause", "position_ms": 50000})
    paused = r.json()["party"]
    await asyncio.sleep(0.05)
    again = (await client.get("/api/v1/watch/dm/neha", headers=auth_headers)).json()["party"]
    assert not again["playing"] and again["position_ms"] == paused["position_ms"] == 50000
    r = await client.post("/api/v1/watch/dm/neha/react", headers=auth_headers, json={"emoji": "😂"})
    assert r.json()["party"]["reactions"][-1]["emoji"] == "😂"
    lib = (await client.get("/api/v1/watch/library", headers=auth_headers, params={"ctx": "dm", "kind": "post"})).json()
    assert any(i["ref"] == pid for i in lib["items"]) and all(i["platform"] == "social" for i in lib["items"])
    assert (await client.delete("/api/v1/watch/dm/neha", headers=auth_headers)).status_code == 204
    assert (await client.get("/api/v1/watch/dm/arjun", headers=neha)).json() == {"party": None}


async def test_room_replies_and_pins(client: AsyncClient, auth_headers: dict) -> None:
    rooms = (await client.get("/api/v1/rooms/mine", headers=auth_headers)).json()
    if not rooms:
        discover = (await client.get("/api/v1/rooms/discover", headers=auth_headers)).json()["items"]
        await client.post(f"/api/v1/rooms/{discover[0]['id']}/join", headers=auth_headers)
        rooms = (await client.get("/api/v1/rooms/mine", headers=auth_headers)).json()
    rid = rooms[0]["id"]
    first = (await client.post(f"/api/v1/rooms/{rid}/messages", headers=auth_headers, json={"text": "who's in for dinner?"})).json()
    r = await client.post(f"/api/v1/rooms/{rid}/messages", headers=auth_headers,
                          json={"text": "me!", "reply_to": first["id"]})
    assert r.status_code == 201, r.text
    assert r.json()["reply_to"]["text"] == "who's in for dinner?"
    r = await client.put(f"/api/v1/rooms/{rid}/messages/{first['id']}/pin", headers=auth_headers, json={"pinned": True})
    assert r.json() == {"pinned": True}
    page = (await client.get(f"/api/v1/rooms/{rid}/messages", headers=auth_headers, params={"limit": 100})).json()["items"]
    by_id = {m["id"]: m for m in page}
    assert by_id[first["id"]]["pinned"] is True
    assert any(m["text"] == f"phlio-system:pin:{first['id']}" for m in page)
    assert any((m.get("reply_to") or {}).get("id") == first["id"] for m in page)
    pins = (await client.get(f"/api/v1/rooms/{rid}/pins", headers=auth_headers)).json()["items"]
    assert pins[0]["id"] == first["id"]
