"""Video upload/discovery and authenticated follow actions."""

import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

from app.api.deps import get_container, get_current_user
from app.core.container import Container, media_root_path
from app.domains.identity.entities import User

router = APIRouter(prefix="/social", tags=["social videos"])


@router.get("/following")
async def following(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    return c.social_video_service.following(user.id)


@router.put("/creators/{username}/follow", status_code=204)
async def follow(
    username: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    creator = await c.identity_repository.get_by_username(username.lower())
    if creator is None:
        raise HTTPException(404, "Creator not found.")
    if creator.id == user.id:
        raise HTTPException(422, "You cannot follow yourself.")
    c.social_video_service.follow(user.id, creator.username, True)


@router.delete("/creators/{username}/follow", status_code=204)
async def unfollow(
    username: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    c.social_video_service.follow(user.id, username.lower(), False)


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
    )


@router.get("/videos")
async def videos(
    before: str | None = None, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    result = []
    for row in c.social_video_service.videos(before):
        video = await video_response(row, c)
        if video:
            result.append(video)
    return result


@router.post("/videos", status_code=201)
async def upload_video(
    title: str = Form(..., min_length=1, max_length=160),
    file: UploadFile = File(...),
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
        url = "/media/social/" + target.name
        c.social_video_service.publish(video_id, user.id, title, url)
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
    )
