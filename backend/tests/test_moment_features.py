"""Moments: duration, rewatches, viewer search, super hearts, spotlight,
viewer notifications; pinned and profile-only posts; chat preview prefs;
bio fonts."""

from __future__ import annotations

import io

import pytest
from httpx import AsyncClient
from PIL import Image

pytestmark = pytest.mark.asyncio
M = "/api/v1/social/moments"


def png() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (16, 16), (90, 40, 200)).save(buf, "PNG")
    return buf.getvalue()


async def login(client, name):
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


async def post_moment(client, h, **data):
    r = await client.post(M, headers=h, files={"file": ("m.png", png(), "image/png")},
                          data={"audience": "everyone", **data})
    assert r.status_code == 201, r.text
    return r.json()


async def test_moment_plus(client: AsyncClient) -> None:
    import datetime as dt

    arjun, neha, kiara = await login(client, "arjun"), await login(client, "neha"), await login(client, "artbykiara")
    assert (await client.post(M, headers=arjun, files={"file": ("m.png", png(), "image/png")},
                              data={"duration_hours": "36"})).status_code == 422
    m = await post_moment(client, arjun, duration_hours="12")
    made = dt.datetime.fromisoformat(m["created_at"])
    assert dt.datetime.fromisoformat(m["expires_at"]) - made == dt.timedelta(hours=12) and m["duration_hours"] == 12
    mid = m["id"].removeprefix("social_moment:")
    m = (await client.put(f"{M}/{mid}/duration", headers=arjun, json={"hours": 48})).json()
    assert dt.datetime.fromisoformat(m["expires_at"]) - made == dt.timedelta(hours=48)
    assert (await client.put(f"{M}/{mid}/duration", headers=neha, json={"hours": 24})).status_code == 403

    # Notify when Neha views; Kiara's view doesn't notify.
    s = (await client.put(f"{M}/settings/me", headers=arjun, json={"notify_viewers": ["neha"], "default_hours": 48})).json()
    assert [p["username"] for p in s["notify_viewers"]] == ["neha"] and s["default_hours"] == 48
    for _ in range(3):
        await client.put(f"{M}/{mid}/seen", headers=neha)
    await client.put(f"{M}/{mid}/seen", headers=kiara)
    notes = (await client.get("/api/v1/notifications", headers=arjun)).json()
    items = notes["items"] if isinstance(notes, dict) else notes
    assert sum(1 for n in items if n.get("kind") == "moment_view") == 1

    # Super heart, rewatches, search.
    r = await client.put(f"{M}/{mid}/reaction", headers=kiara, json={"emoji": "❤️", "super": True})
    assert r.json()["super"] is True
    v = (await client.get(f"{M}/{mid}/viewers", headers=arjun)).json()
    assert v["rewatches"] == 2 and v["super_hearts"] == 1
    by = {p["username"]: p for p in v["people"]}
    assert by["neha"]["views"] == 3 and by["neha"]["last_seen_at"] and by["artbykiara"]["super_heart"]
    found = (await client.get(f"{M}/{mid}/viewers", headers=arjun, params={"q": "@neh"})).json()
    assert [p["username"] for p in found["people"]] == ["neha"] and found["count"] == 2

    # Spotlight once a week; it leads the rail for others.
    await post_moment(client, kiara)
    assert (await client.post(f"{M}/{mid}/spotlight", headers=arjun)).status_code == 200
    assert (await client.post(f"{M}/{mid}/spotlight", headers=arjun)).status_code == 429
    rail = (await client.get(f"{M}/feed", headers=neha)).json()
    others = [g for g in rail if g["author"]["username"] != "neha"]
    assert others[0]["author"]["username"] == "arjun" and others[0]["spotlight"]
    rings = (await client.get(f"{M}/active", headers=neha)).json()
    assert rings["arjun"]["spotlight"] is True


async def test_pins_profile_only_chats_bio(client: AsyncClient) -> None:
    arjun, neha = await login(client, "arjun"), await login(client, "neha")
    ids = []
    for i in range(7):
        r = await client.post("/api/v1/social/posts", headers=arjun, json={"text": f"post {i}"})
        ids.append(r.json()["id"])
    hidden = (await client.post("/api/v1/social/posts", headers=arjun,
                                json={"text": "just for my grid", "profile_only": True})).json()
    assert hidden["profile_only"]
    feed = (await client.get("/api/v1/social/feed", headers=neha, params={"limit": 50})).json()["items"]
    assert hidden["id"] not in [p["id"] for p in feed] and ids[-1] in [p["id"] for p in feed]

    for pid in ids[:6]:
        assert (await client.put(f"/api/v1/social/posts/{pid}/pin", headers=arjun, json={"pinned": True})).status_code == 200
    assert (await client.put(f"/api/v1/social/posts/{ids[6]}/pin", headers=arjun, json={})).status_code == 422
    assert (await client.put(f"/api/v1/social/posts/{ids[0]}/pin", headers=neha, json={})).status_code == 403
    grid = (await client.get("/api/v1/users/arjun/posts", headers=neha)).json()["items"]
    assert [p["id"] for p in grid[:6]] == list(reversed(ids[:6])) and all(p["pinned"] for p in grid[:6])
    assert any(p["id"] == hidden["id"] and p["profile_only"] for p in grid)
    await client.put(f"/api/v1/social/posts/{ids[0]}/pin", headers=arjun, json={"pinned": False})
    grid = (await client.get("/api/v1/users/arjun/posts", headers=neha)).json()["items"]
    assert sum(p["pinned"] for p in grid) == 5

    # Chats: pin, mute (no notification), delete for me.
    await client.post("/api/v1/messaging/peers/neha/messages", headers=arjun, json={"text": "hi"})
    assert (await client.put("/api/v1/messaging/peers/arjun/prefs", headers=neha,
                             json={"pinned": True, "muted": True, "muted_calls": True})).json()["muted"]
    before = (await client.get("/api/v1/notifications", headers=neha)).json()
    await client.post("/api/v1/messaging/peers/neha/messages", headers=arjun, json={"text": "you there?"})
    after = (await client.get("/api/v1/notifications", headers=neha)).json()
    assert len(after["items"] if isinstance(after, dict) else after) == len(before["items"] if isinstance(before, dict) else before)
    chats = (await client.get("/api/v1/messaging/conversations", headers=neha)).json()
    assert chats[0]["peer"]["username"] == "arjun" and chats[0]["pinned"] and chats[0]["muted"]
    assert (await client.delete("/api/v1/messaging/peers/arjun/conversation", headers=neha)).status_code == 204
    chats = (await client.get("/api/v1/messaging/conversations", headers=neha)).json()
    assert all(ch["peer"]["username"] != "arjun" for ch in chats)
    assert any(ch["peer"]["username"] == "neha" for ch in (await client.get("/api/v1/messaging/conversations", headers=arjun)).json())

    # Bio font.
    style = (await client.get("/api/v1/appearance/me", headers=arjun)).json()
    style["bio_font"] = "Script"
    assert (await client.put("/api/v1/appearance/me", headers=arjun, json=style)).json()["bio_font"] == "Script"
    assert (await client.get("/api/v1/appearance/users/arjun", headers=neha)).json()["bio_font"] == "Script"
