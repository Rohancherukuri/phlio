"""Framework-agnostic entities for the Phlio Activity feed.

Activity is the cross-domain notification surface (the bottom-nav's
"Activity" tab): bookings confirmed, payments sent, new followers, room
mentions. Items are produced by other domains' user actions — in this build
stage the Book/Pay services append items through the shared
`ActivityService`, plus a handful of seed items.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from enum import StrEnum


class ActivityKind(StrEnum):
    BOOK = "book"
    PAY = "pay"
    SOCIAL = "social"
    ROOMS = "rooms"
    SHOP = "shop"
    AGENT = "agent"


@dataclass(slots=True)
class ActivityItem:
    id: str
    user_id: str
    kind: ActivityKind
    title: str
    body: str
    icon: str = "🔔"  # emoji glyph keeps the feed light without asset work
    ref_id: str | None = None  # deep-link target (booking id, txn id, ...)
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))
    is_read: bool = False
