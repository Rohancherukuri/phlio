"""Rooms domain service: discovery, membership, and messaging."""

from __future__ import annotations

import logging

from app.common.exceptions import ForbiddenError, NotFoundError, ValidationAppError
from app.domains.rooms.entities import Room, RoomCategory, RoomMessage
from app.domains.rooms.repository import RoomsRepository
from app.infrastructure.core_engine.client import CoreEngineClient

logger = logging.getLogger("phlio.rooms")

MAX_MESSAGE_LENGTH = 4_000


class RoomsService:
    def __init__(self, repository: RoomsRepository, core_engine: CoreEngineClient) -> None:
        self._repository = repository
        self._core_engine = core_engine

    async def discover(
        self, *, category: RoomCategory | None, cursor: str | None, limit: int
    ) -> tuple[list[Room], str | None]:
        return await self._repository.list_rooms(category=category, cursor=cursor, limit=limit)

    async def create_room(
        self,
        *,
        created_by: str,
        name: str,
        description: str,
        category: RoomCategory,
        icon: str,
        is_private: bool,
    ) -> Room:
        name = name.strip()
        if not name:
            raise ValidationAppError("A room needs a name.")
        slug = name.lower().replace(" ", "-")
        room = Room(
            id=await self._core_engine.generate_id("rm"),
            name=name,
            slug=slug,
            description=description.strip(),
            category=category,
            icon=icon,
            is_private=is_private,
            created_by=created_by,
            member_count=0,  # join_room below is the single source of truth for the count
        )
        created = await self._repository.create_room(room)
        joined = await self._repository.join_room(created.id, created_by)
        logger.info("rooms.created room_id=%s name=%s created_by=%s", created.id, created.name, created_by)
        return joined

    async def get_room_or_raise(self, room_id: str) -> Room:
        room = await self._repository.get_room(room_id)
        if room is None:
            raise NotFoundError("Room not found.")
        return room

    async def join(self, room_id: str, user_id: str) -> Room:
        await self.get_room_or_raise(room_id)
        room = await self._repository.join_room(room_id, user_id)
        logger.info("rooms.joined room_id=%s user_id=%s member_count=%d", room_id, user_id, room.member_count)
        return room

    async def my_rooms(self, user_id: str) -> list[Room]:
        return await self._repository.list_member_rooms(user_id)

    async def send_message(self, *, room_id: str, author_id: str, text: str) -> RoomMessage:
        room = await self.get_room_or_raise(room_id)
        text = text.strip()
        if not text:
            raise ValidationAppError("Message cannot be empty.")
        if len(text) > MAX_MESSAGE_LENGTH:
            raise ValidationAppError(f"Messages are limited to {MAX_MESSAGE_LENGTH} characters.")
        if room.is_private and not await self._repository.is_member(room_id, author_id):
            raise ForbiddenError("Join this room before posting in it.")

        message = RoomMessage(
            id=await self._core_engine.generate_id("msg"),
            room_id=room_id,
            author_id=author_id,
            text=text,
        )
        return await self._repository.add_message(message)

    async def get_messages(
        self, room_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[RoomMessage], str | None]:
        await self.get_room_or_raise(room_id)
        return await self._repository.list_messages(room_id, cursor=cursor, limit=limit)
