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
from app.domains.agent.planner import AgentPlanner, AnthropicPlanner, RuleBasedPlanner
from app.domains.agent.repository import AgentRepository
from app.domains.agent.service import AgentService
from app.domains.home.service import HomeService
from app.domains.identity.repository import IdentityRepository
from app.domains.identity.service import IdentityService
from app.domains.rooms.repository import RoomsRepository
from app.domains.rooms.service import RoomsService
from app.domains.shop.repository import ShopRepository
from app.domains.shop.service import ShopService
from app.domains.social.repository import SocialRepository
from app.domains.social.service import SocialService
from app.infrastructure.ai.anthropic_client import AgentLLMClient
from app.infrastructure.core_engine.client import CoreEngineClient


@dataclass(slots=True)
class Container:
    settings: Settings
    core_engine: CoreEngineClient

    identity_repository: IdentityRepository
    social_repository: SocialRepository
    rooms_repository: RoomsRepository
    shop_repository: ShopRepository
    agent_repository: AgentRepository

    identity_service: IdentityService
    social_service: SocialService
    rooms_service: RoomsService
    shop_service: ShopService
    home_service: HomeService
    agent_service: AgentService

    agent_planner: AgentPlanner


async def build_container(settings: Settings) -> Container:
    core_engine = CoreEngineClient(settings)

    identity_repo, social_repo, rooms_repo, shop_repo, agent_repo = await _build_repositories(settings)

    identity_service = IdentityService(identity_repo, core_engine, settings)
    social_service = SocialService(social_repo, core_engine)
    rooms_service = RoomsService(rooms_repo, core_engine)
    shop_service = ShopService(shop_repo)
    home_service = HomeService(rooms_service, shop_service, social_service)

    llm_client = AgentLLMClient(settings)
    planner: AgentPlanner
    if llm_client.is_available:
        planner = AnthropicPlanner(llm_client, core_engine.generate_id)
    else:
        planner = RuleBasedPlanner(core_engine.generate_id)

    agent_service = AgentService(agent_repo, planner, core_engine)

    return Container(
        settings=settings,
        core_engine=core_engine,
        identity_repository=identity_repo,
        social_repository=social_repo,
        rooms_repository=rooms_repo,
        shop_repository=shop_repo,
        agent_repository=agent_repo,
        identity_service=identity_service,
        social_service=social_service,
        rooms_service=rooms_service,
        shop_service=shop_service,
        home_service=home_service,
        agent_service=agent_service,
        agent_planner=planner,
    )


async def _build_repositories(settings: Settings):
    if settings.database_backend == "memory":
        from app.infrastructure.database.memory.agent_repo import InMemoryAgentRepository
        from app.infrastructure.database.memory.identity_repo import InMemoryIdentityRepository
        from app.infrastructure.database.memory.rooms_repo import InMemoryRoomsRepository
        from app.infrastructure.database.memory.shop_repo import InMemoryShopRepository
        from app.infrastructure.database.memory.social_repo import InMemorySocialRepository

        return (
            InMemoryIdentityRepository(),
            InMemorySocialRepository(),
            InMemoryRoomsRepository(),
            InMemoryShopRepository(),
            InMemoryAgentRepository(),
        )

    # database_backend == "surreal"
    from app.infrastructure.database.surreal.client import create_surreal_connection
    from app.infrastructure.database.surreal.identity_repo import SurrealIdentityRepository
    from app.infrastructure.database.surreal.rooms_repo import SurrealRoomsRepository
    from app.infrastructure.database.surreal.shop_repo import SurrealShopRepository
    from app.infrastructure.database.surreal.social_repo import SurrealSocialRepository

    db = await create_surreal_connection(settings)
    # Agent conversation history stays in-memory even in "surreal" mode for
    # this build stage — it is short-term/ephemeral by design (see
    # architecture doc section 17); promote it to a persisted repository
    # once episodic/semantic agent memory is implemented.
    from app.infrastructure.database.memory.agent_repo import InMemoryAgentRepository

    return (
        SurrealIdentityRepository(db),
        SurrealSocialRepository(db),
        SurrealRoomsRepository(db),
        SurrealShopRepository(db),
        InMemoryAgentRepository(),
    )
