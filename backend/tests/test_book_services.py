"""Book services: home services, restaurants, stays and travel, with packages."""

from __future__ import annotations

import datetime as dt

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_service_packages_set_the_price(client: AsyncClient, auth_headers: dict, monkeypatch) -> None:
    from scripts import import_book_services as seedmod

    app = client._transport.app  # the app the client talks to

    monkeypatch.setattr(seedmod, "fetch_osm", lambda cache, refresh=False: [])
    counts = await seedmod.seed(app.state.container, images=False)
    assert counts["home"] == 10 and counts["restaurants"] == 6 and counts["stays"] == 4 and counts["tours"] == 6

    r = await client.get("/api/v1/book/listings/pb_svc_home_deep_clean", headers=auth_headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["vertical"] == "home" and body["kind"] == "slot"
    assert [p["name"] for p in body["meta"]["packages"]] == ["1 BHK", "2 BHK", "3 BHK"]

    day = (dt.date.today() + dt.timedelta(days=2)).isoformat()
    r = await client.post("/api/v1/book/bookings", headers=auth_headers, json={
        "listing_id": "pb_svc_home_deep_clean", "date": day, "time": "10:00:00", "participants": 1,
        "details": {"package": "2 BHK", "units": "1"}})
    assert r.status_code == 201, r.text
    assert r.json()["estimated_total_min_minor_units"] == 3499_00

    r = await client.post("/api/v1/book/bookings", headers=auth_headers, json={
        "listing_id": "pb_svc_stay_lake", "date": day, "time": "12:00:00", "participants": 2,
        "details": {"package": "Lake-view cottage", "units": "2"}})
    assert r.status_code == 201, r.text
    assert r.json()["estimated_total_min_minor_units"] == 7900_00 * 2

    r = await client.post("/api/v1/book/bookings", headers=auth_headers, json={
        "listing_id": "pb_svc_rest_cafe", "date": day, "time": "19:00:00", "participants": 2,
        "details": {"package": "Free lunch"}})
    assert r.status_code == 422
