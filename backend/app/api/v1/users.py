"""Public user profile lookups (does not require authentication)."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.api.deps import get_identity_service
from app.domains.identity.entities import PublicProfile
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
