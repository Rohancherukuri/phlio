"""Repository contract for the Activity feed."""

from __future__ import annotations

from typing import Protocol

from app.domains.activity.entities import ActivityItem


class ActivityRepository(Protocol):
    async def add(self, item: ActivityItem) -> ActivityItem: ...

    async def list_for_user(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[ActivityItem], str | None]: ...

    async def mark_all_read(self, user_id: str) -> int: ...
