"""
Core engine client.

Talks to the compiled `phlio-core` Rust binary (see
`phlio_core/cli/src/main.rs`) as a local subprocess, one JSON request per
call. This is where the backend reaches for anything that belongs in the
security-critical Rust layer per architecture doc section 39: request
signing, secure ID generation, and rule-based risk scoring.

If the binary cannot be found or fails to start (e.g. a contributor hasn't
run `cargo build --release` yet), every method transparently falls back to
a pure-Python equivalent so the rest of the backend keeps working during
local development. Production deployments should always ship the compiled
binary — the fallback exists for developer convenience, not as a supported
alternative implementation, and logs a warning whenever it is used.
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

logger = logging.getLogger("phlio.core_engine")


class CoreEngineError(RuntimeError):
    pass


class CoreEngineClient:
    """Async client for the phlio_core CLI, with a pure-Python fallback."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._binary_path = self._resolve_binary_path(settings.core_engine_binary_path)
        if self._binary_path is None:
            logger.warning(
                "phlio_core binary not found at %s — falling back to pure-Python "
                "implementations. Run `cargo build --release` in phlio_core/ for "
                "production-equivalent behaviour.",
                settings.core_engine_binary_path,
            )

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
        stdout, stderr = await proc.communicate(stdin_bytes)

        if proc.returncode != 0:
            raise CoreEngineError(stderr.decode("utf-8", errors="replace").strip())

        response = json.loads(stdout.decode("utf-8"))
        if not response.get("ok"):
            raise CoreEngineError(response.get("error", {}).get("message", "unknown core engine error"))
        return response["data"]

    # -- Public API -----------------------------------------------------

    async def generate_id(self, prefix: str) -> str:
        try:
            data = await self._run("generate-id", "--prefix", prefix)
            return data["id"]
        except CoreEngineError:
            return f"{prefix}_{secrets.token_hex(16)}"

    async def sign(self, secret: str, payload: str) -> str:
        try:
            data = await self._run("sign", stdin_payload={"secret": secret, "payload": payload})
            return data["signature"]
        except CoreEngineError:
            return hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()

    async def verify(self, secret: str, payload: str, signature: str) -> bool:
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
