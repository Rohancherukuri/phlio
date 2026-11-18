"""Community fact checks: proposing, rating and the bridging rule."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.api.v1 import fact_checks as fc

pytestmark = pytest.mark.asyncio
NOTE = {
    "target": "social/post_123",
    "classification": "missing_context",
    "text": "The photo is from a 2019 flood, not this week's storm; see the original agency report.",
    "sources": ["https://www.example.org/report", "https://news.example.com/2019/floods"],
}


async def register(client: AsyncClient, name: str) -> dict:
    r = await client.post("/api/v1/auth/register", json={
        "full_name": name.title(), "username": name, "email": f"{name}@example.com",
        "password": "correct-horse-battery", "interests": ["news"]})
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


def test_bridging_rule_needs_both_sides() -> None:
    a = [f"a{i}" for i in range(5)]
    b = [f"b{i}" for i in range(5)]
    ratings = []
    for k in range(4):  # history that splits raters into two camps
        ratings += [(u, f"pa{k}", 1.0) for u in a] + [(u, f"pa{k}", 0.0) for u in b]
        ratings += [(u, f"pb{k}", 0.0) for u in a] + [(u, f"pb{k}", 1.0) for u in b]
    ratings += [(u, "bridge", 1.0) for u in a + b]          # both camps agree
    ratings += [(u, "one_sided", 1.0) for u in a]            # only one camp
    ratings += [(u, "bad", 0.0) for u in a[:3] + b[:3]]      # nobody likes it
    notes, raters = fc.score(ratings)
    assert fc.status_for("bridge", ratings, notes, raters)["status"] == "helpful"
    assert fc.status_for("one_sided", ratings, notes, raters)["status"] == "needs_more_ratings"
    assert fc.status_for("bad", ratings, notes, raters)["status"] == "not_helpful"


async def test_propose_rate_and_show(client: AsyncClient, auth_headers: dict) -> None:
    made = await client.post("/api/v1/fact-checks", headers=auth_headers, json=NOTE)
    assert made.status_code == 201, made.text
    note = made.json()
    assert note["status"] == "needs_more_ratings" and note["sources"][0]["host"] == "example.org"
    assert (await client.post("/api/v1/fact-checks", headers=auth_headers, json=NOTE)).status_code == 409
    assert (await client.put(f"/api/v1/fact-checks/{note['id']}/rating", headers=auth_headers,
                             json={"rating": "helpful"})).status_code == 403  # own note

    summary = (await client.get("/api/v1/fact-checks", headers=auth_headers, params={"target": NOTE["target"]})).json()
    assert summary["shown"] == [] and summary["proposed"][0]["id"] == note["id"]

    # Two camps who disagree on other notes both find this one helpful.
    camp_a = [await register(client, f"alpha{i}") for i in range(3)]
    camp_b = [await register(client, f"beta{i}") for i in range(3)]
    for k in range(3):
        for side, mine in ((camp_a, "a"), (camp_b, "b")):
            other = await client.post("/api/v1/fact-checks", headers=side[k], json={
                **NOTE, "target": f"news/split_{mine}{k}", "text": f"Partisan framing number {k} for camp {mine} readers."})
            nid = other.json()["id"]
            for h in camp_a + camp_b:
                if h is side[k]:
                    continue
                verdict = "helpful" if (h in side) else "not_helpful"
                await client.put(f"/api/v1/fact-checks/{nid}/rating", headers=h, json={"rating": verdict})
    for h in camp_a + camp_b:
        r = await client.put(f"/api/v1/fact-checks/{note['id']}/rating", headers=h,
                             json={"rating": "helpful", "reasons": ["good_sources"]})
        assert r.status_code == 200
    summary = (await client.get("/api/v1/fact-checks", headers=auth_headers, params={"target": NOTE["target"]})).json()
    assert [n["id"] for n in summary["shown"]] == [note["id"]], summary

    batch = (await client.post("/api/v1/fact-checks/batch", headers=auth_headers,
                               json={"targets": [NOTE["target"], "rooms/nothing", "bad target"]})).json()
    assert batch[NOTE["target"]]["shown"][0]["id"] == note["id"] and batch["rooms/nothing"]["proposed_count"] == 0
    assert "bad target" not in batch

    queue = (await client.get("/api/v1/fact-checks/queue", headers=camp_a[0])).json()["items"]
    assert note["id"] not in [n["id"] for n in queue]


async def test_validation(client: AsyncClient, auth_headers: dict) -> None:
    bad = [
        {**NOTE, "sources": ["http://insecure.example.com"]},
        {**NOTE, "sources": []},
        {**NOTE, "text": "too short"},
        {**NOTE, "target": "shop/thing"},
    ]
    for body in bad:
        assert (await client.post("/api/v1/fact-checks", headers=auth_headers, json=body)).status_code == 422
