"""Video upload/discovery and authenticated follow actions."""

import json
import subprocess
import uuid
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool

from app.api.deps import get_container, get_current_user
from app.core.container import Container, media_root_path
from app.domains.graph.service import key
from app.domains.identity.entities import User

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


async def video_response(row, c):
    creator = await c.identity_repository.get_by_id(row["creator"])
    if not creator:
        return None
    return dict(
        id=row["id"],
        title=row["title"],
        creator=creator.username,
        creator_name=creator.full_name,
        avatar_url=creator.avatar_url,
        url=row["url"],
        created_at=row["created_at"],
        kind=row.get("kind", "video"),
        thumbnail_url=row.get("thumbnail_url"),
        duration_seconds=row.get("duration_seconds", 0),
    )


@router.get("/videos")
async def videos(
    before: str | None = None, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    before = before.strip() or None if before is not None else None
    revision = await c.graph.store.revision()
    cache_key = f"videos:v2:{revision}:{user.id}:{before}"
    cached = await c.cache.get(cache_key)
    if cached is not None:
        return cached
    result = []
    for row in c.social_video_service.videos(before):
        video = await video_response(row, c)
        obj = await c.graph.store.get(key("phlio_object", "social", row["id"]))
        if (
            video
            and (not obj or obj["state"] == "active")
            and not await c.graph.blocked(user.id, row["creator"])
        ):
            result.append(video)
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
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    title = title.strip()
    suffix = Path(file.filename or "").suffix.lower()
    if not title or suffix not in {".mp4", ".mov", ".m4v", ".webm"}:
        raise HTTPException(422, "Add a title and an MP4, MOV, M4V, or WebM video.")
    video_id = uuid.uuid4().hex
    directory = media_root_path(c.settings) / "social"
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / (video_id + suffix)
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
        c.social_video_service.publish(
            video_id, user.id, title, url, kind=kind, duration_seconds=round(duration)
        )
        obj = await c.graph.register_object(user.id, "social." + kind, video_id, title)
        await c.graph.action(user.id, obj["id"], "created", trusted=True)
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    return dict(
        id=video_id,
        title=title,
        creator=user.username,
        creator_name=user.full_name,
        avatar_url=user.avatar_url,
        url=url,
        kind=kind,
        duration_seconds=round(duration),
    )
