"""
Place names for notes and location sharing, from Google Maps Platform.

OpenStreetMap (what the app used alone before) is patchy for Indian
neighbourhoods: around KPHB Colony in Hyderabad its nearest place node is
"APHB Colony", so notes showed the wrong area. Google's data is much better
there, so the app asks these endpoints first and falls back to
OpenStreetMap when they're not configured or fail.

The key (``GOOGLE_MAPS_API_KEY``) stays on the server. Enable the
**Geocoding API** and **Places API (New)** for it in Google Cloud.

``GET /api/v1/places/area?lat=&lng=``   neighbourhood names for a point,
                                        most specific first
``GET /api/v1/places/nearby?lat=&lng=`` named spots nearby, nearest first
``GET /api/v1/places/search?q=&lat=&lng=`` text search around a point

Coordinates are rounded to ~11 m before calling Google (and as the cache
key), answers are cached for 10 minutes, and each user is rate limited.
"""

from __future__ import annotations

import hashlib
import math
import time

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query

from app.api.deps import get_container, get_current_user

router = APIRouter(prefix="/places", tags=["places"])
GEOCODE = "https://maps.googleapis.com/maps/api/geocode/json"
NEARBY = "https://places.googleapis.com/v1/places:searchNearby"
TEXT = "https://places.googleapis.com/v1/places:searchText"
FIELDS = "places.displayName,places.formattedAddress,places.shortFormattedAddress,places.location,places.primaryTypeDisplayName"
# Address parts that name an area, most specific first.
AREA_TYPES = ("neighborhood", "sublocality_level_3", "sublocality_level_2", "sublocality_level_1", "sublocality", "locality")
TRANSPORT = None  # tests swap in an httpx.MockTransport
_memo: dict[str, tuple[float, dict]] = {}  # in-process cache when Redis is off


def _key(c) -> str:
    key = getattr(c.settings, "google_maps_api_key", "") or ""
    if not key:
        raise HTTPException(503, "Google place names aren't set up on this server.")
    return key


def _metres(lat1, lng1, lat2, lng2) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


async def _cached(c, user, name: str, parts: list, fetch):
    await c.cache.rate_limit(user.id, "places", 60)
    cache_key = "places:" + hashlib.sha256(repr([name, *parts]).encode()).hexdigest()
    memo = _memo.get(cache_key)
    if memo and memo[0] > time.monotonic():
        return memo[1]
    hit = await c.cache.get(cache_key)
    if hit is not None:
        return hit
    try:
        async with httpx.AsyncClient(timeout=10, transport=TRANSPORT) as client:
            result = await fetch(client)
    except httpx.HTTPError as exc:
        raise HTTPException(503, "Google Maps couldn't be reached.") from exc
    await c.cache.put(cache_key, result, ttl=600)
    if len(_memo) > 500:
        _memo.clear()
    _memo[cache_key] = (time.monotonic() + 600, result)
    return result


def _places(body: dict, lat: float | None, lng: float | None) -> list[dict]:
    out = []
    for p in body.get("places") or []:
        loc = p.get("location") or {}
        name = (p.get("displayName") or {}).get("text")
        if not name or loc.get("latitude") is None:
            continue
        out.append(dict(
            name=name, lat=loc["latitude"], lng=loc["longitude"],
            address=p.get("shortFormattedAddress") or p.get("formattedAddress") or "",
            kind=(p.get("primaryTypeDisplayName") or {}).get("text"),
            distance=None if lat is None else round(_metres(lat, lng, loc["latitude"], loc["longitude"])),
        ))
    if lat is not None:
        out.sort(key=lambda x: x["distance"])
    return out


def _check(r: httpx.Response, body: dict):
    status = body.get("status")
    if r.status_code >= 400 or status in ("REQUEST_DENIED", "OVER_QUERY_LIMIT", "INVALID_REQUEST"):
        message = (body.get("error") or {}).get("message") or body.get("error_message") or "Google Maps refused the request."
        raise HTTPException(503, message)


@router.get("/area")
async def area(lat: float = Query(ge=-90, le=90), lng: float = Query(ge=-180, le=180),
               user=Depends(get_current_user), c=Depends(get_container)):
    key = _key(c)
    lat, lng = round(lat, 4), round(lng, 4)

    async def fetch(client):
        r = await client.get(GEOCODE, params={"latlng": f"{lat},{lng}", "key": key, "language": "en"})
        body = r.json()
        _check(r, body)
        names: list[dict] = []
        seen = set()
        for kind in AREA_TYPES:
            for result in body.get("results") or []:
                for comp in result.get("address_components") or []:
                    if kind in comp.get("types", []) and comp["long_name"].lower() not in seen:
                        seen.add(comp["long_name"].lower())
                        city = next((x["long_name"] for x in result["address_components"] if "locality" in x["types"]), "")
                        names.append(dict(name=comp["long_name"], address=city if city != comp["long_name"] else "",
                                          lat=lat, lng=lng, kind="area", distance=0))
        return {"items": names[:6], "source": "google"}

    return await _cached(c, user, "area", [lat, lng], fetch)


@router.get("/nearby")
async def nearby(lat: float = Query(ge=-90, le=90), lng: float = Query(ge=-180, le=180),
                 radius: int = Query(800, ge=50, le=5000),
                 user=Depends(get_current_user), c=Depends(get_container)):
    key = _key(c)
    lat, lng = round(lat, 4), round(lng, 4)

    async def fetch(client):
        r = await client.post(NEARBY, headers={"X-Goog-Api-Key": key, "X-Goog-FieldMask": FIELDS}, json={
            "maxResultCount": 20, "rankPreference": "DISTANCE", "languageCode": "en",
            "locationRestriction": {"circle": {"center": {"latitude": lat, "longitude": lng}, "radius": float(radius)}},
        })
        body = r.json()
        _check(r, body)
        return {"items": _places(body, lat, lng), "source": "google"}

    return await _cached(c, user, "nearby", [lat, lng, radius], fetch)


@router.get("/search")
async def search(q: str = Query(min_length=2, max_length=80), lat: float | None = Query(None, ge=-90, le=90),
                 lng: float | None = Query(None, ge=-180, le=180),
                 user=Depends(get_current_user), c=Depends(get_container)):
    key = _key(c)
    q = " ".join(q.split())
    body_in: dict = {"textQuery": q, "maxResultCount": 20, "languageCode": "en"}
    if lat is not None and lng is not None:
        lat, lng = round(lat, 3), round(lng, 3)
        body_in["locationBias"] = {"circle": {"center": {"latitude": lat, "longitude": lng}, "radius": 20000.0}}

    async def fetch(client):
        r = await client.post(TEXT, headers={"X-Goog-Api-Key": key, "X-Goog-FieldMask": FIELDS}, json=body_in)
        body = r.json()
        _check(r, body)
        return {"items": _places(body, lat, lng), "source": "google"}

    return await _cached(c, user, "search", [q.lower(), lat, lng], fetch)
