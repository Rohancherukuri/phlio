"""Phlio Move: record a run, ride, walk or workout, then share it.

Opened from the Phlio Agent explore tab. A finished activity can be posted
to Phlio Social (a route card in the feed); tapping that post leads to the
activity in the Agent explore tab, where people react (kudos), comment with
@mentions, stickers, GIFs, voice notes and 30-second music snippets (the
shared content-comment system, keyed by the activity's post).

    GET    /activities/sports                 sport catalog (groups)
    GET    /activities/summary                your week, streak, totals, intro flag
    POST   /activities/intro-seen             privacy intro shown
    GET    /activities?user=<username>        a person's activities (newest first)
    POST   /activities                        save (and optionally post) an activity
    GET    /activities/{id}                   detail (route trimmed for others when
                                              "hide start & end" is on)
    GET    /activities/by-post/{post_id}      the activity behind a Social post
    PATCH  /activities/{id}                   edit title, description, sport, privacy, tags
    DELETE /activities/{id}                   delete (and its post)
    PUT    /activities/{id}/kudos {emoji}     react;  DELETE removes your reaction

Privacy
  * visibility "everyone" posts to Social; "only_me" never leaves your device
    list (no post, others get 404).
  * hide_endpoints (default on): the first and last 200 m of the route are
    removed from everything others see — the map, the post image and the
    distance markers — so home and work addresses don't leak.
"""

from __future__ import annotations

import datetime as dt
import math
import re
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.core.container import media_root_path
from app.domains.graph.service import key
from app.domains.graph.store import now

router = APIRouter(prefix="/activities", tags=["activities"])

TABLE = "phlio_activity"
KUDOS = "activity_kudos"
PRIVATE_RADIUS_M = 200
EMOJIS = ("👏", "🔥", "💪", "❤️", "😮", "🏅")

# id → (label, group, uses distance, pace (min/km) rather than speed)
SPORTS: dict[str, tuple[str, str, bool, bool]] = {
    "run": ("Run", "Foot", True, True),
    "trail_run": ("Trail Run", "Foot", True, True),
    "walk": ("Walk", "Foot", True, True),
    "hike": ("Hike", "Foot", True, True),
    "wheelchair": ("Wheelchair", "Foot", True, False),
    "ride": ("Ride", "Cycle", True, False),
    "mountain_bike": ("Mountain Bike Ride", "Cycle", True, False),
    "gravel_ride": ("Gravel Ride", "Cycle", True, False),
    "ebike": ("E-Bike Ride", "Cycle", True, False),
    "handcycle": ("Handcycle", "Cycle", True, False),
    "swim": ("Swim", "Water", True, True),
    "kayak": ("Kayaking", "Water", True, False),
    "rowing": ("Rowing", "Water", True, True),
    "surf": ("Surfing", "Water", False, False),
    "weight_training": ("Weight Training", "Strength", False, False),
    "workout": ("Workout", "Strength", False, False),
    "hiit": ("HIIT", "Strength", False, False),
    "yoga": ("Yoga", "Strength", False, False),
    "ski": ("Ski", "Winter", True, False),
    "snowboard": ("Snowboard", "Winter", True, False),
    "football": ("Football", "Sports", False, False),
    "cricket": ("Cricket", "Sports", False, False),
    "badminton": ("Badminton", "Sports", False, False),
    "tennis": ("Tennis", "Sports", False, False),
    "basketball": ("Basketball", "Sports", False, False),
    "climbing": ("Rock Climbing", "Sports", False, False),
    "dance": ("Dance", "Sports", False, False),
}
# Rough MET values for a calorie estimate (kcal = MET × kg × hours, 70 kg).
MET = {"run": 9.8, "trail_run": 10, "walk": 3.5, "hike": 6, "ride": 7.5, "mountain_bike": 8.5, "swim": 8,
       "weight_training": 5, "workout": 6, "hiit": 8, "yoga": 3, "football": 7, "badminton": 5.5, "tennis": 7,
       "basketball": 6.5, "dance": 5, "climbing": 8, "rowing": 7, "kayak": 5, "ski": 7, "snowboard": 5.3}


