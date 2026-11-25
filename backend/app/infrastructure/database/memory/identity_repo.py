"""In-memory implementation of `IdentityRepository`."""

from __future__ import annotations

import asyncio
import datetime as dt

from app.domains.identity.entities import User


class InMemoryIdentityRepository:
    def __init__(self) -> None:
        self._by_id: dict[str, User] = {}
        self._by_username: dict[str, str] = {}  # username -> id
        self._by_email: dict[str, str] = {}  # email -> id
        self._lock = asyncio.Lock()

    async def create_user(self, user: User) -> User:
        async with self._lock:
            self._by_id[user.id] = user
            self._by_username[user.username] = user.id
            self._by_email[user.email] = user.id
            return user

    async def get_by_id(self, user_id: str) -> User | None:
        return self._by_id.get(user_id)

    async def get_many(self, user_ids: list[str]) -> list[User]:
        return [self._by_id[uid] for uid in set(user_ids) if uid in self._by_id]

    async def get_by_username(self, username: str) -> User | None:
        user_id = self._by_username.get(username)
        return self._by_id.get(user_id) if user_id else None

    async def get_by_email(self, email: str) -> User | None:
        user_id = self._by_email.get(email)
        return self._by_id.get(user_id) if user_id else None

    async def get_by_phone(self, phone_number: str) -> User | None:
        return next((u for u in self._by_id.values() if u.phone_number == phone_number), None)

    async def search_users(self, query: str, limit: int = 30) -> list[User]:
        q = query.casefold().lstrip("@")
        return [u for u in self._by_id.values() if q in u.username.casefold() or q in u.full_name.casefold()][
            :limit
        ]

    async def update_user(self, user: User) -> User:
        async with self._lock:
            self._by_id[user.id] = user
            return user

    # --- Admin analytics -------------------------------------------------
    async def list_users(self, offset: int = 0, limit: int = 50) -> list[User]:
        users = sorted(self._by_id.values(), key=lambda u: u.created_at, reverse=True)
        return users[offset : offset + limit]

    async def count_users(self) -> int:
        return len(self._by_id)

    async def signups_since(self, since: dt.datetime) -> list[dt.datetime]:
        return [u.created_at for u in self._by_id.values() if u.created_at >= since]
