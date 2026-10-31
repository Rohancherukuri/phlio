"""
Phlio API — application entrypoint.

    uv run uvicorn app.main:app --reload --port 8000

Wires together configuration, structured logging, the dependency
container, middleware, routes, and (for the default in-memory backend)
demo seed data, then exposes the `app` object uvicorn serves.
"""

from __future__ import annotations

import logging
import asyncio
import os
from typing import Any
from urllib.parse import quote
from contextlib import suppress
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.types import Scope

from app.api.router import api_router
from app.config import Settings, get_settings
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
    settings = app.state.settings
    # Disk-less hosts: bring back the SQLite databases and DM files from
    # object storage before anything opens them (no-op when not configured).
    from app.infrastructure import media_sync
    await asyncio.to_thread(media_sync.restore_state, settings)
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
    from app.infrastructure.outbox import run as deliver_outbox
    worker = asyncio.create_task(deliver_outbox(container))
    # Backs up state and new uploads to object storage (no-op when not configured).
    state_sync = asyncio.create_task(media_sync.run(settings, settings.state_sync_interval))
    from app.domains.graph.news import run as refresh_news
    news_worker = asyncio.create_task(refresh_news(container)) if settings.news_ingestion_enabled else None
    try:
        yield
    finally:
        if news_worker:
            news_worker.cancel()
            with suppress(asyncio.CancelledError):
                await news_worker
        worker.cancel()
        with suppress(asyncio.CancelledError):
            await worker
        # Cancelling makes the sync do one final backup before shutdown.
        state_sync.cancel()
        with suppress(asyncio.CancelledError):
            await state_sync
    await container.cache.close()
    if container.graph.store.db:
        await container.graph.store.db.close()
    container.messaging_service.db.close()
    container.social_video_service.db.close()
    logger.info("Phlio API shutting down.")


class MediaFiles(StaticFiles):
    """StaticFiles for /media that redirects missing files to object storage.

    On a disk-less deployment the photos, videos and recordings live in a
    public bucket (``MEDIA_PUBLIC_URL``); the app keeps using origin-relative
    ``/media/...`` URLs and players follow the redirect.
    """

    def __init__(self, *args: Any, fallback: str = "", **kwargs: Any) -> None:
        """``fallback`` is the public base URL for missing files ('' disables it)."""
        super().__init__(*args, **kwargs)
        self.fallback = fallback.rstrip("/")

    async def get_response(self, path: str, scope: Scope) -> Response:
        """Serves the file from disk, or redirects to the bucket when it's not there."""
        try:
            return await super().get_response(path, scope)
        except StarletteHTTPException as exc:
            if exc.status_code != 404 or not self.fallback:
                raise
            return RedirectResponse(f"{self.fallback}/{quote(path.replace(os.sep, '/'))}", status_code=307)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    app = FastAPI(
        title=settings.app_name,
        description="Phlio backend API — identity, social, rooms, shop, and the Phlio Agent.",
        version="0.1.0",
        docs_url="/docs",
        redoc_url="/redoc",
        lifespan=lifespan,
    )

    app.state.settings = settings

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
    from app.api.v1.music import callback_router
    app.include_router(callback_router)

    # Room uploads land in settings.media_root (streamed to disk by
    # MediaStorage) and are served back origin-relative under /media so
    # attachment urls stay deploy-host agnostic.
    from app.core.container import media_root_path

    @app.middleware("http")
    async def cache_recorded_media(request, call_next):
        response = await call_next(request)
        if request.url.path.startswith('/media/live_recordings/') and response.status_code in (200,206,304):
            response.headers['Cache-Control'] = 'public, max-age=86400'
        return response

    app.mount("/media", MediaFiles(directory=media_root_path(settings), fallback=settings.media_public_url),
              name="media")

    @app.get("/health", tags=["meta"])
    async def health() -> dict:
        """Liveness/readiness probe for local dev, Docker healthchecks, and
        orchestrators. Deliberately has no auth and touches no dependency so
        it stays fast and always answers, even if a downstream service
        (SurrealDB, the AI provider) is degraded."""
        return {"status": "ok", "service": settings.app_name}

    return app


app = create_app()
