"""
JWT issuance and verification for access/refresh tokens.

Deliberately minimal: Phlio uses short-lived, symmetric-key HS256 access
tokens plus a longer-lived refresh token, both carrying just enough claims
to identify the subject. Sensitive authorization decisions are never
encoded in the token itself (e.g. no "role": "admin" trusted blindly) —
each request re-checks permissions against current data, per the
architecture document's Phlio Guard principle that the AI/token layer
should never become the system of record for authorization.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from typing import Literal

import jwt as pyjwt

from app.common.exceptions import UnauthorizedError
from app.config import Settings

TokenType = Literal["access", "refresh"]


@dataclass(frozen=True, slots=True)
class TokenPair:
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in_seconds: int = 0


def _create_token(user_id: str, token_type: TokenType, settings: Settings) -> str:
    now = dt.datetime.now(dt.UTC)
    if token_type == "access":
        expires_delta = dt.timedelta(minutes=settings.access_token_expire_minutes)
    else:
        expires_delta = dt.timedelta(days=settings.refresh_token_expire_days)

    payload = {
        "sub": user_id,
        "type": token_type,
        "iat": now,
        "exp": now + expires_delta,
    }
    return pyjwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def issue_token_pair(user_id: str, settings: Settings) -> TokenPair:
    access = _create_token(user_id, "access", settings)
    refresh = _create_token(user_id, "refresh", settings)
    return TokenPair(
        access_token=access,
        refresh_token=refresh,
        expires_in_seconds=settings.access_token_expire_minutes * 60,
    )


def decode_token(token: str, expected_type: TokenType, settings: Settings) -> str:
    """Decodes `token`, verifies it is of `expected_type`, and returns the
    subject (user id). Raises `UnauthorizedError` for any failure — expired,
    malformed, wrong type, or wrong signature all look the same to the
    caller by design, so a client cannot use error content to probe which
    part of the token was invalid.
    """
    try:
        payload = pyjwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except pyjwt.PyJWTError as exc:
        raise UnauthorizedError("Invalid or expired token.") from exc

    if payload.get("type") != expected_type:
        raise UnauthorizedError("Invalid or expired token.")

    subject = payload.get("sub")
    if not subject:
        raise UnauthorizedError("Invalid or expired token.")
    return subject
