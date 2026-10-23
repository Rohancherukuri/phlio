"""Tests for browsing the shop marketplace and favoriting."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_cart_quantity_totals_validation_and_removal(client, auth_headers):
    assert (await client.get('/api/v1/shop/cart')).status_code == 401
    product = (await client.get('/api/v1/shop/products', headers=auth_headers)).json()['items'][0]
    path = '/api/v1/shop/cart/' + product['id']
    result = await client.put(path, headers=auth_headers, json={'quantity': 2})
    assert result.status_code == 200
    assert result.json()['totals'][product['currency']] == 2 * product['price_minor_units']
    assert (await client.get('/api/v1/shop/cart', headers=auth_headers)).json()['count'] == 2
    for quantity in (-1, 100):
        assert (await client.put(path, headers=auth_headers, json={'quantity': quantity})).status_code == 422
    assert (await client.put('/api/v1/shop/cart/missing', headers=auth_headers, json={'quantity': 1})).status_code == 404
    assert (await client.put(path, headers=auth_headers, json={'quantity': 0})).json()['count'] == 0


async def test_cart_is_scoped_to_signed_in_user(client, auth_headers):
    product = (await client.get('/api/v1/shop/products', headers=auth_headers)).json()['items'][0]
    await client.put('/api/v1/shop/cart/'+product['id'], headers=auth_headers, json={'quantity': 3})
    login = await client.post('/api/v1/auth/login', json={'identifier': 'neha', 'password': 'password123'})
    other = {'Authorization':'Bearer '+login.json()['tokens']['access_token']}
    assert (await client.get('/api/v1/shop/cart', headers=other)).json()['items'] == []


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
