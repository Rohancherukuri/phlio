"""Shared SurrealDB connection management.

A single `Surreal` client is created at startup (see
`app/core/container.py`) and handed to every `Surreal*Repository`. SurrealDB
connections are cheap to hold open for the process lifetime, so there is no
per-request connect/disconnect overhead.
"""

from __future__ import annotations

from surrealdb import Surreal

from app.config import Settings


async def create_surreal_connection(settings: Settings) -> Surreal:
    db = Surreal(settings.surreal_url)
    await db.connect()
    await db.signin({"user": settings.surreal_user, "pass": settings.surreal_password})
    await db.use(settings.surreal_namespace, settings.surreal_database)
    return db
