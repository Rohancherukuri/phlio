"""Counts product API traffic for the admin dashboard and forwards mutating
requests as events to the analytics tools switched on in the admin panel.

Nothing here can fail a request: telemetry errors are swallowed, Redis
writes and third-party calls run in the background.
"""

from __future__ import annotations

import time

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from app.infrastructure.analytics_bridge import AdminMetrics, AnalyticsBridge, event_name, platform_for


def metrics_for(app) -> AdminMetrics:
    state = app.state
    metrics = getattr(state, "admin_metrics", None)
    if metrics is None:
        metrics = state.admin_metrics = AdminMetrics()
    container = getattr(state, "container", None)
    if metrics.cache is None and container is not None:
        metrics.cache = container.cache
    return metrics


def bridge_for(app) -> AnalyticsBridge:
    bridge = getattr(app.state, "analytics_bridge", None)
    if bridge is None:
        bridge = app.state.analytics_bridge = AnalyticsBridge(app.state.settings.jwt_secret)
    return bridge


def _user_id(request: Request) -> str | None:
    header = request.headers.get("authorization", "")
    if not header.lower().startswith("bearer "):
        return None
    try:
        from app.infrastructure.security.jwt import decode_token

        return decode_token(header.split(" ", 1)[1].strip(), "access", request.app.state.settings)
    except Exception:  # noqa: BLE001 — an invalid token is just an anonymous request here
        return None


class AnalyticsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        started = time.perf_counter()
        response = await call_next(request)
        try:
            settings = request.app.state.settings
            platform = platform_for(request.url.path, settings.api_v1_prefix)
            if platform is None or request.method == "OPTIONS":
                return response
            user_id = _user_id(request)
            event = event_name(request.method, request.url.path, settings.api_v1_prefix) if response.status_code < 400 else None
            metrics_for(request.app).record(platform, response.status_code, (time.perf_counter() - started) * 1000,
                                            user_id, event)
            container = getattr(request.app.state, "container", None)
            if event and container is not None:
                bridge = bridge_for(request.app)
                await bridge.refresh(container.graph.store)
                bridge.track(event, user_id, {"platform": platform, "status": response.status_code})
        except Exception:  # noqa: BLE001
            pass
        return response
