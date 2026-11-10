"""Profile appearance, DM chat themes and the profile dashboard's insights.

Appearance (one JSON shape for profiles and chats):

    {
      "background": "#1B1530" | null,          solid colour behind everything
      "wallpaper": {"type": "none" | "live" | "photo",
                    "style": "mesh",            live: a moment-backdrop shader style
                    "palette": 0,               live: index into the app's palettes
                    "url": "/media/wallpapers/…"},  photo: uploaded image
      "dim": 0.35,                              darkens photo/live wallpapers for legibility
      "effect": "none" | "sparkles" | "snow" | "aurora" | "stars" | "bokeh" | "fireflies"
                | "hearts" | "confetti" | "rain" | "petals" | "bubbles" | "galaxy",
      "effect_color": "#FFD27A",
      "intensity": 0.7
    }

* Profile style: ``profile_style:<user_id>`` (anyone may read it, only the owner writes).
* Chat theme: ``chat_theme:<id_a>:<id_b>`` (sorted ids). Either person may change it,
  and both see it, like a shared chat theme.

Insights are computed from the graph: views and interactions are ``activity`` edges on
the user's own objects, comments are ``content_comment`` rows, new followers are
``follows`` edges into the user. Nothing is estimated.
"""
from __future__ import annotations

import collections
import datetime as dt
import re
import uuid
from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field, field_validator

from app.api.deps import get_container, get_current_user
from app.core.container import media_root_path
from app.domains.graph.service import key

router = APIRouter(tags=["appearance"])

EFFECTS = ("none", "sparkles", "snow", "aurora", "stars", "bokeh", "fireflies",
           "hearts", "confetti", "rain", "petals", "bubbles", "galaxy", "matrix", "glitch")
# Ready-made themes the app can draw (others are "coming soon" in the app).
TEMPLATES = ("hacker_green", "hacker_violet", "hacker_red", "hacker_mono")
LIVE_STYLES = ("mesh", "aurora", "paper", "halftone", "grid", "sunburst", "holo", "film", "linear", "checker")
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
IMAGE_TYPES = {b"\xff\xd8\xff": ".jpg", b"\x89PNG": ".png", b"RIFF": ".webp"}
WALLPAPER_LIMIT = 8_000_000


class Wallpaper(BaseModel):
    type: Literal["none", "live", "photo"] = "none"
    style: Literal[LIVE_STYLES] = "mesh"  # type: ignore[valid-type]
    palette: int = Field(default=0, ge=0, le=31)
    url: str | None = Field(default=None, max_length=300)

    @field_validator("url")
    @classmethod
    def _media_only(cls, value: str | None) -> str | None:
        # Only wallpapers uploaded through /appearance/wallpaper.
        if value is not None and not re.fullmatch(r"/media/wallpapers/[0-9a-f]{32}\.(jpg|png|webp)", value):
            raise ValueError("Upload the wallpaper first.")
        return value


class Appearance(BaseModel):
    background: str | None = None
    wallpaper: Wallpaper = Wallpaper()
    dim: float = Field(default=0.35, ge=0, le=0.9)
    effect: Literal[EFFECTS] = "none"  # type: ignore[valid-type]
    effect_color: str = "#FFD27A"
    intensity: float = Field(default=0.7, ge=0.1, le=1)
    template: Literal[TEMPLATES] | None = None  # type: ignore[valid-type]

    @field_validator("background", "effect_color")
    @classmethod
    def _hex(cls, value: str | None) -> str | None:
        if value is not None and not HEX.fullmatch(value):
            raise ValueError("Use a #RRGGBB colour.")
        return value


def _row_to_appearance(row: dict | None) -> dict:
    if not row:
        return Appearance().model_dump()
    data = {k: v for k, v in row.items() if k in Appearance.model_fields}
    try:
        return Appearance(**data).model_dump()
    except ValueError:
        return Appearance().model_dump()


async def _user(c, username: str):
    person = await c.identity_repository.get_by_username(username.lstrip("@"))
    if not person:
        raise HTTPException(404, "No such person.")
    return person


# -- Profile style -----------------------------------------------------------------------

@router.get("/appearance/me")
async def my_style(user=Depends(get_current_user), c=Depends(get_container)):
    return _row_to_appearance(await c.graph.store.get(key("profile_style", user.id)))


