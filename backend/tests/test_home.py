"""Tests for the cross-domain home overview aggregation."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_home_overview_aggregates_all_domains(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get("/api/v1/home/overview", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()

    assert body["greeting_name"] == "Arjun"
    assert len(body["quick_actions"]) == 8
    assert any(a["kind"] == "shop" and a["is_available"] for a in body["quick_actions"])
    # Pay and Book are live domains now; Stream/News are still roadmap.
    assert any(a["kind"] == "pay" and a["is_available"] for a in body["quick_actions"])
    assert any(a["kind"] == "book" and a["is_available"] for a in body["quick_actions"])
    assert any(a["kind"] == "stream" and not a["is_available"] for a in body["quick_actions"])
    assert body["featured_rooms"]
    assert body["featured_products"]
    assert body["recent_posts"]


async def test_home_overview_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/api/v1/home/overview")
    assert response.status_code == 401
