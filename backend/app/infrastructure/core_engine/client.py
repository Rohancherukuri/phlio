"""
Core engine client.

Routes the backend's security-critical primitives (secure IDs, HMAC
signing/verification, rule-based risk scoring — architecture doc section 39)
to Rust, through the fastest path available:

1. **In-process** — ``phlio_native`` (PyO3 build of ``phlio_core``, see
   ``native.py``). A direct function call: no process, no JSON, no event-loop
   hop. This is what production images use.
2. **Subprocess** — the ``phlio-core`` CLI, one JSON request per call. Kept
   for hosts where the extension can't be loaded; ~1.5 ms per call.
3. **Pure Python** — mirrors of the same algorithms, so local development
   works without any Rust build. Logged once at startup.

All three produce identical results (the Python mirrors are kept in lockstep
with the Rust crates; see ``tests/test_core_engine.py``).
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import logging
import secrets
from pathlib import Path
from typing import Any, Literal

from app.config import Settings
from app.infrastructure.core_engine.native import native

logger = logging.getLogger("phlio.core_engine")

#: Upper bound for one CLI call; a wedged binary must never hang a request.
_SUBPROCESS_TIMEOUT_S = 5.0


class CoreEngineError(RuntimeError):
    pass


class CoreEngineClient:
    """Async facade over the Rust core engine with CLI and Python fallbacks."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._native = native
        self._binary_path = None if native else self._resolve_binary_path(settings.core_engine_binary_path)
        if native is None and self._binary_path is None:
            logger.warning(
                "phlio_core not available (no phlio_native module, no binary at %s) — "
                "using pure-Python implementations. Build it with `maturin develop "
                "--release -m phlio_core/crates/native/Cargo.toml` for production behaviour.",
                settings.core_engine_binary_path,
            )

    @property
    def engine(self) -> str:
        """Which implementation serves calls: ``native``, ``subprocess`` or ``python``."""
        if self._native is not None:
            return "native"
        return "subprocess" if self._binary_path is not None else "python"

    @staticmethod
    def _resolve_binary_path(configured_path: str) -> Path | None:
        candidate = Path(__file__).resolve().parents[3] / configured_path
        candidate = candidate.resolve() if candidate.exists() else Path(configured_path)
        return candidate if candidate.exists() and candidate.is_file() else None

    async def _run(self, *args: str, stdin_payload: dict[str, Any] | None = None) -> dict[str, Any]:
        if self._binary_path is None:
            raise CoreEngineError("binary_unavailable")

        proc = await asyncio.create_subprocess_exec(
            str(self._binary_path),
            *args,
            stdin=asyncio.subprocess.PIPE if stdin_payload is not None else None,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdin_bytes = json.dumps(stdin_payload).encode("utf-8") if stdin_payload is not None else None
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(stdin_bytes), _SUBPROCESS_TIMEOUT_S)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            raise CoreEngineError("core engine timed out") from None

        if proc.returncode != 0:
            raise CoreEngineError(stderr.decode("utf-8", errors="replace").strip())

        response = json.loads(stdout.decode("utf-8"))
        if not response.get("ok"):
            raise CoreEngineError(response.get("error", {}).get("message", "unknown core engine error"))
        return response["data"]

    # -- Public API -----------------------------------------------------

    async def generate_id(self, prefix: str) -> str:
        if self._native is not None:
            return self._native.generate_id(prefix)
        try:
            data = await self._run("generate-id", "--prefix", prefix)
            return data["id"]
        except CoreEngineError:
            return f"{prefix}_{secrets.token_hex(16)}"

    async def sign(self, secret: str, payload: str) -> str:
        if self._native is not None:
            return self._native.sign(secret, payload)
        try:
            data = await self._run("sign", stdin_payload={"secret": secret, "payload": payload})
            return data["signature"]
        except CoreEngineError:
            return hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()

    async def verify(self, secret: str, payload: str, signature: str) -> bool:
        if self._native is not None:
            return self._native.verify(secret, payload, signature)
        try:
            data = await self._run(
                "verify",
                stdin_payload={"secret": secret, "payload": payload, "signature": signature},
            )
            return bool(data["valid"])
        except CoreEngineError:
            expected = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
            return hmac.compare_digest(expected, signature)

    async def score_risk(self, event: dict[str, Any]) -> dict[str, Any]:
        """Scores a risk event. See `phlio_core/crates/risk_features` for the
        canonical rule definitions — this method's fallback intentionally
        mirrors those rules so behaviour stays identical either way."""
        result: dict[str, Any] | None = None
        if self._native is not None:
            try:
                result = self._native.score_risk(event)
            except ValueError as exc:
                logger.warning("core_engine.native_score_rejected %s", exc)
        if result is None:
            try:
                result = await self._run("score-risk", stdin_payload=event)
            except CoreEngineError:
                result = _fallback_score_risk(event)
        if result.get("decision") != "Allow":
            logger.warning(
                "core_engine.risk_flagged decision=%s score=%s reasons=%s",
                result.get("decision"), result.get("score"), result.get("reasons"),
            )
        return result


def _fallback_score_risk(event: dict[str, Any]) -> dict[str, Any]:
    """Pure-Python mirror of phlio_core/crates/risk_features/src/lib.rs.

    Kept deliberately in lockstep with the Rust rules so risk decisions do
    not silently change depending on whether the compiled binary is
    available. Any change to the Rust scoring rules should be mirrored here.
    """
    score = 0
    reasons: list[str] = []

    velocity = event.get("velocity_count", 0)
    if velocity >= 10:
        score += 30
        reasons.append("high_velocity")
    elif velocity >= 5:
        score += 15
        reasons.append("elevated_velocity")

    account_age = event.get("account_age_days", 0)
    if account_age < 1:
        score += 25
        reasons.append("brand_new_account")
    elif account_age < 7:
        score += 10
        reasons.append("young_account")

    if not event.get("is_known_device", True):
        score += 15
        reasons.append("unrecognized_device")

    if event.get("is_unusual_location", False):
        score += 15
        reasons.append("unusual_location")

    if event.get("recent_failed_auth_attempts", 0) >= 3:
        score += 20
        reasons.append("repeated_auth_failures")

    if event.get("amount_minor_units", 0) >= 5_000_000:
        score += 15
        reasons.append("high_value_transaction")

    clamped = max(0, min(score, 100))
    decision: Literal["Allow", "Review", "Block"]
    if clamped >= 75:
        decision = "Block"
    elif clamped >= 40:
        decision = "Review"
    else:
        decision = "Allow"

    return {"score": clamped, "decision": decision, "reasons": reasons}
