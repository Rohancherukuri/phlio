"""Framework-agnostic domain entities for the social feed."""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from enum import StrEnum


class MediaKind(StrEnum):
    IMAGE = "image"
    VIDEO = "video"


@dataclass(slots=True, frozen=True)
class MediaAttachment:
    url: str
    kind: MediaKind


@dataclass(slots=True)
class Post:
    id: str
    author_id: str
    text: str
    media: list[MediaAttachment] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)
    like_count: int = 0
    comment_count: int = 0
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))


@dataclass(slots=True)
class Comment:
    id: str
    post_id: str
    author_id: str
    text: str
    # Optional Foxy sticker (`/stickers` catalog id). Per blueprint section
    # 16, comments support lightweight visual reactions — text stays the
    # primary content, the sticker rides along.
    sticker_id: str | None = None
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))
