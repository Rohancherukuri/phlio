"""NewsAPI parsing and AfterShip parcel tracking (AfterShip mocked)."""

from __future__ import annotations

import json

import httpx
import pytest
from httpx import AsyncClient

from app.domains.graph import newsapi
from app.infrastructure.aftership import normalize


def test_newsapi_parse_keeps_headlines_only() -> None:
    payload = {"articles": [
        {"source": {"name": "Reuters"}, "title": "Markets rally - Reuters", "url": "https://reuters.com/a",
         "urlToImage": "http://insecure/img.jpg", "publishedAt": "2026-11-18T08:00:00Z",
         "description": "Stocks rose.", "content": "FULL BODY SHOULD NOT BE STORED"},
        {"source": {"name": "X"}, "title": "[Removed]", "url": "https://removed.com", "publishedAt": "2026-11-18T08:00:00Z"},
        {"title": "No https", "url": "http://x.com", "publishedAt": "2026-11-18T08:00:00Z"},
    ]}
    rows = newsapi.parse(payload, "Business")
    assert len(rows) == 1
    row = rows[0]
    assert row["title"] == "Markets rally" and row["publisher"] == "Reuters" and row["image_url"] is None
    assert "content" not in row and row["summary"] == "Stocks rose." and row["ref"].startswith("napi_")


TRACKING = {
    "id": "as123", "tracking_number": "1Z999AA10123456784", "slug": "ups", "tag": "InTransit",
    "subtag_message": "Departed facility", "courier_tracking_link": "https://ups.com/track?1Z",
    "latest_estimated_delivery": {"type": "specific", "datetime": "2026-11-21"},
    "checkpoints": [
        {"checkpoint_time": "2026-11-17T10:00:00Z", "message": "Picked up", "city": "Mumbai", "country_region_name": "India", "tag": "InfoReceived"},
        {"checkpoint_time": "2026-11-18T06:00:00Z", "message": "Departed facility", "location": "Pune, IN", "tag": "InTransit"},
    ],
}


def test_normalize_new_and_legacy_shapes() -> None:
    n = normalize(TRACKING)
    assert n["status"] == "In transit" and n["step"] == 2 and n["eta"] == "2026-11-21"
    assert n["checkpoints"][0]["message"] == "Departed facility" and n["checkpoints"][1]["location"] == "Mumbai, India"
    legacy = normalize({"tracking_number": "X1", "tag": "Delivered", "expected_delivery": "2026-01-01"})
    assert legacy["step"] == 4 and legacy["eta"] == "2026-01-01"


@pytest.mark.asyncio
async def test_track_parcel_flow(client: AsyncClient, auth_headers: dict, settings) -> None:
    from app.api.v1 import shop_tracking

    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append((request.method, request.url.path, request.headers.get("as-api-key")))
        if request.method == "POST" and request.url.path.endswith("/trackings"):
            assert "tracking" not in json.loads(request.content)  # flat body (2025-07+)
            return httpx.Response(201, json={"meta": {"code": 201}, "data": TRACKING})
        if request.url.path.endswith("/trackings/as123"):
            return httpx.Response(200, json={"meta": {"code": 200}, "data": dict(TRACKING, tag="Delivered")})
        if request.url.path.endswith("/couriers/detect"):
            return httpx.Response(200, json={"data": {"couriers": [{"slug": "ups", "name": "UPS"}]}})
        return httpx.Response(404, json={"meta": {"code": 4004, "message": "Tracking does not exist."}})

    unset = await client.post("/api/v1/shop/tracking", headers=auth_headers, json={"tracking_number": "1Z999AA10123456784"})
    assert unset.status_code == 503  # no key configured in tests

    settings.aftership_api_key = "test-key"
    shop_tracking.TRANSPORT = httpx.MockTransport(handler)
    try:
        made = await client.post("/api/v1/shop/tracking", headers=auth_headers,
                                 json={"tracking_number": "1z999aa10123456784", "title": "Headphones"})
        assert made.status_code == 201, made.text
        body = made.json()
        assert body["status"] == "In transit" and body["title"] == "Headphones" and "aftership_id" not in body
        assert all(key == "test-key" for _, _, key in calls)

        dup = await client.post("/api/v1/shop/tracking", headers=auth_headers, json={"tracking_number": "1Z999AA10123456784"})
        assert dup.status_code == 409

        listed = (await client.get("/api/v1/shop/tracking", headers=auth_headers)).json()["items"]
        assert [p["id"] for p in listed] == [body["id"]]  # still fresh: no extra AfterShip call
        assert not any(path.endswith("/as123") for _, path, _ in calls)

        detail = (await client.get(f"/api/v1/shop/tracking/{body['id']}", headers=auth_headers)).json()
        assert detail["status"] == "Delivered" and detail["title"] == "Headphones"

        couriers = await client.post("/api/v1/shop/tracking/detect", headers=auth_headers, json={"tracking_number": "1Z999"})
        assert couriers.json()["couriers"][0]["name"] == "UPS"

        assert (await client.delete(f"/api/v1/shop/tracking/{body['id']}", headers=auth_headers)).status_code == 204
        assert (await client.get("/api/v1/shop/tracking", headers=auth_headers)).json()["items"] == []
    finally:
        settings.aftership_api_key = ""
        shop_tracking.TRANSPORT = None
