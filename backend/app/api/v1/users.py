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
    username: str, identity_service: IdentityService = Depends(get_identity_service)
) -> PublicProfileResponse:
    profile = await identity_service.get_public_profile_by_username(username)
    return PublicProfileResponse.from_entity(profile)


@router.get("/{username}/posts", response_model=Page[PostResponse])
async def author_posts(
    username: str,
    cursor: str | None = None,
    limit: int = Query(default=50, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    container: Container = Depends(get_container),
) -> Page[PostResponse]:
    profile = await container.identity_service.get_public_profile_by_username(username)
    posts, next_cursor = await container.social_repository.list_posts_by_author(
        profile.id, cursor=cursor, limit=limit
    )
    return Page(
        items=[
            PostResponse.from_entity(
                post, liked_by_me=await container.social_service.is_liked_by(post.id, current_user.id)
            )
            for post in posts
        ],
        meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None),
    )
