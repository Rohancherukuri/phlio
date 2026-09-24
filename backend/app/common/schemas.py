"""
Generic response envelopes shared by every API route.

Keeping a single, predictable response shape across all domains is a small
thing that pays off enormously for client developers — see architecture doc
section 39: "The UI should be modular" starts with a backend that is
consistent enough for the UI to rely on.
"""

from __future__ import annotations

from typing import Generic, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


class ErrorDetail(BaseModel):
    code: str
    message: str


class ErrorResponse(BaseModel):
    ok: bool = False
    error: ErrorDetail


class PageMeta(BaseModel):
    """Cursor-based pagination metadata.

    Cursor pagination (rather than page numbers) is used throughout Phlio
    because feeds, room messages, and marketplace listings are all
    insertion-ordered, frequently-changing collections where offset
    pagination silently skips or repeats items.
    """

    next_cursor: str | None = Field(
        default=None, description="Pass as `cursor` on the next request. Null when no more items."
    )
    has_more: bool = False


class Page(BaseModel, Generic[T]):
    items: list[T]
    meta: PageMeta
