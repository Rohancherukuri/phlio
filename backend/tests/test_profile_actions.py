"""Profile bell (notification levels and fan-out) and the profile ⋮ menu:
about, shared activity, hide moments, remove follower, restrict, report."""

from __future__ import annotations

import asyncio
import io

import pytest
from httpx import AsyncClient
from PIL import Image

pytestmark = pytest.mark.asyncio
P = "/api/v1/social/profiles"


def png() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (16, 16), (90, 40, 200)).save(buf, "PNG")
    return buf.getvalue()


async def login(client, name):
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


async def notes(client, h):
    await asyncio.sleep(0.2)  # fan-out runs in the background
    return [n for n in (await client.get("/api/v1/notifications", headers=h)).json()["items"]
            if n["kind"].startswith("new_")]


async def test_bell_and_menu(client: AsyncClient) -> None:
    arjun, neha = await login(client, "arjun"), await login(client, "neha")
    await client.put("/api/v1/social/creators/arjun/follow", headers=neha)
    # Defaults: most relevant; neha sets posts to all, moments off.
    got = (await client.get(f"{P}/arjun/notify", headers=neha)).json()
    assert got["levels"]["posts"] == "relevant" and not got["all"]
    got = (await client.put(f"{P}/arjun/notify", headers=neha, json={"posts": "all", "moments": "off"})).json()
    assert got["levels"]["posts"] == "all" and got["all"] and got["levels"]["moments"] == "off"
    assert (await client.put(f"{P}/arjun/notify", headers=neha, json={"posts": "loud"})).status_code == 422
    assert (await client.get(f"{P}/neha/notify", headers=neha)).status_code == 422

    for text in ("first", "second"):
        assert (await client.post("/api/v1/social/posts", headers=arjun, json={"text": text, "media": []})).status_code == 201
    posts = [n for n in await notes(client, neha) if n["kind"] == "new_post"]
    assert len(posts) >= 1 and posts[0]["data"]["creator"] == "arjun" and posts[0]["data"]["path"].startswith("social/")
    # Moments are off for arjun: nothing.
    r = await client.post("/api/v1/social/moments", headers=arjun, files={"file": ("m.png", png(), "image/png")},
                          data={"audience": "everyone"})
    assert r.status_code == 201
    assert not [n for n in await notes(client, neha) if n["kind"] == "new_moment"]

    # Defaults for everyone you follow.
    d = (await client.put(f"{P}/notify-defaults", headers=neha, json={"videos": "off"})).json()
    assert d["levels"]["videos"] == "off" and d["levels"]["posts"] == "relevant"

    # About and shared activity.
    about = (await client.get(f"{P}/arjun/about", headers=neha)).json()
    assert about["username"] == "arjun" and about["followers"] >= 1 and about["joined"]
    shared = (await client.get(f"{P}/arjun/shared", headers=neha)).json()
    assert shared["you_follow"] and "both_follow" in shared

    # Hide moments from neha: she can't see arjun's moment any more.
    assert (await client.put(f"{P}/neha/hide-moments", headers=arjun, json={"hidden": True})).json()["hidden_moments"]
    rail = (await client.get("/api/v1/social/moments/user/arjun", headers=neha)).json()
    assert rail["items"] == []
    await client.put(f"{P}/neha/hide-moments", headers=arjun, json={"hidden": False})
    assert (await client.get("/api/v1/social/moments/user/arjun", headers=neha)).json()["items"]

    rel = (await client.get(f"{P}/neha/relationship", headers=arjun)).json()
    assert rel["follows_you"] and not rel["restricted"]

    # Restrict: DM goes to Requests.
    assert (await client.put(f"{P}/neha/restrict", headers=arjun, json={"restricted": True})).json()["restricted"]
    await client.post("/api/v1/messaging/peers/arjun/messages", headers=neha, json={"text": "hey", "attachments": []})
    convs = (await client.get("/api/v1/messaging/conversations", headers=arjun)).json()
    neha_chat = next(c for c in convs if c["peer"]["username"] == "neha")
    assert neha_chat["folder"] == "requests"

    # Report, remove follower.
    assert (await client.post(f"{P}/neha/report", headers=arjun, json={"reason": "Spam"})).status_code == 204
    assert (await client.delete(f"{P}/neha/follower", headers=arjun)).status_code == 204
    assert not (await client.get(f"{P}/neha/relationship", headers=arjun)).json()["follows_you"]
    assert (await client.delete(f"{P}/neha/follower", headers=arjun)).status_code == 404
