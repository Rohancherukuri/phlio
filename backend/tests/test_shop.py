"""Tests for browsing the shop marketplace and favoriting."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_browse_returns_seeded_products(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get("/api/v1/shop/products", headers=auth_headers)
    assert response.status_code == 200
    titles = {p["title"] for p in response.json()["items"]}
    assert "Handcrafted Wooden Lamp" in titles


async def test_browse_respects_max_price(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get(
        "/api/v1/shop/products",
        headers=auth_headers,
        params={"max_price_minor_units": 2_000_00},
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert items, "expected at least one product under ₹2,000"
    assert all(p["price_minor_units"] <= 2_000_00 for p in items)


async def test_browse_respects_category(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get(
        "/api/v1/shop/products",
        headers=auth_headers,
        params={"category": "art_and_handmade"},
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert items
    assert all(p["category"] == "art_and_handmade" for p in items)


async def test_toggle_favorite(client: AsyncClient, auth_headers: dict) -> None:
    products = await client.get("/api/v1/shop/products", headers=auth_headers)
    product_id = products.json()["items"][0]["id"]
    before = products.json()["items"][0]["favorite_count"]

    favorited = await client.post(f"/api/v1/shop/products/{product_id}/favorite", headers=auth_headers)
    assert favorited.json()["favorite_count"] == before + 1
    assert favorited.json()["favorited_by_me"] is True

    unfavorited = await client.post(f"/api/v1/shop/products/{product_id}/favorite", headers=auth_headers)
    assert unfavorited.json()["favorite_count"] == before


async def test_featured_sellers(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get("/api/v1/shop/sellers/featured", headers=auth_headers)
    assert response.status_code == 200
    handles = {s["handle"] for s in response.json()}
    assert "@artbykiara" in handles


async def test_unknown_product_is_404(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get("/api/v1/shop/products/prd_does_not_exist", headers=auth_headers)
    assert response.status_code == 404
