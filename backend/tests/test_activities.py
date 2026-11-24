"""Phlio Move: activities, privacy trimming, Social posts, kudos, and voice /
music comments on the activity's post."""

from __future__ import annotations

import json

import pytest
from httpx import AsyncClient

from app.api.v1.activities import route_length, splits, trim_endpoints

pytestmark = pytest.mark.asyncio


def line(n: int = 60, step: float = 0.0005) -> list[list[float]]:
    # ~55 m between points going north, 6 s apart (≈ 5:00 /km).
    return [[12.97 + i * step, 77.59, i * 10.0] for i in range(n)]


def test_geometry() -> None:
    route = line()
    assert 3200 < route_length(route) < 3300
    trimmed = trim_endpoints(route)
    assert 2700 < route_length(trimmed) < 2950
    assert trimmed[0] != route[0] and trimmed[-1] != route[-1]
    s = splits(route)
    assert [x["km"] for x in s[:3]] == [1, 2, 3] and 170 <= s[0]["seconds"] <= 200


async def login(client, name):
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


async def test_record_post_react_comment(client: AsyncClient, auth_headers: dict) -> None:
    neha = await login(client, "neha")
    # Neha follows the poster so she hears about it.
    await client.post("/api/v1/social/follow/arjun", headers=neha)
    assert (await client.get("/api/v1/activities/sports", headers=auth_headers)).json()["groups"][0]["name"] == "Foot"
    body = dict(sport="run", description="Finish strong @neha", route=line(), elapsed_s=600, tagged=["neha"])
    r = await client.post("/api/v1/activities", headers=auth_headers, json=body)
    assert r.status_code == 201, r.text
    act = r.json()
    assert act["title"].endswith("Run") and act["post_id"] and act["image_url"].startswith("/media/activities/")
    assert 3200 < act["distance_m"] < 3300 and act["pace_s_per_km"] and act["tagged"][0]["username"] == "neha"

    # Others see the trimmed route; the owner sees it all.
    mine = (await client.get(f"/api/v1/activities/{act['id']}", headers=auth_headers)).json()
    theirs = (await client.get(f"/api/v1/activities/{act['id']}", headers=neha)).json()
    assert len(theirs["route"]) < len(mine["route"]) == 60
    assert (await client.get(f"/api/v1/activities/by-post/{act['post_id']}", headers=neha)).json()["id"] == act["id"]

    notes = (await client.get("/api/v1/notifications", headers=neha)).json()
    items = notes["items"] if isinstance(notes, dict) else notes
    kinds = {n["kind"] for n in items if (n.get("data") or {}).get("activity") == act["id"]}
    assert "activity_tag" in kinds

    r = await client.put(f"/api/v1/activities/{act['id']}/kudos", headers=neha, json={"emoji": "🔥"})
    assert r.json()["kudos"] == {"🔥": 1}
    assert (await client.put(f"/api/v1/activities/{act['id']}/kudos", headers=neha, json={"emoji": "💩"})).status_code == 422

    # Voice note and a 30 s song snippet as comments on the activity post.
    url = f"/api/v1/social/content/{act['post_id']}/comments"
    r = await client.post(url, headers=neha, data={"audio_seconds": "4.2"},
                          files={"audio": ("note.m4a", b"\0" * 2048, "audio/mp4")})
    assert r.status_code == 201, r.text
    assert r.json()["audio_url"].startswith("/media/social_comments/voice/")
    song = dict(title="Sunrise", artist="Phlio", url="/media/stream_music/x.mp3", clip_start=12, clip_length=90)
    r = await client.post(url, headers=neha, data={"music": json.dumps(song)})
    assert r.status_code == 201 and r.json()["music"]["clip_length"] == 30
    assert (await client.post(url, headers=neha, data={"music": json.dumps(dict(song, url="javascript:x"))})).status_code == 422

    # Kudos notification lets the owner reply in the activity's thread.
    owner_notes = (await client.get("/api/v1/notifications", headers=auth_headers)).json()
    owner_items = owner_notes["items"] if isinstance(owner_notes, dict) else owner_notes
    kudos_note = next(n for n in owner_items if n["kind"] == "kudos")
    assert kudos_note["data"]["path"] == f"social/{act['post_id']}" and kudos_note["data"]["image"]

    # Phlio Move in the profile dashboard (Foxy tab).
    dash = (await client.get("/api/v1/profile/dashboard", headers=auth_headers, params={"days": 7})).json()
    move = {s["id"]: s for s in dash["sections"]}["agent"]["extra"]["move"]
    assert move["count"] >= 1 and move["distance_m"] > 3000 and move["kudos"] >= 1
    assert len(move["days"]) == 7 and move["sports"][0]["sport"] == "run" and move["longest"]

    summary = (await client.get("/api/v1/activities/summary", headers=auth_headers)).json()
    assert summary["week"]["count"] >= 1 and summary["streak_days"] >= 1

    # Private activities: no post, invisible to others.
    r = await client.post("/api/v1/activities", headers=auth_headers,
                          json=dict(sport="weight_training", elapsed_s=1800, visibility="only_me"))
    private = r.json()
    assert private["post_id"] is None
    assert (await client.get(f"/api/v1/activities/{private['id']}", headers=neha)).status_code == 404

    assert (await client.delete(f"/api/v1/activities/{act['id']}", headers=auth_headers)).status_code == 204
    assert (await client.get(f"/api/v1/activities/{act['id']}", headers=auth_headers)).status_code == 404
