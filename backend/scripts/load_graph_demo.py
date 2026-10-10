"""Local, read-only 100-account smoke load; not a production capacity benchmark."""

import asyncio
import json
import statistics
import time
from pathlib import Path

import httpx

from app.config import Settings
from app.infrastructure.security.jwt import issue_token_pair


async def main():
    settings = Settings()
    gate = asyncio.Semaphore(10)
    async with httpx.AsyncClient(base_url="http://127.0.0.1:8002", timeout=60) as client:

        async def read(i):
            async with gate:
                token = issue_token_pair(f"demo_{i:03}", settings).access_token
                started = time.perf_counter()
                response = await client.get(
                    "/api/v1/social/feed", params={"limit": 5}, headers={"Authorization": "Bearer " + token}
                )
                response.raise_for_status()
                assert len(response.json()["items"]) == 5
                return (time.perf_counter() - started) * 1000

        results = {}
        for name in ["cold", "warm"]:
            elapsed = await asyncio.gather(*(read(i) for i in range(100)))
            results[name] = {
                "requests": 100,
                "concurrency": 10,
                "median_ms": round(statistics.median(elapsed), 1),
                "p95_ms": round(sorted(elapsed)[94], 1),
            }
        Path("data/graph-load-smoke.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
