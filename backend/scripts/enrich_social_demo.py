"""Upgrade fictional demo profiles and media; never changes non-demo accounts."""

import asyncio
import json
import subprocess
from pathlib import Path

import httpx

from app.config import Settings
from app.core.container import build_container, media_root_path
from app.domains.graph.service import key


async def main():
    c = await build_container(
        Settings(
            database_backend="surreal",
            surreal_database="phlio_graph_dev",
            redis_enabled=True,
            redis_url="redis://127.0.0.1:6379/0",
            redis_namespace="phlio_graph_dev",
            social_video_database="data/phlio_graph_dev_videos.sqlite3",
            messaging_database="data/phlio_graph_dev_messages.sqlite3",
        )
    )
    root = media_root_path(c.settings) / "demo_graph"
    try:
        columns = {r[1] for r in c.social_video_service.db.execute("PRAGMA table_info(videos)")}
        if "duration_seconds" not in columns:
            c.social_video_service.db.execute(
                "ALTER TABLE videos ADD COLUMN duration_seconds INTEGER DEFAULT 0"
            )
        async with httpx.AsyncClient(timeout=45, follow_redirects=True) as client:
            for i in range(90):
                user = await c.identity_repository.get_by_id(f"demo_{i:03}")
                if not user or not user.is_test_user:
                    continue
                image = root / f"portrait_{i:03}.jpg"
                source = (
                    f"https://randomuser.me/api/portraits/{'women' if i % 2 == 0 else 'men'}/{i // 2}.jpg"
                )
                if not image.exists():
                    response = await client.get(source)
                    response.raise_for_status()
                    if not response.content.startswith(b"\xff\xd8"):
                        raise ValueError("Expected a JPEG portrait")
                    image.write_bytes(response.content)
                user.avatar_url = "/media/demo_graph/" + image.name
                await c.identity_repository.update_user(user)
        audit = []
        for i in range(20):
            for kind in ["video", "clip"]:
                seconds = 60 + (i % 5) * 60 if kind == "video" else 15 + (i % 8) * 15
                source = root / f"scene_{kind}_{i:02}.mp4"
                target = root / f"demo_{kind}_{i:02}_{seconds}s.mp4"
                if not target.exists():
                    temporary = target.with_name(target.stem + ".tmp.mp4")
                    subprocess.run(
                        [
                            "ffmpeg",
                            "-v",
                            "error",
                            "-y",
                            "-stream_loop",
                            "-1",
                            "-i",
                            str(source),
                            "-t",
                            str(seconds),
                            "-c",
                            "copy",
                            "-movflags",
                            "+faststart",
                            str(temporary),
                        ],
                        check=True,
                    )
                    temporary.replace(target)
                actual = float(
                    subprocess.check_output(
                        [
                            "ffprobe",
                            "-v",
                            "error",
                            "-show_entries",
                            "format=duration",
                            "-of",
                            "default=nw=1:nk=1",
                            str(target),
                        ],
                        text=True,
                    )
                )
                assert seconds - 0.1 <= actual <= seconds + 0.2
                rid = f"demo_{kind}_{i:02}"
                url = "/media/demo_graph/" + target.name
                c.social_video_service.db.execute(
                    "UPDATE videos SET url=?,kind=?,duration_seconds=? WHERE id=?", (url, kind, seconds, rid)
                )
                oid = key("platform_content", "social", rid)
                row = await c.graph.store.get(oid)
                row.update(media_url=url, duration_seconds=seconds)
                await c.graph.store.put(oid, row)
                audit.append({"id": rid, "duration_seconds": seconds, "actual_duration": actual})
        c.social_video_service.db.commit()
        # Create overlapping accepted friendships for meaningful demo mutuals.
        for i in range(100):
            for offset in [1, 2, 3]:
                a = f"demo_{i:03}"
                b = f"demo_{(i + offset) % 100:03}"
                relation = key("friend", *sorted([a, b]))
                existing = await c.graph.store.get(relation)
                if existing:
                    continue
                await c.graph.relationship(a, b, "request")
                await c.graph.relationship(b, a, "accept")
        Path("data/social-enrichment.json").write_text(
            json.dumps(
                {
                    "portrait_count": 90,
                    "portrait_source": "https://randomuser.me/documentation",
                    "media": audit,
                },
                indent=2,
            )
        )
        print(
            "Updated 90 portrait avatars, 20 videos (60–300 seconds), 20 clips (15–120 seconds), "
            "and mutual friendships."
        )
    finally:
        await c.graph.store.db.close()
        await c.cache.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    asyncio.run(main())
