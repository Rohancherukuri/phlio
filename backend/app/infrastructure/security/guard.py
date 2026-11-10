"""
Brute-force protection for credential checks (password sign-in, 2FA codes).

Each failed attempt is counted against two keys — the account identifier and
the client IP — in a sliding window. Too many failures lock that key with an
exponentially growing lockout (1 min, 2 min, 4 min … capped at 1 h), and the
API answers ``429 Too Many Requests`` with ``Retry-After`` *before* it even
hashes the password, so a locked attacker costs us almost nothing.

* Per-account limits stop password guessing against one user from many IPs.
* Per-IP limits stop password spraying (one password across many users).
* A successful sign-in clears the account key, so real users who mistype a
  few times are never stuck.

The counters live in ``phlio_native.Throttle`` (Rust, bounded memory, see
``phlio_core/crates/guard``) with a behaviour-identical pure-Python fallback.
State is per process — see the crate docs for the multi-instance trade-off.
"""

from __future__ import annotations

import math
import threading
import time
from dataclasses import dataclass, field

from fastapi import HTTPException, Request

from app.infrastructure.core_engine.native import native


@dataclass
class _Entry:
    failures: list[float] = field(default_factory=list)
    locked_until: float = 0.0
    strikes: int = 0
    touched: float = 0.0


class _PyThrottle:
    """Pure-Python mirror of ``phlio_guard::Throttle`` (keep in lockstep)."""

    def __init__(self, max_failures=5, window_secs=900.0, lockout_secs=60.0,
                 max_lockout_secs=3600.0, max_keys=100_000) -> None:
        self.max_failures, self.window = max_failures, window_secs
        self.lockout, self.max_lockout, self.max_keys = lockout_secs, max_lockout_secs, max_keys
        self._entries: dict[str, _Entry] = {}
        self._lock = threading.Lock()

    def retry_after(self, key: str, now: float) -> float:
        with self._lock:
            entry = self._entries.get(key)
            return max(0.0, entry.locked_until - now) if entry else 0.0

    def record_failure(self, key: str, now: float) -> float:
        with self._lock:
            if len(self._entries) >= self.max_keys and key not in self._entries:
                self._make_room(now)
            entry = self._entries.setdefault(key, _Entry(touched=now))
            entry.touched = now
            if entry.locked_until > now:
                return entry.locked_until - now
            entry.failures = [t for t in entry.failures if now - t < self.window]
            entry.failures.append(now)
            if len(entry.failures) >= self.max_failures:
                lockout = min(self.lockout * 2 ** min(entry.strikes, 16), self.max_lockout)
                entry.locked_until, entry.strikes, entry.failures = now + lockout, entry.strikes + 1, []
                return lockout
            return 0.0

    def reset(self, key: str) -> None:
        with self._lock:
            self._entries.pop(key, None)

    def __len__(self) -> int:
        return len(self._entries)

    def _make_room(self, now: float) -> None:
        self._entries = {k: e for k, e in self._entries.items()
                         if e.locked_until > now or any(now - t < self.window for t in e.failures)}
        if len(self._entries) >= self.max_keys:
            oldest = sorted(self._entries, key=lambda k: self._entries[k].touched)
            for k in oldest[: max(1, self.max_keys // 10)]:
                del self._entries[k]


def _throttle(**limits):
    return native.Throttle(**limits) if native is not None else _PyThrottle(**limits)


class CredentialGuard:
    """Account + IP throttles for one kind of credential check."""

    def __init__(self, scope: str, *, per_account: int, per_ip: int) -> None:
        self.scope = scope
        self._limits = (per_account, per_ip)
        self.clear()

    def clear(self) -> None:
        """Forgets every counter (tests; or an operator lifting all lockouts)."""
        per_account, per_ip = self._limits
        self.accounts = _throttle(max_failures=per_account)
        self.ips = _throttle(max_failures=per_ip, lockout_secs=120.0)

    def _keys(self, account: str, ip: str | None) -> list[tuple[object, str]]:
        keys: list[tuple[object, str]] = [(self.accounts, account.strip().lower())]
        if ip:
            keys.append((self.ips, ip))
        return keys

    def check(self, account: str, ip: str | None) -> None:
        """Raises 429 when the account or IP is locked out."""
        now = time.time()
        wait = max(t.retry_after(k, now) for t, k in self._keys(account, ip))
        if wait > 0:
            raise _too_many(wait)

    def failed(self, account: str, ip: str | None) -> None:
        """Counts a failure; raises 429 if it tripped a lockout."""
        now = time.time()
        wait = max(t.record_failure(k, now) for t, k in self._keys(account, ip))
        if wait > 0:
            raise _too_many(wait)

    def succeeded(self, account: str) -> None:
        self.accounts.reset(account.strip().lower())


def _too_many(wait: float) -> HTTPException:
    seconds = max(1, math.ceil(wait))
    minutes = math.ceil(seconds / 60)
    when = f"{minutes} minute{'s' if minutes != 1 else ''}" if seconds > 60 else "a minute"
    return HTTPException(429, f"Too many attempts. Try again in {when}.",
                         headers={"Retry-After": str(seconds)})


def client_ip(request: Request) -> str | None:
    """Client address (uvicorn resolves X-Forwarded-For via --proxy-headers)."""
    return request.client.host if request.client else None


#: Password sign-in: 5 wrong passwords per account, 30 per IP, per 15 min.
login_guard = CredentialGuard("login", per_account=5, per_ip=30)
#: Second factor: 5 wrong codes per account, 20 per IP, per 15 min.
two_factor_guard = CredentialGuard("2fa", per_account=5, per_ip=20)
