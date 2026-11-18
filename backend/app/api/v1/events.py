"""
Seasonal banners: ``GET /api/v1/events/banners?platform=shop&region=IN``.

Public (no sign-in needed) and cheap: the answer only depends on the date,
platform and region, so it is cached for an hour by clients and proxies.
``date`` can be passed (YYYY-MM-DD) to preview a festival's banner.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Query, Response

from app.domains.events import calendar

router = APIRouter(prefix="/events", tags=["events"])


@router.get("/banners")
async def banners(
    response: Response,
    platform: str = Query("social", pattern="^(" + "|".join(calendar.PLATFORMS) + ")$"),
    region: str | None = Query(None, pattern="^[A-Za-z]{2}$"),
    date: dt.date | None = None,
    limit: int = Query(2, ge=1, le=5),
):
    response.headers["Cache-Control"] = "public, max-age=3600"
    today = date or dt.datetime.now(dt.UTC).date()
    return {"date": today.isoformat(), "items": calendar.active(today, platform, region, limit)}


@router.get("/upcoming")
async def upcoming(
    response: Response,
    region: str | None = Query(None, pattern="^[A-Za-z]{2}$"),
    days: int = Query(60, ge=1, le=366),
):
    response.headers["Cache-Control"] = "public, max-age=3600"
    return {"items": calendar.upcoming(dt.datetime.now(dt.UTC).date(), region, days)}
