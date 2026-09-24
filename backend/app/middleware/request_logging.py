"""
Request logging middleware.

Emits one structured log line per HTTP request — method, path, status
code, and duration — through the same logging setup as the rest of the
app (see `app/core/logging.py`), rather than relying on uvicorn's built-in
access log (which isn't structured and doesn't carry the request id).
`uvicorn.access` is quieted in `configure_logging` specifically so this is
the one access-log line a request produces, not two.

`/health` is logged at DEBUG rather than INFO — it's polled continuously
by Docker/orchestrator healthchecks and would otherwise drown out every
other log line within minutes.
"""

from __future__ import annotations

import logging

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from app.core.logging import LogTimer

logger = logging.getLogger("phlio.access")

_QUIET_PATHS = {"/health"}


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        level = logging.DEBUG if request.url.path in _QUIET_PATHS else logging.INFO

        with LogTimer() as timer:
            response = await call_next(request)

        logger.log(
            level,
            "%s %s -> %d (%.1fms)",
            request.method,
            request.url.path,
            response.status_code,
            timer.elapsed_ms,
        )
        return response
