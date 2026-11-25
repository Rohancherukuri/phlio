"""
Phlio API — application entrypoint.

    uv run uvicorn app.main:app --reload --port 8000

Wires together configuration, structured logging, the dependency
container, middleware, routes, and (for the default in-memory backend)
demo seed data, then exposes the `app` object uvicorn serves.
"""

from __future__ import annotations

import base64
import logging
import asyncio
import os
from typing import Any
from urllib.parse import quote
from contextlib import suppress
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import httpx
from fastapi.responses import RedirectResponse, Response, StreamingResponse
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
    from app.infrastructure.database.surreal.client import SurrealUnavailable
    try:
        container = await build_container(settings)
    except SurrealUnavailable as error:
        if settings.app_env != "development" or not settings.dev_memory_fallback:
            raise
        logger.warning(
            "%s\n\n    >>> Starting with the IN-MEMORY demo backend instead: nothing you do is saved."
            "\n    >>> Start SurrealDB and restart to use your real data"
            " (or set DEV_MEMORY_FALLBACK=false to stop instead).\n", error)
        settings.database_backend = "memory"
        container = await build_container(settings)
    if container.cache.redis is not None and settings.app_env == "development":
        # Redis is only a cache: if it isn't running locally, switch it off
        # rather than waiting on a connect timeout in every request.
        try:
            await container.cache.redis.ping()
        except Exception as error:  # noqa: BLE001
            logger.warning("Redis isn't reachable at REDIS_URL (%s); running without the cache.", error)
            await container.cache.close()
            container.cache.redis = None
    app.state.container = container

    if settings.database_backend == "memory":
        from app.core.seed import seed_memory_backend

        await seed_memory_backend(container)
        logger.info("Seeded in-memory backend with demo data.")
        if settings.app_env == "development":
            # Phlio Move activities for the Posts tab's card stack.
            try:
                from scripts.seed_move_activities import seed as seed_move

                people = await container.identity_repository.list_users(0, 50)
                await seed_move(container, people, per_person=3, quiet=True)
            except Exception:  # noqa: BLE001 — demo data must never stop startup
                logger.exception("Seeding Phlio Move activities failed.")

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
    # Demo deploys: keep the seeded community's moments inside their 24 hours.
    from app.domains.graph import demo_refresh
    demo = asyncio.create_task(demo_refresh.run(container))
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
        demo.cancel()
        with suppress(asyncio.CancelledError):
            await demo
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

    # Request headers passed on to the bucket, and response headers passed back.
    _FORWARD = ("range", "if-none-match", "if-modified-since", "if-range")
    _RETURN = ("content-type", "content-length", "content-range", "accept-ranges", "etag", "last-modified")

    def __init__(self, *args: Any, fallback: str = "", delivery: str = "proxy", **kwargs: Any) -> None:
        """``fallback`` is the public base URL for missing files ('' disables it).

        ``delivery``:
          * ``proxy`` (default) — the API streams the file from the bucket.
            Phones only ever talk to the API host, which matters because
            some mobile carriers block or throttle the bucket's ``*.r2.dev``
            domain (the app then loads fully on Wi-Fi but not on mobile data).
          * ``redirect`` — a 307 to the bucket (cheapest for the API; use it
            once the bucket has its own custom domain).
        """
        super().__init__(*args, **kwargs)
        self.fallback = fallback.rstrip("/")
        self.delivery = delivery
        self._client: httpx.AsyncClient | None = None

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=httpx.Timeout(30, read=60), follow_redirects=True,
                limits=httpx.Limits(max_connections=40, max_keepalive_connections=20))
        return self._client

    async def get_response(self, path: str, scope: Scope) -> Response:
        """Serves the file from disk, or from the bucket when it's not there."""
        try:
            return await super().get_response(path, scope)
        except StarletteHTTPException as exc:
            if exc.status_code != 404 or not self.fallback:
                raise
            url = f"{self.fallback}/{quote(path.replace(os.sep, '/'))}"
            if self.delivery == "redirect":
                return RedirectResponse(url, status_code=307)
            return await self._proxy(url, scope)

    async def _proxy(self, url: str, scope: Scope) -> Response:
        headers = {k.decode().lower(): v.decode() for k, v in scope.get("headers", [])}
        forward = {k: headers[k] for k in self._FORWARD if k in headers}
        client = self._http()
        try:
            upstream = await client.send(client.build_request(scope.get("method", "GET"), url, headers=forward),
                                         stream=True)
        except httpx.HTTPError:
            # Bucket unreachable from the server: let the client try it directly.
            return RedirectResponse(url, status_code=307)
        if upstream.status_code == 404:
            await upstream.aclose()
            raise StarletteHTTPException(404)
        out = {k: upstream.headers[k] for k in self._RETURN if k in upstream.headers}
        # Media files are content-addressed or never rewritten in place: let
        # phones and the image/video caches keep them.
        out["cache-control"] = "public, max-age=2592000"
        if scope.get("method") == "HEAD" or upstream.status_code == 304:
            await upstream.aclose()
            return Response(status_code=upstream.status_code, headers=out)
        return StreamingResponse(upstream.aiter_raw(65536), status_code=upstream.status_code, headers=out,
                                 background=_Close(upstream))


class _Close:
    """Background task that closes the upstream response once the body is sent."""

    def __init__(self, upstream: httpx.Response) -> None:
        self.upstream = upstream

    async def __call__(self) -> None:
        await self.upstream.aclose()


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
    # Admin analytics: request telemetry + forwarding to GA4/PostHog/… .
    from app.middleware.analytics import AnalyticsMiddleware
    app.add_middleware(AnalyticsMiddleware)
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

    app.mount("/media", MediaFiles(directory=media_root_path(settings), fallback=settings.media_public_url,
                                   delivery=settings.media_delivery),
              name="media")

    # 1x1 transparent PNG. The app points image widgets here when a record has
    # no image (AppConfig.mediaUrl("")), so they render nothing instead of
    # requesting the bare origin and throwing NetworkImageLoadException (404).
    blank_png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=")

    @app.get("/blank.png", include_in_schema=False)
    async def blank_image() -> Response:
        return Response(blank_png, media_type="image/png",
                        headers={"Cache-Control": "public, max-age=31536000, immutable"})

    @app.get("/health", tags=["meta"])
    async def health() -> dict:
        """Liveness/readiness probe for local dev, Docker healthchecks, and
        orchestrators. Deliberately has no auth and touches no dependency so
        it stays fast and always answers, even if a downstream service
        (SurrealDB, the AI provider) is degraded."""
        return {"status": "ok", "service": settings.app_name}

    return app


app = create_app()