class ActivityIn(BaseModel):
    sport: str = "run"
    title: str = Field(default="", max_length=120)
    description: str = Field(default="", max_length=2000)
    started_at: dt.datetime | None = None
    elapsed_s: int = Field(default=0, ge=0, le=7 * 24 * 3600)
    moving_s: int | None = Field(default=None, ge=0, le=7 * 24 * 3600)
    distance_m: float | None = Field(default=None, ge=0, le=2_000_000)
    elevation_m: float = Field(default=0, ge=0, le=20_000)
    # [[lat, lng, seconds since start], ...]
    route: list[list[float]] = Field(default_factory=list, max_length=20_000)
    visibility: str = "everyone"
    hide_endpoints: bool = True
    tagged: list[str] = Field(default_factory=list, max_length=20)
    post: bool = True


class ActivityPatch(BaseModel):
    sport: str | None = None
    title: str | None = Field(default=None, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    visibility: str | None = None
    hide_endpoints: bool | None = None
    tagged: list[str] | None = Field(default=None, max_length=20)


class KudosIn(BaseModel):
    emoji: str = "👏"


# -- geometry -------------------------------------------------------------------

def haversine(a: list[float], b: list[float]) -> float:
    lat1, lng1, lat2, lng2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lng2 - lng1) / 2) ** 2
    return 2 * 6_371_000 * math.asin(min(1, math.sqrt(h)))


def route_length(route: list[list[float]]) -> float:
    return sum(haversine(route[i - 1], route[i]) for i in range(1, len(route)))


def trim_endpoints(route: list[list[float]], radius: float = PRIVATE_RADIUS_M) -> list[list[float]]:
    """Drop the points within `radius` metres (along the route) of the start
    and of the end."""
    if len(route) < 3:
        return []
    walked, first = 0.0, None
    for i in range(1, len(route)):
        walked += haversine(route[i - 1], route[i])
        if walked >= radius:
            first = i
            break
    walked, last = 0.0, None
    for i in range(len(route) - 1, 0, -1):
        walked += haversine(route[i - 1], route[i])
        if walked >= radius:
            last = i - 1
            break
    if first is None or last is None or last <= first:
        return []
    return route[first:last + 1]


def splits(route: list[list[float]]) -> list[dict]:
    """Per-kilometre splits from timestamped points ([lat, lng, t])."""
    if len(route) < 2 or any(len(p) < 3 for p in route):
        return []
    out, walked, mark, t0 = [], 0.0, 1000.0, route[0][2]
    for i in range(1, len(route)):
        walked += haversine(route[i - 1], route[i])
        while walked >= mark:
            t = route[i][2]
            out.append(dict(km=len(out) + 1, seconds=round(t - t0)))
            t0, mark = t, mark + 1000
    rest = walked - (mark - 1000)
    if rest >= 100 and route[-1][2] > t0:
        out.append(dict(km=round(len(out) + rest / 1000, 2), seconds=round(route[-1][2] - t0), partial=True))
    return out


# -- route picture (used as the Social post image) ------------------------------

def render_route(route: list[list[float]], target) -> bool:
    """A 1080×640 route card in Phlio colours: night map grid, the route in
    the sunset orange, a start dot and a finish ring."""
    if len(route) < 2:
        return False
    from PIL import Image, ImageDraw

    w, h, pad = 1080, 640, 70
    img = Image.new("RGB", (w, h), (12, 19, 30))
    d = ImageDraw.Draw(img)
    # A quiet "street" grid so the route reads as a map.
    for x in range(0, w, 72):
        d.line([(x, 0), (x, h)], fill=(20, 30, 45), width=2)
    for y in range(0, h, 72):
        d.line([(0, y), (w, y)], fill=(20, 30, 45), width=2)
    lats = [p[0] for p in route]
    lngs = [p[1] for p in route]
    mid = math.cos(math.radians((max(lats) + min(lats)) / 2))
    span_x = max((max(lngs) - min(lngs)) * mid, 1e-6)
    span_y = max(max(lats) - min(lats), 1e-6)
    scale = min((w - 2 * pad) / span_x, (h - 2 * pad) / span_y)
    ox = (w - span_x * scale) / 2
    oy = (h - span_y * scale) / 2

    def xy(p):
        return (ox + (p[1] - min(lngs)) * mid * scale, h - (oy + (p[0] - min(lats)) * scale))

    pts = [xy(p) for p in route]
    d.line(pts, fill=(255, 140, 90), width=12, joint="curve")
    sx, sy = pts[0]
    ex, ey = pts[-1]
    d.ellipse([sx - 14, sy - 14, sx + 14, sy + 14], fill=(104, 215, 205), outline=(12, 19, 30), width=4)
    d.ellipse([ex - 16, ey - 16, ex + 16, ey + 16], fill=(247, 247, 250), outline=(255, 140, 90), width=6)
    target.parent.mkdir(parents=True, exist_ok=True)
    img.save(target, "JPEG", quality=86)
    return True


