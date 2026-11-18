"""Festival calendar and the seasonal-banner endpoint."""

from __future__ import annotations

import datetime as dt

import pytest
from httpx import AsyncClient

from app.domains.events import calendar as c


def test_date_rules() -> None:
    assert c.THANKSGIVING(2026) == dt.date(2026, 11, 26)
    assert c._easter(2026) == dt.date(2026, 4, 5) and c._easter(2027) == dt.date(2027, 3, 28)
    assert c.nth_weekday(5, 6, 2)(2026) == dt.date(2026, 5, 10)  # Mother's Day
    assert c.nth_weekday(11, 3, -1)(2026) == dt.date(2026, 11, 26)


def test_every_event_resolves_and_has_copy() -> None:
    ids = [e.id for e in c.EVENTS]
    assert len(ids) == len(set(ids))
    for e in c.EVENTS:
        assert e.rule(2027) is not None, e.id
        assert all(color.startswith("#") for color in e.colors)


def test_diwali_banner_per_platform() -> None:
    day = dt.date(2026, 11, 1)  # a week before Diwali 2026
    social = c.active(day, "social", "IN")
    assert social[0]["id"] == "diwali" and social[0]["status"] == "upcoming" and social[0]["days_to"] == 7
    assert "Diwali" in c.active(day, "shop", "IN")[0]["line"]
    assert c.active(dt.date(2026, 11, 9), "book", "US")[0]["status"] == "live"


def test_regional_events_stay_local() -> None:
    songkran = dt.date(2027, 4, 13)
    assert "songkran" in [b["id"] for b in c.active(songkran, "social", "TH", limit=5)]
    assert "songkran" not in [b["id"] for b in c.active(songkran, "social", "IN", limit=5)]


@pytest.mark.asyncio
async def test_banner_endpoint(client: AsyncClient) -> None:
    r = await client.get("/api/v1/events/banners", params={"platform": "shop", "region": "us", "date": "2026-12-20"})
    assert r.status_code == 200
    assert r.json()["items"][0]["id"] == "christmas"
    assert "max-age" in r.headers["cache-control"]
    assert (await client.get("/api/v1/events/banners", params={"platform": "nope"})).status_code == 422