@router.put("/appearance/me")
async def set_my_style(body: Appearance, user=Depends(get_current_user), c=Depends(get_container)):
    await c.graph.store.put(key("profile_style", user.id),
                            dict(body.model_dump(), owner=user.id, updated_at=dt.datetime.now(dt.UTC).isoformat()))
    return body.model_dump()


@router.get("/appearance/users/{username}")
async def user_style(username: str, user=Depends(get_current_user), c=Depends(get_container)):
    person = await _user(c, username)
    if await c.graph.blocked(user.id, person.id):
        return Appearance().model_dump()
    return _row_to_appearance(await c.graph.store.get(key("profile_style", person.id)))


# -- Private account ---------------------------------------------------------------------
# ``account_setting:<user_id>`` {private}. A private account shows a lock on its
# profile, and only followers (and the owner) see its posts.

async def is_private(c, user_id: str) -> bool:
    row = await c.graph.store.get(key("account_setting", user_id))
    return bool(row and row.get("private"))


async def can_see_private(c, viewer_id: str, owner_id: str) -> bool:
    if viewer_id == owner_id or not await is_private(c, owner_id):
        return True
    return bool(await c.graph.store.get(key("follows", viewer_id, owner_id)))


class PrivacyIn(BaseModel):
    private: bool


@router.get("/account/privacy")
async def get_privacy(user=Depends(get_current_user), c=Depends(get_container)):
    return dict(private=await is_private(c, user.id))


@router.put("/account/privacy")
async def set_privacy(body: PrivacyIn, user=Depends(get_current_user), c=Depends(get_container)):
    await c.graph.store.put(key("account_setting", user.id),
                            dict(owner=user.id, private=body.private,
                                 updated_at=dt.datetime.now(dt.UTC).isoformat()))
    return dict(private=body.private)


# -- Chat themes -------------------------------------------------------------------------

def _chat_key(a: str, b: str) -> str:
    return key("chat_theme", *sorted([a, b]))


@router.get("/appearance/chats/{username}")
async def chat_theme(username: str, user=Depends(get_current_user), c=Depends(get_container)):
    person = await _user(c, username)
    row = await c.graph.store.get(_chat_key(user.id, person.id))
    return dict(_row_to_appearance(row), set_by=(row or {}).get("set_by"))


@router.put("/appearance/chats/{username}")
async def set_chat_theme(username: str, body: Appearance, user=Depends(get_current_user),
                         c=Depends(get_container)):
    person = await _user(c, username)
    if person.id == user.id:
        raise HTTPException(400, "Pick a conversation with someone else.")
    if await c.graph.blocked(user.id, person.id):
        raise HTTPException(403, "This conversation is unavailable.")
    await c.graph.store.put(_chat_key(user.id, person.id),
                            dict(body.model_dump(), set_by=user.id,
                                 updated_at=dt.datetime.now(dt.UTC).isoformat()))
    return dict(body.model_dump(), set_by=user.id)


@router.post("/appearance/wallpaper")
async def upload_wallpaper(file: UploadFile = File(...), user=Depends(get_current_user),
                           c=Depends(get_container)):
    data = await file.read(WALLPAPER_LIMIT + 1)
    if len(data) > WALLPAPER_LIMIT:
        raise HTTPException(413, "Wallpapers must be smaller than 8 MB.")
    suffix = next((ext for magic, ext in IMAGE_TYPES.items() if data.startswith(magic)), None)
    if suffix is None or (suffix == ".webp" and data[8:12] != b"WEBP"):
        raise HTTPException(422, "Choose a JPEG, PNG or WebP image.")
    folder = media_root_path(c.settings) / "wallpapers"
    folder.mkdir(parents=True, exist_ok=True)
    name = uuid.uuid4().hex + suffix
    (folder / name).write_bytes(data)
    return dict(url="/media/wallpapers/" + name)


# -- Insights ----------------------------------------------------------------------------

INTERACTIONS = {"liked", "saved", "shared", "reposted"}


def _when(value) -> dt.datetime | None:
    if not value:
        return None
    try:
        moment = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=dt.UTC)


def _pct(now: int, before: int) -> float | None:
    if before == 0:
        return None if now == 0 else 100.0
    return round((now - before) * 100 / before, 1)


