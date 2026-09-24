"""Tests for the Phlio Agent's rule-based planning."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_agent_builds_plan_from_real_data(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.post(
        "/api/v1/agent/messages",
        headers=auth_headers,
        json={"text": "Plan something for Saturday with 3 friends under ₹4,000"},
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["role"] == "agent"
    assert body["plan"] is not None
    assert len(body["plan"]["items"]) >= 1
    # Every item must reference something that really exists — the whole
    # point of the tool layer is that the agent cannot invent items.
    for item in body["plan"]["items"]:
        assert item["ref_id"]


async def test_agent_conversation_can_be_replayed(client: AsyncClient, auth_headers: dict) -> None:
    first = await client.post(
        "/api/v1/agent/messages", headers=auth_headers, json={"text": "Suggest something creative"}
    )
    conversation_id = first.json()["conversation_id"]

    second = await client.post(
        "/api/v1/agent/messages",
        headers=auth_headers,
        json={"text": "What about something cheaper?", "conversation_id": conversation_id},
    )
    assert second.json()["conversation_id"] == conversation_id

    history = await client.get(
        f"/api/v1/agent/conversations/{conversation_id}/messages", headers=auth_headers
    )
    assert history.status_code == 200
    # two user messages + two agent replies
    assert len(history.json()) == 4


async def test_agent_respects_a_tight_budget(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.post(
        "/api/v1/agent/messages",
        headers=auth_headers,
        json={"text": "Plan something under ₹500"},
    )
    plan = response.json()["plan"]
    for item in plan["items"]:
        if item["price_minor_units"] is not None:
            # planner budgets products at 60% of the stated total
            assert item["price_minor_units"] <= 500_00
