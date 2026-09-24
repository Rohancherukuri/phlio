"""Framework-agnostic entities for the home overview."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from app.domains.rooms.entities import Room
from app.domains.shop.entities import Product
from app.domains.social.entities import Post


class QuickActionKind(StrEnum):
    """The home screen's quick-action grid is exactly the eight top-level
    Phlio domains from Phlio_Final_Product_Blueprint.md section 3 — one
    slot each, no more, no fewer. This is a deliberate design choice: the
    grid *is* the product's domain map, made tappable."""

    PAY = "pay"
    SOCIAL = "social"
    ROOMS = "rooms"
    BOOK = "book"
    SHOP = "shop"
    STREAM = "stream"
    NEWS = "news"
    AGENT = "agent"


@dataclass(slots=True, frozen=True)
class QuickAction:
    kind: QuickActionKind
    label: str
    # Whether this domain has real functionality behind it in this build
    # stage — the Flutter client uses this to grey out / show a "coming
    # soon" state for domains not yet implemented, instead of the backend
    # silently omitting them (better to be honest in the product about
    # what's live vs. roadmap — see Phlio_Final_Product_Blueprint.md
    # section 44, "Recommended Development Strategy").
    is_available: bool


@dataclass(slots=True, frozen=True)
class HomeOverview:
    greeting_name: str
    quick_actions: list[QuickAction]
    featured_rooms: list[Room]
    featured_products: list[Product]
    recent_posts: list[Post]
