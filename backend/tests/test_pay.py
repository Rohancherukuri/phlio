"""Tests for the Phlio Pay endpoints (simulated ledger)."""

from __future__ import annotations

async def test_overview_requires_auth(client):
    response = await client.get("/api/v1/pay/overview")
    assert response.status_code == 401


async def test_overview_returns_seeded_wallet(client, auth_headers):
    response = await client.get("/api/v1/pay/overview", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["balance_minor_units"] == 4_280_50
    assert body["upi_handle"] == "arjun@phlio"
    assert len(body["recent_transactions"]) == 3


async def test_send_money_success(client, auth_headers):
    payload = {
        "counterparty": "Neha Kapoor",
        "amount_minor_units": 50_000,
        "note": "Movie tickets",
    }
    response = await client.post(
        "/api/v1/pay/transactions", json=payload, headers=auth_headers
    )
    assert response.status_code == 201
    txn = response.json()
    assert txn["type"] == "send"
    assert txn["status"] == "success"

    overview = await client.get("/api/v1/pay/overview", headers=auth_headers)
    assert overview.json()["balance_minor_units"] == 4_280_50 - 50_000


async def test_send_money_insufficient_balance(client, auth_headers):
    payload = {
        "counterparty": "Someone",
        "amount_minor_units": 999_999_00,
        "note": "Too much",
    }
    response = await client.post(
        "/api/v1/pay/transactions", json=payload, headers=auth_headers
    )
    assert response.status_code == 422


async def test_send_money_invalid_amount(client, auth_headers):
    response = await client.post(
        "/api/v1/pay/transactions",
        json={"counterparty": "Someone", "amount_minor_units": 0},
        headers=auth_headers,
    )
    assert response.status_code == 422


async def test_split_flow(client, auth_headers):
    payload = {
        "total_minor_units": 3_500_00,
        "participant_names": ["Neha", "Kiara", "Rohan"],
        "note": "Saturday plan",
    }
    response = await client.post("/api/v1/pay/splits", json=payload, headers=auth_headers)
    assert response.status_code == 201
    split = response.json()
    assert len(split["participants"]) == 4
    per_head = 3_500_00 // 4
    amounts = sorted(p["amount_minor_units"] for p in split["participants"])
    # Equal shares; the remainder lands on one participant ("You").
    assert amounts[0] == per_head
    assert sum(p["amount_minor_units"] for p in split["participants"]) == 3_500_00

    listed = await client.get("/api/v1/pay/splits", headers=auth_headers)
    assert listed.status_code == 200
    assert any(s["id"] == split["id"] for s in listed.json()["items"])
