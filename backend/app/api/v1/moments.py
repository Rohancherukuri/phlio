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
from app.api.v1.snap_audience import SnapAudience, can_view, validate_audience
from app.core.container import media_root_path
from app.domains.graph.service import key
from app.domains.graph.store import now

router = APIRouter(prefix="/social/moments", tags=["moments"])

LIFETIME = dt.timedelta(hours=24)
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
    highlight: str = Form(default="", max_length=40),
    ai_label: bool = Form(default=False),
    music: str = Form(default=""),
    user=Depends(get_current_user),
    c=Depends(get_container),
):
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
        filter=filter,
        allow_comments=allow_comments,
        ai_label=ai_label,
        music=song,
        **policy,
        created_at=created.isoformat(),
        expires_at=(created + LIFETIME).isoformat(),
    )
    saved = await c.graph.store.put(moment_id, row)
    if highlight.strip():
        await _add_to_highlight(c, user.id, moment_id, highlight.strip(), saved)
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
        state = result.setdefault(author, dict(unseen=False, fresh=False, user=author))
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


def _group_key(group, viewer):
    return (group["author"]["id"] != viewer, not group["unseen"], -group["latest"])


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
                                               following=author in following))
        item = _public(row, seen, user.id)
        group["items"].append(item)
        group["unseen"] = group["unseen"] or not item["seen"]
        group["latest"] = max(group["latest"], _time(row["created_at"]).timestamp())
    ordered = sorted(groups.values(), key=lambda g: (not g["following"] and g["author"]["id"] != user.id,
                                                    *_group_key(g, user.id)))
    return ordered


@router.get("/user/{identifier}")
async def user_moments(identifier: str, user=Depends(get_current_user), c=Depends(get_container)):
    owner = await c.graph.user(identifier)
    seen = await _seen_ids(c, user.id)
    rows = sorted((r for r in await _visible_rows(c, user.id, include_muted=True) if r["author"] == owner.id),
                  key=lambda r: r["created_at"])
    return dict(author=c.graph.profile(owner), items=[_public(r, seen, user.id) for r in rows])


@router.put("/{moment_id}/seen", status_code=204)
async def mark_seen(moment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _moment(c, moment_id)
    if row["author"] != user.id and not await can_view(c, user.id, row):
        raise HTTPException(404, "Moment unavailable.")
    await c.graph.store.put(key("moment_view", user.id, row["id"]),
                            dict(user_id=user.id, moment_id=row["id"], author=row["author"], seen_at=now()))


@router.get("/{moment_id}/viewers")
async def viewers(moment_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _moment(c, moment_id)
    if row["author"] != user.id:
        raise HTTPException(403, "Only the author can see viewers.")
    people, profiles = [], {}
    for view in await c.graph.store.rows("moment_view", {"moment_id": row["id"]}):
        try:
            people.append(await _profile(c, view["user_id"], profiles))
        except HTTPException:
            continue
    return dict(count=len(people), people=people)


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
