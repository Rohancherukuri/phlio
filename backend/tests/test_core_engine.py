"""The Rust core engine and its Python fallbacks must agree exactly.

Runs against `phlio_native` when it is importable (CI and the Docker image
build it) and always checks the pure-Python mirrors, so a rule change in one
place without the other fails here.
"""

from __future__ import annotations

import hashlib
import hmac
import itertools

import pytest

from app.api.v1 import auth_security
from app.infrastructure.core_engine import client as client_module
from app.infrastructure.core_engine.native import native
from app.infrastructure.security import guard

needs_native = pytest.mark.skipif(native is None, reason="phlio_native not built")

RFC_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"  # RFC 6238 appendix B seed


def _events():
    for v, age, dev, amt, loc, fails in itertools.product(
        (0, 5, 10), (0, 3, 30), (True, False), (0, 5_000_000), (False, True), (0, 3)
    ):
        yield dict(velocity_count=v, account_age_days=age, is_known_device=dev,
                   amount_minor_units=amt, is_unusual_location=loc, recent_failed_auth_attempts=fails)


@needs_native
def test_native_risk_matches_python_mirror():
    for event in _events():
        assert native.score_risk(event) == client_module._fallback_score_risk(event)


@needs_native
def test_native_crypto_matches_stdlib():
    sig = native.sign("secret", "payload")
    assert sig == hmac.new(b"secret", b"payload", hashlib.sha256).hexdigest()
    assert native.verify("secret", "payload", sig)
    assert not native.verify("secret", "payload!", sig)
    assert not native.verify("secret", "payload", "not-hex")
    assert native.sha256_hex(b"abc") == hashlib.sha256(b"abc").hexdigest()
    assert native.constant_time_eq("a", "a") and not native.constant_time_eq("a", "b")
    ident = native.generate_id("pst")
    assert ident.startswith("pst_") and len(ident) == 36
    with pytest.raises(ValueError):
        native.generate_id("bad/prefix")


@pytest.mark.parametrize("now,code", [(59, "287082"), (1111111109, "081804"), (2000000000, "279037")])
def test_totp_rfc_vectors_both_engines(monkeypatch, now, code):
    assert auth_security.matching_step(RFC_SECRET, code, now) == now // 30
    monkeypatch.setattr(auth_security, "native", None)
    assert auth_security.matching_step(RFC_SECRET, code, now) == now // 30
    assert auth_security.totp(RFC_SECRET, now // 30) == code


def test_totp_rejects_wrong_and_malformed_codes():
    assert auth_security.matching_step(RFC_SECRET, "000000", 59) is None
    assert auth_security.matching_step(RFC_SECRET, "12ab56", 59) is None


@pytest.mark.parametrize("make", [guard._PyThrottle] + ([native.Throttle] if native else []))
def test_throttle_engines_behave_the_same(make):
    t = make(max_failures=3, window_secs=60.0, lockout_secs=10.0, max_lockout_secs=35.0, max_keys=4)
    assert [t.record_failure("k", x) for x in (0.0, 1.0, 2.0)] == [0.0, 0.0, 10.0]
    assert t.retry_after("k", 5.0) == 7.0
    assert t.record_failure("k", 5.0) == 7.0  # no extension while locked
    now, lockouts = 12.0, []
    for _ in range(6):
        if (lock := t.record_failure("k", now)) > 0:
            lockouts.append(lock)
            now += lock
    assert lockouts == [20.0, 35.0]
    t.reset("k")
    assert t.retry_after("k", now) == 0.0
    for i in range(50):
        t.record_failure(f"x{i}", 100.0 + i)
    assert len(t) <= 4


async def test_client_prefers_native():
    from app.config import Settings

    c = client_module.CoreEngineClient(Settings(app_env="testing"))
    assert c.engine == ("native" if native else c.engine)
    ident = await c.generate_id("usr")
    assert ident.startswith("usr_")
    assert await c.verify("k", "p", await c.sign("k", "p"))
