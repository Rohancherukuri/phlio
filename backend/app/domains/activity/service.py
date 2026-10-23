"""Activity domain service: the cross-domain notification feed.

Book/Pay domain code paths (and, later, Rooms/Social events) append items
here through [record]; the API exposes a read-only feed plus mark-all-read.
Read state stays ephemeral in this build stage — same tradeoff as Agent
conversation history.
"""

from __future__ import annotations

import logging

from app.domains.activity.entities import ActivityItem, ActivityKind
from app.domains.activity.repository import ActivityRepository

logger = logging.getLogger("phlio.activity")


class ActivityService:
    def __init__(self, repository: ActivityRepository, id_factory) -> None:
        self._repository = repository
        self._id_factory = id_factory

    async def record(
        self,
        *,
        user_id: str,
        kind: ActivityKind,
        title: str,
        body: str,
        icon: str = "🔔",
        ref_id: str | None = None,
    ) -> ActivityItem:
        item = ActivityItem(
            id=await self._id_factory("act"),
            user_id=user_id,
            kind=kind,
            title=title,
            body=body,
            icon=icon,
            ref_id=ref_id,
        )
        created = await self._repository.add(item)
        logger.debug("activity.recorded id=%s kind=%s user_id=%s", created.id, kind, user_id)
        return created

    async def list_feed(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[ActivityItem], str | None]:
        return await self._repository.list_for_user(user_id=user_id, cursor=cursor, limit=limit)

    async def mark_all_read(self, user_id: str) -> int:
        return await self._repository.mark_all_read(user_id)
