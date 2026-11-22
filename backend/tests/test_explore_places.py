"""Places search, a place's posts and the area map in Social explore."""

from __future__ import annotations

import io
import json

import pytest
from httpx import AsyncClient
from PIL import Image

pytestmark = pytest.mark.asyncio


def png() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (8, 8), (200, 80, 40)).save(buf, "PNG")
    return buf.getvalue()


async def login(client, name):
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


async def share(client, headers, place, audience="everyone"):
    r = await client.post("/api/v1/social/memories", headers=headers, files={"file": ("e.png", png(), "image/png")},
                          data={"kind": "experience", "audience": audience, "location": json.dumps(place)})
    assert r.status_code == 201, r.text
    return r.json()


async def test_places_search_posts_and_area(client: AsyncClient, auth_headers: dict) -> None:
    cafe = {"name": "Cooking Retreat Mysore", "address": "Gokulam, Mysuru", "lat": 12.3290, "lng": 76.6268}
    near = dict(cafe, lat=12.3292, lng=76.6270)  # same spot, a few metres off
    far = {"name": "Brigade Road Cooking Studio", "address": "Bengaluru", "lat": 12.9716, "lng": 77.6070}
    a = await share(client, auth_headers, cafe)
    await share(client, auth_headers, near)
    await share(client, auth_headers, far)
    neha = await login(client, "neha")
    hidden = await share(client, neha, dict(cafe, name="Cooking Retreat Mysore"), audience="friends")

    r = await client.get("/api/v1/explore/places/search", headers=auth_headers, params={"q": "cooking"})
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    names = [p["name"] for p in items]
    assert names[0] == "Cooking Retreat Mysore" and items[0]["posts"] == 2  # neha (not a friend) is hidden
    assert "Brigade Road Cooking Studio" in names and items[0]["cover"]["id"] in {a["id"]} | {p["cover"]["id"] for p in items}
    assert r.json()["external"] in {"unavailable", "none", "google"}

    r = await client.get("/api/v1/explore/places/posts", headers=auth_headers,
                         params={"lat": cafe["lat"], "lng": cafe["lng"], "name": cafe["name"], "sort": "recent"})
    body = r.json()
    assert body["place"]["posts"] == 2 and all(x["id"] != hidden["id"] for x in body["items"])
    assert body["items"][0]["place"]["name"] == "Cooking Retreat Mysore"

    r = await client.get("/api/v1/explore/places/area", headers=auth_headers,
                         params={"lat": 12.33, "lng": 76.63, "radius_km": 5})
    assert len(r.json()["items"]) == 2 and len(r.json()["places"]) == 1

    r = await client.put("/api/v1/explore/places/saved", headers=auth_headers, json={**cafe, "saved": True})
    assert r.json() == {"saved": True}
    r = await client.get("/api/v1/explore/places/posts", headers=auth_headers, params={"lat": cafe["lat"], "lng": cafe["lng"]})
    assert r.json()["place"]["saved"] is True
