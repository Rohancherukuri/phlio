"""Durable Activity feed (notifications) on SurrealDB, table ``activity_item``.

(``activity`` is taken by the social graph's edges.) Replaces the in-memory
store in "surreal" mode so notifications survive restarts and deploys.
"""

from __future__ import annotations

from dataclasses import asdict

from app.domains.activity.entities import ActivityItem, ActivityKind
from app.infrastructure.database.memory.social_repo import _paginate
from app.infrastructure.database.surreal.client import record
from app.infrastructure.database.surreal.pay_repo import _raw_id, _when


class SurrealActivityRepository:
    def __init__(self, db):
        self._db = db

    async def seed_item(self, item: ActivityItem) -> None:
        await self.add(item)

    async def add(self, item: ActivityItem) -> ActivityItem:
        data = asdict(item)
        data.pop("id")
        data.update(kind=str(item.kind), created_at=item.created_at.isoformat())
        await self._db.query("UPSERT $id CONTENT $data", {"id": record("activity_item:" + item.id), "data": data})
        return item

    async def list_for_user(self, *, user_id: str, cursor: str | None, limit: int):
        rows = await self._db.rows(
            "SELECT * FROM activity_item WHERE user_id = $u ORDER BY created_at DESC", {"u": user_id})
        items = [
            ActivityItem(id=_raw_id(r), user_id=r["user_id"], kind=ActivityKind(r["kind"]), title=r["title"],
                         body=r.get("body", ""), icon=r.get("icon", "🔔"), ref_id=r.get("ref_id"),
                         created_at=_when(r["created_at"]), is_read=bool(r.get("is_read")))
            for r in rows
        ]
        return _paginate(items, cursor=cursor, limit=limit)

    async def mark_all_read(self, user_id: str) -> int:
        rows = await self._db.rows(
            "UPDATE activity_item SET is_read = true WHERE user_id = $u AND is_read = false RETURN BEFORE",
            {"u": user_id})
        return len(rows or [])
