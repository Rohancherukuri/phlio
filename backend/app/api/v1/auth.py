"""
Auth endpoints: register, login, refresh, and "who am I".

Request/response Pydantic schemas live here, co-located with the routes
that use them — they are an HTTP-boundary concern, distinct from the
framework-agnostic domain entities in `app/domains/identity/entities.py`.
Each response model has a small `from_entity` classmethod that performs the
conversion, so the mapping is defined once and can't drift between routes.
"""

from __future__ import annotations

import datetime as dt
import re

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, EmailStr, Field, field_validator

from app.api.deps import get_container, get_current_user, get_identity_service
from app.core.container import Container
from app.domains.identity.entities import User
from app.domains.identity.service import IdentityService
from app.infrastructure.security.jwt import TokenPair, decode_token, issue_token_pair

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=120)
    username: str = Field(min_length=3, max_length=30, pattern=r"^[a-zA-Z0-9._]+$")
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    interests: list[str] = Field(default_factory=list, max_length=20)
    date_of_birth: dt.date | None = None
    phone_number: str | None = None

    @field_validator("date_of_birth")
    @classmethod
    def valid_birthday(cls, value):
        if value is not None and not dt.date(1900, 1, 1) <= value < dt.datetime.now(dt.UTC).date():
            raise ValueError("Choose a date of birth in the past, from 1900 onward.")
        return value

    @field_validator("phone_number")
    @classmethod
    def valid_phone(cls, value):
        if value is None:
            return None
        value = re.sub(r"[\s()\-]", "", value)
        if not re.fullmatch(r"\+[1-9][0-9]{7,14}", value):
            raise ValueError("Enter a phone number with country code, for example +919876543210.")
        return value


class LoginRequest(BaseModel):
    identifier: str = Field(description="Username, email, or international phone number.")
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class UserResponse(BaseModel):
    id: str
    username: str
    full_name: str
    email: str
    avatar_url: str | None
    bio: str
    interests: list[str]
    is_verified: bool
    created_at: dt.datetime
    is_creator: bool = False
    is_test_user: bool = False
    date_of_birth: dt.date | None = None
    phone_number: str | None = None

    @classmethod
    def from_entity(cls, user: User) -> UserResponse:
        return cls(
            id=user.id,
            username=user.username,
            full_name=user.full_name,
            email=user.email,
            avatar_url=user.avatar_url,
            bio=user.bio,
            interests=user.interests,
            is_verified=user.is_verified,
            created_at=user.created_at,
            is_creator=user.is_creator,
            is_test_user=user.is_test_user,
            date_of_birth=user.date_of_birth,
            phone_number=user.phone_number,
        )


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str
    expires_in_seconds: int

    @classmethod
    def from_token_pair(cls, tokens: TokenPair) -> TokenResponse:
        return cls(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            token_type=tokens.token_type,
            expires_in_seconds=tokens.expires_in_seconds,
        )


class AuthResponse(BaseModel):
    user: UserResponse
    tokens: TokenResponse


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(
    body: RegisterRequest, identity_service: IdentityService = Depends(get_identity_service)
) -> AuthResponse:
    user, tokens = await identity_service.register(
        full_name=body.full_name,
        username=body.username,
        email=body.email,
        password=body.password,
        interests=body.interests,
        date_of_birth=body.date_of_birth,
        phone_number=body.phone_number,
    )
    return AuthResponse(user=UserResponse.from_entity(user), tokens=TokenResponse.from_token_pair(tokens))


@router.post("/login", response_model=AuthResponse)
async def login(
    body: LoginRequest, identity_service: IdentityService = Depends(get_identity_service)
) -> AuthResponse:
    user, tokens = await identity_service.authenticate(identifier=body.identifier, password=body.password)
    return AuthResponse(user=UserResponse.from_entity(user), tokens=TokenResponse.from_token_pair(tokens))


@router.post("/refresh", response_model=TokenResponse)
async def refresh(body: RefreshRequest, container: Container = Depends(get_container)) -> TokenResponse:
    user_id = decode_token(body.refresh_token, "refresh", container.settings)
    # Confirms the user still exists (e.g. hasn't been deleted) before
    # minting a fresh access token.
    await container.identity_service.get_user_or_raise(user_id)
    tokens = issue_token_pair(user_id, container.settings)
    return TokenResponse.from_token_pair(tokens)


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)) -> UserResponse:
    return UserResponse.from_entity(current_user)
