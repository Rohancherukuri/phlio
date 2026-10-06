"""Rooms domain service: discovery, membership, messaging, files, reactions."""

from __future__ import annotations

import logging
import mimetypes
import os

from app.common.exceptions import ForbiddenError, NotFoundError, ValidationAppError
from app.domains.rooms.entities import MessageAttachment, MessageReaction, Room, RoomCategory, RoomMessage
from app.domains.rooms.repository import RoomsRepository
from app.infrastructure.core_engine.client import CoreEngineClient
from app.infrastructure.media_storage import MediaStorage

logger = logging.getLogger("phlio.rooms")

MAX_MESSAGE_LENGTH = 4_000
MAX_FILE_BYTES = 2 * 1024 * 1024 * 1024  # 2 GB — documents of large size ride here
MAX_FILES_PER_MESSAGE = 10

ATTACHMENT_KINDS = frozenset({"image", "video", "audio", "document", "sticker", "gif"})
REACTION_KINDS = frozenset({"emoji", "sticker", "gif"})

# Extensions that map to a visual preview kind; everything else is a document.
_IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic", ".bmp"}
_VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".webm", ".avi"}
_AUDIO_EXTS = {".mp3", ".wav", ".ogg", ".m4a", ".flac", ".aac", ".opus"}


def classify_file(filename: str) -> str:
    ext = os.path.splitext(filename)[1].lower()
    if ext in _IMAGE_EXTS:
        return "image"
    if ext in _VIDEO_EXTS:
        return "video"
    if ext in _AUDIO_EXTS:
        return "audio"
    return "document"


class RoomsService:
    def __init__(
        self,
        repository: RoomsRepository,
        core_engine: CoreEngineClient,
        media_storage: MediaStorage | None = None,
    ) -> None:
        self._repository = repository
        self._core_engine = core_engine
        self._media = media_storage

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

    async def send_message(
        self,
        *,
        room_id: str,
        author_id: str,
        text: str,
        attachments: list[MessageAttachment] | None = None,
    ) -> RoomMessage:
        room = await self.get_room_or_raise(room_id)
        text = text.strip()
        attachments = attachments or []
        if not text and not attachments:
            raise ValidationAppError("Message cannot be empty.")
        if len(text) > MAX_MESSAGE_LENGTH:
            raise ValidationAppError(f"Messages are limited to {MAX_MESSAGE_LENGTH} characters.")
        if len(attachments) > MAX_FILES_PER_MESSAGE:
            raise ValidationAppError(
                f"Messages carry at most {MAX_FILES_PER_MESSAGE} files."
            )
        for attachment in attachments:
            if attachment.kind not in ATTACHMENT_KINDS:
                raise ValidationAppError(f"Unknown attachment kind '{attachment.kind}'.")
        if room.is_private and not await self._repository.is_member(room_id, author_id):
            raise ForbiddenError("Join this room before posting in it.")

        message = RoomMessage(
            id=await self._core_engine.generate_id("msg"),
            room_id=room_id,
            author_id=author_id,
            text=text,
            attachments=attachments,
        )
        return await self._repository.add_message(message)

    async def attach_files(
        self, *, room_id: str, author_id: str, files: list[tuple[str, object]]
    ) -> list[MessageAttachment]:
        """Stream uploaded files into media storage and return their metadata.

        `files` pairs (filename, async-readable content). Bytes never buffer
        in memory, so multi-GB documents upload fine.
        """
        if self._media is None:
            raise ValidationAppError("File uploads are not enabled on this backend.")
        room = await self.get_room_or_raise(room_id)
        if room.is_private and not await self._repository.is_member(room_id, author_id):
            raise ForbiddenError("Join this room before posting files in it.")
        if not files:
            raise ValidationAppError("Pick at least one file to upload.")
        if len(files) > MAX_FILES_PER_MESSAGE:
            raise ValidationAppError(f"At most {MAX_FILES_PER_MESSAGE} files per message.")

        attachments: list[MessageAttachment] = []
        for filename, content in files:
            url, size = await self._media.save(room_id=room_id, filename=filename, content=content)
            attachments.append(
                MessageAttachment(
                    id=await self._core_engine.generate_id("att"),
                    kind=classify_file(filename),
                    name=filename,
                    size=size,
                    mime=mimetypes.guess_type(filename)[0] or "application/octet-stream",
                    url=url,
                )
            )
        logger.info(
            "rooms.files_attached room_id=%s user=%s count=%d",
            room_id, author_id, len(attachments),
        )
        return attachments

    async def toggle_reaction(
        self, *, room_id: str, message_id: str, user_id: str, kind: str, value: str
    ) -> RoomMessage:
        """Add a reaction, or remove the caller's identical one (toggle)."""
        if kind not in REACTION_KINDS:
            raise ValidationAppError(f"Unknown reaction kind '{kind}'.")
        value = value.strip()
        if not value or len(value) > 64:
            raise ValidationAppError("Reaction value is missing or too long.")
        message = await self._repository.get_message(room_id, message_id)
        if message is None:
            raise NotFoundError("Message not found.")

        remaining = [
            r for r in message.reactions
            if not (r.user_id == user_id and r.kind == kind and r.value == value)
        ]
        if len(remaining) == len(message.reactions):
            remaining.append(MessageReaction(kind=kind, value=value, user_id=user_id))
        message.reactions = remaining
        return await self._repository.update_message(message)

    async def get_messages(
        self, room_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[RoomMessage], str | None]:
        await self.get_room_or_raise(room_id)
        return await self._repository.list_messages(room_id, cursor=cursor, limit=limit)
