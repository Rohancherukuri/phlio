"""Pinned SDK adapter shared by domain repositories and the graph store."""

from __future__ import annotations

import datetime as dt
import re
from pathlib import Path

from surrealdb import AsyncSurreal, RecordID

from app.config import Settings

_REFERENCE_KEYS = {
    "user",
    "room",
    "post",
    "author",
    "seller",
    "product",
    "created_by",
    "author_id",
    "room_id",
    "user_id",
    "seller_id",
    "post_id",
    "in",
    "out",
}


def record(value):
    table, key = value.split(":", 1)
    return RecordID(table, key)


def encode(value, key=""):
    if isinstance(value, dict):
        return {k: encode(v, k) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [encode(v, key) for v in value]
    if isinstance(value, str) and key in _REFERENCE_KEYS and re.fullmatch(r"[a-z_]+:[a-zA-Z0-9_]+", value):
        return record(value)
    if isinstance(value, str) and key in {"cursor", "cursor_ts"} and "T" in value:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    return value


def decode(value):
    if isinstance(value, RecordID):
        return str(value)
    if isinstance(value, dict):
        return {k: decode(v) for k, v in value.items()}
    if isinstance(value, list):
        return [decode(v) for v in value]
    if type(value).__name__ == "Datetime":
        return dt.datetime.fromisoformat(str(value).strip('d"').replace("Z", "+00:00"))
    return value


class SurrealConnection:
    def __init__(self, client):
        self.client = client

    async def query(self, query, params=None):
        response = await self.client.query_raw(query, encode(params or {}))
        if "error" in response:
            raise RuntimeError(response["error"].get("message", "Database query failed"))
        for item in response["result"]:
            if item["status"] != "OK":
                raise RuntimeError(str(item["result"]))
        return decode(response["result"])

    async def rows(self, query, params=None):
        result = await self.query(query, params)
        return result[-1]["result"] if result else []

    async def create(self, key, data):
        return decode(await self.client.create(record(key), encode(data)))

    async def select(self, key):
        return decode(await self.client.select(record(key)))

    async def merge(self, key, data):
        return decode(await self.client.merge(record(key), encode(data)))

    async def close(self):
        await self.client.close()


async def create_surreal_connection(settings: Settings):
    client = AsyncSurreal(settings.surreal_url)
    await client.connect()
    await client.signin({"username": settings.surreal_user, "password": settings.surreal_password})
    await client.use(settings.surreal_namespace, settings.surreal_database)
    db = SurrealConnection(client)
    schema = Path(__file__).parents[4] / "migrations" / "social_graph.surql"
    await db.query(schema.read_text(encoding="utf-8"))
    return db
