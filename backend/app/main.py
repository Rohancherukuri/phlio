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
from app.middleware.security import BodySizeLimitMiddleware, SecurityHeadersMiddleware, add_compression

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
    # Free hosting: stop the service from falling asleep (no-op unless KEEP_AWAKE=true).
    from app.infrastructure import keep_awake
    awake = asyncio.create_task(keep_awake.run(container, settings.keep_awake_interval))
    from app.domains.graph.news import run as refresh_news
    news_worker = asyncio.create_task(refresh_news(container)) if settings.news_ingestion_enabled else None
    # Development: make sure Phlio Book has its catalogue (sample services +
    # OpenStreetMap places + openly licensed photos) without a manual seed.
    book_seed = None
    if settings.database_backend != "memory" and not settings.is_production:
        async def seed_book():
            try:
                from scripts.import_book_services import ensure_catalog
                await ensure_catalog(container)
            except Exception:
                logger.exception("Phlio Book catalogue seed failed (run scripts.import_book_services).")
        book_seed = asyncio.create_task(seed_book())
    try:
        yield
    finally:
        if book_seed and not book_seed.done():
            book_seed.cancel()
            with suppress(asyncio.CancelledError):
                await book_seed
        if news_worker:
            news_worker.cancel()
            with suppress(asyncio.CancelledError):
                await news_worker
        worker.cancel()
        with suppress(asyncio.CancelledError):
            await worker
        awake.cancel()
        with suppress(asyncio.CancelledError):
            await awake
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
        # API docs are off in production unless API_DOCS_ENABLED=true: they
        # map every endpoint and schema for anyone probing the server.
        docs_url="/docs" if settings.docs_enabled else None,
        redoc_url="/redoc" if settings.docs_enabled else None,
        openapi_url="/openapi.json" if settings.docs_enabled else None,
        lifespan=lifespan,
    )

    app.state.settings = settings

    # Order matters: middleware runs outside-in on the way in, inside-out on
    # the way out. Request ID must be assigned before RequestLogging runs so
    # the access-log line (and everything it triggers) can be tagged with it.
    # Innermost first: gzip wraps the routes, then the body cap, logging,
    # request id, security headers (so even errors and 413s carry them), and
    # CORS outermost so preflight requests are answered before anything else.
    add_compression(app)
    app.add_middleware(BodySizeLimitMiddleware, max_bytes=settings.max_json_body_bytes)
    app.add_middleware(RequestLoggingMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.add_middleware(SecurityHeadersMiddleware, hsts=settings.is_production,
                       api_prefix=settings.api_v1_prefix)
    origins = settings.cors_origins_list
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        # The app authenticates with bearer tokens, never cookies, so
        # credentialed CORS is only needed for an explicit origin list; with
        # "*" it would let any website make authenticated browser requests.
        allow_credentials="*" not in origins,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["*"],
        max_age=600,
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
