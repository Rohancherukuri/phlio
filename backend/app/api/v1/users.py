"""Public user profile lookups (does not require authentication)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.api.deps import get_container, get_current_user, get_identity_service
from app.api.v1.social import PostResponse
from app.common.schemas import Page, PageMeta
from app.core.container import Container
from app.domains.identity.entities import PublicProfile, User
from app.domains.identity.service import IdentityService

router = APIRouter(prefix="/users", tags=["users"])


class PublicProfileResponse(BaseModel):
    id: str
    username: str
    full_name: str
    avatar_url: str | None
    bio: str
    interests: list[str]
    is_verified: bool
    followers: int = 0
    following: int = 0
    post_count: int = 0
    # Private account: a lock on the profile; only followers see its posts.
    is_private: bool = False

    @classmethod
    def from_entity(cls, profile: PublicProfile) -> PublicProfileResponse:
        return cls(
            id=profile.id,
            username=profile.username,
            full_name=profile.full_name,
            avatar_url=profile.avatar_url,
            bio=profile.bio,
            interests=profile.interests,
            is_verified=profile.is_verified,
        )


@router.get("/{username}", response_model=PublicProfileResponse)
async def get_public_profile(
    username: str,
    identity_service: IdentityService = Depends(get_identity_service),
    container: Container = Depends(get_container),
) -> PublicProfileResponse:
    profile = await identity_service.get_public_profile_by_username(username)
    response = PublicProfileResponse.from_entity(profile)
    from app.api.v1.appearance import is_private

    response.is_private = await is_private(container, profile.id)
    response.followers = len(await container.graph.store.rows("follows", {"out": "user:" + profile.id}))
    response.following = len(await container.graph.store.rows("follows", {"in": "user:" + profile.id}))
    posts, cursor = await container.social_repository.list_posts_by_author(profile.id, cursor=None, limit=100)
    response.post_count = sum([await container.social_service.visible_to(p, profile.id) for p in posts])
    while cursor:
        posts, cursor = await container.social_repository.list_posts_by_author(
            profile.id, cursor=cursor, limit=100
        )
        response.post_count += sum([await container.social_service.visible_to(p, profile.id) for p in posts])
    # Uploaded videos and clips count as posts too.
    response.post_count += container.social_video_service.db.execute(
        "SELECT COUNT(*) FROM videos WHERE creator=?", (profile.id,)
    ).fetchone()[0]
    return response


@router.get("/{username}/posts", response_model=Page[PostResponse])
async def author_posts(
    username: str,
    cursor: str | None = None,
    limit: int = Query(default=50, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    container: Container = Depends(get_container),
) -> Page[PostResponse]:
    profile = await container.identity_service.get_public_profile_by_username(username)
    if await container.graph.blocked(current_user.id, profile.id):
        from fastapi import HTTPException

        raise HTTPException(404, "Profile content unavailable.")
    from app.api.v1.appearance import can_see_private

    if not await can_see_private(container, current_user.id, profile.id):
        # Private account: followers only.
        return Page(items=[], meta=PageMeta(next_cursor=None, has_more=False))
    posts, next_cursor = await container.social_repository.list_posts_by_author(
        profile.id, cursor=cursor, limit=limit
    )
    from app.api.v1.social import post_settings

    # Pinned posts (up to 6) lead the first page, newest pin first.
    pins = sorted((r for r in await container.graph.store.rows("post_setting", {"author": profile.id})
                   if r.get("pinned_at")), key=lambda r: r["pinned_at"], reverse=True)
    pinned_ids = [r["post_id"] for r in pins]
    if cursor is None and pinned_ids:
        lead = []
        for pid in pinned_ids:
            found = next((p for p in posts if p.id == pid), None) or await container.social_repository.get_post(pid)
            if found is not None:
                lead.append(found)
        posts = lead + [p for p in posts if p.id not in pinned_ids]
    elif pinned_ids:
        posts = [p for p in posts if p.id not in pinned_ids]
    settings = await post_settings(container, [p.id for p in posts])
    items = []
    for post in posts:
        if not await container.social_service.visible_to(post, current_user.id):
            continue
        out = PostResponse.from_entity(
            post, liked_by_me=await container.social_service.is_liked_by(post.id, current_user.id))
        out.pinned = post.id in pinned_ids
        out.profile_only = bool(settings.get(post.id, {}).get("profile_only"))
        items.append(out)
    return Page(
        items=items,
        meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None),
    )