# -- helpers --------------------------------------------------------------------

def _default_title(sport: str, at: dt.datetime) -> str:
    hour = at.hour
    part = "Morning" if 5 <= hour < 12 else "Afternoon" if hour < 17 else "Evening" if hour < 21 else "Night"
    return f"{part} {SPORTS[sport][0]}"


def _fmt_km(m: float) -> str:
    return f"{m / 1000:.2f} km"


def _summary_line(row: dict) -> str:
    label = SPORTS.get(row["sport"], ("activity",))[0].lower()
    if row.get("distance_m"):
        return f"{_fmt_km(row['distance_m'])} {label}"
    mins = round((row.get("moving_s") or row.get("elapsed_s") or 0) / 60)
    return f"{mins} min {label}"


async def _resolve_tags(c, actor_id: str, usernames: list[str]) -> list[str]:
    ids = []
    for name in usernames:
        person = await c.identity_repository.get_by_username(name.lstrip("@").lower())
        if person and person.id != actor_id and not await c.graph.blocked(actor_id, person.id) and person.id not in ids:
            ids.append(person.id)
    return ids


async def _get(c, activity_id: str) -> dict:
    row = await c.graph.store.get(f"{TABLE}:{activity_id.removeprefix(TABLE + ':')}")
    if not row:
        raise HTTPException(404, "Activity not found.")
    return row


async def _visible(c, row: dict, viewer: str) -> bool:
    if row["user_id"] == viewer:
        return True
    if row.get("visibility") == "only_me":
        return False
    return not await c.graph.blocked(viewer, row["user_id"])


async def _out(c, row: dict, viewer: str, *, full: bool = True) -> dict:
    mine = row["user_id"] == viewer
    route = row.get("route") or []
    if not mine and row.get("hide_endpoints", True):
        route = trim_endpoints(route)
    author = await c.identity_repository.get_by_id(row["user_id"])
    label, group, uses_distance, pace = SPORTS.get(row["sport"], ("Activity", "Other", False, False))
    moving = row.get("moving_s") or row.get("elapsed_s") or 0
    dist = row.get("distance_m") or 0
    out = dict(
        id=row["id"].removeprefix(TABLE + ":"), sport=row["sport"], sport_label=label, group=group,
        uses_distance=uses_distance, pace=pace, title=row["title"], description=row.get("description", ""),
        started_at=row["started_at"], elapsed_s=row.get("elapsed_s", 0), moving_s=moving, distance_m=dist,
        elevation_m=row.get("elevation_m", 0), calories=row.get("calories", 0),
        pace_s_per_km=round(moving / (dist / 1000)) if dist >= 50 and moving else None,
        speed_kmh=round(dist / 1000 / (moving / 3600), 1) if dist and moving else None,
        visibility=row.get("visibility", "everyone"), hide_endpoints=row.get("hide_endpoints", True),
        post_id=row.get("post_id"), image_url=row.get("image_url"), mine=mine,
        author=c.graph.profile(author) if author else None, created_at=row.get("created_at"),
    )
    kudos = await c.graph.store.rows(KUDOS, {"activity_id": row["id"]})
    kudos = [k for k in kudos if not await c.graph.blocked(viewer, k["user_id"])]
    counts: dict[str, int] = {}
    for k in kudos:
        counts[k["emoji"]] = counts.get(k["emoji"], 0) + 1
    out.update(kudos_count=len(kudos), kudos=counts,
               my_kudos=next((k["emoji"] for k in kudos if k["user_id"] == viewer), None))
    if full:
        tagged = []
        for uid in row.get("tagged", []):
            person = await c.identity_repository.get_by_id(uid)
            if person and not await c.graph.blocked(viewer, uid):
                tagged.append(c.graph.profile(person))
        givers = []
        for k in sorted(kudos, key=lambda k: k["at"], reverse=True)[:12]:
            person = await c.identity_repository.get_by_id(k["user_id"])
            if person:
                givers.append(dict(c.graph.profile(person), emoji=k["emoji"]))
        out.update(route=[p[:2] for p in route], splits=splits(row.get("route") or []) if mine or not row.get("hide_endpoints", True) else splits(route),
                   tagged=tagged, kudos_people=givers)
    return out


