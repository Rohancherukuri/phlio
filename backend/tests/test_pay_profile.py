"""Phlio Pay profile: QR codes per UPI id, test accounts and cards, settings."""

from __future__ import annotations

from urllib.parse import parse_qs, urlparse

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio
P = "/api/v1/pay/profile"


async def test_pay_profile(client: AsyncClient, auth_headers: dict) -> None:
    r = await client.get(P, headers=auth_headers)
    assert r.status_code == 200, r.text
    p = r.json()
    assert p["test_mode"] and p["receiving"] and 2 <= len(p["accounts"]) <= 3
    first = p["accounts"][0]
    assert first["primary"] and first["upi_id"].endswith("@phlio") and len(first["last4"]) == 4
    qr = urlparse(first["qr"])
    assert qr.scheme == "upi" and parse_qs(qr.query)["pa"] == [first["upi_id"]]
    assert {c["kind"] for c in p["cards"]} == {"debit", "credit"}
    assert p["settings"]["shake_to_scan"] is True and p["refer"]["code"].startswith("PHLIO")
    # Stable per user.
    again = (await client.get(P, headers=auth_headers)).json()
    assert again["accounts"] == p["accounts"] and again["refer"]["code"] == p["refer"]["code"]

    s = (await client.patch(f"{P}/settings", headers=auth_headers, json={"fingerprint": True, "shake_to_scan": False})).json()
    assert s["fingerprint"] is True and s["shake_to_scan"] is False and s["autopay"] is False

    other = p["accounts"][1]["id"]
    assert (await client.put(f"{P}/primary", headers=auth_headers, json={"account_id": other})).status_code == 200
    p = (await client.get(P, headers=auth_headers)).json()
    assert p["accounts"][0]["id"] == other and p["accounts"][0]["primary"]
    assert (await client.put(f"{P}/primary", headers=auth_headers, json={"account_id": "nope"})).status_code == 404
