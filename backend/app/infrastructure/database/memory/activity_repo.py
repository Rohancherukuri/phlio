"""In-memory implementation of `ActivityRepository`."""

from __future__ import annotations

import asyncio

from app.domains.activity.entities import ActivityItem
from app.infrastructure.database.memory.social_repo import _paginate


class InMemoryActivityRepository:
    def __init__(self) -> None:
        self._items_by_user: dict[str, list[ActivityItem]] = {}
        self._lock = asyncio.Lock()

    # -- seeding helper (used by app/core/seed.py, not part of Protocol) ----
    async def seed_item(self, item: ActivityItem) -> None:
        self._items_by_user.setdefault(item.user_id, []).append(item)
        self._items_by_user[item.user_id].sort(key=lambda i: i.created_at, reverse=True)

    async def add(self, item: ActivityItem) -> ActivityItem:
        async with self._lock:
            self._items_by_user.setdefault(item.user_id, []).insert(0, item)
            return item

    async def list_for_user(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[ActivityItem], str | None]:
        return _paginate(self._items_by_user.get(user_id, []), cursor=cursor, limit=limit)

    async def mark_all_read(self, user_id: str) -> int:
        async with self._lock:
            changed = 0
            for item in self._items_by_user.get(user_id, []):
                if not item.is_read:
                    item.is_read = True
                    changed += 1
            return changed
