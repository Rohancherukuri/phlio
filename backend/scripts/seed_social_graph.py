"""Idempotent, synthetic development population. Never touches non-demo accounts.
Run: uv run python -m scripts.seed_social_graph --database phlio_graph_dev
"""

import argparse
import asyncio
import datetime as dt
import json
import random
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

from app.config import Settings
from app.core.container import build_container, media_root_path
from app.domains.graph.service import key
from app.domains.graph.store import now
from app.domains.identity.entities import User
from app.domains.rooms.entities import Room, RoomCategory
from app.domains.social.entities import MediaAttachment, MediaKind, Post
from app.infrastructure.security.password import hash_password

FIRST = [
    "Aanya",
    "Aarav",
    "Mira",
    "Kabir",
    "Tara",
    "Ishaan",
    "Zoya",
    "Dev",
    "Nila",
    "Arin",
    "Leah",
    "Noah",
    "Lina",
    "Omar",
    "Yuna",
    "Kai",
    "Eva",
    "Leo",
    "Nora",
    "Finn",
]
LAST = ["Mehta", "Rao", "Shah", "Das", "Sen", "Kapoor", "Patel", "Roy", "Ali", "Iyer"]
TOPICS = ["Design", "Gaming", "Music", "Code", "Travel", "Food", "Fitness", "Photography", "Books", "Science"]
COLORS = ["#8D78FF", "#72A7FF", "#E795D7", "#FFB58F", "#68D7CD"]
PASSWORD = "PhlioDemo!2026"


def assets(root):
    root.mkdir(parents=True, exist_ok=True)
    for i in range(100):
        rng = random.Random(700 + i)
        image = Image.new("RGB", (256, 256), "#182231")
        d = ImageDraw.Draw(image)
        skin = rng.choice(["#f7c6a0", "#c88b65", "#885239", "#e8ac82", "#aa7052"])
        d.ellipse((22, 162, 234, 355), fill=COLORS[i % 5])
        d.ellipse((69, 44, 187, 190), fill=skin)
        d.pieslice((60, 28, 194, 158), 180, 360, fill=rng.choice(["#242128", "#513827", "#171c27"]))
        d.ellipse((96, 110, 105, 120), fill="#20212a")
        d.ellipse((151, 110, 160, 120), fill="#20212a")
        d.arc((111, 129, 145, 153), 0, 180, fill="#582c35", width=4)
        image.save(root / f"avatar_{i:03}.png")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("Install ffmpeg to generate playable test clips.")
    for i in range(20):
        image = Image.new("RGB", (960, 540), "#080E16")
        d = ImageDraw.Draw(image)
        for j in range(7):
            x = (i * 83 + j * 151) % 960
            y = (i * 41 + j * 83) % 540
            d.rounded_rectangle((x - 110, y - 70, x + 150, y + 120), radius=45, fill=COLORS[(i + j) % 5])
        d.rounded_rectangle((40, 355, 920, 500), radius=24, fill="#111925")
        d.text(
            (68, 382), f"PHLIO / {TOPICS[i % 10].upper()} / CREATOR {i + 1:02}", fill="#F7F7FA", font_size=30
        )
        d.text((68, 434), "Synthetic development content", fill="#C4C8D2", font_size=22)
        image.save(root / f"cover_{i:02}.jpg", quality=88)
        for kind, scale in [("video", "960:540"), ("clip", "360:640")]:
            target = root / f"{kind}_{i:02}.mp4"
            if target.exists():
                continue
            subprocess.run(
                [
                    ffmpeg,
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-y",
                    "-loop",
                    "1",
                    "-i",
                    str(root / f"cover_{i:02}.jpg"),
                    "-f",
                    "lavfi",
                    "-i",
                    f"sine=frequency={220 + i * 18}:sample_rate=44100",
                    "-vf",
                    f"scale={scale}:force_original_aspect_ratio=increase,crop={scale},eq=brightness=0.04*sin(t*2):eval=frame",
                    "-t",
                    "6",
                    "-r",
                    "24",
                    "-c:v",
                    "libx264",
                    "-preset",
                    "ultrafast",
                    "-pix_fmt",
                    "yuv420p",
                    "-c:a",
                    "aac",
                    "-af",
                    "volume=0.05",
                    "-movflags",
                    "+faststart",
                    str(target),
                ],
                check=True,
            )


