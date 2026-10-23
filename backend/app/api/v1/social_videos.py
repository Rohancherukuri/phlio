"""Video upload/discovery and authenticated follow actions."""

import asyncio
import json
import subprocess
import uuid
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
from app.domains.graph.store import now
from app.api.v1.content import resolve

from app.api.deps import get_container, get_current_user
from app.core.container import Container, media_root_path
from app.domains.graph.service import key
from app.domains.identity.entities import User
from app.infrastructure.video_thumbnail import make_thumbnail

router = APIRouter(prefix="/social", tags=["social videos"])


@router.get("/following")
async def following(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    return [p["username"] for p in (await c.graph.connections(user.id))["following"]]


@router.put("/creators/{username}/follow", status_code=204)
async def follow(
    username: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    creator = await c.identity_repository.get_by_username(username.lower())
    if creator is None:
        raise HTTPException(404, "Creator not found.")
    if creator.id == user.id:
        raise HTTPException(422, "You cannot follow yourself.")
    await c.graph.relationship(user.id, creator.id, "follow")


@router.delete("/creators/{username}/follow", status_code=204)
async def unfollow(
    username: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    await c.graph.relationship(user.id, username.lower(), "unfollow")


async def video_response(row, c, creator=None, details=None):
    creator = creator or await c.identity_repository.get_by_id(row["creator"])
    if not creator:
        return None
    if details is None:
        details = await c.graph.store.get(key("platform_content", "social", row["id"])) or {}
    thumbnail = row.get('thumbnail_url')
    if thumbnail and thumbnail.startswith('/media/'):
        root = media_root_path(c.settings).resolve()
        path = (root / thumbnail.removeprefix('/media/').split('?')[0]).resolve()
        if path.is_relative_to(root) and path.is_file():
            thumbnail = thumbnail.split('?')[0] + f'?v={path.stat().st_mtime_ns}'
    return dict(
        sources=details.get("sources", []),
        song_title=details.get("song_title"),
        song_artist=details.get("song_artist"),
        attribution=details.get("attribution"),
        id=row["id"],
        title=row["title"],
        creator=creator.username,
        creator_name=creator.full_name,
        avatar_url=creator.avatar_url,
        url=row["url"],
        created_at=row["created_at"],
        kind=row.get("kind", "video"),
        thumbnail_url=thumbnail,
        duration_seconds=row.get("duration_seconds", 0),
        description=details.get("description", ""),
        visibility=details.get("visibility", "public"),
        audience=details.get("audience", "everyone"),
        location=details.get("location"),
        related_video=details.get("related_video"),
        paid_promotion=details.get("paid_promotion", False),
    )


def visible_video(row, details, viewer_id):
    """Private videos are creator-only; unlisted ones stay out of feeds
    (they still open from a shared link)."""
    return row["creator"] == viewer_id or details.get("visibility", "public") == "public"


@router.get("/videos")
async def videos(
    before: str | None = None, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    before = before.strip() or None if before is not None else None
    revision = await c.graph.store.revision()
    cache_key = f"videos:v4:{revision}:{user.id}:{before}"
    cached = await c.cache.get(cache_key)
    if cached is not None:
        return cached
    rows = c.social_video_service.videos(before)
    creator_ids = list({row['creator'] for row in rows})
    creators, objects, details, blocks = await asyncio.gather(
        c.identity_repository.get_many(creator_ids),
        c.graph.store.get_many([key('phlio_object', 'social', row['id']) for row in rows]),
        c.graph.store.get_many([key('platform_content', 'social', row['id']) for row in rows]),
        c.graph.store.get_many([key('block', a, b) for peer in creator_ids
                              for a, b in [(user.id, peer), (peer, user.id)]]),
    )
    creators = {creator.id: creator for creator in creators}
    objects = {obj['id']: obj for obj in objects}
    details = {detail['id']: detail for detail in details}
    blocked = {edge['id'] for edge in blocks}
    result = []
    for row in rows:
        obj = objects.get(key('phlio_object', 'social', row['id']))
        creator = creators.get(row['creator'])
        detail = details.get(key('platform_content', 'social', row['id']), {})
        if (creator and (not obj or obj['state'] == 'active')
            and visible_video(row, detail, user.id)
            and key('block', user.id, creator.id) not in blocked
            and key('block', creator.id, user.id) not in blocked):
            result.append(await video_response(row, c, creator,
                details.get(key('platform_content', 'social', row['id']), {})))
    await c.cache.put(cache_key, result)
    return result


def probe_duration(path):
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration:stream=codec_type",
                "-of",
                "json",
                str(path),
            ],
            capture_output=True,
            text=True,
            check=True,
            timeout=20,
        )
        data = json.loads(result.stdout)
        if not any(stream.get("codec_type") == "video" for stream in data.get("streams", [])):
            raise ValueError("No video track")
        return float(data["format"]["duration"])
    except FileNotFoundError as exc:
        raise HTTPException(503, "Video processing is unavailable. Please try again later.") from exc
    except (subprocess.SubprocessError, ValueError, KeyError) as exc:
        raise HTTPException(422, "Choose a playable video file.") from exc


@router.post("/videos", status_code=201)
async def upload_video(
    title: str = Form(..., min_length=1, max_length=160),
    file: UploadFile = File(...),
    kind: Literal["video", "clip"] = Form("video"),
    music_id: str | None = Form(None, pattern=r"^[A-Za-z0-9]{22}$"),
    description: str = Form("", max_length=5000),
    visibility: Literal["public", "unlisted", "private"] = Form("public"),
    audience: Literal["everyone", "adults"] = Form("everyone"),
    location: str | None = Form(None, max_length=120),
    related_video: str | None = Form(None, max_length=64),
    paid_promotion: bool = Form(False),
    playlist_ids: str = Form("", max_length=2000),
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    from app.api.v1.music import prepare_selection, attach_selection
    music = await prepare_selection(c,user.id,kind,music_id)
    title = title.strip()
    suffix = Path(file.filename or "").suffix.lower()
    if not title or suffix not in {".mp4", ".mov", ".m4v", ".webm"}:
        raise HTTPException(422, "Add a title and an MP4, MOV, M4V, or WebM video.")
    video_id = uuid.uuid4().hex
    directory = media_root_path(c.settings) / "social"
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / (video_id + suffix)
    cover = directory / (video_id + '.jpg')
    size = 0
    try:
        with target.open("wb") as destination:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > 2 * 1024 * 1024 * 1024:
                    raise HTTPException(413, "Video must be smaller than 2 GB.")
                destination.write(chunk)
        if not size:
            raise HTTPException(422, "The video is empty.")
        duration = await run_in_threadpool(probe_duration, target)
        minimum, maximum = (15, 120) if kind == "clip" else (60, 300)
        if not minimum <= duration <= maximum + 0.2:
            raise HTTPException(422, f"{kind.title()} must be between {minimum} and {maximum} seconds.")
        url = "/media/social/" + target.name
        try:
            await run_in_threadpool(make_thumbnail, target, cover, duration)
        except (OSError, subprocess.SubprocessError, ValueError) as exc:
            raise HTTPException(422, 'Could not generate a preview for this video.') from exc
        thumbnail_url = '/media/social/' + cover.name
        c.social_video_service.publish(
            video_id, user.id, title, url, kind=kind, duration_seconds=round(duration)
        )
        c.social_video_service.db.execute('UPDATE videos SET thumbnail_url=? WHERE id=?', (thumbnail_url, video_id))
        c.social_video_service.db.commit()
        obj = await c.graph.register_object(user.id, "social." + kind, video_id, title)
        await c.graph.action(user.id, obj["id"], "created", trusted=True)
        attach_selection(c,user.id,kind,video_id,music)
        # Upload details (Add details page).
        detail_key = key("platform_content", "social", video_id)
        existing = await c.graph.store.get(detail_key) or {}
        await c.graph.store.put(detail_key, dict(
            {k: v for k, v in existing.items() if k != "id"},
            description=description.strip(), visibility=visibility, audience=audience,
            location=(location or "").strip() or None,
            related_video=related_video or None, paid_promotion=paid_promotion))
    except BaseException:
        target.unlink(missing_ok=True)
        cover.unlink(missing_ok=True)
        raise
    # Add to the chosen Social playlists (bookmarks the video for the owner).
    if playlist_ids.strip():
        from app.api.v1.playlists import SaveBookmark, save_bookmark
        for pid in [p for p in playlist_ids.split(",") if p.strip()][:20]:
            try:
                await save_bookmark(SaveBookmark(platform="social", ref=video_id,
                                                 playlist_id=pid.strip(), move=False), user, c)
            except HTTPException:
                continue
    return dict(
        id=video_id,
        title=title,
        creator=user.username,
        creator_name=user.full_name,
        avatar_url=user.avatar_url,
        url=url,
        kind=kind,
        duration_seconds=round(duration),
        thumbnail_url=thumbnail_url,
    )


class ClipFeedback(BaseModel):
    preference: Literal["interested", "not_interested"]


@router.get("/clips/preferences")
async def clip_preferences(user=Depends(get_current_user), c=Depends(get_container)):
    return await c.graph.store.rows("clip_feedback", {"user_id": user.id})


@router.put("/clips/{clip_id}/preference", status_code=204)
async def clip_preference(clip_id: str, body: ClipFeedback,
                          user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c, user.id, "social", clip_id)
    # Videos share the same "Not interested" feedback as clips.
    if obj["object_type"] not in {"social.clip", "social.video"}:
        raise HTTPException(422, "Choose a clip or video.")
    await c.graph.store.put(key("clip_feedback", user.id, clip_id), dict(
        user_id=user.id, clip_id=clip_id, preference=body.preference,
        title=obj["title"], creator=(await c.identity_repository.get_by_id(obj["owner"])).username, updated_at=now()))


@router.put("/creators/{creator}/preference", status_code=204)
async def creator_preference(creator: str, user=Depends(get_current_user), c=Depends(get_container)):
    """"Don't recommend creator": hides the creator's clips and videos from
    this viewer's recommendations. Stored alongside clip feedback so
    GET /clips/preferences returns it to the client ranker."""
    person = await c.identity_repository.get_by_username(creator.lstrip("@").lower())
    if not person:
        raise HTTPException(404, "Creator unavailable.")
    if person.id == user.id:
        raise HTTPException(422, "You can't hide yourself.")
    await c.graph.store.put(key("clip_feedback", user.id, "creator:" + person.username), dict(
        user_id=user.id, clip_id="creator:" + person.username, preference="hide_creator",
        title="", creator=person.username, updated_at=now()))


@router.post("/clips/{clip_id}/report", status_code=204)
async def report_clip(clip_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c, user.id, "social", clip_id)
    await c.graph.store.put(key("content_report", user.id, obj["id"]), dict(
        user_id=user.id, object_id=obj["id"], status="pending", created_at=now()))
