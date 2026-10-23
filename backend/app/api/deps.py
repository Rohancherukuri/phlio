"""
FastAPI dependency providers.

Route handlers depend on these instead of constructing services themselves,
which keeps `api/v1/*.py` files thin (HTTP concerns only) and makes the
domain services trivially mockable in tests (`backend/tests/conftest.py`
overrides `get_container` with a test-specific one).
"""

from __future__ import annotations

from fastapi import Depends, Header, Request

from app.common.exceptions import UnauthorizedError
from app.core.container import Container
from app.domains.activity.service import ActivityService
from app.domains.agent.service import AgentService
from app.domains.agent.tools import AgentTools
from app.domains.book.service import BookService
from app.domains.home.service import HomeService
from app.domains.identity.entities import User
from app.domains.identity.service import IdentityService
from app.domains.pay.service import PayService
from app.domains.rooms.service import RoomsService
from app.domains.shop.service import ShopService
from app.domains.social.service import SocialService
from app.infrastructure.security.jwt import decode_token


def get_container(request: Request) -> Container:
    """Retrieves the single `Container` built at startup (see
    `app/main.py`'s lifespan handler) off of `app.state`."""
    return request.app.state.container


def get_identity_service(container: Container = Depends(get_container)) -> IdentityService:
    return container.identity_service


def get_social_service(container: Container = Depends(get_container)) -> SocialService:
    return container.social_service


def get_rooms_service(container: Container = Depends(get_container)) -> RoomsService:
    return container.rooms_service


def get_shop_service(container: Container = Depends(get_container)) -> ShopService:
    return container.shop_service


def get_home_service(container: Container = Depends(get_container)) -> HomeService:
    return container.home_service


def get_agent_service(container: Container = Depends(get_container)) -> AgentService:
    return container.agent_service


def get_book_service(container: Container = Depends(get_container)) -> BookService:
    return container.book_service


def get_pay_service(container: Container = Depends(get_container)) -> PayService:
    return container.pay_service


def get_activity_service(container: Container = Depends(get_container)) -> ActivityService:
    return container.activity_service


async def get_current_user(
    container: Container = Depends(get_container),
    authorization: str | None = Header(default=None),
) -> User:
    """Resolves the authenticated `User` from the `Authorization: Bearer
    <token>` header. Every domain that needs to know "who is calling"
    depends on this rather than re-implementing token parsing.
    """
    if not authorization or not authorization.lower().startswith("bearer "):
        raise UnauthorizedError("Missing or malformed Authorization header.")

    token = authorization.split(" ", 1)[1].strip()
    user_id = decode_token(token, "access", container.settings)
    return await container.identity_service.get_user_or_raise(user_id)


def get_agent_tools(
    user: User = Depends(get_current_user),
    container: Container = Depends(get_container),
    rooms_service: RoomsService = Depends(get_rooms_service),
    shop_service: ShopService = Depends(get_shop_service),
    social_service: SocialService = Depends(get_social_service),
    book_service: BookService = Depends(get_book_service),
) -> AgentTools:
    return AgentTools(
        graph=container.graph,
        viewer_id=user.id,
        rooms_service=rooms_service,
        shop_service=shop_service,
        social_service=social_service,
        book_service=book_service,
    )
