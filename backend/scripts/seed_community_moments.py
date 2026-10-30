"""Seed believable moments (24-hour stories) and profile highlights.

Community accounts post photos and short vertical videos from local media:
Tears of Steel stills and vertical clips for the film creators, and product,
venue and post photos for everyone else. Each run re-dates the live moments
so they stay inside their 24 hours (it runs on every Start-GraphDemo start);
older moments are filed into named highlights on each creator's profile.
Never writes as a real (non-test) account.
"""

import asyncio
import datetime as dt
import hashlib
import random

from app.core.container import build_container
from app.domains.graph.service import key
from scripts.run_graph_demo import settings

TOPICS = ["Design", "Gaming", "Music", "Code", "Travel", "Food", "Fitness", "Photography", "Books", "Science"]
FILM_CAPTIONS = [
    "frame 7 of my Tears of Steel study 🎬", "the lighting in this shot >>>", "rewatching for the compositing",
    "colour grade experiments tonight", "this scene never gets old", "the practical set work here 🤯",
    "study session · open movie edition", "how is this an open-source film", "late night edit 🌙",
    "bridge scene breakdown coming soon", "tracking this shot took forever", "vertical crop test",
]
TOPIC_CAPTIONS = {
    "Design": ["moodboard monday ✨", "new type pairing I'm obsessed with", "desk setup refresh"],
    "Gaming": ["one more match and then sleep", "ranked grind 🎮", "new controller day"],
    "Music": ["studio session 🎧", "this chord progression though", "soundcheck"],
    "Code": ["shipping on a sunday", "it compiled on the first try 😳", "pair programming w/ chai"],
    "Travel": ["golden hour from the window seat ✈️", "weekend getaway", "found the best cafe here"],
    "Food": ["dinner tonight 🍝", "tried a new recipe", "street food crawl"],
    "Fitness": ["5k done before 7am 🏃", "leg day", "stretch and reset"],
    "Photography": ["shot on a 35mm prime", "street walk", "light was perfect today 📷"],
    "Books": ["current read 📖", "annotations everywhere", "bookstore haul"],
    "Science": ["clear skies tonight 🔭", "lab day", "explaining this in my next post"],
}
PURCHASE_CAPTIONS = ["new in 🛍️", "finally ordered it", "unboxing later!", "treat yourself moment"]
VENUE_CAPTIONS = ["tonight's plan 🎟️", "who's coming?", "booked it!", "this place 😍"]
HIGHLIGHT_TITLES = {
    "film": ["Film studies", "Behind the scenes", "Edits"],
    "Design": ["Studio", "Moodboards"], "Gaming": ["Streams", "Setup"], "Music": ["Studio", "Gigs"],
    "Code": ["Builds", "Desk"], "Travel": ["Travel", "Cafés"], "Food": ["Recipes", "Food diaries"],
    "Fitness": ["Workouts", "Runs"], "Photography": ["Street", "Portraits"], "Books": ["Reading", "Hauls"],
    "Science": ["Night sky", "Lab"],
}


def stamp(moment):
    return moment.isoformat()


