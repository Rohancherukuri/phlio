"""
Keeps the demo community's moments alive on a deployed server.

Moments last 24 hours. Locally, ``scripts/seed_community_moments.py`` re-dates
the community's seeded "live" moments every time Start-GraphDemo runs. A cloud
deployment has no such step, so a day after the database was published every
seeded moment has expired and the Moments row on Social Home is empty.

With ``DEMO_CONTENT_REFRESH=true`` this task does the same re-dating on the
server, once an hour: every *seeded* live moment (``seed == "moments-v1"``,
id ``…_live_N``) that has expired or will within the next two hours is given
a new creation time between 8 minutes and 20 hours ago. Only seeded demo
content is touched (moments created by the seed script for test accounts);
real users' moments are never changed. Highlights are left alone.
"""

from __future__ import annotations

import asyncio
import datetime as dt
import hashlib
import logging

log = logging.getLogger("phlio.demo_refresh")

SEED = "moments-v1"
LIFETIME = dt.timedelta(hours=24)
MARGIN = dt.timedelta(hours=2)


def _offset(moment_id: str, day: str) -> dt.timedelta:
    """Stable per moment and day: between 8 minutes and 20 hours."""
    digest = int(hashlib.sha256(f"{moment_id}|{day}".encode()).hexdigest(), 16)
    return dt.timedelta(minutes=8 + digest % (20 * 60 - 8))


def _parse(value: str | None) -> dt.datetime | None:
    try:
        parsed = dt.datetime.fromisoformat(str(value))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=dt.UTC)


async def refresh_once(container, now: dt.datetime | None = None) -> int:
    """Re-dates seeded live moments that are expired or about to expire."""
    now = now or dt.datetime.now(dt.UTC)
    rows = await container.graph.store.rows("social_moment", {"seed": SEED})
    changed = 0
    for row in rows:
        moment_id = str(row.get("id") or "")
        if "_live_" not in moment_id:
            continue  # highlight moments stay in the past on purpose
        expires = _parse(row.get("expires_at"))
        if expires and expires - now > MARGIN:
            continue
        created = now - _offset(moment_id, now.date().isoformat())
        await container.graph.store.put(moment_id, dict(row, created_at=created.isoformat(),
                                                        expires_at=(created + LIFETIME).isoformat()))
        changed += 1
    return changed


async def run(container, interval: float = 3600) -> None:
    """Background task: refresh now, then every ``interval`` seconds."""
    if not container.settings.demo_content_refresh:
        return
    while True:
        try:
            changed = await refresh_once(container)
            if changed:
                log.info("Refreshed %d seeded demo moments", changed)
        except Exception:  # never take the API down over demo content
            log.exception("Demo moment refresh failed")
        await asyncio.sleep(interval)
