"""Open communities for Phlio Rooms: fan and open-source hangouts with real
Creative Commons artwork and lively channels.

What it does (idempotent; rerun any time):
  1. Creates community rooms across every category: Blender Artists, Godot
     Engine Devs, Unity Creators, Among Us Crewmates, Hollow Knight fans,
     Stardew farmers, Celeste climbers and more. These are fan / community
     spaces, not official ones: no brand logos, no "official" claims.
  2. Gives every room (including the five original demo rooms) a banner and an
     icon. Images are searched on Openverse (openverse.org, the WordPress
     Foundation's index of openly licensed media), restricted to licences that
     allow commercial use and modification, cropped locally and credited in
     the room profile. Rooms about the Blender open movies use stills from
     media/open_movies/ (CC BY, Blender Foundation) when those exist.
     Searches are thematic ("glowing cave fungi", "spaceship interior") so no
     copyrighted game characters or logos are pulled in.
  3. Fills rooms with community members (demo accounts) and a few days of
     natural conversation, with emoji reactions.
  4. Replaces the placeholder descriptions and wrong categories of the five
     original demo rooms (Design Lab, Gaming Lab, ...).

Images land in media/rooms_community/ with credits.json beside them.

Run: uv run python -m scripts.import_open_communities [--no-images]
"""
import argparse
import asyncio
import datetime as dt
import hashlib
import io
import json
import random

import httpx
from PIL import Image, ImageOps

from app.core.container import build_container, media_root_path
from app.domains.graph.service import key
from app.domains.graph.store import now
from app.domains.rooms.entities import MessageReaction, Room, RoomCategory, RoomMessage
from scripts.run_graph_demo import settings

SEED = "open-communities-v1"
OPENVERSE = "https://api.openverse.org/v1/images/"
HEADERS = {"User-Agent": "PhlioDevSeed/1.0 (community demo data)"}

G, T, A, TR, F, S, M, ST, L = (RoomCategory.GAMING, RoomCategory.TECH, RoomCategory.ART, RoomCategory.TRAVEL,
                               RoomCategory.FOOD, RoomCategory.SPORTS, RoomCategory.MOVIES, RoomCategory.STUDY,
                               RoomCategory.LOCAL)

