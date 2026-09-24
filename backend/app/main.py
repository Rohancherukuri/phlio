"""
Phlio API — application entrypoint.

    uv run uvicorn app.main:app --reload --port 8000

Wires together configuration, structured logging, the dependency
container, middleware, routes, and (for the default in-memory backend)
demo seed data, then exposes the `app` object uvicorn serves.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.config import get_settings
from app.core.container import build_container
from app.core.logging import configure_logging
from app.middleware.error_handler import register_exception_handlers
from app.middleware.request_id import RequestIDMiddleware
from app.middleware.request_logging import RequestLoggingMiddleware

# Logging is configured at import time (before `create_app()` runs) so
# even the earliest startup log lines — settings validation, container
# construction — use the configured format instead of Python's unconfigured
# default (which prints WARNING+ only, with no request-id support).
configure_logging(get_settings())
logger = logging.getLogger("phlio.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    container = await build_container(settings)
    app.state.container = container

    if settings.database_backend == "memory":
        from app.core.seed import seed_memory_backend

        await seed_memory_backend(container)
        logger.info("Seeded in-memory backend with demo data.")

    logger.info(
        "Phlio API started (env=%s, database_backend=%s, agent_planner=%s)",
        settings.app_env,
        settings.database_backend,
        type(container.agent_planner).__name__,
    )
    yield
    logger.info("Phlio API shutting down.")


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        description="Phlio backend API — identity, social, rooms, shop, and the Phlio Agent.",
        version="0.1.0",
        docs_url="/docs",
        redoc_url="/redoc",
        lifespan=lifespan,
    )

    # Order matters: middleware runs outside-in on the way in, inside-out on
    # the way out. Request ID must be assigned before RequestLogging runs so
    # the access-log line (and everything it triggers) can be tagged with it.
    app.add_middleware(RequestLoggingMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    register_exception_handlers(app)
    app.include_router(api_router, prefix=settings.api_v1_prefix)

    @app.get("/health", tags=["meta"])
    async def health() -> dict:
        """Liveness/readiness probe for local dev, Docker healthchecks, and
        orchestrators. Deliberately has no auth and touches no dependency so
        it stays fast and always answers, even if a downstream service
        (SurrealDB, the AI provider) is degraded."""
        return {"status": "ok", "service": settings.app_name}

    return app


app = create_app()
