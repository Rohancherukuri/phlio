"""
Request ID middleware.

Every request is tagged with a unique `X-Request-ID` (reusing an
upstream-supplied one if present, e.g. from a load balancer) so that a
single request can be traced across logs, error responses, and any
downstream service calls (the Rust core engine, the AI service). This is
the first building block of the observability story in the architecture
document — everything else (structured logging, tracing) hangs off of this.

The request id is stored two ways: on `request.state` (for anything with
direct access to the request, like `error_handler.py`) and in the
`request_id_var` ContextVar from `app/core/logging.py` (so background code
with no `Request` object — a domain service several calls deep — still
gets it attached to its log lines automatically).
"""

from __future__ import annotations

import uuid

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from app.core.logging import request_id_var

REQUEST_ID_HEADER = "X-Request-ID"


class RequestIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        request_id = request.headers.get(REQUEST_ID_HEADER) or str(uuid.uuid4())
        request.state.request_id = request_id
        token = request_id_var.set(request_id)
        try:
            response = await call_next(request)
        finally:
            request_id_var.reset(token)
        response.headers[REQUEST_ID_HEADER] = request_id
        return response