# id, name, slug, category, members, banner search, icon search, description, chat
COMMUNITIES = [
    ("hollow_knight", "Hallownest Explorers", "hallownest", G, 88,
     "glowing cave fungi dark", "moth macro",
     "A fan community for Hollow Knight and Silksong: boss strategies, charm builds, lore theories and fan art.",
     ["finally beat the Radiance after 40 tries 😭", "congrats!! which charm build?",
      "Quick Slash + Unbreakable Strength + Shape of Unn, slow but safe", "the lore in the Abyss still haunts me",
      "anyone else replaying before Silksong drops more news?", "Path of Pain is a myth, I refuse",
      "PoP took me two evenings, worth it for the ending room tbh", "drop your favourite area 👇",
      "Greenpath, the music is so calming", "City of Tears every time 🌧️"]),
    ("among_us", "Among Us Crewmates", "crewmates", G, 81,
     "spaceship interior corridor", "astronaut helmet",
     "Find a lobby, plan a game night and share your best impostor plays. Fan-run and friendly.",
     ["lobby at 9pm tonight, need 4 more", "I'm in! proximity chat mod?", "yes, vanilla rules otherwise",
      "who vented in front of me last night 😂", "not me, I was doing wires I swear", "sus",
      "the airship map is so underrated", "fungle map > all", "game night recap: crew won 4/6 🔥",
      "rematch Friday?"]),
    ("stardew", "Stardew Farmers", "stardew-valley", G, 73,
     "farm field sunrise", "chicken farm",
     "Cozy farming chat: layouts, co-op saves, fishing tips and the best gifts for every villager.",
     ["year 3 and I still haven't finished the community center 😅", "the fish bundle is the worst",
      "use the trap bobber, life changing", "my greenhouse layout is finally done 🌱", "post pics!!",
      "ancient fruit wine = gold", "starting a co-op save this weekend, anyone?", "count me in",
      "Ginger Island is my happy place"]),
    ("celeste", "Celeste Climbers", "summit", G, 46,
     "snowy mountain summit night", "strawberry",
     "Celeste fans: speedrun routes, golden strawberry attempts and assist mode is valid.",
     ["got the Farewell golden?? no way", "after 9 hours, hands shaking", "the B-side music hits different",
      "learning wavedashes is humbling", "assist mode is valid, play how you like 💙", "summit is the best chapter",
      "the mirror temple chase still scares me"]),
    ("speedrun", "Speedrun Hub", "speedrun", G, 39,
     "arcade machines neon", "stopwatch",
     "Routes, splits and PB celebrations for any game. Bring your timer.",
     ["new PB on Super Metroid any%! 🎉", "what was the time?", "47:12, the Draygon fight finally behaved",
      "anyone running a relay race next month?", "I can do a segment", "LiveSplit layout tips?",
      "keep it simple: splits, sum of best, previous segment"]),
    ("blender", "Blender Artists", "blender", T, 94,
     None, None,
     "For everyone making things in Blender, the free and open-source 3D suite: modelling, Geometry Nodes, Cycles and EEVEE renders, critiques and help.",
     ["geometry nodes finally clicked for me today", "what were you building?", "a procedural city block generator 🏙️",
      "Cycles or EEVEE for product shots?", "Cycles with denoise, EEVEE for previews", "rendered my first donut 🍩",
      "the donut tutorial is a rite of passage", "anyone tried the new sculpt brushes?", "they're so much smoother",
      "weekly challenge theme: 'tiny worlds'"]),
    ("godot", "Godot Engine Devs", "godot", T, 67,
     "pixel art landscape", "robot toy",
     "Open-source game dev with Godot: GDScript help, shaders, jam teams and devlogs.",
     ["Godot 4 tilemaps are so much nicer now", "anyone joining the game jam this weekend?",
      "looking for an artist, I do code + sound", "I'm in! DM me", "how do you handle save files?",
      "ResourceSaver with a custom Resource, works great", "my first game is on itch.io 🎮", "link pls!",
      "shader tip: use screen_uv for that CRT effect"]),
    ("unity", "Unity Creators", "unity", T, 58,
     "game developer desk monitors", "cube geometric",
     "A community of Unity developers: C# help, URP/HDRP tips, asset workflows and devlogs.",
     ["URP or HDRP for a stylised indie?", "URP, lighter and plenty pretty", "DOTS finally makes sense to me",
      "anyone tried the new input system?", "yes, rebinding is so much easier", "posting my devlog #12 tonight",
      "ScriptableObjects for game data changed my life"]),
    ("linux", "Linux & Open Source", "open-source", T, 52,
     "server room cables", "penguin",
     "Distros, dotfiles, first pull requests and Hacktoberfest buddies. All open-source projects welcome.",
     ["merged my first PR into an open-source project today 🎉", "which project?", "a docs fix for a CLI tool, but it counts",
      "it absolutely counts", "Arch or Fedora for a new laptop?", "Fedora if you want it to just work",
      "rate my rice 👀", "clean, what bar is that?"]),
    ("krita", "Krita Painters", "krita", A, 49,
     "digital painting colorful", "paint brushes",
     "Digital painting with Krita and other open tools: brush packs, timelapses and critique threads.",
     ["new brush pack dropped, link in #resources", "my first full illustration in Krita 🎨", "the colours are gorgeous",
      "how do you paint skies so soft?", "big airbrush + colour smudge, low opacity", "doing a 30-day sketch challenge"]),
    ("pixel_art", "Pixel Art Club", "pixel-art", A, 44,
     "pixel art city", "mosaic tiles",
     "Tiny canvases, big ideas. Palettes, animation tips and weekly prompts.",
     ["prompt of the week: 'rainy shop'", "32x32 or 64x64?", "64 gives you room for lighting",
      "posted a 12-frame walk cycle", "the bounce feels so natural", "palette recommendations?",
      "lospec has great ones, try Endesga 32"]),
    ("open_movies", "Open Movie Club", "open-movies", M, 61,
     None, None,
     "Watch parties and breakdowns of Creative Commons films like Sintel, Big Buck Bunny and Tears of Steel.",
     ["watch party Saturday: Sintel ⚔️🐉", "bringing tissues", "Big Buck Bunny next for the vibes 🐰",
      "the Tears of Steel VFX breakdown is fascinating", "all these films are free to watch and remix, so good",
      "who's doing a rescore challenge?"]),
    ("lofi", "Lo-fi Producers", "lofi", M, 55,
     "synthesizer studio", "vinyl record",
     "Beats to study to, made by us. Share loops, mixing tips and collab ideas.",
     ["new beat, rain samples + rhodes 🌧️", "that vinyl crackle 👌", "any free sample packs you trust?",
      "Freesound has great CC0 field recordings", "collab? I have a chord loop", "sidechain the pads lightly"]),
    ("study_hall", "Open Courseware Study Hall", "study-hall", ST, 63,
     "library reading room", "stack of books",
     "Accountability for self-learners: free courses, pomodoro sessions and study buddies.",
     ["pomodoro starting in 5, who's in?", "in! working on linear algebra", "MIT OCW 18.06 is amazing",
      "finished week 3 of CS50 🎉", "notes or flashcards?", "Anki for facts, notes for concepts"]),
    ("backpackers", "Backpackers Lounge", "backpackers", TR, 47,
     "mountain trail backpack hiking", "compass map",
     "Trip reports, budget routes and gear swaps from travellers everywhere.",
     ["back from 10 days in Ladakh 🏔️", "photos please!", "best budget airline in SE Asia?",
      "depends on the route, book early either way", "lightest rain jacket recommendations?",
      "packing cubes changed my life"]),
    ("home_cooks", "Home Cooks", "home-cooks", F, 57,
     "kitchen cooking vegetables", "spices bowls",
     "Recipes, kitchen wins and fails. Weeknight dinners to weekend projects.",
     ["made biryani from scratch for the first time 🍛", "dum or pakki?", "dum, the smell was unreal",
      "sourdough starter day 6, it's alive", "what flour?", "half whole wheat, half bread flour",
      "weekly challenge: one-pot meals"]),
    ("runners", "Morning Runners", "runners", S, 42,
     "running track sunrise", "running shoes",
     "Couch-to-5K to marathons. Share runs, training plans and race-day nerves.",
     ["5K PB this morning! 24:31 🏃", "nice!! what plan are you on?", "Couch-to-5K then easy miles",
      "half marathon signup done, terrified", "you'll be fine, long runs slow",
      "anyone running the city 10K next month?"]),
    ("blr_meetups", "Bengaluru Meetups", "bengaluru", L, 51,
     "Bangalore city skyline", "park trees bench",
     "Meetups, board-game nights and tech talks around Bengaluru.",
     ["board games at a cafe in Indiranagar on Sunday, 6 spots left", "count me in 🎲",
      "any good Flutter meetups lately?", "there's one next Thursday, I'll share the link",
      "Cubbon Park walk Saturday morning?", "yes! 7am at the bandstand"]),
]

