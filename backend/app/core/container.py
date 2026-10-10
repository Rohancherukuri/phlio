"""
Application container.

A deliberately simple, explicit dependency-injection container — no magic
framework, just one object built once at startup that wires:

    Settings -> Infrastructure clients -> Repositories -> Domain services

`DATABASE_BACKEND` (see `app/config.py`) picks between the in-memory and
SurrealDB repository implementations at this single point; nothing else in
the codebase needs to know which one is active. This is the concrete
realization of architecture doc section 39's "database should store state,
not decide behaviour."

FastAPI resolves this container once via `app/api/deps.py` and pulls
individual services off of it per-request through `Depends(...)`.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.config import Settings
from app.domains.activity.repository import ActivityRepository
from app.domains.activity.service import ActivityService
from app.domains.agent.planner import AgentPlanner, AnthropicPlanner, RuleBasedPlanner
from app.domains.agent.repository import AgentRepository
from app.domains.agent.service import AgentService
from app.domains.book.repository import BookRepository
from app.domains.book.service import BookService
from app.domains.graph.service import GraphService
from app.domains.graph.store import MemoryGraphStore, SurrealGraphStore
from app.domains.home.service import HomeService
from app.domains.identity.repository import IdentityRepository
from app.domains.identity.service import IdentityService
from app.domains.messaging.service import MessagingService
from app.domains.pay.repository import PayRepository
from app.domains.pay.service import PayService
from app.domains.rooms.repository import RoomsRepository
from app.domains.rooms.service import RoomsService
from app.domains.shop.repository import ShopRepository
from app.domains.shop.service import ShopService
from app.domains.social.repository import SocialRepository
from app.domains.social.service import SocialService
from app.domains.social.video_service import SocialVideoService
from app.infrastructure.ai.anthropic_client import AgentLLMClient
from app.infrastructure.cache import Cache
from app.infrastructure.core_engine.client import CoreEngineClient
from app.infrastructure.media_storage import MediaStorage


@dataclass(slots=True)
class Container:
    settings: Settings
    graph: GraphService
    cache: Cache
    core_engine: CoreEngineClient

    identity_repository: IdentityRepository
    social_repository: SocialRepository
    rooms_repository: RoomsRepository
    shop_repository: ShopRepository
    agent_repository: AgentRepository
    book_repository: BookRepository
    pay_repository: PayRepository
    activity_repository: ActivityRepository

    identity_service: IdentityService
    social_service: SocialService
    rooms_service: RoomsService
    shop_service: ShopService
    home_service: HomeService
    agent_service: AgentService
    book_service: BookService
    pay_service: PayService
    activity_service: ActivityService

    social_video_service: SocialVideoService
    messaging_service: MessagingService
    agent_planner: AgentPlanner


async def build_container(settings: Settings) -> Container:
    core_engine = CoreEngineClient(settings)

    (
        identity_repo,
        social_repo,
        rooms_repo,
        shop_repo,
        agent_repo,
        book_repo,
        pay_repo,
        activity_repo,
    ) = await _build_repositories(settings)

    cache = Cache(settings.redis_url, settings.redis_enabled, settings.redis_namespace)
    graph_store = (
        SurrealGraphStore(identity_repo._db) if settings.database_backend == "surreal" else MemoryGraphStore()
    )
    graph = GraphService(graph_store, identity_repo, rooms_repo, cache)

    identity_service = IdentityService(identity_repo, core_engine, settings)
    social_service = SocialService(social_repo, core_engine, graph)
    media_storage = MediaStorage(media_root_path(settings))
    rooms_service = RoomsService(rooms_repo, core_engine, media_storage, graph)
    shop_service = ShopService(shop_repo)
    home_service = HomeService(rooms_service, shop_service, social_service)
    book_service = BookService(book_repo)
    pay_service = PayService(pay_repo, core_engine.generate_id)
    activity_service = ActivityService(activity_repo, core_engine.generate_id)

    llm_client = AgentLLMClient(settings)
    planner: AgentPlanner
    if llm_client.is_available:
        planner = AnthropicPlanner(llm_client, core_engine.generate_id)
    else:
        planner = RuleBasedPlanner(core_engine.generate_id)

    agent_service = AgentService(agent_repo, planner, core_engine)

    return Container(
        settings=settings,
        graph=graph,
        cache=cache,
        core_engine=core_engine,
        identity_repository=identity_repo,
        social_repository=social_repo,
        rooms_repository=rooms_repo,
        shop_repository=shop_repo,
        agent_repository=agent_repo,
        book_repository=book_repo,
        pay_repository=pay_repo,
        activity_repository=activity_repo,
        identity_service=identity_service,
        social_service=social_service,
        rooms_service=rooms_service,
        shop_service=shop_service,
        home_service=home_service,
        agent_service=agent_service,
        book_service=book_service,
        pay_service=pay_service,
        activity_service=activity_service,
        social_video_service=SocialVideoService(settings.social_video_database),
        messaging_service=MessagingService(settings.messaging_database),
        agent_planner=planner,
    )


def media_root_path(settings: Settings):
    from pathlib import Path

    root = Path(settings.media_root)
    if not root.is_absolute():
        # Anchored at the backend/ package root so `uv run uvicorn` works
        # from any working directory.
        root = Path(__file__).resolve().parent.parent.parent / root
    root.mkdir(parents=True, exist_ok=True)
    return root


async def _build_repositories(settings: Settings):
    if settings.database_backend == "memory":
        from app.infrastructure.database.memory.activity_repo import InMemoryActivityRepository
        from app.infrastructure.database.memory.agent_repo import InMemoryAgentRepository
        from app.infrastructure.database.memory.book_repo import InMemoryBookRepository
        from app.infrastructure.database.memory.identity_repo import InMemoryIdentityRepository
        from app.infrastructure.database.memory.pay_repo import InMemoryPayRepository
        from app.infrastructure.database.memory.rooms_repo import InMemoryRoomsRepository
        from app.infrastructure.database.memory.shop_repo import InMemoryShopRepository
        from app.infrastructure.database.memory.social_repo import InMemorySocialRepository

        return (
            InMemoryIdentityRepository(),
            InMemorySocialRepository(),
            InMemoryRoomsRepository(),
            InMemoryShopRepository(),
            InMemoryAgentRepository(),
            InMemoryBookRepository(),
            InMemoryPayRepository(),
            InMemoryActivityRepository(),
        )

    # database_backend == "surreal"
    from app.infrastructure.database.surreal.client import create_surreal_connection
    from app.infrastructure.database.surreal.identity_repo import SurrealIdentityRepository
    from app.infrastructure.database.surreal.rooms_repo import SurrealRoomsRepository
    from app.infrastructure.database.surreal.shop_repo import SurrealShopRepository
    from app.infrastructure.database.surreal.social_repo import SurrealSocialRepository

    db = await create_surreal_connection(settings)
    # Agent conversation history, Book, Pay and Activity stay in-memory even
    # in "surreal" mode for this build stage — Agent history is ephemeral by
    # design, while Book/Pay/Activity get Surreal repositories alongside the
    # existing four once their schemas land in data/surrealdb/schema/.
    from app.infrastructure.database.memory.activity_repo import InMemoryActivityRepository
    from app.infrastructure.database.memory.agent_repo import InMemoryAgentRepository
    from app.infrastructure.database.surreal.book_repo import SurrealBookRepository
    from app.infrastructure.database.memory.pay_repo import InMemoryPayRepository

    return (
        SurrealIdentityRepository(db),
        SurrealSocialRepository(db),
        SurrealRoomsRepository(db),
        SurrealShopRepository(db),
        InMemoryAgentRepository(),
        SurrealBookRepository(db),
        InMemoryPayRepository(),
        InMemoryActivityRepository(),
    )
