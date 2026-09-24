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
class RoomMessage:
    id: str
    room_id: str
    author_id: str
    text: str
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))
