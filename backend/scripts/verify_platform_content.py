"""Read-only smoke test of the populated platform catalogs and media server."""

import asyncio
import json
from pathlib import Path

import httpx


async def main():
    async with httpx.AsyncClient(base_url="http://127.0.0.1:8002/api/v1", timeout=90) as client:
        response = await client.post(
            "/auth/login", json={"identifier": "demo_viewer_021", "password": "PhlioDemo!2026"}
        )
        response.raise_for_status()
        client.headers["Authorization"] = "Bearer " + response.json()["tokens"]["access_token"]
        audit = {}
        for platform, count in [("book", 24), ("shop", 24), ("stream", 12), ("news", 12), ("pay", 6)]:
            response = await client.get("/content/" + platform, params={"limit": 100})
            response.raise_for_status()
            assert len(response.json()["items"]) == count
            audit[platform] = count
        response = await client.get("/social/videos")
        response.raise_for_status()
        videos = response.json()
        audit["videos_and_clips"] = len(videos)
        assert len(videos) == 40
        response = await client.get(
            "http://127.0.0.1:8002" + videos[0]["url"], headers={"Range": "bytes=0-1023"}
        )
        assert response.status_code == 206
        audit["video_range_status"] = response.status_code
        for _ in range(2):
            response = await client.get("/content/book/demo_booking_listing_00/engagement")
            response.raise_for_status()
            data = response.json()
            assert len(data["avatars"]) == 3 and data["more_count"] == data["count"] - 3
        audit["sample_engagement"] = {
            "count": data["count"],
            "avatars": len(data["avatars"]),
            "more": data["more_count"],
        }
        response = await client.get("/social/graph-status")
        response.raise_for_status()
        audit["graph_status"] = response.json()
        Path("data/platform-verification.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
        print(json.dumps(audit, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
