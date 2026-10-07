"""Framework-agnostic domain entities for identity/accounts.

These are plain dataclasses, not Pydantic models — they represent the
*business* shape of a user, independent of how it is transported over HTTP
or stored. API schemas (`app/api/v1/auth.py`) and storage rows
(`app/infrastructure/database/*`) both convert to/from this type, but this
type itself depends on neither.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field


@dataclass(slots=True)
class User:
    id: str
    username: str
    full_name: str
    email: str
    hashed_password: str
    avatar_url: str | None
    bio: str
    interests: list[str] = field(default_factory=list)
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))
    is_verified: bool = False
    date_of_birth: dt.date | None = None
    phone_number: str | None = None

    def public_profile(self) -> PublicProfile:
        return PublicProfile(
            id=self.id,
            username=self.username,
            full_name=self.full_name,
            avatar_url=self.avatar_url,
            bio=self.bio,
            interests=self.interests,
            is_verified=self.is_verified,
        )


@dataclass(slots=True, frozen=True)
class PublicProfile:
    """The subset of `User` that is safe to expose to other users."""

    id: str
    username: str
    full_name: str
    avatar_url: str | None
    bio: str
    interests: list[str]
    is_verified: bool