# The five original demo rooms: better copy and the right categories.
DEMO_ROOMS = {
    "demo_room_0": ("Design Lab", "design-lab", A, "UI, branding and motion design: critiques, inspiration and tool tips.",
                    "design studio desk", "color swatches",
                    ["new portfolio piece up, feedback welcome", "love the type pairing",
                     "Figma or Penpot for a team of 3?", "Penpot is open source and great now"]),
    "demo_room_1": ("Gaming Lab", "gaming-lab", G, "Squad up, share clips and talk about whatever you're playing this week.",
                    "gaming setup rgb", "game controller",
                    ["what's everyone playing this weekend?", "back on Hades II, can't stop",
                     "co-op recs for 3 people?", "Deep Rock Galactic, rock and stone ⛏️"]),
    "demo_room_2": ("Music Lab", "music-lab", M, "Producers, players and listeners: share tracks, gear and playlists.",
                    "concert stage lights", "headphones",
                    ["new playlist for late-night coding 🎧", "adding this to my queue",
                     "anyone learning guitar?", "3 months in, barre chords hurt"]),
    "demo_room_3": ("Code Lab", "code-lab", T, "Pair programming, code review and side projects. Every language welcome.",
                    "code on screen", "keyboard mechanical",
                    ["rubber-duck session at 8?", "I'm in, stuck on a race condition",
                     "Rust or Go for a CLI?", "Go if you want it done this weekend 😄"]),
    "demo_room_4": ("Travel Lab", "travel-lab", TR, "Plan trips together, swap itineraries and share photos from the road.",
                    "travel road trip mountains", "suitcase vintage",
                    ["Kerala in monsoon, yes or no?", "yes!! the greenery is unreal",
                     "best app for offline maps?", "Organic Maps, open source and works offline"]),
}

