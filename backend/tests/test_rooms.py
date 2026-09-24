"""Tests for room discovery, membership, and messaging."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_discover_lists_seeded_rooms(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get("/api/v1/rooms/discover", headers=auth_headers)
    assert response.status_code == 200
    names = {r["name"] for r in response.json()["items"]}
    assert "Tech & AI" in names


async def test_discover_filters_by_category(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get(
        "/api/v1/rooms/discover", headers=auth_headers, params={"category": "art_and_creators"}
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert all(r["category"] == "art_and_creators" for r in items)
    assert len(items) >= 1


async def test_create_room_and_join(client: AsyncClient, auth_headers: dict) -> None:
    create = await client.post(
        "/api/v1/rooms",
        headers=auth_headers,
        json={
            "name": "Weekend Hikers",
            "description": "Trail meetups every Saturday.",
            "category": "travel_and_explore",
            "icon": "🥾",
        },
    )
    assert create.status_code == 201, create.text
    room = create.json()
    assert room["member_count"] == 1  # creator auto-joins

    mine = await client.get("/api/v1/rooms/mine", headers=auth_headers)
    assert any(r["id"] == room["id"] for r in mine.json())


async def test_send_and_list_messages(client: AsyncClient, auth_headers: dict) -> None:
    rooms = await client.get("/api/v1/rooms/discover", headers=auth_headers)
    room_id = rooms.json()["items"][0]["id"]

    sent = await client.post(
        f"/api/v1/rooms/{room_id}/messages", headers=auth_headers, json={"text": "Hello room!"}
    )
    assert sent.status_code == 201, sent.text

    messages = await client.get(f"/api/v1/rooms/{room_id}/messages", headers=auth_headers)
    texts = [m["text"] for m in messages.json()["items"]]
    assert "Hello room!" in texts


async def test_empty_message_is_rejected(client: AsyncClient, auth_headers: dict) -> None:
    rooms = await client.get("/api/v1/rooms/discover", headers=auth_headers)
    room_id = rooms.json()["items"][0]["id"]

    response = await client.post(
        f"/api/v1/rooms/{room_id}/messages", headers=auth_headers, json={"text": "   "}
    )
    assert response.status_code == 422


async def test_message_in_unknown_room_is_404(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.post(
        "/api/v1/rooms/rm_does_not_exist/messages", headers=auth_headers, json={"text": "hi"}
    )
    assert response.status_code == 404
