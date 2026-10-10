"""Reproducible fictional content across all public catalogs."""

import asyncio
import datetime as dt
import random
import shutil
import subprocess
from pathlib import Path

from app.config import Settings
from app.core.container import build_container, media_root_path
from app.domains.book.entities import BookCategory, BookListing
from app.domains.graph.service import key
from app.infrastructure.database.surreal.client import record


async def seed():
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
    source = Path("../frontend/ui/assets/images/placeholders")
    objects = []
    rng = random.Random(42)

    async def upsert(table, rid, data):
        await c.graph.store.db.query(
            "UPSERT $id CONTENT $data", {"id": record(table + ":" + rid), "data": data}
        )

    async def content(platform, ref, kind, title, description, image, media=""):
        oid = key("phlio_object", platform, ref)
        obj = await c.graph.store.get(oid)
        if obj:
            obj["title"] = title
            await c.graph.store.put(oid, obj)
        else:
            obj = await c.graph.register_object("demo_000", platform + "." + kind, ref, title)
        await c.graph.store.put(
            key("platform_content", platform, ref),
            dict(
                platform=platform,
                domain_ref=ref,
                object_id=oid,
                description=description,
                image_url=image,
                media_url=media,
                kind=kind,
                demo=True,
            ),
        )
        objects.append(obj)

    try:
        for i in range(100):
            await c.graph.set_policy(
                f"demo_{i:03}",
                dict(
                    platform="*",
                    object_type="*",
                    verb="liked",
                    audience="public",
                    identity_mode="identified",
                    foxy_access="none",
                    selected_users=[],
                ),
            )
        titles = [
            "Sketching a neon skyline",
            "Late-night music session",
            "Creative coding experiments",
            "Weekend food walk",
            "The final-round comeback",
            "Small-space workouts",
            "A cozy desk setup",
            "From sketch to color",
            "Exploring a neighborhood",
            "A playlist for focus",
        ]
        print("Preparing 20 videos and 20 clips (existing media is reused)...", flush=True)
        for i in range(20):
            for kind, glob, size in [("video", "thumb_*.png", "960x540"), ("clip", "clip_*.png", "360x640")]:
                images = sorted((source / "social").glob(glob))
                image = images[i % len(images)]
                cover = f"scene_{kind}_{i:02}.png"
                shutil.copyfile(image, root / cover)
                target = root / f"scene_{kind}_{i:02}.mp4"
                print(f"Media {i + 1}/20: {kind}", flush=True)
                if not target.exists():
                    subprocess.run(
                        [
                            "ffmpeg",
                            "-hide_banner",
                            "-loglevel",
                            "error",
                            "-y",
                            "-i",
                            str(image),
                            "-f",
                            "lavfi",
                            "-i",
                            f"sine=frequency={150 + i * 11}:sample_rate=44100",
                            "-vf",
                            f"scale=1200:-2,zoompan=z='min(zoom+0.0008,1.2)':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=240:s={size}:fps=24",
                            "-t",
                            "10",
                            "-c:v",
                            "libx264",
                            "-preset",
                            "ultrafast",
                            "-pix_fmt",
                            "yuv420p",
                            "-c:a",
                            "aac",
                            "-af",
                            "volume=0.035",
                            "-movflags",
                            "+faststart",
                            str(target),
                        ],
                        check=True,
                    )
                ref = f"demo_{kind}_{i:02}"
                title = f"{titles[i % 10]} — {kind} {i + 1}"
                url = "/media/demo_graph/" + target.name
                cover = "/media/demo_graph/" + cover
                c.social_video_service.db.execute(
                    "UPDATE videos SET title=?,url=?,thumbnail_url=? WHERE id=?", (title, url, cover, ref)
                )
                await content("social", ref, kind, title, "Synthetic animated demo content.", cover, url)
        c.social_video_service.db.commit()
        shopnames = [
            "Ceramic breakfast set",
            "Warm desk lamp",
            "Monsoon art print",
            "Brass lantern",
            "Everyday necklace",
            "City sketch collection",
        ]
        for i in range(24):
            ref = f"demo_product_{i:02}"
            seller = f"demo_seller_{i % 6}"
            image = sorted((source / "shop").glob("*.png"))[i % 6]
            shutil.copyfile(image, root / image.name)
            url = "/media/demo_graph/" + image.name
            await upsert(
                "seller",
                seller,
                dict(
                    user_id="user:" + f"demo_{i % 6:03}",
                    display_name=f"Creative Studio {i % 6 + 1}",
                    handle=f"demo_shop_{i % 6}",
                    specialty="Independent design",
                    bio="Fictional demo storefront.",
                    followers_count=0,
                ),
            )
            title = f"{shopnames[i % 6]} · Edition {i // 6 + 1}"
            description = (
                "A fictional handcrafted product for testing discovery and sharing. "
                "Not a real offer for sale."
            )
            await upsert(
                "product",
                ref,
                dict(
                    seller_id="seller:" + seller,
                    title=title,
                    description=description,
                    category="art_and_handmade",
                    condition="handmade",
                    price_minor_units=(650 + i * 125) * 100,
                    currency="INR",
                    image_urls=[url],
                    favorite_count=0,
                    created_at=dt.datetime.now(dt.UTC) - dt.timedelta(minutes=i),
                ),
            )
            await content("shop", ref, "product", title, description, url)
        names = [
            "Rooftop acoustic evening",
            "Weekend badminton",
            "Sunset cycling",
            "Pottery for beginners",
            "Coffee and conversation",
            "Lakeside weekend",
        ]
        bookimages = [
            "listing_movie.png",
            "listing_badminton.png",
            "listing_walk.png",
            "listing_cafe.png",
            "listing_dinner.png",
            "listing_travel.png",
        ]
        for i in range(24):
            ref = f"demo_booking_listing_{i:02}"
            title = f"{names[i % 6]} · Session {i // 6 + 1}"
            image = bookimages[i % 6]
            shutil.copyfile(source / "book" / image, root / image)
            description = "A fictional Hyderabad experience. Invite friends and test the booking flow."
            await c.book_repository.seed_listing(
                BookListing(
                    id=ref,
                    title=title,
                    category=list(BookCategory)[i % 6],
                    venue=[
                        "Skyline Studio",
                        "Rally Courts",
                        "Lakeside Trail",
                        "Clay House",
                        "Coffee Yard",
                        "Green Valley",
                    ][i % 6],
                    location_note="Hyderabad · Demo venue",
                    description=description,
                    price_min_minor_units=(200 + i * 50) * 100,
                    price_max_minor_units=(350 + i * 50) * 100,
                    duration_label="90 minutes",
                    rating=4.5,
                    tags=["demo", "weekend"],
                )
            )
            await content("book", ref, "activity", title, description, "/media/demo_graph/" + image)
        stream_titles = ["Midnight Arcade", "The Quiet City", "Color in Motion", "Weekend Journeys"]
        news_titles = [
            "How shared studios spark creativity",
            "Designing calmer digital spaces",
            "A guide to neighborhood walks",
            "Building welcoming communities",
        ]
        merchants = [
            "Coffee Yard",
            "Clay House",
            "Green Market",
            "Paper Trails",
            "Rally Courts",
            "City Cycles",
        ]
        for i in range(12):
            image = f"/media/demo_graph/scene_video_{i:02}.png"
            await content(
                "stream",
                f"demo_stream_{i:02}",
                "movie",
                f"{stream_titles[i % 4]} · Part {i // 4 + 1}",
                "Synthetic short for testing Stream discovery and playback.",
                image,
                f"/media/demo_graph/scene_video_{i:02}.mp4",
            )
            await content(
                "news",
                f"demo_news_{i:02}",
                "article",
                f"{news_titles[i % 4]} · Perspective {i // 4 + 1}",
                "DEMO ARTICLE — Fictional editorial content.\n\n"
                "Communities grow through repeated moments of connection. "
                "Shared spaces and accessible events make it easier to meet people.\n\n"
                "Start with a small gathering, "
                "listen to participants, and build around activities they enjoy. "
                "This sample is not reporting about real events.",
                image,
            )
        for i in range(6):
            await content(
                "pay",
                f"demo_merchant_{i}",
                "merchant",
                merchants[i],
                "Fictional merchant profile. No real payment is initiated.",
                "/media/demo_graph/" + bookimages[i],
            )
        objects.extend(
            [
                o
                for o in await c.graph.store.rows("phlio_object", {"platform": "social"})
                if o["domain_ref"].startswith("demo_post_")
            ]
        )
        objects.extend(await c.graph.store.rows("phlio_object", {"platform": "rooms"}))
        for obj in objects:
            for i in rng.sample(range(20, 100), rng.randint(6, 15)):
                actor = f"demo_{i:03}"
                if not await c.graph.store.get(key("activity", actor, obj["id"], "liked")):
                    await c.graph.action(actor, obj["id"], "liked")
                if obj["object_type"] == "social.post":
                    await c.social_repository.set_liked(obj["domain_ref"], actor, True)
        print(
            "Ready: 40 videos/clips, 24 products, 24 experiences, "
            "12 Stream shorts, 12 News articles, 6 Pay merchants and cross-platform likes."
        )
    finally:
        await c.graph.store.db.close()
        await c.cache.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    asyncio.run(seed())
