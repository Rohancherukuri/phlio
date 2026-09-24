"""
Password hashing.

Uses `bcrypt` directly (rather than a heavier abstraction layer) — bcrypt
is a well-audited, purpose-built password hash with a built-in work factor,
which is exactly what's needed here and nothing more. Hashing is CPU-bound
and synchronous by nature; callers run it in a thread via
`fastapi.concurrency.run_in_threadpool` so it never blocks the event loop.
"""

from __future__ import annotations

import bcrypt

_BCRYPT_ROUNDS = 12


def hash_password(plain_password: str) -> str:
    salt = bcrypt.gensalt(rounds=_BCRYPT_ROUNDS)
    hashed = bcrypt.hashpw(plain_password.encode("utf-8"), salt)
    return hashed.decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))
    except ValueError:
        # Malformed hash in storage — treat as "does not match" rather than
        # raising, so a corrupt record fails closed instead of 500ing.
        return False
