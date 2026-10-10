"""At-least-once delivery. Consumers deduplicate by the stable event_id field."""

import asyncio
import logging

from redis.exceptions import RedisError

log = logging.getLogger("phlio.outbox")


async def publish_pending(container):
    redis = container.cache.redis
    db = container.graph.store.db
    if redis is None or db is None:
        return 0
    events = await db.rows("SELECT * FROM graph_outbox WHERE delivered = false ORDER BY created_at LIMIT 100")
    for event in events:
        await redis.xadd(
            container.cache.prefix + "events",
            {"event_id": event["id"], "event": event["event"], "entity": event["entity"]},
            maxlen=10000,
            approximate=True,
        )
        await db.merge(event["id"], {"delivered": True})
    return len(events)


async def run(container):
    while True:
        try:
            await publish_pending(container)
        except (RedisError, RuntimeError, OSError):
            log.warning("Outbox delivery deferred; durable events retained.")
        await asyncio.sleep(2)
