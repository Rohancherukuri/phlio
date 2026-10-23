"""Redis is an expendable cache/rate limiter, never the graph's source of truth."""

import hashlib
import json
import logging
import time
from collections import Counter

from fastapi import HTTPException
from redis.asyncio import Redis
from redis.exceptions import RedisError

log = logging.getLogger("phlio.cache")


class Cache:
    def __init__(self, url: str, enabled: bool, namespace: str):
        self.redis = (
            Redis.from_url(url, decode_responses=True, protocol=2, socket_connect_timeout=1, socket_timeout=1)
            if enabled
            else None
        )
        self.prefix = f"phlio:{namespace}:"
        self.stats = Counter()
        self._limits = {}

    def key(self, scope, value):
        return self.prefix + scope + ":" + hashlib.sha256(value.encode()).hexdigest()

    async def get(self, key):
        if self.redis:
            try:
                value = await self.redis.get(self.prefix + key)
                if value is not None:
                    self.stats["hits"] += 1
                    return json.loads(value)
            except (RedisError, ValueError):
                self.stats["errors"] += 1
        self.stats["misses"] += 1
        return None

    async def put(self, key, value, ttl=60):
        if self.redis:
            try:
                await self.redis.set(self.prefix + key, json.dumps(value, default=str), ex=ttl)
            except RedisError:
                self.stats["errors"] += 1

    async def rate_limit(self, user, action, maximum=120):
        bucket = int(time.time() // 60)
        key = self.key("rate", f"{user}:{action}:{bucket}")
        count = None
        if self.redis:
            try:
                async with self.redis.pipeline(transaction=True) as pipe:
                    result = await pipe.incr(key).expire(key, 65).execute()
                    count = result[0]
            except RedisError:
                self.stats["errors"] += 1
        if count is None:
            # Bounded local protection while Redis is down; correctness still uses the database.
            self._limits = {k: v for k, v in self._limits.items() if k[2] == bucket}
            entry = (user, action, bucket)
            count = self._limits[entry] = self._limits.get(entry, 0) + 1
        if count > maximum:
            raise HTTPException(429, "Too many requests. Try again shortly.", headers={"Retry-After": "60"})

    async def close(self):
        if self.redis:
            await self.redis.aclose()
