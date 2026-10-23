"""In-memory implementation of `RoomsRepository`."""

from __future__ import annotations

import asyncio

from app.domains.rooms.entities import Room, RoomCategory, RoomMessage
from app.infrastructure.database.memory.social_repo import _paginate


class InMemoryRoomsRepository:
    def __init__(self) -> None:
        self._rooms: dict[str, Room] = {}
        self._rooms_by_slug: dict[str, str] = {}
        self._members: dict[str, set[str]] = {}  # room_id -> {user_id}
        self._messages_by_room: dict[str, list[RoomMessage]] = {}
        self._lock = asyncio.Lock()

    async def create_room(self, room: Room) -> Room:
        async with self._lock:
            self._rooms[room.id] = room
            self._rooms_by_slug[room.slug] = room.id
            self._members.setdefault(room.id, set())
            return room

    async def get_room(self, room_id: str) -> Room | None:
        return self._rooms.get(room_id)

    async def get_room_by_slug(self, slug: str) -> Room | None:
        room_id = self._rooms_by_slug.get(slug)
        return self._rooms.get(room_id) if room_id else None

    async def list_rooms(
        self, *, category: RoomCategory | None, cursor: str | None, limit: int
    ) -> tuple[list[Room], str | None]:
        rooms = sorted(self._rooms.values(), key=lambda r: r.member_count, reverse=True)
        if category is not None:
            rooms = [r for r in rooms if r.category == category]
        return _paginate(rooms, cursor=cursor, limit=limit)

    async def is_member(self, room_id: str, user_id: str) -> bool:
        return user_id in self._members.get(room_id, set())

    async def join_room(self, room_id: str, user_id: str) -> Room:
        async with self._lock:
            members = self._members.setdefault(room_id, set())
            room = self._rooms[room_id]
            if user_id not in members:
                members.add(user_id)
                room.member_count += 1
            return room

    async def list_member_rooms(self, user_id: str) -> list[Room]:
        return [
            self._rooms[room_id]
            for room_id, members in self._members.items()
            if user_id in members and room_id in self._rooms
        ]

    async def add_message(self, message: RoomMessage) -> RoomMessage:
        async with self._lock:
            messages = self._messages_by_room.setdefault(message.room_id, [])
            messages.append(message)
            # Sort by `created_at` rather than trusting insertion order — see
            # the identical comment in memory/social_repo.py.
            messages.sort(key=lambda m: m.created_at, reverse=True)
            return message

    async def get_message(self, room_id: str, message_id: str) -> RoomMessage | None:
        for message in self._messages_by_room.get(room_id, []):
            if message.id == message_id:
                return message
        return None

    async def update_message(self, message: RoomMessage) -> RoomMessage:
        # The in-memory store keeps live dataclass instances, so reaction
        # edits made on the instance are already "persisted"; the call just
        # re-sorts and hands it back for symmetry with the real repos.
        async with self._lock:
            messages = self._messages_by_room.get(message.room_id, [])
            messages.sort(key=lambda m: m.created_at, reverse=True)
            return message

    async def list_messages(
        self, room_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[RoomMessage], str | None]:
        messages = self._messages_by_room.get(room_id, [])
        return _paginate(messages, cursor=cursor, limit=limit)
