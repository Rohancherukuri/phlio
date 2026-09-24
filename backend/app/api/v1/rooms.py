"""Phlio Rooms endpoints: discovery, joining, and channel-style messaging."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, Field

from app.api.deps import get_current_user, get_rooms_service
from app.common.pagination import clamp_limit
from app.common.schemas import Page, PageMeta
from app.domains.identity.entities import User
from app.domains.rooms.entities import Room, RoomCategory, RoomMessage
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


class SendMessageRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


class RoomMessageResponse(BaseModel):
    id: str
    room_id: str
    author_id: str
    text: str
    created_at: dt.datetime

    @classmethod
    def from_entity(cls, message: RoomMessage) -> RoomMessageResponse:
        return cls(
            id=message.id,
            room_id=message.room_id,
            author_id=message.author_id,
            text=message.text,
            created_at=message.created_at,
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
async def get_room(
    room_id: str, rooms_service: RoomsService = Depends(get_rooms_service)
) -> RoomResponse:
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
) -> Page[RoomMessageResponse]:
    messages, next_cursor = await rooms_service.get_messages(
        room_id, cursor=cursor, limit=clamp_limit(limit)
    )
    items = [RoomMessageResponse.from_entity(m) for m in messages]
    return Page(items=items, meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None))


@router.post(
    "/{room_id}/messages", response_model=RoomMessageResponse, status_code=status.HTTP_201_CREATED
)
async def send_message(
    room_id: str,
    body: SendMessageRequest,
    rooms_service: RoomsService = Depends(get_rooms_service),
    current_user: User = Depends(get_current_user),
) -> RoomMessageResponse:
    message = await rooms_service.send_message(room_id=room_id, author_id=current_user.id, text=body.text)
    return RoomMessageResponse.from_entity(message)