async def main():
    c = await build_container(settings)
    now = dt.datetime.now(dt.UTC)
    try:
        members = {}
        for i in range(100):
            person = await c.identity_repository.get_by_id(f"demo_{i:03}")
            if person and person.is_test_user:
                members[person.id] = person
        if not members:
            raise SystemExit("Seed the community accounts first (Start-GraphDemo.ps1 -Seed).")

        catalog = []
        for platform in ("shop", "book"):
            for row in await c.graph.store.rows("platform_content", {"platform": platform}):
                if row.get("image_url"):
                    catalog.append((platform, row["image_url"]))
        catalog.sort()

        # Songs from Phlio Stream (CC BY tracks) for moment soundtracks.
        songs = []
        for item in await c.graph.store.rows("platform_content", {"platform": "stream"}):
            if str(item.get("media_url", "")).endswith(".mp3"):
                obj = await c.graph.store.get(item.get("object_id", "")) if item.get("object_id") else None
                songs.append(dict(title=(obj or {}).get("title") or "Untitled",
                                  artist=item.get("publisher") or "Phlio Stream",
                                  url=item["media_url"], cover_url=item.get("image_url"),
                                  path="stream/" + item["domain_ref"]))
        songs.sort(key=lambda song: song["url"])
        profiles = {uid: dict(id=uid, username=p.username, display_name=p.full_name,
                              avatar_url=p.avatar_url) for uid, p in members.items()}

        stills = [f"/media/licensed_social/tears-clip-{i:02}.jpg" for i in range(20)]
        clips = [(f"/media/licensed_social/tears-clip-{i:02}.mp4",
                  f"/media/licensed_social/tears-clip-{i:02}-cover-v2.jpg") for i in range(20)]
        posts = [f"/media/licensed_social/post-{i:02}-{j}-cover-v2.jpg" for i in range(20) for j in (1, 2)]

        creators = [uid for uid in sorted(members) if int(uid[-3:]) < 20]
        viewers = [uid for uid in sorted(members) if int(uid[-3:]) >= 20]
        authors = creators + random.Random(7).sample(viewers, min(16, len(viewers)))
        written = highlights = views = 0
        for uid in authors:
            index = int(uid[-3:])
            rng = random.Random(hashlib.sha256(("moments-v1" + uid).encode()).hexdigest())
            topic = TOPICS[index % 10]
            film = index < 20

            def media():
                roll = rng.random()
                if film and roll < 0.55:
                    video, cover = rng.choice(clips)
                    return "video", video, cover, rng.choice(FILM_CAPTIONS)
                if film and roll < 0.85:
                    still = rng.choice(stills)
                    return "image", still, still, rng.choice(FILM_CAPTIONS)
                if catalog and rng.random() < 0.6:
                    platform, image = rng.choice(catalog)
                    caption = rng.choice(PURCHASE_CAPTIONS if platform == "shop" else VENUE_CAPTIONS)
                    return "image", image, image, caption
                image = rng.choice(posts + stills)
                return "image", image, image, rng.choice(TOPIC_CAPTIONS[topic])

            def row(kind, url, cover, caption, created):
                overlays = []
                if rng.random() < 0.45:
                    overlays.append(dict(type="text", text=caption, x=0.5, y=rng.choice([0.16, 0.22, 0.78]),
                                         color="#FFFFFF", size=24, style="pill"))
                    caption = ""
                extra = {}
                if songs and kind == "image" and rng.random() < 0.55:
                    extra["music"] = rng.choice(songs)
                if film and kind == "video" and rng.random() < 0.3:
                    # A reshare of another creator's clip ("↻ @creator").
                    other = rng.choice([u for u in creators if u != uid] or [uid])
                    extra["reshared_from"] = profiles[other]
                return dict(**extra, author=uid, media_url=url, media_kind=kind, cover_url=cover, caption=caption,
                            overlays=overlays, filter="normal", allow_comments=rng.random() > 0.15,
                            ai_label=False, audience="everyone", recipients=[], seed="moments-v1",
                            created_at=stamp(created), expires_at=stamp(created + dt.timedelta(hours=24)))

            # Live moments, re-dated on every run so they stay within 24 hours.
            live = rng.randint(1, 4) if film else rng.randint(1, 2)
            minutes = sorted(rng.sample(range(8, 20 * 60), live), reverse=True)
            for n, ago in enumerate(minutes):
                kind, url, cover, caption = media()
                mid = f"social_moment:seed_{uid}_live_{n}"
                existing = await c.graph.store.get(mid)
                await c.graph.store.put(mid, row(kind, url, cover, caption, now - dt.timedelta(minutes=ago)))
                written += 1
                if existing:
                    continue  # re-dated only; its views were seeded the first time
                # Other members have watched it already.
                for fan in rng.sample(sorted(members), rng.randint(3, 14)):
                    if fan != uid:
                        await c.graph.store.put(key("moment_view", fan, mid),
                                                dict(user_id=fan, moment_id=mid, author=uid, seen_at=stamp(now)))
                        views += 1

            # Older moments that live on as highlights.
            titles = HIGHLIGHT_TITLES["film"][:1] + HIGHLIGHT_TITLES[topic] if film else HIGHLIGHT_TITLES[topic][:1]
            for t, title in enumerate(titles):
                hid = key("moment_highlight", uid, title.lower())
                if await c.graph.store.get(hid):
                    continue  # highlights are permanent; create them once
                ids, cover_url = [], None
                for n in range(rng.randint(2, 4)):
                    kind, url, cover, caption = media()
                    created = now - dt.timedelta(days=rng.randint(3, 60), minutes=rng.randint(0, 600))
                    mid = f"social_moment:seed_{uid}_h{t}_{n}"
                    await c.graph.store.put(mid, row(kind, url, cover, caption, created))
                    ids.append(mid)
                    cover_url = cover_url or cover
                    written += 1
                await c.graph.store.put(hid, dict(owner=uid, title=title, moment_ids=ids, cover_url=cover_url,
                                                  seed="moments-v1",
                                                  created_at=stamp(now - dt.timedelta(days=90 - t)),
                                                  updated_at=stamp(now)))
                highlights += 1
        print(f"Seeded {written} moments for {len(authors)} people ({highlights} highlights, {views} views).")
    finally:
        await c.cache.close()
        await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    asyncio.run(main())
