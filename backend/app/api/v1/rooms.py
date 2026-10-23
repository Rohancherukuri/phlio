"""Phlio Rooms endpoints: discovery, joining, channel messaging, file
uploads, and message reactions."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user, get_rooms_service
from app.common.pagination import clamp_limit
from app.common.schemas import Page, PageMeta
from app.core.container import Container
from app.domains.identity.entities import User
from app.domains.rooms.entities import (
    MessageAttachment,
    MessageReaction,
    Room,
    RoomCategory,
    RoomMessage,
)
from app.domains.rooms.service import RoomsService

router = APIRouter(prefix="/rooms", tags=["rooms"])


class RoomResponse(BaseModel):
    id: str
    name: str
    slug: str
    description: str
    category: RoomCategory
    icon: str
    is_private: bool
    member_count: int
    created_at: dt.datetime

    @classmethod
    def from_entity(cls, room: Room) -> RoomResponse:
        return cls(
            id=room.id,
            name=room.name,
            slug=room.slug,
            description=room.description,
            category=room.category,
            icon=room.icon,
            is_private=room.is_private,
            member_count=room.member_count,
            created_at=room.created_at,
        )


class CreateRoomRequest(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    description: str = Field(default="", max_length=500)
    category: RoomCategory
    icon: str = Field(default="💬", max_length=8)
    is_private: bool = False


class AttachmentIn(BaseModel):
    """Client-side attachment metadata (pack stickers/GIFs carry no bytes;
    uploaded files reference the url returned by the upload endpoint)."""

    kind: str = Field(pattern="^(image|video|audio|document|sticker|gif)$")
    name: str = Field(min_length=1, max_length=200)
    size: int = Field(default=0, ge=0)
    mime: str = Field(default="", max_length=120)
    url: str = Field(default="", max_length=500)
    value: str = Field(default="", max_length=120)


class AttachmentResponse(BaseModel):
    id: str
    kind: str
    name: str
    size: int
    mime: str
    url: str
    value: str

    @classmethod
    def from_entity(cls, attachment: MessageAttachment) -> AttachmentResponse:
        return cls(
            id=attachment.id,
            kind=attachment.kind,
            name=attachment.name,
            size=attachment.size,
            mime=attachment.mime,
            url=attachment.url,
            value=attachment.value,
        )


class ReactionResponse(BaseModel):
    kind: str
    value: str
    user_id: str

    @classmethod
    def from_entity(cls, reaction: MessageReaction) -> ReactionResponse:
        return cls(kind=reaction.kind, value=reaction.value, user_id=reaction.user_id)


class SendMessageRequest(BaseModel):
    text: str = Field(default="", max_length=4000)
    attachments: list[AttachmentIn] = Field(default_factory=list, max_length=10)


class ReactionRequest(BaseModel):
    kind: str = Field(pattern="^(emoji|sticker|gif)$")
    value: str = Field(min_length=1, max_length=64)


class RoomMessageResponse(BaseModel):
    id: str
    room_id: str
    author_id: str
    author_name: str = ""
    text: str
    created_at: dt.datetime
    attachments: list[AttachmentResponse] = []
    reactions: list[ReactionResponse] = []

    @classmethod
    def from_entity(cls, message: RoomMessage, author_name: str = "") -> RoomMessageResponse:
        return cls(
            id=message.id,
            room_id=message.room_id,
            author_id=message.author_id,
            author_name=author_name,
            text=message.text,
            created_at=message.created_at,
            attachments=[AttachmentResponse.from_entity(a) for a in message.attachments],
            reactions=[ReactionResponse.from_entity(r) for r in message.reactions],
        )


@router.get("/discover", response_model=Page[RoomResponse])
async def discover_rooms(
    category: RoomCategory | None = Query(default=None),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    rooms_service: RoomsService = Depends(get_rooms_service),
) -> Page[RoomResponse]:
    rooms, next_cursor = await rooms_service.discover(
        category=category, cursor=cursor, limit=clamp_limit(limit)
    )
    items = [RoomResponse.from_entity(r) for r in rooms]
    return Page(items=items, meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None))


@router.get("/mine", response_model=list[RoomResponse])
async def my_rooms(
    rooms_service: RoomsService = Depends(get_rooms_service),
    current_user: User = Depends(get_current_user),
) -> list[RoomResponse]:
    rooms = await rooms_service.my_rooms(current_user.id)
    return [RoomResponse.from_entity(r) for r in rooms]


@router.post("", response_model=RoomResponse, status_code=status.HTTP_201_CREATED)
async def create_room(
    body: CreateRoomRequest,
    rooms_service: RoomsService = Depends(get_rooms_service),
    current_user: User = Depends(get_current_user),
) -> RoomResponse:
    room = await rooms_service.create_room(
        created_by=current_user.id,
        name=body.name,
        description=body.description,
        category=body.category,
        icon=body.icon,
        is_private=body.is_private,
    )
    return RoomResponse.from_entity(room)


@router.get("/{room_id}", response_model=RoomResponse)
async def get_room(room_id: str, rooms_service: RoomsService = Depends(get_rooms_service)) -> RoomResponse:
    room = await rooms_service.get_room_or_raise(room_id)
    return RoomResponse.from_entity(room)


@router.post("/{room_id}/join", response_model=RoomResponse)
async def join_room(
    room_id: str,
    rooms_service: RoomsService = Depends(get_rooms_service),
    current_user: User = Depends(get_current_user),
) -> RoomResponse:
    room = await rooms_service.join(room_id, current_user.id)
    return RoomResponse.from_entity(room)


@router.get("/{room_id}/messages", response_model=Page[RoomMessageResponse])
async def list_messages(
    room_id: str,
    cursor: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=100),
    rooms_service: RoomsService = Depends(get_rooms_service),
    container: Container = Depends(get_container),
) -> Page[RoomMessageResponse]:
    messages, next_cursor = await rooms_service.get_messages(room_id, cursor=cursor, limit=clamp_limit(limit))
    authors = {}
    for message in messages:
        if message.author_id not in authors:
            author = await container.identity_repository.get_by_id(message.author_id)
            authors[message.author_id] = author.full_name if author else "Member"
    items = [RoomMessageResponse.from_entity(m, authors[m.author_id]) for m in messages]
    return Page(items=items, meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None))


@router.post("/{room_id}/messages", response_model=RoomMessageResponse, status_code=status.HTTP_201_CREATED)
async def send_message(
    room_id: str,
    body: SendMessageRequest,
    rooms_service: RoomsService = Depends(get_rooms_service),
    current_user: User = Depends(get_current_user),
) -> RoomMessageResponse:
    if not body.text.strip() and not body.attachments:
        # 422 from the model would also catch this; a friendly message reads
        # better in the client's error snackbars.
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Message cannot be empty.")
    message = await rooms_service.send_message(
        room_id=room_id,
        author_id=current_user.id,
        text=body.text,
        attachments=[
            MessageAttachment(
                id="",  # server assigns ids for uploaded files; pack items keyed by value
                kind=a.kind,
                name=a.name,
                size=a.size,
                mime=a.mime,
                url=a.url,
                value=a.value,
            )
            for a in body.attachments
        ],
    )
    return RoomMessageResponse.from_entity(message, current_user.full_name)


@router.post(
    "/{room_id}/files",
    response_model=list[AttachmentResponse],
    status_code=status.HTTP_201_CREATED,
)
async def upload_files(
    room_id: str,
    files: list[UploadFile] = File(..., description="One or many files; large sizes supported"),
    rooms_service: RoomsService = Depends(get_rooms_service),
    current_user: User = Depends(get_current_user),
) -> list[AttachmentResponse]:
    """Upload files for a room message.

    Streams each part to the media root in 1 MiB chunks, so multi-GB
    documents upload without buffering. Returns attachment metadata the
    client then sends alongside `POST /rooms/{id}/messages`.
    """
    attachments = await rooms_service.attach_files(
        room_id=room_id,
        author_id=current_user.id,
        files=[(f.filename or "file", f.file) for f in files],
    )
    return [AttachmentResponse.from_entity(a) for a in attachments]


@router.post(
    "/{room_id}/messages/{message_id}/reactions",
    response_model=RoomMessageResponse,
)
async def toggle_reaction(
    room_id: str,
    message_id: str,
    body: ReactionRequest,
    rooms_service: RoomsService = Depends(get_rooms_service),
    current_user: User = Depends(get_current_user),
    container: Container = Depends(get_container),
) -> RoomMessageResponse:
    """Toggle the caller's reaction (emoji, Foxy sticker or GIF) on a message."""
    message = await rooms_service.toggle_reaction(
        room_id=room_id,
        message_id=message_id,
        user_id=current_user.id,
        kind=body.kind,
        value=body.value,
    )
    author = await container.identity_repository.get_by_id(message.author_id)
    return RoomMessageResponse.from_entity(message, author.full_name if author else "Member")