EMOJI = ["🔥", "😂", "❤️", "👍", "🎉", "👀", "💯", "😭"]


def openverse(client, query, aspect):
    """Openly licensed results (commercial use + modification allowed)."""
    response = client.get(OPENVERSE, params=dict(q=query, license_type="commercial,modification",
                                                 aspect_ratio=aspect, page_size=20, mature="false"))
    response.raise_for_status()
    return [r for r in response.json().get("results", []) if r.get("url")]


def fetch_image(client, results, rng, size, used):
    """First result (in a stable shuffled order) that downloads and decodes."""
    order = list(results)
    rng.shuffle(order)
    for item in order:
        if item["url"] in used:
            continue
        for url in (item["url"], item.get("thumbnail")):
            if not url:
                continue
            try:
                data = client.get(url, timeout=40, follow_redirects=True).content
                image = Image.open(io.BytesIO(data)).convert("RGB")
            except Exception:
                continue
            if min(image.size) < 200:
                continue
            used.add(item["url"])
            credit = item.get("attribution") or (
                f"\"{item.get('title') or 'Untitled'}\" by {item.get('creator') or 'unknown'}, "
                f"{(item.get('license') or '').upper()} {item.get('license_version') or ''}".strip())
            return ImageOps.fit(image, size, Image.LANCZOS, centering=(0.5, 0.45)), dict(
                credit=credit, source=item.get("foreign_landing_url") or item["url"],
                license=item.get("license"), license_url=item.get("license_url"))
    return None, None


def local_still(root, prefer):
    covers = sorted((root / "open_movies").glob(f"{prefer}-*-cover.jpg")) if (root / "open_movies").exists() else []
    return covers


async def update_room(c, room_id, **fields):
    repo = c.rooms_repository
    if getattr(repo, "_db", None) is not None:
        values = {k: (v.value if isinstance(v, RoomCategory) else v) for k, v in fields.items()}
        await repo._db.merge(f"room:{room_id}", values)
    else:
        room = await repo.get_room(room_id)
        for name, value in fields.items():
            setattr(room, name, value)


