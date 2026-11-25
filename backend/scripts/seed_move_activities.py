"""Seeds Phlio Move activities from the community accounts (seed id ``move-v1``).

Runs, rides, walks, a swim and a few no-GPS sessions (yoga, gym, badminton)
around real Indian parks and promenades, over the last ten days. Each one is
shared to Phlio Social like a real activity (route picture, post), and other
members give kudos, so the Posts tab's Move card stack has something to show.

Routes are drawn, not recorded: smooth loops or out-and-backs with a little
wobble, timed at a realistic pace. Followers are not notified.

    uv run python -m scripts.seed_move_activities            # local graph (demo_000…)
    uv run python -m scripts.seed_move_activities --cloud    # Surreal Cloud (.env.publish)
    uv run python -m scripts.seed_move_activities --reset    # remove this seed

In development with the in-memory backend the API seeds this by itself at
startup (see app/main.py), using the demo users.
"""

from __future__ import annotations

import asyncio
import datetime as dt
import hashlib
import math
import random

SEED = "move-v1"
TABLE = "phlio_activity"
KUDOS = "activity_kudos"
EMOJIS = ["👏", "🔥", "💪", "❤️"]

# name, centre (lat, lng), loop radius in metres (or None for a straight promenade + bearing)
PLACES = [
    ("Cubbon Park, Bengaluru", (12.9763, 77.5929), 650, None),
    ("KBR Park, Hyderabad", (17.4239, 78.4250), 520, None),
    ("Lodhi Garden, Delhi", (28.5933, 77.2195), 380, None),
    ("Necklace Road, Hyderabad", (17.4239, 78.4738), 900, None),
    ("Marine Drive, Mumbai", (18.9440, 72.8230), None, 20),
    ("Besant Nagar beach, Chennai", (13.0003, 80.2717), None, 5),
    ("Sukhna Lake, Chandigarh", (30.7421, 76.8188), 700, None),
    ("Kasturba Road, Pune", (18.5335, 73.8830), 450, None),
]

# sport, title, description, distance km (min, max), pace s/km (min, max) or minutes for no-GPS
PLANS = [
    ("run", "Morning loop", "Easy pace, legs felt fresh. Coffee next ☕", (4.5, 8.0), (300, 380)),
    ("run", "Tempo Tuesday", "3 km warm-up then tempo. That last km hurt 😅", (7.0, 10.0), (270, 320)),
    ("ride", "Sunday ride", "Breezy out there, perfect for a long spin.", (18.0, 32.0), (110, 150)),
    ("walk", "Evening walk", "Sunset walk with the family 🌅", (2.5, 4.5), (600, 720)),
    ("run", "Long run", "Building up for the half marathon. Slow and steady.", (12.0, 16.0), (330, 390)),
    ("hike", "Weekend hike", "Steps, trees and a lot of birds.", (5.0, 8.0), (700, 900)),
    ("ride", "Commute ride", "Beat the traffic today 🚲", (8.0, 12.0), (130, 170)),
    ("run", "Recovery jog", "Nice and slow after yesterday.", (3.0, 5.0), (360, 420)),
    ("walk", "Lunch walk", "Got my steps in between meetings.", (2.0, 3.0), (620, 700)),
    ("swim", "Pool session", "20 laps. Working on breathing every 3.", (1.0, 1.6), (130, 170)),
    ("yoga", "Sunrise yoga", "45 minutes of flow. Calm start to the day 🧘", None, (40, 60)),
    ("weight_training", "Leg day", "Squats, lunges, deadlifts. Stairs will be fun tomorrow.", None, (45, 70)),
    ("badminton", "Badminton doubles", "3 games, won 2 🏸", None, (50, 80)),
    ("hiit", "HIIT at home", "20 minutes, no equipment, zero mercy.", None, (18, 25)),
]


