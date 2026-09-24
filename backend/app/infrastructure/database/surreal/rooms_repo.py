"""SurrealDB implementation of `RoomsRepository`.

Table shape (see `data/surrealdb/schema/rooms.surql`):

    DEFINE TABLE room SCHEMAFULL;
    DEFINE FIELD name          ON room TYPE string;
    DEFINE FIELD slug          ON room TYPE string;
    DEFINE FIELD description   ON room TYPE string;
    DEFINE FIELD category      ON room TYPE string;
    DEFINE FIELD icon          ON room TYPE string;
    DEFINE FIELD is_private    ON room TYPE bool DEFAULT false;
    DEFINE FIELD member_count  ON room TYPE int DEFAULT 0;
    DEFINE FIELD created_by    ON room TYPE option<record<user>>;
    DEFINE FIELD created_at    ON room TYPE datetime DEFAULT time::now();
    DEFINE INDEX room_slug_unique ON room FIELDS slug UNIQUE;

    -- Membership as a graph edge, the same pattern as `liked` in social.surql:
    DEFINE TABLE member_of TYPE RELATION FROM user TO room;

    DEFINE TABLE room_message SCHEMAFULL;
    DEFINE FIELD room_id   ON room_message TYPE record<room>;
    DEFINE FIELD author_id ON room_message TYPE record<user>;
    DEFINE FIELD text      ON room_message TYPE string;
    DEFINE FIELD created_at ON room_message TYPE datetime DEFAULT time::now();
"""

from __future__ import annotations

from surrealdb import Surreal

from app.domains.rooms.entities import Room, RoomCategory, RoomMessage

_ROOMS = "room"
_MESSAGES = "room_message"


def _strip_prefix(record_id: str) -> str:
    return record_id.split(":", 1)[1] if ":" in record_id else record_id


def _row_to_room(row: dict) -> Room:
    return Room(
        id=_strip_prefix(row["id"]),
        name=row["name"],
        slug=row["slug"],
        description=row.get("description", ""),
        category=RoomCategory(row["category"]),
        icon=row.get("icon", "💬"),
        is_private=row.get("is_private", False),
        member_count=row.get("member_count", 0),
        created_by=_strip_prefix(row["created_by"]) if row.get("created_by") else None,
        created_at=row["created_at"],
    )


def _row_to_message(row: dict) -> RoomMessage:
    return RoomMessage(
        id=_strip_prefix(row["id"]),
        room_id=_strip_prefix(row["room_id"]),
        author_id=_strip_prefix(row["author_id"]),
        text=row["text"],
        created_at=row["created_at"],
    )


class SurrealRoomsRepository:
    def __init__(self, db: Surreal) -> None:
        self._db = db

    async def create_room(self, room: Room) -> Room:
        row = await self._db.create(
            f"{_ROOMS}:{room.id}",
            {
                "name": room.name,
                "slug": room.slug,
                "description": room.description,
                "category": room.category.value,
                "icon": room.icon,
                "is_private": room.is_private,
                "member_count": room.member_count,
                "created_by": f"user:{room.created_by}" if room.created_by else None,
                "created_at": room.created_at,
            },
        )
        return _row_to_room(row[0] if isinstance(row, list) else row)

    async def get_room(self, room_id: str) -> Room | None:
        row = await self._db.select(f"{_ROOMS}:{room_id}")
        return _row_to_room(row[0] if isinstance(row, list) else row) if row else None

    async def get_room_by_slug(self, slug: str) -> Room | None:
        result = await self._db.query(
            f"SELECT * FROM {_ROOMS} WHERE slug = $slug LIMIT 1", {"slug": slug}
        )
        records = result[0]["result"] if result and result[0].get("result") else []
        return _row_to_room(records[0]) if records else None

    async def list_rooms(
        self, *, category: RoomCategory | None, cursor: str | None, limit: int
    ) -> tuple[list[Room], str | None]:
        query = f"SELECT * FROM {_ROOMS} "
        params: dict = {"limit": limit + 1}
        clauses = []
        if category is not None:
            clauses.append("category = $category")
            params["category"] = category.value
        if cursor:
            clauses.append("member_count <= $cursor")
            params["cursor"] = int(cursor)
        if clauses:
            query += "WHERE " + " AND ".join(clauses) + " "
        query += "ORDER BY member_count DESC LIMIT $limit"

        result = await self._db.query(query, params)
        records = result[0]["result"] if result and result[0].get("result") else []
        has_more = len(records) > limit
        page = records[:limit]
        next_cursor = str(page[-1]["member_count"]) if has_more and page else None
        return [_row_to_room(r) for r in page], next_cursor

    async def is_member(self, room_id: str, user_id: str) -> bool:
        result = await self._db.query(
            "SELECT VALUE count() FROM member_of WHERE in = $user AND out = $room",
            {"user": f"user:{user_id}", "room": f"{_ROOMS}:{room_id}"},
        )
        records = result[0]["result"] if result and result[0].get("result") else []
        return bool(records and records[0])

    async def join_room(self, room_id: str, user_id: str) -> Room:
        if not await self.is_member(room_id, user_id):
            await self._db.query(
                "RELATE $user->member_of->$room",
                {"user": f"user:{user_id}", "room": f"{_ROOMS}:{room_id}"},
            )
            await self._db.query(f"UPDATE {_ROOMS}:{room_id} SET member_count += 1")
        room = await self.get_room(room_id)
        assert room is not None
        return room

    async def list_member_rooms(self, user_id: str) -> list[Room]:
        result = await self._db.query(
            "SELECT ->member_of->room.* AS rooms FROM $user",
            {"user": f"user:{user_id}"},
        )
        records = result[0]["result"] if result and result[0].get("result") else []
        rooms = records[0].get("rooms", []) if records else []
        return [_row_to_room(r) for r in rooms]

    async def add_message(self, message: RoomMessage) -> RoomMessage:
        row = await self._db.create(
            f"{_MESSAGES}:{message.id}",
            {
                "room_id": f"{_ROOMS}:{message.room_id}",
                "author_id": f"user:{message.author_id}",
                "text": message.text,
                "created_at": message.created_at,
            },
        )
        return _row_to_message(row[0] if isinstance(row, list) else row)

    async def list_messages(
        self, room_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[RoomMessage], str | None]:
        query = f"SELECT * FROM {_MESSAGES} WHERE room_id = $room "
        params: dict = {"room": f"{_ROOMS}:{room_id}", "limit": limit + 1}
        if cursor:
            query += "AND created_at < $cursor "
            params["cursor"] = cursor
        query += "ORDER BY created_at DESC LIMIT $limit"

        result = await self._db.query(query, params)
        records = result[0]["result"] if result and result[0].get("result") else []
        has_more = len(records) > limit
        page = records[:limit]
        next_cursor = page[-1]["created_at"].isoformat() if has_more and page else None
        return [_row_to_message(r) for r in page], next_cursor
