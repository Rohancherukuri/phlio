"""Foxy Timeline: tasks, repeats, inbox, and Foxy planning a day."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.api.v1.timeline import parse_prompt

pytestmark = pytest.mark.asyncio


def test_parse_prompt() -> None:
    tasks = parse_prompt("gym at 7am, study for 2 hours, dinner with Neha at 8pm")
    assert [t["title"] for t in tasks] == ["Gym", "Study", "Dinner with Neha"]
    assert tasks[0]["start"] == 7 * 60 and tasks[0]["icon"] == "fitness"
    assert tasks[1]["duration_min"] == 120 and tasks[1]["start"] is None
    assert tasks[2]["start"] == 20 * 60 and tasks[2]["icon"] == "food"


async def test_tasks_repeat_toggle_inbox(client: AsyncClient, auth_headers: dict) -> None:
    r = await client.post("/api/v1/timeline/tasks", headers=auth_headers, json={
        "title": "Morning run", "date": "2026-05-11", "start": "07:00", "duration_min": 30,
        "icon": "fitness", "color": "#22C55E", "repeat": "weekdays"})
    assert r.status_code == 201, r.text
    tid = r.json()["id"]
    assert (await client.post("/api/v1/timeline/tasks", headers=auth_headers,
                              json={"title": "x", "color": "orange"})).status_code == 422
    await client.post("/api/v1/timeline/tasks", headers=auth_headers, json={"title": "Call mom"})
    week = (await client.get("/api/v1/timeline", headers=auth_headers,
                             params={"start": "2026-05-11", "days": 7})).json()["days"]
    assert [len(d["tasks"]) for d in week] == [1, 1, 1, 1, 1, 0, 0]
    assert week[0]["dots"] == ["#22C55E"]
    r = await client.post(f"/api/v1/timeline/tasks/{tid}/toggle", headers=auth_headers, json={"date": "2026-05-12"})
    assert r.json()["done"] is True
    week = (await client.get("/api/v1/timeline", headers=auth_headers,
                             params={"start": "2026-05-11", "days": 3})).json()["days"]
    assert [d["tasks"][0]["done"] for d in week] == [False, True, False]
    inbox = (await client.get("/api/v1/timeline/inbox", headers=auth_headers)).json()["items"]
    assert [t["title"] for t in inbox] == ["Call mom"]
    r = await client.patch(f"/api/v1/timeline/tasks/{inbox[0]['id']}", headers=auth_headers,
                           json={"date": "2026-05-13", "start": "18:00", "color": "#EC4899"})
    assert r.json()["date"] == "2026-05-13" and r.json()["start"] == "18:00"
    assert (await client.get("/api/v1/timeline/inbox", headers=auth_headers)).json()["items"] == []
    assert (await client.delete(f"/api/v1/timeline/tasks/{tid}", headers=auth_headers)).status_code == 204


async def test_foxy_plans_a_day(client: AsyncClient, auth_headers: dict) -> None:
    body = {"date": "2026-06-02", "prompt": "gym at 7am, study 2 hours", "sources": ["routine", "book", "social"]}
    r = await client.post("/api/v1/timeline/foxy", headers=auth_headers, json=body)
    assert r.status_code == 200, r.text
    added = r.json()["added"]
    titles = [t["title"] for t in added]
    assert titles[0] == "Gym" and "Rise and shine" in titles and "Wind down" in titles and "Study" in titles
    study = next(t for t in added if t["title"] == "Study")
    assert study["start"] and study["duration_min"] == 120
    # Planning again doesn't duplicate.
    again = (await client.post("/api/v1/timeline/foxy", headers=auth_headers, json=body)).json()
    assert again["added"] == []