def _route(rng: random.Random, centre, radius, bearing, distance_m: float, pace: float) -> list[list[float]]:
    """[[lat, lng, seconds], ...] covering about ``distance_m``."""
    lat0, lng0 = centre
    m_lat = 111_320.0
    m_lng = 111_320.0 * math.cos(math.radians(lat0))
    points = []
    if radius:
        # Loops around the park; several laps when the distance is long.
        laps = max(1.0, distance_m / (2 * math.pi * radius))
        n = int(90 * laps)
        stretch = rng.uniform(0.75, 1.25)
        phase = rng.uniform(0, math.tau)
        for i in range(n + 1):
            a = phase + math.tau * laps * i / n
            wobble = 1 + 0.06 * math.sin(5 * a) + rng.uniform(-0.01, 0.01)
            dy = radius * wobble * math.sin(a)
            dx = radius * stretch * wobble * math.cos(a)
            points.append([lat0 + dy / m_lat, lng0 + dx / m_lng])
    else:
        # Out and back along a promenade.
        half = distance_m / 2
        n = 140
        b = math.radians(bearing)
        for i in range(n + 1):
            f = i / n
            d = half * (2 * f if f <= 0.5 else 2 - 2 * f)
            side = 6 * math.sin(f * 40) + (8 if f > 0.5 else 0)
            dy = d * math.cos(b) - side * math.sin(b)
            dx = d * math.sin(b) + side * math.cos(b)
            points.append([lat0 + dy / m_lat, lng0 + dx / m_lng])
    total = 0.0
    out = [[points[0][0], points[0][1], 0.0]]
    for prev, cur in zip(points, points[1:]):
        step = math.hypot((cur[0] - prev[0]) * m_lat, (cur[1] - prev[1]) * m_lng)
        total += step * pace / 1000 * rng.uniform(0.9, 1.1)
        out.append([round(cur[0], 6), round(cur[1], 6), round(total, 1)])
    return out


async def backdate_posts(c) -> int:
    """Gives each seeded activity's Social post its activity's start time.

    Posts are created "now", so a fresh seed put ~40 activity posts on top of
    the feed; with the Posts tab showing activities in the card stack instead,
    the first page of posts could look empty. Idempotent."""
    rows = [r for r in await c.graph.store.rows(TABLE) if r.get("seed") == SEED and r.get("post_id")]
    db = getattr(c.graph.store, "db", None)
    fixed = 0
    for row in rows:
        when = dt.datetime.fromisoformat(row["started_at"]).astimezone(dt.UTC)
        if db is not None:
            await db.query("UPDATE type::record('post', $id) SET created_at = $at RETURN NONE",
                           {"id": row["post_id"], "at": when})
        else:
            repo = c.social_repository
            post = getattr(repo, "_posts", {}).get(row["post_id"])
            if post is None:
                continue
            post.created_at = when
            repo._posts_newest_first.sort(key=lambda p: p.created_at, reverse=True)
        fixed += 1
    return fixed