async def main(images=True):
    c = await build_container(settings)
    root = media_root_path(settings)
    out = root / "rooms_community"
    out.mkdir(parents=True, exist_ok=True)
    credits_path = out / "credits.json"
    credits = json.loads(credits_path.read_text(encoding="utf-8")) if credits_path.exists() else {}
    stamp = dt.datetime.now(dt.UTC)
    try:
        members = []
        for i in range(100):
            person = await c.identity_repository.get_by_id(f"demo_{i:03}")
            if person and person.is_test_user:
                members.append(person.id)
        if len(members) < 20:
            raise SystemExit("Seed the community accounts first (Start-GraphDemo.ps1 -Seed).")
        creators = [m for m in members if int(m[-3:]) < 20]

        plan = []  # (room_id, name, slug, category, size, banner_q, icon_q, description, chat)
        for cid, name, slug, category, size, banner_q, icon_q, description, chat in COMMUNITIES:
            plan.append((f"community_{cid}", name, slug, category, size, banner_q, icon_q, description, chat))
        for rid, (name, slug, category, description, banner_q, icon_q, chat) in DEMO_ROOMS.items():
            plan.append((rid, name, slug, category, None, banner_q, icon_q, description, chat))

        client = httpx.Client(headers=HEADERS, timeout=30, follow_redirects=True) if images else None
        used: set = set()
        made = messages = 0
        for rid, name, slug, category, size, banner_q, icon_q, description, chat in plan:
            rng = random.Random(hashlib.sha256((SEED + rid).encode()).hexdigest())
            owner = rng.choice(creators)
            room = await c.rooms_repository.get_room(rid)
            if room is None:
                if size is None:
                    continue  # demo room missing: seed_social_graph hasn't run
                room = await c.rooms_repository.create_room(Room(
                    id=rid, name=name, slug=slug, description=description, category=category,
                    icon="", created_by=owner))
                made += 1
            else:
                owner = room.created_by or owner
                await update_room(c, rid, name=name, slug=slug, description=description, category=category)
            obj = await c.graph.register_object(owner, "rooms.room", rid, name, room_id=rid) \
                if not await c.graph.store.get(key("phlio_object", "rooms", rid)) else \
                await c.graph.store.get(key("phlio_object", "rooms", rid))

            # Members: everyone already in + a stable sample up to the target.
            target = size or 0
            pool = [m for m in members if m != owner]
            joiners = [owner] + rng.sample(pool, min(len(pool), max(0, target - 1)))
            for uid in joiners:
                if not await c.rooms_repository.is_member(rid, uid):
                    await c.rooms_repository.join_room(rid, uid)
                edge = key("graph_member", uid, obj["id"])
                if not await c.graph.store.get(edge):
                    await c.graph.store.put(edge, {"in": "user:" + uid, "out": obj["id"],
                                                   "role": "owner" if uid == owner else "member",
                                                   "created_at": now()})

            # Banner + icon.
            profile_key = key("room_profile", rid)
            profile = await c.graph.store.get(profile_key) or {}
            profile.update(room_id=rid, description=description, seed=SEED)
            for part, query, box in (("banner", banner_q, (960, 400)), ("icon", icon_q, (256, 256))):
                target_file = out / f"{slug}-{part}.jpg"
                if not target_file.exists():
                    image = info = None
                    film = {"blender": "sintel", "open-movies": "bbb"}.get(slug)
                    if film:
                        covers = local_still(root, film if part == "banner" else ("bbb" if film == "sintel" else "sintel"))
                        if covers:
                            image = ImageOps.fit(Image.open(rng.choice(covers)).convert("RGB"), box, Image.LANCZOS)
                            info = dict(credit="Still from a Blender Foundation open movie (blender.org), CC BY",
                                        source="https://studio.blender.org/films/", license="by",
                                        license_url="https://creativecommons.org/licenses/by/3.0/")
                    if image is None and client is not None and query:
                        try:
                            results = openverse(client, query, "wide" if part == "banner" else "square")
                            image, info = fetch_image(client, results, rng, box, used)
                        except httpx.HTTPError as exc:
                            print(f"  Openverse search failed for '{query}': {exc}", flush=True)
                    if image is None and film is None and client is not None and query:
                        print(f"  no {part} for {name}; it will show initials", flush=True)
                    if image is not None:
                        image.save(target_file, quality=86)
                        credits[target_file.name] = info
                if target_file.exists():
                    profile[f"{part}_url"] = f"/media/rooms_community/{target_file.name}"
                    if part == "banner" and target_file.name in credits:
                        profile["credit"] = credits[target_file.name]["credit"]
            await c.graph.store.put(profile_key, profile)

            # A few days of conversation (oldest first), with reactions.
            speakers = [m for m in joiners if m != owner] or joiners
            start = stamp - dt.timedelta(days=rng.uniform(4, 6))
            span = (stamp - start).total_seconds() - 1800
            times = sorted(rng.random() for _ in chat)
            previous = None
            for n, (text, t) in enumerate(zip(chat, times)):
                mid = f"seed_{rid}_{n:02}"
                if await c.rooms_repository.get_message(rid, mid):
                    continue
                author = owner if n == 0 and rng.random() < .5 else rng.choice(speakers)
                if author == previous and len(speakers) > 1:
                    author = rng.choice([s for s in speakers if s != previous])
                previous = author
                reactions = []
                for fan in rng.sample(joiners, min(len(joiners), rng.choice([0, 0, 1, 2, 3, 5]))):
                    if fan != author:
                        reactions.append(MessageReaction(kind="emoji", value=rng.choice(EMOJI[:4] if n % 2 else EMOJI),
                                                         user_id=fan))
                await c.rooms_repository.add_message(RoomMessage(
                    id=mid, room_id=rid, author_id=author, text=text,
                    created_at=start + dt.timedelta(seconds=span * t), reactions=reactions))
                messages += 1
            print(f"{name}: {len(joiners)} members, banner {'yes' if profile.get('banner_url') else 'no'}, "
                  f"icon {'yes' if profile.get('icon_url') else 'no'}", flush=True)
        credits_path.write_text(json.dumps(credits, indent=2, ensure_ascii=False), encoding="utf-8")
        if client is not None:
            client.close()
        print(f"Created {made} community rooms; added {messages} messages.", flush=True)
    finally:
        await c.cache.close()
        if getattr(c.graph.store, "db", None):
            await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-images", action="store_true", help="skip the Openverse image search")
    asyncio.run(main(images=not parser.parse_args().no_images))
