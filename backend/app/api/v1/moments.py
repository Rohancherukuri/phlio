"""Moments: 24-hour photo/video posts (Instagram stories) and highlights.

A moment is visible for 24 hours from `created_at` (rings around avatars,
the story rail, the viewer). Saving it to a highlight keeps it on the
author's profile after it expires. Audience rules reuse snap audiences:
`everyone`, `friends` or `close_friends` (+ recipients).
"""

import asyncio
import datetime as dt
import io
import json
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field, ValidationError

from app.api.deps import get_container, get_current_user
from app.api.v1.content import ShareIn
from app.api.v1.snap_audience import SnapAudience, can_view, validate_audience
from app.core.container import media_root_path
from app.domains.graph.service import key
from app.domains.graph.store import now

router = APIRouter(prefix="/social/moments", tags=["moments"])

LIFETIME = dt.timedelta(hours=24)
# How long a moment stays up: 12 h, 24 h (default) or 48 h.
DURATIONS = (12, 24, 48)
SPOTLIGHT_EVERY = dt.timedelta(days=7)
IMAGE_TYPES = {"JPEG": ".jpg", "PNG": ".png", "WEBP": ".webp"}
VIDEO_TYPES = {".mp4", ".mov", ".m4v", ".webm", ".3gp"}
MAX_IMAGE = 20 * 1024 * 1024
MAX_VIDEO = 120 * 1024 * 1024


def _time(value):
    moment = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return moment if moment.tzinfo else moment.replace(tzinfo=dt.UTC)


def _active(row, at=None):
    return _time(row["expires_at"]) > (at or dt.datetime.now(dt.UTC))


async def _visible_rows(c, viewer, *, active_only=True, include_muted=False):
    """Moments the viewer may see (blocked authors and audience rules applied;
    muted authors are left out of the rail and rings)."""
    rows = []
    blocked = {}
    muted = set() if include_muted else {
        r["author"] for r in await c.graph.store.rows("moment_mute", {"user_id": viewer})}
    for row in await c.graph.store.rows("social_moment"):
        if active_only and not _active(row):
            continue
        author = row["author"]
        if author in muted and author != viewer:
            continue
        if author != viewer:
            if author not in blocked:
                blocked[author] = await c.graph.blocked(viewer, author)
            if blocked[author] or not await can_view(c, viewer, row):
                continue
        rows.append(row)
    return rows


async def _seen_ids(c, viewer):
    return {r["moment_id"] for r in await c.graph.store.rows("moment_view", {"user_id": viewer})}


def _public(row, seen, viewer):
    safe = {k: v for k, v in row.items() if k not in {"recipients", "seed"}}
    safe["seen"] = row["id"] in seen or row["author"] == viewer
    safe["mine"] = row["author"] == viewer
    return safe


async def _tagged(c, user, raw: str, caption: str) -> list[dict]:
    """Profiles of the people a moment mentions (stickers + caption)."""
    from app.api.v1.social_comments import comment_mentions
    try:
        names = json.loads(raw or "[]")
        if not isinstance(names, list) or len(names) > 20 or not all(isinstance(n, str) for n in names):
            raise ValueError()
    except ValueError as exc:
        raise HTTPException(422, "Invalid mentions.") from exc
    text = " ".join([caption or "", *("@" + n.lstrip("@") for n in names)])
    return [p for p in await comment_mentions(c, user, text) if p["id"] != user.id]


async def _profile(c, uid, cache):
    if uid not in cache:
        cache[uid] = c.graph.profile(await c.graph.user(uid))
    return cache[uid]