async def seed(c, people: list, *, per_person: int = 2, quiet: bool = False) -> int:
    """Creates the activities for ``people`` (identity ``User`` objects).
    Idempotent: does nothing if this seed is already there."""
    from app.api.v1 import activities as A
    from app.domains.graph.service import key

    existing = [r for r in await c.graph.store.rows(TABLE) if r.get("seed") == SEED]
    if existing or len(people) < 2:
        if existing:
            await backdate_posts(c)
        return 0
    now_dt = dt.datetime.now(dt.UTC)
    announce = A._announce

    async def silent(*_args, **_kwargs):
        return None

    A._announce = silent  # seeded activities don't notify anyone
    written = 0
    try:
        for person in people:
            rng = random.Random(hashlib.sha256((SEED + person.id).encode()).hexdigest())
            for n in range(per_person):
                sport, title, desc, km, pace = PLANS[rng.randrange(len(PLANS))]
                place, centre, radius, bearing = PLACES[rng.randrange(len(PLACES))]
                started = (now_dt - dt.timedelta(days=rng.uniform(0.1, 10))).replace(
                    hour=rng.choice([6, 6, 7, 7, 8, 17, 18, 19]), minute=rng.randrange(60), second=0, microsecond=0)
                if started > now_dt:
                    started -= dt.timedelta(days=1)
                body = dict(sport=sport, title=f"{title} · {place.split(',')[0]}" if km else title, description=desc,
                            started_at=started, visibility="everyone", hide_endpoints=True, post=True)
                if km:
                    distance = rng.uniform(*km) * 1000
                    p = rng.uniform(*pace)
                    route = _route(rng, centre, radius, bearing if bearing is not None else 0, distance, p)
                    body.update(route=route, elapsed_s=int(route[-1][2] * rng.uniform(1.02, 1.12)),
                                moving_s=int(route[-1][2]), elevation_m=round(rng.uniform(4, 60), 1))
                else:
                    minutes = rng.uniform(*pace)
                    body.update(elapsed_s=int(minutes * 60))
                saved = await A.create(A.ActivityIn(**body), user=person, c=c)
                aid = saved["id"]
                row = await c.graph.store.get(f"{TABLE}:{aid}")
                await c.graph.store.put(row["id"], dict({k: v for k, v in row.items() if k != "id"}, seed=SEED))
                givers = [p for p in people if p.id != person.id]
                for giver in rng.sample(givers, min(len(givers), rng.randint(1, 9))):
                    at = started + dt.timedelta(minutes=rng.randint(30, 600))
                    await c.graph.store.put(key(KUDOS, aid, giver.id), dict(
                        activity_id=row["id"], user_id=giver.id, emoji=rng.choice(EMOJIS),
                        at=min(at, now_dt).isoformat(), seed=SEED))
                written += 1
    finally:
        A._announce = announce
    await backdate_posts(c)
    if not quiet:
        print(f"Seeded {written} Phlio Move activities for {len(people)} people.")
    return written


async def reset(c) -> int:
    from app.api.v1 import activities as A

    rows = [r for r in await c.graph.store.rows(TABLE) if r.get("seed") == SEED]
    for row in rows:
        owner = await c.identity_repository.get_by_id(row["user_id"])
        try:
            # Deletes the activity and marks its Social post deleted.
            await A.delete(row["id"].removeprefix(TABLE + ":"), user=owner, c=c)
        except Exception:  # noqa: BLE001
            await c.graph.store.delete(row["id"])
    for k in [r for r in await c.graph.store.rows(KUDOS) if r.get("seed") == SEED]:
        await c.graph.store.delete(k["id"])
    print(f"Removed {len(rows)} seeded activities.")
    return len(rows)


async def main(cloud: bool = False, do_reset: bool = False):
    from app.core.container import build_container

    if cloud:
        from scripts.run_seeded_spaces import cloud_settings
        target = cloud_settings()
    else:
        from scripts.run_graph_demo import settings as target
    c = await build_container(target)
    try:
        if do_reset:
            await reset(c)
            return
        people = []
        for i in range(100):
            person = await c.identity_repository.get_by_id(f"demo_{i:03}")
            if person and person.is_test_user:
                people.append(person)
        if not people:
            raise SystemExit("Seed the community accounts first (Start-GraphDemo.ps1 -Seed).")
        # About 40 activities: two each from 20 members.
        rng = random.Random(SEED)
        chosen = rng.sample(people, min(20, len(people)))
        if not await seed(c, chosen, per_person=2):
            print("Already seeded; activity posts are dated to their activities (use --reset to remove and seed again).")
    finally:
        await c.cache.close()
        db = getattr(c.graph.store, "db", None)
        if db is not None:
            await db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Seed Phlio Move activities from community accounts.")
    parser.add_argument("--cloud", action="store_true", help="write to Surreal Cloud (backend/.env.publish)")
    parser.add_argument("--reset", action="store_true", help="remove this seed's activities, posts and kudos")
    args = parser.parse_args()
    asyncio.run(main(args.cloud, args.reset))
