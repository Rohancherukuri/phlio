"""Tests for `app/core/logging.py` — the formatters and request-id tagging
that every other log line in the app depends on."""

from __future__ import annotations

import json
import logging

from app.core.logging import JsonFormatter, RequestIdFilter, TextFormatter, request_id_var


def _make_record(msg: str = "hello world", **extra: object) -> logging.LogRecord:
    record = logging.LogRecord(
        name="phlio.test",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg=msg,
        args=(),
        exc_info=None,
    )
    for key, value in extra.items():
        setattr(record, key, value)
    return record


def test_text_formatter_includes_level_and_logger_name() -> None:
    record = _make_record()
    line = TextFormatter().format(record)
    assert "INFO" in line
    assert "phlio.test" in line
    assert "hello world" in line


def test_text_formatter_includes_request_id_when_present() -> None:
    record = _make_record(request_id="abcdef12-3456-7890")
    line = TextFormatter().format(record)
    # Only the first 8 chars are shown, to keep the line short.
    assert "[req=abcdef12]" in line


def test_text_formatter_omits_request_tag_when_absent() -> None:
    record = _make_record(request_id=None)
    line = TextFormatter().format(record)
    assert "[req=" not in line


def test_json_formatter_produces_valid_json_with_expected_keys() -> None:
    record = _make_record(request_id="req-123")
    line = JsonFormatter().format(record)
    payload = json.loads(line)
    assert payload["level"] == "INFO"
    assert payload["logger"] == "phlio.test"
    assert payload["message"] == "hello world"
    assert payload["request_id"] == "req-123"


def test_json_formatter_carries_extra_fields() -> None:
    record = _make_record(user_id="usr_abc", action="login")
    payload = json.loads(JsonFormatter().format(record))
    assert payload["user_id"] == "usr_abc"
    assert payload["action"] == "login"


def test_json_formatter_omits_request_id_when_absent() -> None:
    record = _make_record()
    payload = json.loads(JsonFormatter().format(record))
    assert "request_id" not in payload


def test_request_id_filter_attaches_current_context_value() -> None:
    token = request_id_var.set("ctx-request-id")
    try:
        record = _make_record()
        assert RequestIdFilter().filter(record) is True
        assert record.request_id == "ctx-request-id"
    finally:
        request_id_var.reset(token)


def test_request_id_filter_attaches_none_outside_a_request() -> None:
    # No `request_id_var.set(...)` call — simulates code running outside
    # any HTTP request (a startup task, a background job).
    record = _make_record()
    RequestIdFilter().filter(record)
    assert record.request_id is None
