"""Home overview aggregation service."""

from __future__ import annotations

import logging

from app.domains.home.entities import HomeOverview, QuickAction, QuickActionKind
from app.domains.identity.entities import User
from app.domains.rooms.service import RoomsService
from app.domains.shop.service import ShopService
from app.domains.social.service import SocialService

logger = logging.getLogger("phlio.home")

# The eight Phlio domains, in the order Phlio_Final_Product_Blueprint.md
# section 3 lists them. Social, Rooms, Shop, Agent, Book and Pay are backed
# by real domains in this build stage (Stage 1-4 of section 44); Stream and
# News are represented honestly as roadmap, not omitted.
_QUICK_ACTIONS = [
    QuickAction(QuickActionKind.PAY, "Pay", is_available=True),
    QuickAction(QuickActionKind.SOCIAL, "Social", is_available=True),
    QuickAction(QuickActionKind.ROOMS, "Rooms", is_available=True),
    QuickAction(QuickActionKind.BOOK, "Book", is_available=True),
    QuickAction(QuickActionKind.SHOP, "Shop", is_available=True),
    QuickAction(QuickActionKind.STREAM, "Stream", is_available=False),
    QuickAction(QuickActionKind.NEWS, "News", is_available=False),
    QuickAction(QuickActionKind.AGENT, "Agent", is_available=True),
]


class HomeService:
    def __init__(
        self,
        rooms_service: RoomsService,
        shop_service: ShopService,
        social_service: SocialService,
    ) -> None:
        self._rooms_service = rooms_service
        self._shop_service = shop_service
        self._social_service = social_service

    async def get_overview(self, user: User) -> HomeOverview:
        rooms, _ = await self._rooms_service.discover(category=None, cursor=None, limit=3)
        products, _ = await self._shop_service.browse(
            category=None, max_price_minor_units=None, cursor=None, limit=4
        )
        posts, _ = await self._social_service.get_feed(cursor=None, limit=3)

        logger.debug(
            "home.overview_built user_id=%s rooms=%d products=%d posts=%d",
            user.id, len(rooms), len(products), len(posts),
        )

        return HomeOverview(
            greeting_name=user.full_name.split(" ")[0] if user.full_name else user.username,
            quick_actions=list(_QUICK_ACTIONS),
            featured_rooms=rooms,
            featured_products=products,
            recent_posts=posts,
        )
