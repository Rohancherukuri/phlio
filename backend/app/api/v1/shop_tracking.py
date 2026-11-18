"""
Phlio Shop parcel tracking, powered by AfterShip.

Add any tracking number (the courier is detected automatically, or pass its
AfterShip ``slug``) and the app shows the status, ETA and every checkpoint.
Each user's parcels are stored in the graph table ``shop_tracking``; the
live status is fetched from AfterShip and cached on the record for
``FRESH`` so opening the list doesn't call AfterShip for every parcel.

Endpoints under ``/api/v1/shop/tracking``:

``GET    /``            my parcels (refreshed when stale)
``POST   /``            ``{tracking_number, slug?, title?}`` start tracking
``POST   /detect``      ``{tracking_number}`` → possible couriers
``GET    /{id}``        one parcel, refreshed
``DELETE /{id}``        stop showing it
"""

from __future__ import annotations

import asyncio
import datetime as dt
import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key
from app.infrastructure.aftership import AfterShip, TrackingUnavailable, normalize

router = APIRouter(prefix="/shop/tracking", tags=["shop"])
FRESH = dt.timedelta(minutes=20)
NUMBER = r"^[A-Za-z0-9][A-Za-z0-9\-_. ]{3,63}$"


class TrackIn(BaseModel):
    tracking_number: str = Field(pattern=NUMBER)
    slug: str | None = Field(default=None, pattern=r"^[a-z0-9\-]{2,40}$")
    title: str | None = Field(default=None, max_length=80)


class DetectIn(BaseModel):
    tracking_number: str = Field(pattern=NUMBER)


TRANSPORT = None  # tests swap in an httpx.MockTransport


def client(c) -> AfterShip:
    s = c.settings
    return AfterShip(s.aftership_api_key, s.aftership_api_endpoint, TRANSPORT)


def _now() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def _fail(exc: TrackingUnavailable):
    raise HTTPException(exc.status, str(exc)) from exc


async def _refresh(c, row: dict, force: bool = False) -> dict:
    checked = row.get("checked_at")
    if not force and checked and _now() - dt.datetime.fromisoformat(checked) < FRESH:
        return row
    if row.get("tag") == "Delivered" and not force:
        return row
    try:
        live = normalize(await client(c).get(row["aftership_id"]))
    except TrackingUnavailable:
        return row  # keep the last known status
    title = row.get("title")
    row = {**row, **live, "title": title or live.get("title"), "checked_at": _now().isoformat()}
    await c.graph.store.put(key("shop_tracking", row["user_id"], row["parcel_id"]), row)
    return row


def _public(row: dict) -> dict:
    # The store sets ``id`` to the record key; the app uses our parcel id.
    out = {k: v for k, v in row.items() if k not in ("id", "user_id", "aftership_id", "parcel_id")}
    return dict(out, id=row["parcel_id"])


@router.get("")
async def list_parcels(user=Depends(get_current_user), c=Depends(get_container)):
    rows = await c.graph.store.rows("shop_tracking", {"user_id": user.id})
    rows = await asyncio.gather(*(_refresh(c, r) for r in rows))
    active = [r for r in rows if r.get("tag") != "Delivered"]
    active.sort(key=lambda r: r.get("created_at", ""), reverse=True)
    done = [r for r in rows if r.get("tag") == "Delivered"]
    done.sort(key=lambda r: r.get("created_at", ""), reverse=True)
    return {"items": [_public(r) for r in active + done], "configured": client(c).configured}


@router.post("", status_code=201)
async def track(body: TrackIn, user=Depends(get_current_user), c=Depends(get_container)):
    await c.cache.rate_limit(user.id, "shop-tracking", 20)
    number = body.tracking_number.replace(" ", "").upper()
    mine = await c.graph.store.rows("shop_tracking", {"user_id": user.id})
    if any(r.get("tracking_number", "").upper() == number for r in mine):
        raise HTTPException(409, "You're already tracking this parcel.")
    if len(mine) >= 50:
        raise HTTPException(400, "Remove a delivered parcel to track a new one.")
    api = client(c)
    try:
        try:
            t = await api.create(number, body.slug, body.title)
        except TrackingUnavailable as exc:
            # 4003: someone (maybe another Phlio user) already added it to our AfterShip account.
            if getattr(exc, "code", None) != 4003:
                raise
            t = await api.find(number)
            if not t:
                raise
    except TrackingUnavailable as exc:
        _fail(exc)
    rid = uuid.uuid4().hex[:16]
    row = dict(normalize(t), parcel_id=rid, user_id=user.id, created_at=_now().isoformat(), checked_at=_now().isoformat())
    if body.title:
        row["title"] = body.title
    await c.graph.store.put(key("shop_tracking", user.id, rid), row)
    return _public(row)


@router.post("/detect")
async def detect(body: DetectIn, user=Depends(get_current_user), c=Depends(get_container)):
    await c.cache.rate_limit(user.id, "shop-tracking-detect", 30)
    try:
        return {"couriers": await client(c).detect(body.tracking_number.replace(" ", "").upper())}
    except TrackingUnavailable as exc:
        _fail(exc)


async def _mine(c, user_id: str, rid: str) -> dict:
    row = await c.graph.store.get(key("shop_tracking", user_id, rid))
    if not row:
        raise HTTPException(404, "Parcel not found.")
    return row


@router.get("/{rid}")
async def parcel(rid: str, user=Depends(get_current_user), c=Depends(get_container)):
    return _public(await _refresh(c, await _mine(c, user.id, rid), force=True))


@router.delete("/{rid}", status_code=204)
async def untrack(rid: str, user=Depends(get_current_user), c=Depends(get_container)):
    await _mine(c, user.id, rid)
    await c.graph.store.delete(key("shop_tracking", user.id, rid))