# -- endpoints ------------------------------------------------------------------

@router.get("/sports")
async def sports():
    groups: dict[str, list] = {}
    for sid, (label, group, uses_distance, pace) in SPORTS.items():
        groups.setdefault(group, []).append(dict(id=sid, label=label, uses_distance=uses_distance, pace=pace))
    return dict(groups=[dict(name=g, sports=s) for g, s in groups.items()])


@router.get("/summary")
async def summary(user=Depends(get_current_user), c=Depends(get_container)):
    rows = await c.graph.store.rows(TABLE, {"user_id": user.id})
    today = dt.datetime.now(dt.UTC).date()
    week_start = today - dt.timedelta(days=today.weekday())
    days = {dt.datetime.fromisoformat(r["started_at"]).date() for r in rows}
    week = [r for r in rows if dt.datetime.fromisoformat(r["started_at"]).date() >= week_start]
    streak, day = 0, today if today in days else today - dt.timedelta(days=1)
    while day in days:
        streak += 1
        day -= dt.timedelta(days=1)
    top: dict[str, int] = {}
    for r in rows:
        top[r["sport"]] = top.get(r["sport"], 0) + 1
    seen = await c.graph.store.get(key("account_setting", user.id, "activity_intro"))
    return dict(
        intro_seen=bool(seen),
        streak_days=streak,
        week=dict(count=len(week), distance_m=sum(r.get("distance_m") or 0 for r in week),
                  moving_s=sum(r.get("moving_s") or r.get("elapsed_s") or 0 for r in week),
                  elevation_m=sum(r.get("elevation_m") or 0 for r in week),
                  days=[(week_start + dt.timedelta(days=i)).isoformat() in {d.isoformat() for d in days} for i in range(7)]),
        totals=dict(count=len(rows), distance_m=sum(r.get("distance_m") or 0 for r in rows),
                    moving_s=sum(r.get("moving_s") or r.get("elapsed_s") or 0 for r in rows)),
        top_sports=[s for s, _ in sorted(top.items(), key=lambda kv: -kv[1])[:3]] or ["run", "walk", "hike"],
    )


@router.post("/intro-seen", status_code=204)
async def intro_seen(user=Depends(get_current_user), c=Depends(get_container)):
    await c.graph.store.put(key("account_setting", user.id, "activity_intro"), dict(user_id=user.id, at=now()))
    return Response(status_code=204)


@router.get("")
async def list_activities(user_name: str | None = Query(None, alias="user"), limit: int = Query(30, ge=1, le=100),
                          user=Depends(get_current_user), c=Depends(get_container)):
    owner = user
    if user_name and user_name.lstrip("@").lower() != user.username.lower():
        owner = await c.identity_repository.get_by_username(user_name.lstrip("@").lower())
        if owner is None:
            raise HTTPException(404, "No one with that username.")
    rows = await c.graph.store.rows(TABLE, {"user_id": owner.id})
    rows = [r for r in rows if await _visible(c, r, user.id)]
    rows.sort(key=lambda r: r["started_at"], reverse=True)
    return dict(items=[await _out(c, r, user.id, full=False) for r in rows[:limit]])


