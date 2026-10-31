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
        # "table:key" with the raw key, so record() turns it back into the same
        # RecordID. (str() would give "table:⟨key⟩" for keys with "-", and each
        # read → write round trip would wrap the key in another pair of ⟨⟩.)
        if isinstance(value.id, (str, int)):
            return f"{value.table_name}:{value.id}"
        return str(value)
    if isinstance(value, dict):
        return {k: decode(v) for k, v in value.items()}
    if isinstance(value, list):
        return [decode(v) for v in value]
    if type(value).__name__ == "Datetime":
        return dt.datetime.fromisoformat(str(value).strip('d"').replace("Z", "+00:00"))
    return value


_MISSING_TABLE = re.compile(r"The table '([A-Za-z_][A-Za-z0-9_]*)' does not exist")


class SurrealConnection:
    def __init__(self, client):
        self.client = client

    async def query(self, query, params=None):
        # SurrealDB 3 reports an error when a SELECT reads a table nobody has
        # written to yet (2.x returned no rows). Tables here are created on
        # first write, so define the missing one (schemaless, as 2.x would)
        # and run the query again. Bounded, in case several are missing.
        for _ in range(8):
            try:
                return await self._query(query, params)
            except RuntimeError as error:
                missing = _MISSING_TABLE.search(str(error))
                if not missing:
                    raise
                await self._query(f"DEFINE TABLE IF NOT EXISTS {missing.group(1)} SCHEMALESS;")
        return await self._query(query, params)

    async def _query(self, query, params=None):
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
