"""Home screen aggregation endpoint. See `app/domains/home/service.py`."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.api.deps import get_current_user, get_home_service
from app.api.v1.rooms import RoomResponse
from app.api.v1.shop import ProductResponse
from app.api.v1.social import PostResponse
from app.domains.home.entities import HomeOverview, QuickAction, QuickActionKind
from app.domains.home.service import HomeService
from app.domains.identity.entities import User

router = APIRouter(prefix="/home", tags=["home"])


class QuickActionResponse(BaseModel):
    kind: QuickActionKind
    label: str
    is_available: bool

    @classmethod
    def from_entity(cls, action: QuickAction) -> QuickActionResponse:
        return cls(kind=action.kind, label=action.label, is_available=action.is_available)


class HomeOverviewResponse(BaseModel):
    greeting_name: str
    quick_actions: list[QuickActionResponse]
    featured_rooms: list[RoomResponse]
    featured_products: list[ProductResponse]
    recent_posts: list[PostResponse]

    @classmethod
    def from_entity(cls, overview: HomeOverview) -> HomeOverviewResponse:
        return cls(
            greeting_name=overview.greeting_name,
            quick_actions=[QuickActionResponse.from_entity(a) for a in overview.quick_actions],
            featured_rooms=[RoomResponse.from_entity(r) for r in overview.featured_rooms],
            # Home overview products/posts are shown without a per-viewer
            # favorited/liked flag to keep the aggregation query cheap and
            # cache-friendly; the dedicated /shop and /social endpoints
            # return that flag once the user drills into a specific list.
            featured_products=[
                ProductResponse.from_entity(p, favorited_by_me=False) for p in overview.featured_products
            ],
            recent_posts=[PostResponse.from_entity(p, liked_by_me=False) for p in overview.recent_posts],
        )


@router.get("/overview", response_model=HomeOverviewResponse)
async def get_home_overview(
    home_service: HomeService = Depends(get_home_service),
    current_user: User = Depends(get_current_user),
) -> HomeOverviewResponse:
    overview = await home_service.get_overview(current_user)
    return HomeOverviewResponse.from_entity(overview)
