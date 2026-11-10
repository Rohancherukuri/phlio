"""HTTP hardening: headers, body limits, compression, sign-in lockouts."""

from __future__ import annotations

import pytest

from app.config import Settings


async def test_security_headers_on_api_and_errors(client):
    for path in ("/health", "/api/v1/does-not-exist"):
        r = await client.get(path)
        assert r.headers["x-content-type-options"] == "nosniff"
        assert r.headers["x-frame-options"] == "DENY"
        assert r.headers["referrer-policy"] == "no-referrer"
        assert "default-src 'none'" in r.headers["content-security-policy"]
    # HSTS is production-only (local development is plain http).
    assert "strict-transport-security" not in r.headers


async def test_auth_responses_are_not_cached(client):
    r = await client.post("/api/v1/auth/login", json={"identifier": "nobody", "password": "wrong-password"})
    assert r.headers["cache-control"] == "no-store"


async def test_oversized_json_is_rejected(client):
    r = await client.post("/api/v1/auth/login", content=b'{"x":"' + b"a" * (5 * 1024 * 1024) + b'"}',
                          headers={"content-type": "application/json"})
    assert r.status_code == 413
    assert r.json()["error"]["code"] == "payload_too_large"


async def test_json_responses_are_gzipped(client):
    r = await client.get("/openapi.json", headers={"accept-encoding": "gzip"})
    assert r.status_code == 200
    assert r.headers.get("content-encoding") == "gzip"


async def test_login_locks_out_after_repeated_failures(client):
    body = {"identifier": "Arjun", "password": "definitely-wrong"}
    codes = [(await client.post("/api/v1/auth/login", json=body)).status_code for _ in range(6)]
    assert codes == [401, 401, 401, 401, 429, 429]
    locked = await client.post("/api/v1/auth/login", json=body)
    assert int(locked.headers["retry-after"]) > 0
    # Case/whitespace variations of the same account share the lock, and the
    # right password doesn't get through while it lasts.
    again = {"identifier": " arjun ", "password": "password123"}
    assert (await client.post("/api/v1/auth/login", json=again)).status_code == 429


async def test_successful_login_clears_failures(client):
    wrong = {"identifier": "arjun", "password": "nope-nope"}
    for _ in range(4):
        assert (await client.post("/api/v1/auth/login", json=wrong)).status_code == 401
    ok = await client.post("/api/v1/auth/login", json={"identifier": "arjun", "password": "password123"})
    assert ok.status_code == 200
    assert (await client.post("/api/v1/auth/login", json=wrong)).status_code == 401


def test_production_refuses_default_jwt_secret():
    with pytest.raises(ValueError, match="JWT_SECRET"):
        Settings(app_env="production", _env_file=None)
    ok = Settings(app_env="production", jwt_secret="x" * 40, debug=True, _env_file=None)
    assert ok.debug is False and ok.docs_enabled is False