@router.post("", status_code=201)
async def create(body: ActivityIn, user=Depends(get_current_user), c=Depends(get_container)):
    if body.sport not in SPORTS:
        raise HTTPException(422, "Choose a sport from the list.")
    if body.visibility not in {"everyone", "only_me"}:
        raise HTTPException(422, "Visibility must be everyone or only_me.")
    if body.elapsed_s <= 0 and not body.route:
        raise HTTPException(422, "Add how long the activity took.")
    await c.cache.rate_limit(user.id, "activity", 30)
    route = [p[:3] for p in body.route if len(p) >= 2 and -90 <= p[0] <= 90 and -180 <= p[1] <= 180]
    started = (body.started_at or dt.datetime.now(dt.UTC)).astimezone(dt.UTC)
    distance = body.distance_m if body.distance_m is not None else round(route_length(route), 1)
    elapsed = body.elapsed_s or (round(route[-1][2] - route[0][2]) if route and len(route[0]) > 2 else 0)
    moving = min(body.moving_s if body.moving_s is not None else elapsed, elapsed) if elapsed else body.moving_s or 0
    aid = uuid.uuid4().hex
    calories = round(MET.get(body.sport, 5) * 70 * (moving / 3600))
    row = dict(user_id=user.id, sport=body.sport, title=body.title.strip() or _default_title(body.sport, started.astimezone()),
               description=body.description.strip(), started_at=started.isoformat(), elapsed_s=elapsed,
               moving_s=moving, distance_m=round(distance or 0, 1), elevation_m=round(body.elevation_m, 1),
               calories=calories, route=route, visibility=body.visibility, hide_endpoints=body.hide_endpoints,
               tagged=await _resolve_tags(c, user.id, body.tagged), post_id=None, image_url=None, created_at=now())

    # The post image is drawn from the route others may see.
    public_route = trim_endpoints(route) if body.hide_endpoints else route
    image = media_root_path(c.settings) / "activities" / f"{aid}.jpg"
    if render_route(public_route, image):
        row["image_url"] = f"/media/activities/{aid}.jpg"
    saved = await c.graph.store.put(f"{TABLE}:{aid}", row)

    if body.post and body.visibility == "everyone":
        from app.domains.social.entities import MediaAttachment, MediaKind

        text = row["title"] + (f"\n\n{row['description']}" if row["description"] else "")
        media = [MediaAttachment(url=row["image_url"], kind=MediaKind.IMAGE)] if row["image_url"] else []
        if not media:
            # Indoor / no-GPS activities: a shared card still needs a picture
            # so the feed can tell it's an activity.
            card = media_root_path(c.settings) / "activities" / f"{aid}.jpg"
            if render_card(row, card):
                row["image_url"] = f"/media/activities/{aid}.jpg"
                media = [MediaAttachment(url=row["image_url"], kind=MediaKind.IMAGE)]
        post = await c.social_service.create_post(author_id=user.id, text=text, media=media,
                                                  tags=["phliomove", row["sport"].replace("_", "")])
        row["post_id"] = post.id
        saved = await c.graph.store.put(saved["id"], {k: v for k, v in row.items() if k != "id"})
        await _announce(c, user, saved)
    return await _out(c, saved, user.id)


def render_card(row: dict, target) -> bool:
    """A plain stats card (no GPS route): sport, time and distance."""
    from PIL import Image, ImageDraw, ImageFont

    w, h = 1080, 640
    img = Image.new("RGB", (w, h), (12, 19, 30))
    d = ImageDraw.Draw(img)
    for i in range(0, w, 6):
        t = i / w
        d.line([(i, h - 18), (i + 6, h - 18)], fill=(int(141 + 114 * t), int(120 + 61 * t), int(255 - 112 * t)), width=18)
    try:
        big = ImageFont.load_default(size=110)
        small = ImageFont.load_default(size=44)
    except TypeError:  # very old Pillow
        big = small = ImageFont.load_default()
    label = SPORTS.get(row["sport"], ("Activity",))[0]
    mins = round((row.get("moving_s") or row.get("elapsed_s") or 0) / 60)
    main = _fmt_km(row["distance_m"]) if row.get("distance_m") else f"{mins} min"
    d.text((80, 170), label.upper(), font=small, fill=(255, 181, 143))
    d.text((80, 250), main, font=big, fill=(247, 247, 250))
    if row.get("distance_m"):
        d.text((80, 400), f"{mins} min", font=small, fill=(196, 200, 210))
    target.parent.mkdir(parents=True, exist_ok=True)
    img.save(target, "JPEG", quality=86)
    return True


async def _announce(c, user, row: dict) -> None:
    """Followers hear about it; tagged people and @mentions get their own note."""
    from app.api.v1.notifications import notify

    aid = row["id"].removeprefix(TABLE + ":")
    who = user.full_name or user.username
    data = dict(activity=aid, path=f"social/{row['post_id']}" if row.get("post_id") else None,
                image=row.get("image_url"), sport=row["sport"])
    line = f"{_summary_line(row)} · {row['title']}"
    done = {user.id}
    for uid in row.get("tagged", []):
        await notify(c, uid, "agent", "activity_tag", who, f"tagged you in {row['title']}", actor=user.id, data=data)
        done.add(uid)
    for handle in set(h.rstrip(".") for h in re.findall(r"@([A-Za-z0-9_.]{1,50})", row.get("description", ""))):
        person = await c.identity_repository.get_by_username(handle.lower())
        if person and person.id not in done:
            await notify(c, person.id, "agent", "mention", who, f"mentioned you in {row['title']}", actor=user.id, data=data)
            done.add(person.id)
    followers = await c.graph.store.rows("follows", {"in": "user:" + user.id})
    for edge in followers[:500]:
        uid = str(edge.get("out", "")).removeprefix("user:")
        if uid and uid not in done:
            await notify(c, uid, "agent", "activity", who, f"finished a {line}", actor=user.id, data=data,
                         group=f"activity:{user.id}", push=False)


