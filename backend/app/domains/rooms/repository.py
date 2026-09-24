"""Repository contract for the rooms domain."""

from __future__ import annotations

from typing import Protocol

from app.domains.rooms.entities import Room, RoomCategory, RoomMessage


class RoomsRepository(Protocol):
    async def create_room(self, room: Room) -> Room: ...

    async def get_room(self, room_id: str) -> Room | None: ...

    async def get_room_by_slug(self, slug: str) -> Room | None: ...

    async def list_rooms(
        self, *, category: RoomCategory | None, cursor: str | None, limit: int
    ) -> tuple[list[Room], str | None]: ...

    async def is_member(self, room_id: str, user_id: str) -> bool: ...

    async def join_room(self, room_id: str, user_id: str) -> Room: ...

    async def list_member_rooms(self, user_id: str) -> list[Room]: ...

    async def add_message(self, message: RoomMessage) -> RoomMessage: ...

    async def list_messages(
        self, room_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[RoomMessage], str | None]: ...
