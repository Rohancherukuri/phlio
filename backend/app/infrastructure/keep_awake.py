"""
Keeps a free-tier deployment warm.

Render's free web services go to sleep after 15 minutes without inbound
requests, and the next request then waits 30-60 s while the container boots,
restores state from object storage and reconnects to SurrealDB — which the
app experiences as "takes forever to load" or "can't reach Phlio".

With ``KEEP_AWAKE=true`` this task requests the service's own public URL
(``RENDER_EXTERNAL_URL``, set by Render, or ``KEEP_AWAKE_URL``) every
``KEEP_AWAKE_INTERVAL`` seconds (default 10 min). The request goes out
through Render's edge and back in, so it counts as traffic. Each tick also
runs a trivial SurrealDB query, keeping the database connection (and a
Surreal Cloud instance) active.

Cost note: Render gives free accounts 750 instance-hours a month; one service
kept awake all month uses about 744 of them. Leave this off if the same
account runs other free services.
"""

from __future__ import annotations

import asyncio
import logging
import os

import httpx

log = logging.getLogger("phlio.keep_awake")


async def run(container, interval: float = 600.0) -> None:
    settings = container.settings
    base = (settings.keep_awake_url or os.environ.get("RENDER_EXTERNAL_URL", "")).rstrip("/")
    if not settings.keep_awake or not base:
        return
    log.info("Keep-awake on: pinging %s/health every %.0fs", base, interval)
    async with httpx.AsyncClient(timeout=30, headers={"User-Agent": "phlio-keep-awake"}) as http:
        while True:
            await asyncio.sleep(interval)
            try:
                await http.get(f"{base}/health")
            except httpx.HTTPError as exc:
                log.warning("keep-awake ping failed: %s", exc)
            db = getattr(getattr(getattr(container, "graph", None), "store", None), "db", None)
            if db is not None:
                try:
                    await db.query("RETURN 1", {})
                except Exception as exc:  # reconnect logic lives in the client
                    log.warning("keep-awake database ping failed: %s", exc)