@router.get("/by-post/{post_id}")
async def by_post(post_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    for row in await c.graph.store.rows(TABLE, {"post_id": post_id}):
        if await _visible(c, row, user.id):
            return await _out(c, row, user.id, full=False)
    raise HTTPException(404, "Activity not found.")


@router.get("/{activity_id}")
async def detail(activity_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, activity_id)
    if not await _visible(c, row, user.id):
        raise HTTPException(404, "Activity not found.")
    return await _out(c, row, user.id)


@router.patch("/{activity_id}")
async def edit(activity_id: str, body: ActivityPatch, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, activity_id)
    if row["user_id"] != user.id:
        raise HTTPException(404, "Activity not found.")
    if body.sport is not None:
        if body.sport not in SPORTS:
            raise HTTPException(422, "Choose a sport from the list.")
        row["sport"] = body.sport
    if body.visibility is not None:
        if body.visibility not in {"everyone", "only_me"}:
            raise HTTPException(422, "Visibility must be everyone or only_me.")
        row["visibility"] = body.visibility
    if body.title is not None:
        row["title"] = body.title.strip() or row["title"]
    if body.description is not None:
        row["description"] = body.description.strip()
    if body.hide_endpoints is not None and body.hide_endpoints != row.get("hide_endpoints", True):
        row["hide_endpoints"] = body.hide_endpoints
        image = media_root_path(c.settings) / "activities" / f"{row['id'].removeprefix(TABLE + ':')}.jpg"
        route = row.get("route") or []
        render_route(trim_endpoints(route) if body.hide_endpoints else route, image)
    if body.tagged is not None:
        row["tagged"] = await _resolve_tags(c, user.id, body.tagged)
    saved = await c.graph.store.put(row["id"], {k: v for k, v in row.items() if k != "id"})
    return await _out(c, saved, user.id)


@router.delete("/{activity_id}", status_code=204)
async def delete(activity_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, activity_id)
    if row["user_id"] != user.id:
        raise HTTPException(404, "Activity not found.")
    if row.get("post_id"):
        from app.api.v1.social import delete_content

        try:
            await delete_content(row["post_id"], user, c)
        except HTTPException:  # already gone
            pass
    for k in await c.graph.store.rows(KUDOS, {"activity_id": row["id"]}):
        await c.graph.store.delete(k["id"])
    await c.graph.store.delete(row["id"])
    return Response(status_code=204)


@router.put("/{activity_id}/kudos")
async def give_kudos(activity_id: str, body: KudosIn, user=Depends(get_current_user), c=Depends(get_container)):
    if body.emoji not in EMOJIS:
        raise HTTPException(422, "Pick one of the reactions.")
    row = await _get(c, activity_id)
    if not await _visible(c, row, user.id):
        raise HTTPException(404, "Activity not found.")
    k = key(KUDOS, row["id"].removeprefix(TABLE + ":"), user.id)
    first = await c.graph.store.get(k) is None
    await c.graph.store.put(k, dict(activity_id=row["id"], user_id=user.id, emoji=body.emoji, at=now()))
    if first:
        from app.api.v1.notifications import notify

        await notify(c, row["user_id"], "agent", "kudos", user.full_name or user.username,
                     f"reacted {body.emoji} to {row['title']}", actor=user.id,
                     data=dict(activity=row["id"].removeprefix(TABLE + ":"),
                               path=f"social/{row['post_id']}" if row.get("post_id") else None,
                               image=row.get("image_url"), sport=row["sport"]),
                     group=f"kudos:{row['id']}")
    return await _out(c, row, user.id, full=False)


@router.delete("/{activity_id}/kudos")
async def remove_kudos(activity_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, activity_id)
    await c.graph.store.delete(key(KUDOS, row["id"].removeprefix(TABLE + ":"), user.id))
    return await _out(c, row, user.id, full=False)
