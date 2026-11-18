"""Creator memberships: plans, members-only gating, Razorpay test checkout (mocked)."""

from __future__ import annotations

import hashlib
import hmac
import uuid

import pytest
from httpx import AsyncClient

from app.api.v1 import memberships, pay_gateway
from app.domains.graph.service import key

pytestmark = pytest.mark.asyncio


async def login(client: AsyncClient, name: str) -> dict:
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


async def test_members_only_flow(client: AsyncClient, settings, monkeypatch) -> None:
    kiara, neha = await login(client, "artbykiara"), await login(client, "neha")
    settings.razorpay_key_id, settings.razorpay_key_secret = "rzp_test_abc", "secret"
    calls = []

    async def fake_provider(c, method, path, payload=None):
        calls.append((method, path, payload))
        if method == "POST":
            return {"id": "order_T1"}
        return {"items": [{"id": "pay_P1", "status": "captured", "amount": 4900, "currency": "INR",
                           "order_id": "order_T1"}]}

    monkeypatch.setattr(pay_gateway, "provider", fake_provider)
    try:
        # A video by Kiara (seed one directly in the video store).
        vid = uuid.uuid4().hex
        c = client._transport.app.state.container
        kiara_id = (await c.identity_repository.get_by_username("artbykiara")).id
        c.social_video_service.publish(vid, kiara_id,
                                       "Studio tour", "/media/social/x.mp4", kind="video", duration_seconds=90)

        # Members-only needs a plan first.
        r = await client.put(f"/api/v1/memberships/videos/{vid}", headers=kiara, json={"members_only": True})
        assert r.status_code == 409
        plan = await client.put("/api/v1/memberships/plan", headers=kiara,
                                json={"price_minor_units": 4900, "title": "Studio pass", "perks": ["Early videos", " Live Q&A "]})
        assert plan.json()["plan"]["perks"] == ["Early videos", "Live Q&A"]
        assert (await client.put(f"/api/v1/memberships/videos/{vid}", headers=kiara, json={"members_only": True})).status_code == 200
        assert (await client.put(f"/api/v1/memberships/videos/{vid}", headers=neha, json={"members_only": False})).status_code == 403

        def find(items):
            return next(v for v in items if v["id"] == vid)

        locked = find((await client.get("/api/v1/social/videos", headers=neha)).json())
        assert locked["members_only"] and locked["locked"] and locked["url"] == ""
        assert locked["membership"]["price_minor_units"] == 4900
        own = find((await client.get("/api/v1/social/videos", headers=kiara)).json())
        assert not own["locked"] and own["url"].endswith("x.mp4")

        info = (await client.get("/api/v1/memberships/creators/artbykiara", headers=neha)).json()
        assert info["plan"]["title"] == "Studio pass" and not info["member"]

        order = (await client.post("/api/v1/memberships/creators/artbykiara/join", headers=neha,
                                   json={"request_id": str(uuid.uuid4())})).json()
        assert order["razorpay_order_id"] == "order_T1" and order["key_id"] == "rzp_test_abc"

        bad = await client.post(f"/api/v1/memberships/orders/{order['id']}/verify", headers=neha,
                                json={"payment_id": "pay_P1", "signature": "0" * 64})
        assert bad.status_code == 422
        sig = hmac.new(b"secret", b"order_T1|pay_P1", hashlib.sha256).hexdigest()
        ok = await client.post(f"/api/v1/memberships/orders/{order['id']}/verify", headers=neha,
                               json={"payment_id": "pay_P1", "signature": sig})
        assert ok.status_code == 200 and ok.json()["member"] is True

        unlocked = find((await client.get("/api/v1/social/videos", headers=neha)).json())
        assert not unlocked["locked"] and unlocked["url"].endswith("x.mp4")
        assert (await client.get("/api/v1/memberships/mine", headers=neha)).json()["items"][0]["creator"] == "artbykiara"
        assert (await client.post("/api/v1/memberships/creators/artbykiara/join", headers=kiara,
                                  json={"request_id": str(uuid.uuid4())})).status_code == 400

        # Content API never leaks the file of a members-only video.
        from app.api.v1.content import presentation
        obj = await c.graph.register_object("x", "social.video", vid, "Studio tour")
        shown = await presentation(c, obj)
        assert shown.get("members_only") and not shown.get("media_url")
    finally:
        settings.razorpay_key_id, settings.razorpay_key_secret = "", ""
