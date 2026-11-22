"""All-in-one profile dashboard: every platform, full Pay analytics."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_dashboard_covers_every_platform(client: AsyncClient, auth_headers: dict) -> None:
    for note, amount in (("Dinner at the cafe", 120_000), ("Uber to airport", 45_000)):
        r = await client.post("/api/v1/pay/transactions", headers=auth_headers,
                              json={"counterparty": "Neha Kapoor", "amount_minor_units": amount, "note": note})
        assert r.status_code == 201, r.text
    for text in ("hi", "how are you?"):
        await client.post("/api/v1/messaging/peers/neha/messages", headers=auth_headers, json={"text": text})
    products = (await client.get("/api/v1/shop/products", headers=auth_headers)).json()["items"]
    pid = products[0]["id"]
    assert (await client.put(f"/api/v1/content/shop/{pid}/actions/viewed", headers=auth_headers)).status_code == 200
    await client.put(f"/api/v1/shop/cart/{pid}", headers=auth_headers, json={"quantity": 2})

    r = await client.get("/api/v1/profile/dashboard", headers=auth_headers, params={"days": 7})
    assert r.status_code == 200, r.text
    data = r.json()
    sections = {s["id"]: s for s in data["sections"]}
    assert list(sections) == ["social", "pay", "messages", "rooms", "stream", "news", "shop", "book"]
    for s in sections.values():
        assert {"headline", "kpis", "insights", "has_data"} <= set(s)
        if s["series"]:
            assert len(s["series"]["days"]) == 7

    pay = sections["pay"]
    kpis = {k["id"]: k for k in pay["kpis"]}
    assert kpis["sent"]["value"] >= 165_000 and pay["headline"]["format"] == "money"
    cats = {i["label"]: i["value"] for i in pay["breakdown"]["items"]}
    assert cats["Food & drinks"] >= 120_000 and cats["Travel"] >= 45_000
    assert pay["extra"]["biggest"]["amount"] >= 120_000
    assert sum(d["sent"] for d in pay["series"]["days"]) == kpis["sent"]["value"]
    assert any("% of what you spent" in line for line in pay["insights"])
    assert len(pay["extra"]["weekday"]) == 7 and len(pay["extra"]["hours"]) == 24

    msgs = {k["id"]: k["value"] for k in sections["messages"]["kpis"]}
    assert msgs["sent"] >= 2 and sections["messages"]["top"]["items"][0]["username"] == "neha"

    shop = {k["id"]: k["value"] for k in sections["shop"]["kpis"]}
    assert shop["viewed"] >= 1 and shop["bag"] == products[0]["price_minor_units"] * 2

    ov = data["overview"]
    mix = {m["id"]: m["value"] for m in ov["mix"]}
    assert mix["pay"] >= 2 and mix["messages"] >= 2 and mix["shop"] >= 1
    assert ov["active_days"] >= 1 and ov["favourite"] in mix
    assert len(ov["headlines"]) == 8


async def test_dashboard_new_user_is_empty_not_broken(client: AsyncClient) -> None:
    r = await client.post("/api/v1/auth/register", json={
        "username": "freshface", "email": "fresh@example.com", "password": "password123",
        "full_name": "Fresh Face", "phone_number": "+919800000123"})
    assert r.status_code in (200, 201), r.text
    token = r.json()["tokens"]["access_token"]
    r = await client.get("/api/v1/profile/dashboard", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200, r.text
    assert r.json()["overview"]["total"] == 0
