"""
Structured logging.

Configured once, at process startup (`configure_logging`, called from
`app/main.py` before the FastAPI app is built), rather than each module
calling `logging.basicConfig` — a second `basicConfig` call is a silent
no-op in the stdlib, which is exactly the kind of "why isn't my log level
working" bug this avoids.

Two output formats, chosen via `Settings.log_format`:
  - "text": one human-readable line per record, for a local terminal.
  - "json": one JSON object per line, for a log aggregator in staging/
    production (see Phlio_Final_Product_Blueprint.md section 38).

Every log record — from any module, in any domain — automatically carries
the current request's `request_id` when one is active, via a
`logging.Filter` reading the same `ContextVar` that
`app/middleware/request_id.py` populates. Nobody has to remember to pass
`extra={"request_id": ...}` by hand.
"""

from __future__ import annotations

import contextvars
import json
import logging
import sys
import time
from typing import Any

from app.config import Settings

# Populated by `app/middleware/request_id.py` for the lifetime of a single
# request; read here so every log line emitted while handling that request
# is automatically tagged, without threading a `request_id` parameter
# through every function call.
request_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar("request_id", default=None)


class RequestIdFilter(logging.Filter):
    """Attaches the active request id (if any) to every log record."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get()
        return True


class TextFormatter(logging.Formatter):
    """Compact single-line format for local development.

    Example:
        2026-09-22 10:15:03 INFO     phlio.social [req=a1b2c3d4] Post created post_id=pst_...
    """

    def format(self, record: logging.LogRecord) -> str:
        timestamp = self.formatTime(record, "%Y-%m-%d %H:%M:%S")
        request_id = getattr(record, "request_id", None)
        request_tag = f" [req={request_id[:8]}]" if request_id else ""
        message = record.getMessage()
        line = f"{timestamp} {record.levelname:<8} {record.name}{request_tag} {message}"
        if record.exc_info:
            line += "\n" + self.formatException(record.exc_info)
        return line


class JsonFormatter(logging.Formatter):
    """One JSON object per line — machine-parseable for a log aggregator."""

    _RESERVED = frozenset(logging.LogRecord("", 0, "", 0, "", (), None).__dict__) | {"message", "asctime"}

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        request_id = getattr(record, "request_id", None)
        if request_id:
            payload["request_id"] = request_id
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        # Any caller-supplied `extra={...}` fields ride along too, e.g.
        # `logger.info("...", extra={"user_id": user.id})`.
        for key, value in record.__dict__.items():
            if key not in self._RESERVED and key not in payload:
                payload[key] = value

        return json.dumps(payload, default=str)


def configure_logging(settings: Settings) -> None:
    """Configures the root logger once, at process startup.

    Idempotent-ish: re-configuring (e.g. under `--reload`) replaces
    handlers rather than stacking duplicate ones, so log lines are never
    doubled/tripled after a hot reload.
    """
    root = logging.getLogger()
    root.setLevel(settings.log_level.upper())
    root.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    handler.addFilter(RequestIdFilter())
    handler.setFormatter(JsonFormatter() if settings.log_format == "json" else TextFormatter())
    root.addHandler(handler)

    # Uvicorn's own loggers are noisy at INFO (an "access" line per
    # request, duplicating `middleware/request_logging.py`'s structured
    # version) — quiet them down rather than disabling uvicorn's logging
    # config outright, so startup/shutdown messages are still visible.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)


class LogTimer:
    """Tiny context manager for timing a block of code in milliseconds.

    Usage:
        with LogTimer() as timer:
            ...
        logger.info("did_thing duration_ms=%.1f", timer.elapsed_ms)
    """

    def __enter__(self) -> LogTimer:
        self._start = time.perf_counter()
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.elapsed_ms = (time.perf_counter() - self._start) * 1000