@router.get("/profile/insights")
async def insights(days: int = Query(30, ge=7, le=90), user=Depends(get_current_user), c=Depends(get_container)):
    """Views, interactions, followers and content for the last `days`, with the
    period before for comparison, a daily series, top content and when the
    audience is active."""
    cache_key = f"insights:{user.id}:{days}:{await c.graph.store.revision()}"
    cached = await c.cache.get(cache_key)
    if cached is not None:
        return cached
    now = dt.datetime.now(dt.UTC)
    start = (now - dt.timedelta(days=days)).replace(hour=0, minute=0, second=0, microsecond=0)
    before = start - dt.timedelta(days=days)
    month_end = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    month_start = (month_end - dt.timedelta(days=1)).replace(day=1)

    objects = await c.graph.store.rows("phlio_object", {"owner": user.id})
    series = {(start + dt.timedelta(days=i)).date().isoformat(): dict(views=0, interactions=0, followers=0)
              for i in range(days + 1)}
    totals = collections.Counter()
    previous = collections.Counter()
    month = collections.Counter()
    hours = [0] * 24
    per_object = collections.Counter()
    shared = shared_before = 0

    def bucket(moment, name, counter_name):
        if moment >= start:
            totals[counter_name] += 1
            day = series.get(moment.date().isoformat())
            if day is not None:
                day[name] += 1
        elif moment >= before:
            previous[counter_name] += 1
        if month_start <= moment < month_end:
            month[counter_name] += 1

    for obj in objects:
        created = _when(obj.get("created_at"))
        if created and created >= start:
            shared += 1
        elif created and created >= before:
            shared_before += 1
        if created and month_start <= created < month_end:
            month["shared"] += 1
        for edge in await c.graph.store.rows("activity", {"out": obj["id"]}):
            moment = _when(edge.get("created_at"))
            verb = edge.get("verb")
            if not moment or str(edge.get("in")) == "user:" + user.id:
                continue  # your own views and likes don't count
            if verb == "viewed":
                bucket(moment, "views", "views")
                if moment >= start:
                    hours[moment.hour] += 1
                    per_object[obj["id"]] += 1
            elif verb in INTERACTIONS:
                bucket(moment, "interactions", "interactions")
                totals[verb] += moment >= start
        for comment in await c.graph.store.rows("content_comment", {"object_id": obj["id"]}):
            moment = _when(comment.get("created_at"))
            if moment and comment.get("author_id") != user.id:
                bucket(moment, "interactions", "interactions")
                totals["commented"] += moment >= start
    for edge in await c.graph.store.rows("follows", {"out": "user:" + user.id}):
        moment = _when(edge.get("created_at"))
        if moment:
            bucket(moment, "followers", "followers")

    titles = {o["id"]: o for o in objects}
    top = []
    for object_id, views in per_object.most_common(5):
        obj = titles[object_id]
        details = await c.graph.store.get(key("platform_content", obj["platform"], obj["domain_ref"])) or {}
        top.append(dict(id=object_id, title=obj.get("title") or "Untitled", type=obj.get("object_type"),
                        views=views, image_url=details.get("image_url")))
    peak = max(range(24), key=lambda h: hours[h]) if any(hours) else None

    # What's trending on Phlio Social right now (tags on recent public videos).
    tags = collections.Counter()
    for row in await c.graph.store.rows("platform_content", {"platform": "social"}):
        if row.get("visibility", "public") == "public":
            tags.update(t for t in row.get("tags") or [] if t not in {"fyp", "4you", "phlio"})

    result = dict(
        days=days, start=start.date().isoformat(), end=now.date().isoformat(),
        views=dict(value=totals["views"], change=_pct(totals["views"], previous["views"])),
        interactions=dict(value=totals["interactions"], change=_pct(totals["interactions"], previous["interactions"]),
                          liked=totals["liked"], saved=totals["saved"], shared=totals["shared"],
                          reposted=totals["reposted"], commented=totals["commented"]),
        followers=dict(value=totals["followers"], change=_pct(totals["followers"], previous["followers"])),
        content=dict(value=shared, change=_pct(shared, shared_before)),
        series=[dict(day=day, **values) for day, values in series.items()],
        active_hours=hours, peak_hour=peak, top_content=top,
        trending_tags=[dict(tag=t, count=n) for t, n in tags.most_common(12)],
        recap=dict(month=month_start.strftime("%B %Y"), views=month["views"], interactions=month["interactions"],
                   followers=month["followers"], shared=month["shared"]),
    )
    await c.cache.put(cache_key, result, ttl=60)
    return result