async def seed(database):
    settings = Settings(
        database_backend="surreal",
        surreal_database=database,
        redis_enabled=True,
        redis_url="redis://127.0.0.1:6379/0",
        redis_namespace=database,
        social_video_database=f"data/{database}_videos.sqlite3",
        messaging_database=f"data/{database}_messages.sqlite3",
    )
    if settings.is_production:
        raise RuntimeError("Demo seed is development-only.")
    assets(media_root_path(settings) / "demo_graph")
    c = await build_container(settings)
    hashed = hash_password(PASSWORD)
    rng = random.Random(20261007)
    base = dt.datetime.now(dt.UTC) - dt.timedelta(days=7)
    try:
        for i in range(100):
            uid = f"demo_{i:03}"
            creator = i < 20
            if not await c.identity_repository.get_by_id(uid):
                await c.identity_repository.create_user(
                    User(
                        id=uid,
                        username=f"demo_{'creator' if creator else 'viewer'}_{i + 1:03}",
                        full_name=f"{FIRST[i % 20]} {LAST[(i // 10 + i) % 10]}",
                        email=f"{uid}@example.test",
                        hashed_password=hashed,
                        avatar_url=f"/media/demo_graph/avatar_{i:03}.png",
                        bio=f"Synthetic test account. {TOPICS[i % 10]} enthusiast.",
                        interests=[TOPICS[i % 10].lower(), TOPICS[(i + 3) % 10].lower()],
                        is_creator=creator,
                        is_test_user=True,
                    )
                )
            if not await c.graph.store.get(key("privacy_policy", uid, "social", "*", "*")):
                await c.graph.set_policy(
                    uid,
                    dict(
                        platform="social",
                        object_type="*",
                        verb="*",
                        audience="friends",
                        identity_mode="anonymous" if i % 4 == 0 else "identified",
                        foxy_access="none" if i % 3 == 0 else "both",
                        selected_users=[],
                    ),
                )
        objects = []
        for i in range(20):
            uid = f"demo_{i:03}"
            topic = TOPICS[i % 10]
            for j in range(3):
                pid = f"demo_post_{i:02}_{j}"
                media = (
                    []
                    if j == 0
                    else [
                        MediaAttachment(
                            url=(
                                f"/media/demo_graph/{'cover' if j == 1 else 'clip'}_{i:02}."
                                f"{'jpg' if j == 1 else 'mp4'}"
                            ),
                            kind=MediaKind.IMAGE if j == 1 else MediaKind.VIDEO,
                        )
                    ]
                )
                text = [
                    (
                        f"My week in {topic.lower()}: three things I learned by practising every day. "
                        "What are you working on?"
                    ),
                    (
                        f"A little {topic.lower()} inspiration from my latest project. "
                        "Sharing the process, not just the finish."
                    ),
                    f"Six seconds from my {topic.lower()} notebook. Small experiments lead to better ideas.",
                ][j]
                if not await c.social_repository.get_post(pid):
                    await c.social_repository.create_post(
                        Post(
                            id=pid,
                            author_id=uid,
                            text=text,
                            media=media,
                            tags=[topic.lower(), "syntheticdemo"],
                            created_at=base + dt.timedelta(minutes=i * 3 + j),
                        )
                    )
                obj = await c.graph.register_object(uid, "social.post", pid, text[:160])
                objects.append(obj)
                await c.graph.action(uid, obj["id"], "created", trusted=True)
            for kind in ["video", "clip"]:
                vid = f"demo_{kind}_{i:02}"
                title = f"{topic}: {'studio session' if kind == 'video' else 'quick creative cut'} {i + 1}"
                if not c.social_video_service.db.execute(
                    "SELECT id FROM videos WHERE id=?", (vid,)
                ).fetchone():
                    c.social_video_service.publish(vid, uid, title, f"/media/demo_graph/{kind}_{i:02}.mp4")
                c.social_video_service.db.execute(
                    "UPDATE videos SET kind=?, thumbnail_url=? WHERE id=?",
                    (kind, f"/media/demo_graph/cover_{i:02}.jpg", vid),
                )
                c.social_video_service.db.commit()
                await c.graph.register_object(uid, "social." + kind, vid, title)
        for i in range(100):
            uid = f"demo_{i:03}"
            for target in rng.sample([n for n in range(20) if n != i], 4):
                if not await c.graph.store.get(key("follows", uid, f"demo_{target:03}")):
                    await c.graph.relationship(uid, f"demo_{target:03}", "follow")
            peer = f"demo_{(i + 1) % 100:03}"
            fid = key("friend", *sorted([uid, peer]))
            if not await c.graph.store.get(fid):
                await c.graph.relationship(uid, peer, "request")
                if i % 5:
                    await c.graph.relationship(peer, uid, "accept")
            if i >= 20:
                for obj in rng.sample(objects, 4):
                    if not await c.social_repository.is_liked_by(obj["domain_ref"], uid):
                        await c.social_repository.set_liked(obj["domain_ref"], uid, True)
                    await c.graph.action(uid, obj["id"], "liked")
                    await c.graph.action(uid, obj["id"], "viewed")
        for i in range(5):
            rid = f"demo_room_{i}"
            owner = f"demo_{i:03}"
            if not await c.rooms_repository.get_room(rid):
                await c.rooms_repository.create_room(
                    Room(
                        id=rid,
                        name=f"{TOPICS[i]} Lab",
                        slug=f"demo-{TOPICS[i].lower()}",
                        description="A synthetic development community for sharing ideas.",
                        category=list(RoomCategory)[i],
                        icon=["🎨", "🎮", "🎵", "💻", "🌍"][i],
                        created_by=owner,
                    )
                )
            obj = await c.graph.register_object(owner, "rooms.room", rid, f"{TOPICS[i]} Lab", room_id=rid)
            for n in range(i, 100, 5):
                uid = f"demo_{n:03}"
                if not await c.rooms_repository.is_member(rid, uid):
                    await c.rooms_repository.join_room(rid, uid)
                await c.graph.store.put(
                    key("graph_member", uid, obj["id"]),
                    dict(
                        **{"in": "user:" + uid, "out": obj["id"]},
                        role="owner" if uid == owner else "member",
                        created_at=now(),
                    ),
                )
        note_id = "phlio_note:demo_welcome"
        if not await c.graph.store.get(note_id):
            await c.graph.store.put(
                note_id,
                dict(
                    author="demo_000",
                    recipients=["demo_020"],
                    text=(
                        "Welcome to the Design Lab. These are synthetic accounts "
                        "for testing Phlio's social graph."
                    ),
                    created_at=now(),
                ),
            )
        manifest = dict(
            database=database,
            users=100,
            creators=20,
            consumers=80,
            posts=60,
            videos=20,
            clips=20,
            password=PASSWORD,
            creator="demo_creator_001",
            consumer="demo_viewer_021",
            media="Procedurally generated fictional portraits and animated test patterns; no scraped people.",
        )
        Path("data").mkdir(exist_ok=True)
        Path("data/social_graph_demo.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print(json.dumps(manifest, indent=2))
    finally:
        await c.cache.close()
        await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", default="phlio_graph_dev")
    args = parser.parse_args()
    asyncio.run(seed(args.database))
