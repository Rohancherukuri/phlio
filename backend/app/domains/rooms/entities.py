"""Framework-agnostic domain entities for Phlio Rooms."""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from enum import StrEnum


class RoomCategory(StrEnum):
    TECH = "tech_and_ai"
    GAMING = "gaming"
    ART = "art_and_creators"
    TRAVEL = "travel_and_explore"
    FOOD = "food_and_lifestyle"
    SPORTS = "sports_and_fitness"
    MOVIES = "movies_and_music"
    STUDY = "study_and_learn"
    LOCAL = "local_nearby"


@dataclass(slots=True)
class Room:
    id: str
    name: str
    slug: str
    description: str
    category: RoomCategory
    icon: str  # an emoji or short glyph, matches the reference UI's channel icons
    is_private: bool = False
    member_count: int = 0
    created_by: str | None = None
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))


@dataclass(slots=True)
class MessageAttachment:
    """A file attached to a room message.

    `kind` drives the chat renderer: images get a visual preview, documents
    a branded file card, stickers/GIFs render from the app-bundled Foxy
    pack (`value` = asset id, no stored bytes). Uploaded files live under
    the media root and are addressed by `url` (origin-relative).
    """

    id: str
    kind: str  # image | video | audio | document | sticker | gif
    name: str
    size: int = 0  # bytes, 0 for pack items
    mime: str = ""
    url: str = ""  # origin-relative, e.g. /media/rooms/rm_x/abc.pdf
    value: str = ""  # pack asset id for sticker/gif kinds


@dataclass(slots=True)
class MessageReaction:
    """One reaction on a message: an emoji glyph or a Foxy pack asset."""

    kind: str  # emoji | sticker | gif
    value: str  # emoji glyph, or the pack asset id
    user_id: str


@dataclass(slots=True)
class RoomMessage:
    id: str
    room_id: str
    author_id: str
    text: str
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))
    attachments: list[MessageAttachment] = field(default_factory=list)
    reactions: list[MessageReaction] = field(default_factory=list)
