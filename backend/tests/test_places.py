"""Google place names for notes (Google mocked)."""

from __future__ import annotations

import httpx
import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio

GEOCODE = {"status": "OK", "results": [
    {"address_components": [
        {"long_name": "Kukatpally Housing Board Colony", "types": ["sublocality_level_2", "sublocality", "political"]},
        {"long_name": "Kukatpally", "types": ["sublocality_level_1", "sublocality", "political"]},
        {"long_name": "Hyderabad", "types": ["locality", "political"]},
    ]},
]}
NEARBY = {"places": [
    {"displayName": {"text": "Far Cafe"}, "location": {"latitude": 17.4950, "longitude": 78.3990}, "shortFormattedAddress": "Road 2"},
    {"displayName": {"text": "Near Temple"}, "location": {"latitude": 17.4936, "longitude": 78.3961},
     "primaryTypeDisplayName": {"text": "Hindu temple"}},
]}


async def test_places_use_google_and_need_a_key(client: AsyncClient, auth_headers: dict, settings) -> None:
    from app.api.v1 import places

    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        if "geocode" in request.url.path:
            assert request.url.params["key"] == "gk" and request.url.params["latlng"] == "17.4935,78.396"
            return httpx.Response(200, json=GEOCODE)
        assert request.headers["X-Goog-Api-Key"] == "gk"
        if request.url.path.endswith("searchNearby"):
            return httpx.Response(200, json=NEARBY)
        return httpx.Response(403, json={"error": {"message": "Places API (New) has not been used in project"}})

    q = {"lat": 17.49351, "lng": 78.39601}
    assert (await client.get("/api/v1/places/area", headers=auth_headers, params=q)).status_code == 503
    settings.google_maps_api_key = "gk"
    places.TRANSPORT = httpx.MockTransport(handler)
    try:
        area = (await client.get("/api/v1/places/area", headers=auth_headers, params=q)).json()["items"]
        assert [a["name"] for a in area] == ["Kukatpally Housing Board Colony", "Kukatpally", "Hyderabad"]
        again = await client.get("/api/v1/places/area", headers=auth_headers, params=q)
        assert again.status_code == 200 and len(calls) == 1  # cached

        spots = (await client.get("/api/v1/places/nearby", headers=auth_headers, params=q)).json()["items"]
        assert [s["name"] for s in spots] == ["Near Temple", "Far Cafe"] and spots[0]["kind"] == "Hindu temple"

        refused = await client.get("/api/v1/places/search", headers=auth_headers, params={**q, "q": "kphb"})
        assert refused.status_code == 503 and "Places API" in refused.text
    finally:
        settings.google_maps_api_key = ""
        places.TRANSPORT = None
