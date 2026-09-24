"""
Agent tool layer.

Per architecture doc section 18 ("AI Tool System"), the Agent interacts
with the rest of Phlio through a small set of controlled tools rather than
reaching into repositories or domain services directly. This module is
that boundary: every tool here is a plain, deterministic, read-only async
function backed by an already-implemented domain service, so nothing the
planner does can bypass the normal authorization or validation rules those
services enforce.

None of these tools mutate state or move money — read-only discovery tools
are deliberately the only category implemented in this build stage. A
future `create_booking`/`create_payment_request` tool would additionally
need the "Proposed Action -> Backend Policy -> User Confirmation" flow
described in section 16, which is out of scope until the Book/Core payment
domains exist.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.domains.rooms.entities import Room
from app.domains.rooms.service import RoomsService
from app.domains.shop.entities import Product
from app.domains.shop.service import ShopService
from app.domains.social.entities import Post
from app.domains.social.service import SocialService

# Tool schemas in the shape Anthropic's tool-use API expects. Kept alongside
# the implementations so the description and the code can never drift apart.
# Only used when `planner.AnthropicPlanner` is active; the rule-based
# planner below calls the Python functions directly.
TOOL_SPECS: list[dict] = [
    {
        "name": "search_rooms",
        "description": "Find Phlio Rooms (communities/events) matching a category.",
        "input_schema": {
            "type": "object",
            "properties": {
                "category": {"type": "string", "description": "e.g. 'art_and_creators', 'local_nearby'"},
                "limit": {"type": "integer", "default": 3},
            },
        },
    },
    {
        "name": "search_products",
        "description": "Find products on Phlio Shop under a maximum price.",
        "input_schema": {
            "type": "object",
            "properties": {
                "max_price_minor_units": {"type": "integer"},
                "limit": {"type": "integer", "default": 3},
            },
        },
    },
    {
        "name": "search_posts",
        "description": "Find recent Phlio Social posts, optionally by tag.",
        "input_schema": {
            "type": "object",
            "properties": {
                "tag": {"type": "string"},
                "limit": {"type": "integer", "default": 3},
            },
        },
    },
]


@dataclass(slots=True)
class AgentTools:
    """Bundles the domain services the tool layer needs.

    Constructed once per request in `app/api/deps.py` and handed to
    whichever planner is active — the planner never sees the services
    directly, only these narrow tool methods.
    """

    rooms_service: RoomsService
    shop_service: ShopService
    social_service: SocialService

    async def search_rooms(self, *, category: str | None = None, limit: int = 3) -> list[Room]:
        from app.domains.rooms.entities import RoomCategory

        parsed_category = None
        if category:
            try:
                parsed_category = RoomCategory(category)
            except ValueError:
                parsed_category = None
        rooms, _ = await self.rooms_service.discover(category=parsed_category, cursor=None, limit=limit)
        return rooms

    async def search_products(
        self, *, max_price_minor_units: int | None = None, limit: int = 3
    ) -> list[Product]:
        products, _ = await self.shop_service.browse(
            category=None,
            max_price_minor_units=max_price_minor_units,
            cursor=None,
            limit=limit,
        )
        return products

    async def search_posts(self, *, tag: str | None = None, limit: int = 3) -> list[Post]:
        posts, _ = await self.social_service.get_feed(cursor=None, limit=limit)
        if tag:
            posts = [p for p in posts if tag.lower() in p.tags] or posts[:limit]
        return posts[:limit]
