"""Identity domain service: registration, authentication, profile lookups.

Business rules that live here (rather than in the API layer or the
repository) because they are true regardless of transport or storage:
 - usernames/emails must be unique
 - passwords are always hashed before touching storage
 - "authenticate" never reveals whether a username or a password was wrong
"""

from __future__ import annotations

import logging

from fastapi.concurrency import run_in_threadpool

from app.common.exceptions import ConflictError, NotFoundError, UnauthorizedError
from app.config import Settings
from app.domains.identity.entities import User
from app.domains.identity.repository import IdentityRepository
from app.infrastructure.core_engine.client import CoreEngineClient
from app.infrastructure.security.jwt import TokenPair, issue_token_pair
from app.infrastructure.security.password import hash_password, verify_password

logger = logging.getLogger("phlio.identity")


class IdentityService:
    def __init__(
        self,
        repository: IdentityRepository,
        core_engine: CoreEngineClient,
        settings: Settings,
    ) -> None:
        self._repository = repository
        self._core_engine = core_engine
        self._settings = settings

    async def register(
        self,
        *,
        full_name: str,
        username: str,
        email: str,
        password: str,
        interests: list[str] | None = None,
    ) -> tuple[User, TokenPair]:
        username_normalized = username.strip().lower()
        email_normalized = email.strip().lower()

        if await self._repository.get_by_username(username_normalized) is not None:
            logger.info("identity.register_rejected reason=username_taken username=%s", username_normalized)
            raise ConflictError("That username is already taken.", code="username_taken")
        if await self._repository.get_by_email(email_normalized) is not None:
            logger.info("identity.register_rejected reason=email_taken")
            raise ConflictError("An account with that email already exists.", code="email_taken")

        user_id = await self._core_engine.generate_id("usr")
        # bcrypt hashing is CPU-bound; run off the event loop.
        hashed = await run_in_threadpool(hash_password, password)

        user = User(
            id=user_id,
            username=username_normalized,
            full_name=full_name.strip(),
            email=email_normalized,
            hashed_password=hashed,
            avatar_url=None,
            bio="",
            interests=interests or [],
        )
        created = await self._repository.create_user(user)
        tokens = issue_token_pair(created.id, self._settings)
        logger.info("identity.registered user_id=%s username=%s", created.id, created.username)
        return created, tokens

    async def authenticate(self, *, identifier: str, password: str) -> tuple[User, TokenPair]:
        identifier_normalized = identifier.strip().lower()
        user = await self._repository.get_by_username(
            identifier_normalized
        ) or await self._repository.get_by_email(identifier_normalized)

        # Deliberately identical error for "no such user" and "wrong
        # password" — distinguishing them lets an attacker enumerate valid
        # usernames/emails.
        invalid = UnauthorizedError("Incorrect username/email or password.")
        if user is None:
            logger.info("identity.login_rejected reason=no_such_user")
            raise invalid
        if not await run_in_threadpool(verify_password, password, user.hashed_password):
            logger.warning("identity.login_rejected reason=wrong_password user_id=%s", user.id)
            raise invalid

        tokens = issue_token_pair(user.id, self._settings)
        logger.info("identity.authenticated user_id=%s", user.id)
        return user, tokens

    async def get_user_or_raise(self, user_id: str) -> User:
        user = await self._repository.get_by_id(user_id)
        if user is None:
            raise NotFoundError("User not found.")
        return user

    async def get_public_profile_by_username(self, username: str):
        user = await self._repository.get_by_username(username.strip().lower())
        if user is None:
            raise NotFoundError("User not found.")
        return user.public_profile()
