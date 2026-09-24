"""
Domain exception hierarchy.

Domain services raise these instead of HTTP-specific errors — a service in
`app/domains/social` should never know it's being called from an HTTP API
at all. The `middleware/error_handler.py` module is the single place that
translates these into HTTP responses, which keeps the mapping consistent
across every endpoint instead of each route handler inventing its own
status codes (architecture doc section 9: API -> Application -> Domain ->
Infrastructure, with the domain layer staying framework-agnostic).
"""

from __future__ import annotations


class AppError(Exception):
    """Base class for all expected, "handled" application errors.

    `code` is a short machine-readable identifier (stable across releases,
    safe to key client-side error handling off of). `message` is safe to
    show to end users unless a subclass says otherwise.
    """

    code: str = "app_error"
    http_status: int = 500

    def __init__(self, message: str, *, code: str | None = None) -> None:
        super().__init__(message)
        self.message = message
        if code:
            self.code = code


class NotFoundError(AppError):
    code = "not_found"
    http_status = 404


class ValidationAppError(AppError):
    """Raised for domain-level validation failures (distinct from FastAPI's
    own request-schema validation, which is handled separately)."""

    code = "validation_error"
    http_status = 422


class ConflictError(AppError):
    """E.g. username already taken, duplicate like, etc."""

    code = "conflict"
    http_status = 409


class UnauthorizedError(AppError):
    """Missing or invalid credentials."""

    code = "unauthorized"
    http_status = 401


class ForbiddenError(AppError):
    """Authenticated, but not allowed to perform this action."""

    code = "forbidden"
    http_status = 403


class RateLimitedError(AppError):
    code = "rate_limited"
    http_status = 429
