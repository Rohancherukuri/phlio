"""Smart filters: saved with moments / snaps, editable afterwards, presets."""

from __future__ import annotations

import io
import json

import pytest
from httpx import AsyncClient
from PIL import Image

pytestmark = pytest.mark.asyncio

SPEC = {
    "look": "clarendon", "effect": "grain", "strength": 0.8,
    "overlays": [
        {"type": "weather", "style": "big", "color": "#FFFFFF", "x": 0.5, "y": 0.2, "scale": 1.2,
         "data": {"temp": 27, "unit": "C", "icon": "☀️", "city": "Hyderabad"}},
        {"type": "time", "style": "lcd", "x": 0.2, "y": 0.9, "data": {"at": "2026-11-18T10:00:00+05:30"}},
    ],
}


def png() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (64, 64), (200, 80, 120)).save(buf, "PNG")
    return buf.getvalue()


async def test_moment_with_filter_then_edit(client: AsyncClient, auth_headers: dict) -> None:
    r = await client.post("/api/v1/social/moments", headers=auth_headers,
                          files={"file": ("m.png", png(), "image/png")},
                          data={"filter_spec": json.dumps(SPEC)})
    assert r.status_code == 201, r.text
    m = r.json()
    assert m["filter"] == "clarendon+grain" and m["filter_spec"]["overlays"][0]["data"]["city"] == "Hyderabad"

    edited = {**SPEC, "look": "moon", "effect": None, "overlays": [{**SPEC["overlays"][1], "style": "pill", "x": 0.7}]}
    e = await client.put(f"/api/v1/social/filters/moments/{m['id']}", headers=auth_headers, json={"spec": edited})
    assert e.status_code == 200 and e.json()["filter"] == "moon"
    again = (await client.get(f"/api/v1/social/moments/user/arjun", headers=auth_headers)).json()
    items = again["items"] if isinstance(again, dict) else again
    mine = next(i for i in items if i["id"] == m["id"])
    assert mine["filter_spec"]["overlays"][0]["style"] == "pill"

    other = await client.post("/api/v1/auth/login", json={"identifier": "neha", "password": "password123"})
    neha = {"Authorization": f"Bearer {other.json()['tokens']['access_token']}"}
    assert (await client.put(f"/api/v1/social/filters/moments/{m['id']}", headers=neha, json={"spec": edited})).status_code == 403


async def test_snap_filter_and_validation(client: AsyncClient, auth_headers: dict) -> None:
    r = await client.post("/api/v1/social/memories", headers=auth_headers,
                          files={"file": ("s.png", png(), "image/png")},
                          data={"filter_spec": json.dumps(SPEC), "audience": "friends"})
    assert r.status_code == 201, r.text
    snap = r.json()
    assert snap["filter_spec"]["look"] == "clarendon"
    ok = await client.put(f"/api/v1/social/filters/memories/{snap['id']}", headers=auth_headers,
                          json={"spec": {"look": "normal", "overlays": []}})
    assert ok.status_code == 200 and ok.json()["filter"] == "normal"

    bad_style = {**SPEC, "overlays": [{"type": "time", "style": "gauge"}]}
    r = await client.post("/api/v1/social/memories", headers=auth_headers,
                          files={"file": ("s.png", png(), "image/png")}, data={"filter_spec": json.dumps(bad_style)})
    assert r.status_code == 422
    too_many = {**SPEC, "overlays": [SPEC["overlays"][1]] * 7}
    assert (await client.put(f"/api/v1/social/filters/memories/{snap['id']}", headers=auth_headers,
                             json={"spec": too_many})).status_code == 422


async def test_presets(client: AsyncClient, auth_headers: dict) -> None:
    made = await client.post("/api/v1/social/filters/presets", headers=auth_headers, json={"name": "Sunny day", "spec": SPEC})
    assert made.status_code == 201
    preset = made.json()
    assert preset["spec"]["overlays"][0]["data"] == {}  # captured values aren't kept
    listed = (await client.get("/api/v1/social/filters/presets", headers=auth_headers)).json()["items"]
    assert [p["name"] for p in listed] == ["Sunny day"]
    renamed = await client.put(f"/api/v1/social/filters/presets/{preset['id']}", headers=auth_headers,
                               json={"name": "Golden hour", "spec": SPEC})
    assert renamed.json()["name"] == "Golden hour"
    assert (await client.delete(f"/api/v1/social/filters/presets/{preset['id']}", headers=auth_headers)).status_code == 204
    assert (await client.get("/api/v1/social/filters/presets", headers=auth_headers)).json()["items"] == []


async def test_avatar_config(client: AsyncClient, auth_headers: dict) -> None:
    assert (await client.get("/api/v1/social/avatar", headers=auth_headers)).json() == {"avatar": None}
    cfg = {"skin": "#8D5524", "hair": "curly", "hair_color": "#111111", "glasses": "round", "top": "kurta",
           "top_color": "#F5636B", "accessory": "bindi"}
    saved = await client.put("/api/v1/social/avatar", headers=auth_headers, json=cfg)
    assert saved.status_code == 200 and saved.json()["avatar"]["face"] == "oval"
    theirs = await client.get("/api/v1/social/avatar/u/arjun", headers=auth_headers)
    assert theirs.json()["avatar"]["hair"] == "curly"
    assert (await client.put("/api/v1/social/avatar", headers=auth_headers, json={"hair": "mohawk"})).status_code == 422
    assert (await client.put("/api/v1/social/avatar", headers=auth_headers, json={"skin": "red"})).status_code == 422


async def test_avatar_snap_decoration(client: AsyncClient, auth_headers: dict) -> None:
    deco = [{"type": "avatar", "x": 0.5, "y": 0.6, "data": {"name": "Arjun", "avatar": {"hair": "afro", "glasses": "sun"}}}]
    r = await client.post("/api/v1/social/memories", headers=auth_headers,
                          files={"file": ("s.png", png(), "image/png")}, data={"decorations": json.dumps(deco)})
    assert r.status_code == 201, r.text
    assert r.json()["decorations"][0]["data"]["avatar"]["hair"] == "afro"
    bad = [{"type": "avatar", "data": {"avatar": {"hair": "mohawk"}}}]
    r = await client.post("/api/v1/social/memories", headers=auth_headers,
                          files={"file": ("s.png", png(), "image/png")}, data={"decorations": json.dumps(bad)})
    assert r.status_code == 422