@router.post("", status_code=201)
async def create_moment(
    file: UploadFile = File(...),
    caption: str = Form(default="", max_length=500),
    audience: str = Form(default="everyone"),
    recipients: str = Form(default="[]"),
    allow_comments: bool = Form(default=True),
    overlays: str = Form(default="[]"),
    filter: str = Form(default="normal", max_length=24),
    filter_spec: str = Form(default=""),
    highlight: str = Form(default="", max_length=40),
    ai_label: bool = Form(default=False),
    music: str = Form(default=""),
    edits: str = Form(default=""),
    mentions: str = Form(default="[]", max_length=2000),
    duration_hours: int = Form(default=24),
    user=Depends(get_current_user),
    c=Depends(get_container),
):
    if duration_hours not in DURATIONS:
        raise HTTPException(422, "A moment can last 12, 24 or 48 hours.")
    try:
        choice = SnapAudience(audience=audience, recipients=json.loads(recipients))
        layers = json.loads(overlays)
        if not isinstance(layers, list) or len(layers) > 30:
            raise ValueError()
        song = json.loads(music) if music.strip() else None
        if song is not None and (not isinstance(song, dict) or len(json.dumps(song)) > 2000):
            raise ValueError()
    except (ValueError, TypeError, ValidationError):
        raise HTTPException(422, "Invalid moment settings.")
    from app.api.v1.media_edits import apply_video_edits, parse_media_edits
    video_edits = parse_media_edits(edits)
    tagged = await _tagged(c, user, mentions, caption)
    policy = await validate_audience(c, user.id, choice)
    await c.cache.rate_limit(user.id, "create_moment", 30)

    folder = media_root_path(c.settings) / "social_moments"
    folder.mkdir(parents=True, exist_ok=True)
    extension = Path(file.filename or "").suffix.lower()
    is_video = (file.content_type or "").startswith("video/") or extension in VIDEO_TYPES
    identifier = uuid.uuid4().hex
    if is_video:
        target = folder / (identifier + (extension if extension in VIDEO_TYPES else ".mp4"))
        size = 0
        with target.open("wb") as out:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_VIDEO:
                    out.close()
                    target.unlink(missing_ok=True)
                    raise HTTPException(413, "Choose a video under 120 MB.")
                out.write(chunk)
        try:
            process = await asyncio.create_subprocess_exec(
                "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_type",
                "-of", "csv=p=0", str(target), stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
            output, _ = await asyncio.wait_for(process.communicate(), timeout=15)
            if process.returncode != 0 or b"video" not in output:
                target.unlink(missing_ok=True)
                raise HTTPException(422, "Could not read this video.")
        except (FileNotFoundError, asyncio.TimeoutError):
            pass  # ffprobe unavailable: accept the upload as-is
        # Trim, speed, crop, rotate and time effects (boomerang, slow motion…).
        target = await apply_video_edits(target, video_edits)
        kind = "video"
        cover = folder / (identifier + "-cover.jpg")
        try:
            process = await asyncio.create_subprocess_exec(
                "ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", "0.5", "-i", str(target), "-frames:v", "1",
                "-vf", "scale=540:-2", str(cover), stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
            await asyncio.wait_for(process.wait(), timeout=20)
        except (FileNotFoundError, asyncio.TimeoutError):
            pass
    else:
        from PIL import Image, UnidentifiedImageError
        raw = await file.read(MAX_IMAGE + 1)
        if len(raw) > MAX_IMAGE:
            raise HTTPException(413, "Choose a photo under 20 MB.")
        try:
            with Image.open(io.BytesIO(raw)) as picture:
                fmt = picture.format
                if fmt not in IMAGE_TYPES or picture.width * picture.height > 30_000_000:
                    raise ValueError()
                picture.verify()
        except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
            raise HTTPException(422, "Choose a JPEG, PNG or WebP photo, or a video.")
        target = folder / (identifier + IMAGE_TYPES[fmt])
        target.write_bytes(raw)
        kind = "image"

    from app.api.v1.smart_filters import FilterSpec, parse_filter_spec
    spec = parse_filter_spec(filter_spec)
    spec_legacy = FilterSpec.model_validate(spec).legacy() if spec else None
    created = dt.datetime.now(dt.UTC)
    moment_id = "social_moment:" + identifier
    row = dict(
        author=user.id,
        media_url="/media/social_moments/" + target.name,
        media_kind=kind,
        cover_url=("/media/social_moments/" + identifier + "-cover.jpg"
                   if kind == "video" and (folder / (identifier + "-cover.jpg")).exists()
                   else ("/media/social_moments/" + target.name if kind == "image" else None)),
        caption=caption.strip(),
        overlays=layers,
        filter=spec_legacy or filter,
        # Smart filter (look, effect, info overlays), drawn live by the app.
        filter_spec=spec,
        allow_comments=allow_comments,
        ai_label=ai_label,
        music=song,
        # People tagged with mention stickers or @ in the caption.
        mentions=tagged,
        **policy,
        created_at=created.isoformat(),
        duration_hours=duration_hours,
        expires_at=(created + dt.timedelta(hours=duration_hours)).isoformat(),
    )
    saved = await c.graph.store.put(moment_id, row)
    if highlight.strip():
        await _add_to_highlight(c, user.id, moment_id, highlight.strip(), saved)
    from app.api.v1.profile_actions import fanout_later
    fanout_later(c, user.id, "moments", row=saved)
    return _public(saved, set(), user.id)


@router.get("/active")
async def active(user=Depends(get_current_user), c=Depends(get_container)):
    """`{user id, username or avatar url: {unseen, fresh, user}}` for every author with a live
    moment the viewer can see — drives the rim light on avatars app-wide."""
    seen = await _seen_ids(c, user.id)
    nowish = dt.datetime.now(dt.UTC)
    result, profiles = {}, {}
    for row in await _visible_rows(c, user.id):
        author = row["author"]
        state = result.setdefault(author, dict(unseen=False, fresh=False, spotlight=False, user=author))
        if _spotlit(row):
            state["spotlight"] = True
        if author != user.id and row["id"] not in seen:
            state["unseen"] = True
        if author == user.id and nowish - _time(row["created_at"]) < dt.timedelta(minutes=2):
            state["fresh"] = True
    for author, state in list(result.items()):
        try:
            profile = await _profile(c, author, profiles)
            result[profile["username"]] = state
            # Avatar URL key: rings appear on any avatar showing this photo,
            # even where the UI only knows the picture (comments, lists…).
            if profile.get("avatar_url"):
                result[profile["avatar_url"]] = state
        except HTTPException:
            pass
    return result


def _spotlit(row) -> bool:
    """Spotlighted moments go to the front of friends' rails while live."""
    return bool(row.get("spotlight_at")) and _active(row)


def _group_key(group, viewer):
    return (group["author"]["id"] != viewer, not group.get("spotlight"), not group["unseen"], -group["latest"])


@router.get("/feed")
async def feed(user=Depends(get_current_user), c=Depends(get_container)):
    """Story rail: you first, then people you follow / are friends with
    (unseen first), then other public moments as suggestions."""
    seen = await _seen_ids(c, user.id)
    following = {r["out"].removeprefix("user:") for r in await c.graph.store.rows("follows", {"in": "user:" + user.id})}
    groups, profiles = {}, {}
    for row in sorted(await _visible_rows(c, user.id), key=lambda r: r["created_at"]):
        author = row["author"]
        try:
            profile = await _profile(c, author, profiles)
        except HTTPException:
            continue
        group = groups.setdefault(author, dict(author=profile, items=[], unseen=False, latest=0.0,
                                               following=author in following, spotlight=False))
        group["spotlight"] = group["spotlight"] or _spotlit(row)
        item = _public(row, seen, user.id)
        group["items"].append(item)
        group["unseen"] = group["unseen"] or not item["seen"]
        group["latest"] = max(group["latest"], _time(row["created_at"]).timestamp())
    await _enrich(c, [i for g in groups.values() for i in g["items"]], user.id)
    ordered = sorted(groups.values(), key=lambda g: (not g["following"] and not g["spotlight"]
                                                    and g["author"]["id"] != user.id,
                                                    *_group_key(g, user.id)))
    return ordered


@router.get("/user/{identifier}")
async def user_moments(identifier: str, user=Depends(get_current_user), c=Depends(get_container)):
    owner = await c.graph.user(identifier)
    seen = await _seen_ids(c, user.id)
    rows = sorted((r for r in await _visible_rows(c, user.id, include_muted=True) if r["author"] == owner.id),
                  key=lambda r: r["created_at"])
    items = [_public(r, seen, user.id) for r in rows]
    await _enrich(c, items, user.id)
    return dict(author=c.graph.profile(owner), items=items)


@router.put("/{moment_id}/seen", status_code=204)
async def mark_seen(moment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _moment(c, moment_id)
    if row["author"] != user.id and not await can_view(c, user.id, row):
        raise HTTPException(404, "Moment unavailable.")
    view_key = key("moment_view", user.id, row["id"])
    before = await c.graph.store.get(view_key)
    stamp = now()
    # Every open counts: views − 1 are rewatches (the author's insights).
    await c.graph.store.put(view_key, dict(
        user_id=user.id, moment_id=row["id"], author=row["author"],
        seen_at=(before or {}).get("seen_at") or stamp, last_seen_at=stamp,
        views=int((before or {}).get("views") or 1) + (1 if before else 0)))
    if before is None and row["author"] != user.id:
        settings = await _settings_row(c, row["author"])
        if user.id in settings.get("notify_viewers", []):
            from app.api.v1.notifications import notify
            await notify(c, row["author"], "social", "moment_view", user.full_name or user.username,
                         "viewed your moment", actor=user.id,
                         data=dict(moment=row["id"].removeprefix("social_moment:")),
                         group=f"moment_view:{row['id']}")


@router.get("/{moment_id}/viewers")
async def viewers(moment_id: str, q: str = "", user=Depends(get_current_user), c=Depends(get_container)):
    """Who watched your moment, with their reaction and whether they
    commented — people who reacted come first, then newest views."""
    row = await _moment(c, moment_id)
    if row["author"] != user.id:
        raise HTTPException(403, "Only the author can see viewers.")
    views = {v["user_id"]: v for v in await c.graph.store.rows("moment_view", {"moment_id": row["id"]})}
    reactions = {r["user_id"]: r for r in await c.graph.store.rows("moment_reaction", {"moment_id": row["id"]})}
    comments: dict[str, int] = {}
    for comment in await c.graph.store.rows("moment_comment", {"moment_id": row["id"]}):
        comments[comment["user_id"]] = comments.get(comment["user_id"], 0) + 1
    answered: dict[str, int] = {}
    for response in await c.graph.store.rows("moment_response", {"moment_id": row["id"]}):
        answered[response["user_id"]] = answered.get(response["user_id"], 0) + 1
    people, profiles = [], {}
    for uid in {*views, *reactions} - {user.id}:
        try:
            profile = await _profile(c, uid, profiles)
        except HTTPException:
            continue
        reaction = reactions.get(uid)
        view = views.get(uid) or {}
        count = int(view.get("views") or (1 if view else 0))
        people.append(dict(profile,
                           reaction=reaction["emoji"] if reaction else None,
                           super_heart=bool(reaction and reaction.get("super")),
                           reacted_at=reaction["reacted_at"] if reaction else None,
                           comments=comments.get(uid, 0),
                           responses=answered.get(uid, 0),
                           seen_at=view.get("seen_at"),
                           last_seen_at=view.get("last_seen_at") or view.get("seen_at"),
                           views=count, rewatches=max(0, count - 1)))
    people.sort(key=lambda p: (p["reaction"] is None, -_stamp(p["reacted_at"] or p["seen_at"])))
    total = dict(count=len(people), reactions=sum(1 for p in people if p["reaction"]),
                 comments=sum(comments.values()), rewatches=sum(p["rewatches"] for p in people),
                 super_hearts=sum(1 for p in people if p["super_heart"]))
    # Search the viewer list by name or username (counts stay for everyone).
    needle = q.strip().lstrip("@").lower()
    if needle:
        people = [p for p in people if needle in (p.get("username") or "").lower()
                  or needle in (p.get("display_name") or "").lower()]
    return dict(total, people=people)


def _stamp(value) -> float:
    try:
        return _time(value).timestamp()
    except (TypeError, ValueError):
        return 0.0


async def _enrich(c, items: list[dict], viewer: str) -> None:
    """Adds comment counts and your reaction to moments (plus view and
    reaction counts on your own) for the viewer's bottom bar."""
    if not items:
        return
    ids = {i["id"] for i in items}
    comment_counts: dict[str, int] = {}
    for comment in await c.graph.store.rows("moment_comment"):
        if comment["moment_id"] in ids:
            comment_counts[comment["moment_id"]] = comment_counts.get(comment["moment_id"], 0) + 1
    reactions: dict[str, list[dict]] = {}
    for reaction in await c.graph.store.rows("moment_reaction"):
        if reaction["moment_id"] in ids:
            reactions.setdefault(reaction["moment_id"], []).append(reaction)
    views: dict[str, int] = {}
    if any(i.get("mine") for i in items):
        for view in await c.graph.store.rows("moment_view", {"author": viewer}):
            if view["moment_id"] in ids and view["user_id"] != viewer:
                views[view["moment_id"]] = views.get(view["moment_id"], 0) + 1
    for item in items:
        mine = [r for r in reactions.get(item["id"], []) if r["user_id"] == viewer]
        item["comment_count"] = comment_counts.get(item["id"], 0)
        item["my_reaction"] = mine[0]["emoji"] if mine else None
        if item.get("mine"):
            item["view_count"] = views.get(item["id"], 0)
            item["reaction_count"] = len(reactions.get(item["id"], []))


@router.delete("/{moment_id}", status_code=204)
async def delete_moment(moment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _moment(c, moment_id)
    if row["author"] != user.id:
        raise HTTPException(403, "You can only delete your own moments.")
    for highlight in await c.graph.store.rows("moment_highlight", {"owner": user.id}):
        if row["id"] in highlight.get("moment_ids", []):
            ids = [m for m in highlight["moment_ids"] if m != row["id"]]
            if ids:
                await c.graph.store.put(highlight["id"], dict(highlight, moment_ids=ids))
            else:
                await c.graph.store.delete(highlight["id"])
    for table in ("moment_comment", "moment_reaction"):
        for extra in await c.graph.store.rows(table, {"moment_id": row["id"]}):
            await c.graph.store.delete(extra["id"])
    await c.graph.store.delete(row["id"])


async def _moment(c, moment_id):
    if not moment_id.startswith("social_moment:"):
        moment_id = "social_moment:" + moment_id
    row = await c.graph.store.get(moment_id)
    if not row:
        raise HTTPException(404, "Moment unavailable.")
    return row


async def _add_to_highlight(c, owner, moment_id, title, row):
    hid = key("moment_highlight", owner, title.lower())
    current = await c.graph.store.get(hid) or dict(owner=owner, title=title, moment_ids=[], created_at=now())
    if moment_id not in current["moment_ids"]:
        current["moment_ids"] = [*current["moment_ids"], moment_id]
    if row.get("media_kind") == "image" or not current.get("cover_url"):
        current["cover_url"] = row.get("cover_url") or row["media_url"]
    current["updated_at"] = now()
    return await c.graph.store.put(hid, current)


class HighlightIn(BaseModel):
    title: str = Field(default="Highlights", min_length=1, max_length=40)


@router.post("/{moment_id}/highlight")
async def add_highlight(moment_id: str, body: HighlightIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _moment(c, moment_id)
    if row["author"] != user.id:
        raise HTTPException(403, "You can only highlight your own moments.")
    saved = await _add_to_highlight(c, user.id, row["id"], body.title.strip(), row)
    return dict(id=saved["id"], title=saved["title"])


@router.delete("/{moment_id}/highlight", status_code=204)
async def remove_highlight(moment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _moment(c, moment_id)
    for highlight in await c.graph.store.rows("moment_highlight", {"owner": user.id}):
        if row["id"] in highlight.get("moment_ids", []):
            ids = [m for m in highlight["moment_ids"] if m != row["id"]]
            if ids:
                await c.graph.store.put(highlight["id"], dict(highlight, moment_ids=ids))
            else:
                await c.graph.store.delete(highlight["id"])


@router.get("/highlights/{identifier}")
async def highlights(identifier: str, user=Depends(get_current_user), c=Depends(get_container)):
    """Profile highlights; moments stay here after their 24 hours."""
    owner = await c.graph.user(identifier)
    if owner.id != user.id and await c.graph.blocked(user.id, owner.id):
        return []
    seen = await _seen_ids(c, user.id)
    result = []
    rows = sorted(await c.graph.store.rows("moment_highlight", {"owner": owner.id}),
                  key=lambda r: str(r.get("created_at", "")))
    for highlight in rows:
        items = []
        for moment_id in highlight.get("moment_ids", []):
            row = await c.graph.store.get(moment_id)
            if row and (owner.id == user.id or await can_view(c, user.id, row)):
                items.append(_public(row, seen, user.id))
        if items:
            await _enrich(c, items, user.id)
            result.append(dict(id=highlight["id"], title=highlight["title"],
                               cover_url=highlight.get("cover_url") or items[-1].get("cover_url")
                               or items[-1]["media_url"],
                               items=items))
    return dict(author=c.graph.profile(owner), highlights=result)


class ReportIn(BaseModel):
    reason: str = Field(default="Something else", min_length=1, max_length=120)


@router.post("/{moment_id}/report", status_code=204)
async def report_moment(moment_id: str, body: ReportIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _moment(c, moment_id)
    await c.cache.rate_limit(user.id, "moment_report", 30)
    await c.graph.store.put(key("content_report", user.id, row["id"]), dict(
        reporter_id=user.id, moment_id=row["id"], author=row["author"], reason=body.reason,
        status="pending", created_at=now()))


class MuteIn(BaseModel):
    muted: bool = True


@router.put("/mute/{identifier}")
async def mute_author(identifier: str, body: MuteIn, user=Depends(get_current_user), c=Depends(get_container)):
    """Mute hides someone's moments from your rail and avatar rings."""
    author = await c.graph.user(identifier)
    rid = key("moment_mute", user.id, author.id)
    if body.muted:
        await c.graph.store.put(rid, dict(user_id=user.id, author=author.id, created_at=now()))
    elif await c.graph.store.get(rid):
        await c.graph.store.delete(rid)
    return dict(muted=body.muted)


# -- interactive stickers ---------------------------------------------------------------
#
# Moments can carry interactive stickers in `overlays` (poll, emoji slider,
# question, countdown, like, add yours). Each has an `id`; viewers respond
# once per sticker (answering again replaces the answer). Authors see every
# response; everyone sees the totals.

INTERACTIVE = {"poll", "slider", "question", "countdown", "like", "addyours"}


class RespondIn(BaseModel):
    """One viewer's answer to one sticker."""

    sticker: str = Field(min_length=1, max_length=40)
    value: str | float | int | bool = Field(description="poll: option index; slider: 0-1; question: text")


def _sticker(row: dict, sticker_id: str) -> dict:
    """The interactive overlay `sticker_id` on a moment, or 404."""
    for layer in row.get("overlays") or []:
        if isinstance(layer, dict) and layer.get("id") == sticker_id and layer.get("type") in INTERACTIVE:
            return layer
    raise HTTPException(404, "Sticker unavailable.")


def _clean(layer: dict, value: str | float | int | bool) -> str | float | int | bool:
    """Validates a response for the sticker's type."""
    kind = layer["type"]
    if kind == "poll":
        options = (layer.get("data") or {}).get("options") or []
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value < len(options):
            raise HTTPException(422, "Choose one of the options.")
        return value
    if kind == "slider":
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            raise HTTPException(422, "Invalid slider value.")
        return max(0.0, min(1.0, float(value)))
    if kind == "question":
        text = str(value).strip()
        if not text or len(text) > 300:
            raise HTTPException(422, "Write an answer up to 300 characters.")
        return text
    return True  # countdown reminder, like, add yours: just "I did"


@router.post("/{moment_id}/respond")
async def respond(moment_id: str, body: RespondIn, user=Depends(get_current_user), c=Depends(get_container)):
    """Vote in a poll, slide the emoji slider, answer a question, set a countdown reminder…"""
    row = await _moment(c, moment_id)
    if row["author"] != user.id and not await can_view(c, user.id, row):
        raise HTTPException(404, "Moment unavailable.")
    layer = _sticker(row, body.sticker)
    value = _clean(layer, body.value)
    await c.cache.rate_limit(user.id, "moment_respond", 120)
    await c.graph.store.put(key("moment_response", user.id, row["id"], body.sticker), dict(
        user_id=user.id, moment_id=row["id"], author=row["author"], sticker=body.sticker,
        kind=layer["type"], value=value, created_at=now()))
    return await _totals(c, row, user.id)


@router.get("/{moment_id}/responses")
async def responses(moment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    """Per-sticker totals (and, for the author, who answered what)."""
    row = await _moment(c, moment_id)
    if row["author"] != user.id and not await can_view(c, user.id, row):
        raise HTTPException(404, "Moment unavailable.")
    return await _totals(c, row, user.id)


async def _totals(c, row: dict, viewer: str) -> dict:
    """`{sticker_id: {kind, count, counts?, average?, mine, people?}}`."""
    mine_author = row["author"] == viewer
    out: dict[str, dict] = {}
    for layer in row.get("overlays") or []:
        if isinstance(layer, dict) and layer.get("type") in INTERACTIVE and layer.get("id"):
            entry: dict = dict(kind=layer["type"], count=0, mine=None)
            if layer["type"] == "poll":
                entry["counts"] = [0] * len((layer.get("data") or {}).get("options") or [])
            if mine_author:
                entry["people"] = []
            out[layer["id"]] = entry
    slider_sums: dict[str, float] = {}
    profiles: dict = {}
    for r in await c.graph.store.rows("moment_response", {"moment_id": row["id"]}):
        entry = out.get(r["sticker"])
        if entry is None:
            continue
        entry["count"] += 1
        if r["user_id"] == viewer:
            entry["mine"] = r["value"]
        if entry["kind"] == "poll" and isinstance(r["value"], int) and r["value"] < len(entry["counts"]):
            entry["counts"][r["value"]] += 1
        if entry["kind"] == "slider":
            slider_sums[r["sticker"]] = slider_sums.get(r["sticker"], 0.0) + float(r["value"])
        if mine_author:
            try:
                person = await _profile(c, r["user_id"], profiles)
            except HTTPException:
                continue
            entry["people"].append(dict(user=person, value=r["value"], at=r["created_at"]))
    for sticker, total in slider_sums.items():
        out[sticker]["average"] = total / max(1, out[sticker]["count"])
    return out


@router.get("/prompts")
async def trending_prompts(user=Depends(get_current_user), c=Depends(get_container)):
    """Trending "Add yours" prompts from live moments you can see.

    Groups the add-yours stickers by prompt text: how many moments use it,
    up to three people who joined (avatars) and the newest moment's cover,
    most used first. Feeds Templates → Trending prompts.
    """
    groups: dict[str, dict] = {}
    profiles: dict = {}
    rows = sorted(await _visible_rows(c, user.id), key=lambda r: r["created_at"], reverse=True)
    for row in rows:
        for layer in row.get("overlays") or []:
            if not isinstance(layer, dict) or layer.get("type") != "addyours":
                continue
            prompt = str((layer.get("data") or {}).get("prompt") or "").strip()
            if not prompt:
                continue
            group = groups.setdefault(prompt.lower(), dict(
                prompt=prompt, count=0, people=[], cover_url=row.get("cover_url") or row["media_url"],
                moment_id=row["id"], author=row["author"]))
            group["count"] += 1
            if len(group["people"]) < 3 and all(p["id"] != row["author"] for p in group["people"]):
                try:
                    group["people"].append(await _profile(c, row["author"], profiles))
                except HTTPException:
                    pass
    return sorted(groups.values(), key=lambda g: -g["count"])[:20]


# -- reactions and comments ---------------------------------------------------------------
#
# A reaction is one emoji per viewer per moment (sending another replaces
# it); the author sees it next to that person in Viewers. Comments are a
# public thread under the moment for everyone who can see it (one level of
# replies), unless the author turned comments off. Commenters can edit or
# delete their own; the author can delete any.


class ReactionIn(BaseModel):
    emoji: str = Field(min_length=1, max_length=12)
    # A super heart: press and hold the like button (bursts on screen).
    super: bool = False


async def _viewable(c, moment_id: str, viewer: str) -> dict:
    row = await _moment(c, moment_id)
    if row["author"] != viewer and (not _active(row) and not await _highlighted(c, row)
                                    or not await can_view(c, viewer, row)):
        raise HTTPException(404, "Moment unavailable.")
    return row


async def _highlighted(c, row: dict) -> bool:
    return any(row["id"] in h.get("moment_ids", [])
               for h in await c.graph.store.rows("moment_highlight", {"owner": row["author"]}))


@router.put("/{moment_id}/reaction")
async def react(moment_id: str, body: ReactionIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _viewable(c, moment_id, user.id)
    if row["author"] == user.id:
        raise HTTPException(422, "You can't react to your own moment.")
    await c.cache.rate_limit(user.id, "moment_react", 120)
    await c.graph.store.put(key("moment_reaction", user.id, row["id"]), dict(
        user_id=user.id, moment_id=row["id"], author=row["author"], emoji=body.emoji.strip(), reacted_at=now(),
        super=body.super))
    return dict(reaction=body.emoji.strip(), super=body.super)


@router.delete("/{moment_id}/reaction", status_code=204)
async def unreact(moment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _moment(c, moment_id)
    rid = key("moment_reaction", user.id, row["id"])
    if await c.graph.store.get(rid):
        await c.graph.store.delete(rid)


class CommentIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    reply_to: str | None = Field(default=None, max_length=120)


class CommentEdit(BaseModel):
    text: str = Field(min_length=1, max_length=500)


def _comment_id(value: str) -> str:
    return value if value.startswith("moment_comment:") else "moment_comment:" + value


async def _comment_out(c, comment: dict, row: dict, viewer: str, profiles: dict, by_id: dict) -> dict | None:
    try:
        person = await _profile(c, comment["user_id"], profiles)
    except HTTPException:
        return None
    parent = by_id.get(comment.get("reply_to") or "")
    parent_user = None
    if parent:
        try:
            parent_user = (await _profile(c, parent["user_id"], profiles))["username"]
        except HTTPException:
            pass
    return dict(id=comment["id"], text=comment["text"], user=person, created_at=comment["created_at"],
                mentions=comment.get("mentions") or [],
                edited_at=comment.get("edited_at"), reply_to=comment.get("reply_to"), reply_to_user=parent_user,
                mine=comment["user_id"] == viewer, by_author=comment["user_id"] == row["author"],
                can_delete=comment["user_id"] == viewer or row["author"] == viewer)


@router.get("/{moment_id}/comments")
async def list_comments(moment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    """The moment's comments, oldest first, replies right under their comment."""
    row = await _viewable(c, moment_id, user.id)
    rows = sorted(await c.graph.store.rows("moment_comment", {"moment_id": row["id"]}),
                  key=lambda r: r["created_at"])
    blocked: dict[str, bool] = {}
    visible = []
    for comment in rows:
        uid = comment["user_id"]
        if uid != user.id:
            if uid not in blocked:
                blocked[uid] = await c.graph.blocked(user.id, uid)
            if blocked[uid]:
                continue
        visible.append(comment)
    by_id = {r["id"]: r for r in visible}
    top = [r for r in visible if not r.get("reply_to") or r["reply_to"] not in by_id]
    ordered = []
    for comment in top:
        ordered.append(comment)
        ordered += [r for r in visible if r.get("reply_to") == comment["id"]]
    profiles: dict = {}
    items = [out for r in ordered if (out := await _comment_out(c, r, row, user.id, profiles, by_id))]
    return dict(count=len(items), allow_comments=row.get("allow_comments", True) is not False, items=items)


@router.post("/{moment_id}/comments", status_code=201)
async def add_comment(moment_id: str, body: CommentIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _viewable(c, moment_id, user.id)
    if row.get("allow_comments") is False and row["author"] != user.id:
        raise HTTPException(403, "Comments are turned off for this moment.")
    text = body.text.strip()
    if not text:
        raise HTTPException(422, "Write a comment.")
    await c.cache.rate_limit(user.id, "moment_comment", 60)
    reply_to = None
    if body.reply_to:
        parent = await c.graph.store.get(_comment_id(body.reply_to))
        if not parent or parent["moment_id"] != row["id"]:
            raise HTTPException(404, "That comment is gone.")
        # One level of replies: answering a reply joins its thread.
        reply_to = parent.get("reply_to") or parent["id"]
    from app.api.v1.social_comments import comment_mentions
    cid = "moment_comment:" + uuid.uuid4().hex
    saved = await c.graph.store.put(cid, dict(
        moment_id=row["id"], author=row["author"], user_id=user.id, text=text, reply_to=reply_to,
        mentions=await comment_mentions(c, user, text), created_at=now()))
    await _comment_dms(c, row, user.id, text, reply_to)
    by_id = {r["id"]: r for r in await c.graph.store.rows("moment_comment", {"moment_id": row["id"]})}
    return await _comment_out(c, saved, row, user.id, {}, by_id)


async def _comment_dms(c, row: dict, uid: str, text: str, reply_to: str | None) -> None:
    """Comments go straight to DMs: the moment's author gets every comment
    from someone else, and whoever you reply to gets your reply."""
    try:
        owner = await _profile(c, row["author"], {})
    except HTTPException:
        return
    link = f"\nphlio://app/moments/{owner['username']}"
    sends: dict[str, str] = {}
    if uid != row["author"]:
        sends[row["author"]] = f"💬 Commented on your moment: {text}{link}"
    if reply_to:
        parent = await c.graph.store.get(reply_to)
        target = parent and parent["user_id"]
        if target and target != uid and target not in sends:
            whose = "my" if uid == row["author"] else f"@{owner['username']}'s"
            sends[target] = f"↩️ Replied to your comment on {whose} moment: {text}{link}"
    for target, message in sends.items():
        try:
            if await c.graph.blocked(uid, target):
                continue
            c.messaging_service.send(uid, target, message, [])
        except Exception:  # the comment is saved either way
            continue


@router.put("/{moment_id}/comments/{comment_id}")
async def edit_comment(moment_id: str, comment_id: str, body: CommentEdit,
                       user=Depends(get_current_user), c=Depends(get_container)):
    row = await _viewable(c, moment_id, user.id)
    comment = await c.graph.store.get(_comment_id(comment_id))
    if not comment or comment["moment_id"] != row["id"]:
        raise HTTPException(404, "That comment is gone.")
    if comment["user_id"] != user.id:
        raise HTTPException(403, "You can only edit your own comments.")
    from app.api.v1.social_comments import comment_mentions
    text = body.text.strip()
    saved = await c.graph.store.put(comment["id"], dict(
        comment, text=text, mentions=await comment_mentions(c, user, text), edited_at=now()))
    by_id = {r["id"]: r for r in await c.graph.store.rows("moment_comment", {"moment_id": row["id"]})}
    return await _comment_out(c, saved, row, user.id, {}, by_id)


@router.delete("/{moment_id}/comments/{comment_id}", status_code=204)
async def delete_comment(moment_id: str, comment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _moment(c, moment_id)
    comment = await c.graph.store.get(_comment_id(comment_id))
    if not comment or comment["moment_id"] != row["id"]:
        raise HTTPException(404, "That comment is gone.")
    if user.id not in (comment["user_id"], row["author"]):
        raise HTTPException(403, "You can't delete this comment.")
    for reply in await c.graph.store.rows("moment_comment", {"moment_id": row["id"]}):
        if reply.get("reply_to") == comment["id"]:
            await c.graph.store.delete(reply["id"])
    await c.graph.store.delete(comment["id"])


async def _visible_comment(c, moment_id: str, comment_id: str, viewer: str) -> tuple[dict, dict]:
    row = await _viewable(c, moment_id, viewer)
    comment = await c.graph.store.get(_comment_id(comment_id))
    if not comment or comment["moment_id"] != row["id"] or await c.graph.blocked(viewer, comment["user_id"]):
        raise HTTPException(404, "That comment is gone.")
    return row, comment


@router.post("/{moment_id}/comments/{comment_id}/share", status_code=201)
async def share_comment(moment_id: str, comment_id: str, body: ShareIn,
                        user=Depends(get_current_user), c=Depends(get_container)):
    """Send a moment's comment to a DM, a group, a new group or a room."""
    from app.api.v1.content import deliver_text
    row, comment = await _visible_comment(c, moment_id, comment_id, user.id)
    await c.cache.rate_limit(user.id, "share", 30)
    owner = await _profile(c, row["author"], {})
    writer = await _profile(c, comment["user_id"], {})
    text = (f"💬 Shared a comment by @{writer['username']} on @{owner['username']}'s moment:\n"
            f"“{comment['text']}”\nphlio://app/moments/{owner['username']}")
    return await deliver_text(c, user, body, text, about=comment["user_id"])


@router.post("/{moment_id}/comments/{comment_id}/report", status_code=204)
async def report_comment(moment_id: str, comment_id: str, body: ReportIn,
                         user=Depends(get_current_user), c=Depends(get_container)):
    row, comment = await _visible_comment(c, moment_id, comment_id, user.id)
    await c.cache.rate_limit(user.id, "moment_report", 30)
    await c.graph.store.put(key("content_report", user.id, comment["id"]), dict(
        reporter_id=user.id, moment_id=row["id"], comment_id=comment["id"], author=comment["user_id"],
        reason=body.reason, status="pending", created_at=now()))



# -- duration, spotlight and moment settings ------------------------------------------------


class DurationIn(BaseModel):
    hours: int


@router.put("/{moment_id}/duration")
async def set_duration(moment_id: str, body: DurationIn, user=Depends(get_current_user), c=Depends(get_container)):
    """Make a live moment last 12, 24 or 48 hours from when it was shared."""
    row = await _moment(c, moment_id)
    if row["author"] != user.id:
        raise HTTPException(403, "Only the author can change this.")
    if body.hours not in DURATIONS:
        raise HTTPException(422, "A moment can last 12, 24 or 48 hours.")
    expires = _time(row["created_at"]) + dt.timedelta(hours=body.hours)
    if expires <= dt.datetime.now(dt.UTC):
        raise HTTPException(422, "That would end this moment already.")
    row = dict(row, duration_hours=body.hours, expires_at=expires.isoformat())
    saved = await c.graph.store.put(row["id"], {k: v for k, v in row.items() if k != "id"})
    return _public(saved, set(), user.id)


@router.post("/{moment_id}/spotlight")
async def spotlight(moment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    """Put a live moment at the front of friends' rails. Once every 7 days."""
    row = await _moment(c, moment_id)
    if row["author"] != user.id:
        raise HTTPException(403, "Only the author can spotlight a moment.")
    if not _active(row):
        raise HTTPException(422, "This moment has ended.")
    nowish = dt.datetime.now(dt.UTC)
    last = max((_time(r["spotlight_at"]) for r in await c.graph.store.rows("social_moment", {"author": user.id})
                if r.get("spotlight_at")), default=None)
    if last and nowish - last < SPOTLIGHT_EVERY:
        nxt = last + SPOTLIGHT_EVERY
        raise HTTPException(429, f"You can spotlight again on {nxt.strftime('%d %b, %I:%M %p')} UTC.")
    row = dict(row, spotlight_at=nowish.isoformat())
    saved = await c.graph.store.put(row["id"], {k: v for k, v in row.items() if k != "id"})
    return dict(_public(saved, set(), user.id), next_spotlight_at=(nowish + SPOTLIGHT_EVERY).isoformat())


async def _settings_row(c, user_id: str) -> dict:
    return await c.graph.store.get(key("account_setting", user_id, "moments")) or {}


class MomentSettingsIn(BaseModel):
    notify_viewers: list[str] | None = Field(default=None, max_length=50)
    default_hours: int | None = None


async def _settings_out(c, user_id: str, row: dict) -> dict:
    people, profiles = [], {}
    for uid in row.get("notify_viewers", []):
        try:
            people.append(await _profile(c, uid, profiles))
        except HTTPException:
            pass
    last = max((_time(r["spotlight_at"]) for r in await c.graph.store.rows("social_moment", {"author": user_id})
                if r.get("spotlight_at")), default=None)
    return dict(notify_viewers=people, default_hours=row.get("default_hours", 24),
                next_spotlight_at=(last + SPOTLIGHT_EVERY).isoformat() if last else None)


@router.get("/settings/me")
async def my_settings(user=Depends(get_current_user), c=Depends(get_container)):
    """Moment settings: people whose views notify you, default duration."""
    return await _settings_out(c, user.id, await _settings_row(c, user.id))


@router.put("/settings/me")
async def save_settings(body: MomentSettingsIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _settings_row(c, user.id)
    if body.notify_viewers is not None:
        ids = []
        for name in dict.fromkeys(body.notify_viewers):
            person = await c.graph.user(name)
            if person.id != user.id:
                ids.append(person.id)
        row["notify_viewers"] = ids
    if body.default_hours is not None:
        if body.default_hours not in DURATIONS:
            raise HTTPException(422, "A moment can last 12, 24 or 48 hours.")
        row["default_hours"] = body.default_hours
    await c.graph.store.put(key("account_setting", user.id, "moments"), dict(row, owner=user.id, updated_at=now()))
    return await _settings_out(c, user.id, row)
