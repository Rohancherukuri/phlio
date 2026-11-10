"""
HTTP hardening and compression middleware (pure ASGI, no per-request objects).

``SecurityHeadersMiddleware``
    Adds the OWASP-recommended response headers to every response:

    * ``X-Content-Type-Options: nosniff`` — browsers must not guess types
      (stops an uploaded "image" being run as HTML/JS).
    * ``X-Frame-Options: DENY`` + CSP ``frame-ancestors 'none'`` — no
      click-jacking through iframes.
    * ``Referrer-Policy: no-referrer`` — URLs (which may carry ids) never
      leak to third parties.
    * ``Permissions-Policy`` — the API never needs camera/mic/location in a
      browser context, so they are switched off.
    * ``Content-Security-Policy: default-src 'none'`` on API/media responses —
      a JSON or media response can never execute script even if it is opened
      directly in a browser. Skipped for the interactive docs pages, which
      need their own scripts.
    * ``Strict-Transport-Security`` in production (HTTPS only, 1 year).
    * ``Cache-Control: no-store`` on ``/auth`` responses, so tokens are never
      kept by an intermediary or the device's HTTP cache.

``BodySizeLimitMiddleware``
    Rejects JSON / form bodies over a limit (default 2 MiB) with ``413``,
    checking ``Content-Length`` up front and counting streamed (chunked)
    bodies as they arrive, so a client cannot exhaust memory by posting a
    huge JSON document. File uploads (``multipart/form-data``, raw media) are
    left to their endpoints, which stream to disk with their own caps.

``add_compression``
    gzip for API responses ≥ 1 KiB (feeds, search results, inboxes are JSON
    and shrink 70–90 %, which is most of the "loading" time on mobile data).
    Already-compressed media types are excluded, as are ``/media`` and
    ``Range`` requests, so video seeking keeps working byte-for-byte.
"""

from __future__ import annotations

import json

from fastapi import FastAPI
from starlette.middleware.gzip import GZipMiddleware
from starlette.types import ASGIApp, Message, Receive, Scope, Send

_BASE_HEADERS: list[tuple[bytes, bytes]] = [
    (b"x-content-type-options", b"nosniff"),
    (b"x-frame-options", b"DENY"),
    (b"referrer-policy", b"no-referrer"),
    (b"permissions-policy", b"camera=(), microphone=(), geolocation=(), payment=(), usb=()"),
    (b"cross-origin-opener-policy", b"same-origin"),
]
_API_CSP = (b"content-security-policy", b"default-src 'none'; frame-ancestors 'none'; base-uri 'none'")
_HSTS = (b"strict-transport-security", b"max-age=31536000; includeSubDomains")
_NO_STORE = (b"cache-control", b"no-store")
_DOC_PATHS = ("/docs", "/redoc", "/openapi.json")


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp, *, hsts: bool, api_prefix: str = "/api/v1") -> None:
        self.app = app
        self.hsts = hsts
        self.auth_prefix = f"{api_prefix}/auth"

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        path: str = scope.get("path", "")
        extra = list(_BASE_HEADERS)
        if not path.startswith(_DOC_PATHS):
            extra.append(_API_CSP)
        if self.hsts:
            extra.append(_HSTS)
        no_store = path.startswith(self.auth_prefix)

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                present = {name.lower() for name, _ in headers}
                headers.extend(h for h in extra if h[0] not in present)
                if no_store:
                    headers = [h for h in headers if h[0].lower() != b"cache-control"]
                    headers.append(_NO_STORE)
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, send_with_headers)


class _TooLarge(Exception):
    pass


class BodySizeLimitMiddleware:
    #: Content types whose bodies are parsed in memory and therefore capped.
    _CAPPED = (b"application/json", b"application/x-www-form-urlencoded", b"text/")

    def __init__(self, app: ASGIApp, *, max_bytes: int = 2 * 1024 * 1024) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope.get("method") in ("GET", "HEAD", "OPTIONS"):
            await self.app(scope, receive, send)
            return
        content_type = b""
        length: int | None = None
        for name, value in scope.get("headers", []):
            if name == b"content-type":
                content_type = value.lower()
            elif name == b"content-length":
                try:
                    length = int(value)
                except ValueError:
                    await _reject(send, 400, "Invalid Content-Length.")
                    return
        if not content_type.startswith(self._CAPPED):
            await self.app(scope, receive, send)
            return
        if length is not None and length > self.max_bytes:
            await _reject(send, 413, "Request body is too large.")
            return

        received = 0
        started = False

        async def counting_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    raise _TooLarge
            return message

        async def tracking_send(message: Message) -> None:
            nonlocal started
            started = started or message["type"] == "http.response.start"
            await send(message)

        try:
            await self.app(scope, counting_receive, tracking_send)
        except _TooLarge:
            if not started:
                await _reject(send, 413, "Request body is too large.")


async def _reject(send: Send, status: int, message: str) -> None:
    code = "payload_too_large" if status == 413 else "invalid_request"
    body = json.dumps({"error": {"code": code, "message": message}}).encode()
    await send({"type": "http.response.start", "status": status,
                "headers": [(b"content-type", b"application/json"),
                            (b"content-length", str(len(body)).encode()), (b"connection", b"close")]})
    await send({"type": "http.response.body", "body": body})


class _SelectiveGZip:
    """GZip, except for /media files and byte-range requests."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app
        # Level 5: ~95 % of level 9's ratio for a third of the CPU — matters on
        # small instances where gzip would otherwise compete with requests.
        self.gzip = GZipMiddleware(app, minimum_size=1024, compresslevel=5)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope.get("path", "").startswith("/media/") or any(
            name == b"range" for name, _ in scope.get("headers", [])
        ):
            await self.app(scope, receive, send)
        else:
            await self.gzip(scope, receive, send)


def add_compression(app: FastAPI) -> None:
    app.add_middleware(_SelectiveGZip)
