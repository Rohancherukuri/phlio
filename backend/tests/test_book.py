"""Tests for the Phlio Book endpoints."""

from __future__ import annotations

import datetime as dt

async def test_browse_listings_public_discovery(client):
    # Discovery is public, like Rooms discovery; only creating bookings
    # requires a token.
    response = await client.get("/api/v1/book/listings")
    assert response.status_code == 200


async def test_browse_listings_returns_seeded_data(client, auth_headers):
    response = await client.get("/api/v1/book/listings", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    titles = [item["title"] for item in body["items"]]
    assert "Movie: Kingdom" in titles
    assert any(item["is_free"] for item in body["items"])


async def test_browse_listings_category_filter(client, auth_headers):
    response = await client.get(
        "/api/v1/book/listings",
        params={"category": "entertainment"},
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["items"]
    assert all(i["category"] == "entertainment" for i in response.json()["items"])


async def test_create_booking_and_list_mine(client, auth_headers):
    payload = {
        "listing_id": "bl_movie_kingdom",
        "date": (dt.date.today() + dt.timedelta(days=3)).isoformat(),
        "time": "19:00",
        "participants": 3,
    }
    response = await client.post(
        "/api/v1/book/bookings", json=payload, headers=auth_headers
    )
    assert response.status_code == 201
    booking = response.json()
    assert booking["status"] == "confirmed"
    assert booking["title"] == "Movie: Kingdom"
    assert booking["participants"] == 3

    # Duplicate booking for the same listing/date conflicts.
    duplicate = await client.post(
        "/api/v1/book/bookings", json=payload, headers=auth_headers
    )
    assert duplicate.status_code == 409

    mine = await client.get("/api/v1/book/bookings", headers=auth_headers)
    assert mine.status_code == 200
    assert any(b["id"] == booking["id"] for b in mine.json()["items"])


async def test_create_booking_unknown_listing(client, auth_headers):
    payload = {
        "listing_id": "bl_missing",
        "date": (dt.date.today() + dt.timedelta(days=1)).isoformat(),
    }
    response = await client.post(
        "/api/v1/book/bookings", json=payload, headers=auth_headers
    )
    assert response.status_code == 404


async def test_create_booking_past_date_rejected(client, auth_headers):
    payload = {
        "listing_id": "bl_movie_kingdom",
        "date": (dt.date.today() - dt.timedelta(days=1)).isoformat(),
    }
    response = await client.post(
        "/api/v1/book/bookings", json=payload, headers=auth_headers
    )
    assert response.status_code == 422
