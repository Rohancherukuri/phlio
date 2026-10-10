import copy
import datetime as dt
import uuid

from app.infrastructure.database.surreal.client import record

TABLES = {
    "shared_story",
    "platform_content",
    "graph_group",
    "graph_group_message",
    "phlio_object",
    "friend",
    "follows",
    "block",
    "activity",
    "graph_member",
    "object_link",
    "privacy_policy",
    "phlio_note",
    "object_alias",
    "graph_audit",
    "graph_outbox",
}
EDGES = {"friend", "follows", "block", "activity", "graph_member", "object_link"}


def now():
    return dt.datetime.now(dt.UTC).isoformat()


class MemoryGraphStore:
    """Isolated test double with the same transactional revision contract."""

    def __init__(self):
        self.data = {name: {} for name in TABLES}
        self.version = 0
        self.db = None

    async def get(self, key):
        table = key.split(":", 1)[0]
        return copy.deepcopy(self.data[table].get(key))

    async def rows(self, table, filters=None):
        return [
            copy.deepcopy(v)
            for v in self.data[table].values()
            if all(v.get(k) == value for k, value in (filters or {}).items())
        ]

    async def put(self, key, data):
        table = key.split(":", 1)[0]
        assert table in TABLES
        self.data[table][key] = dict(copy.deepcopy(data), id=key)
        if table not in {"graph_audit", "graph_outbox"}:
            self.version += 1
            event_id = "graph_outbox:" + uuid.uuid4().hex
            self.data["graph_outbox"][event_id] = dict(
                id=event_id, event=table, entity=key, created_at=now(), delivered=False
            )
        return await self.get(key)

    async def delete(self, key):
        self.data[key.split(":", 1)[0]].pop(key, None)
        self.version += 1
        event_id = "graph_outbox:" + uuid.uuid4().hex
        self.data["graph_outbox"][event_id] = dict(
            id=event_id, event="deleted", entity=key, created_at=now(), delivered=False
        )

    async def revision(self):
        return self.version


class SurrealGraphStore:
    def __init__(self, db):
        self.db = db

    async def get(self, key):
        assert key.split(":", 1)[0] in TABLES
        value = await self.db.select(key)
        return value[0] if isinstance(value, list) and value else value or None

    async def rows(self, table, filters=None):
        assert table in TABLES
        # Only internal, fixed field names reach this method.
        filters = filters or {}
        clauses = []
        params = {}
        for index, (key, value) in enumerate(filters.items()):
            assert key.replace("_", "").isalnum()
            clauses.append(f"{key} = $p{index}")
            params[f"p{index}"] = record(value) if key in {"in", "out"} else value
        query = f"SELECT * FROM {table}" + (" WHERE " + " AND ".join(clauses) if clauses else "")
        return await self.db.rows(query, params)

    async def put(self, key, data):
        table = key.split(":", 1)[0]
        assert table in TABLES
        data = {k: v for k, v in data.items() if k != "id" and v is not None}
        params = {"rid": record(key), "data": data}
        if table in EDGES:
            params.update(source=record(data["in"]), target=record(data["out"]))
            write = "RELATE $source->$rid->$target CONTENT $data;"
        else:
            write = "UPSERT $rid CONTENT $data;"
        event = ""
        if table not in {"graph_audit", "graph_outbox"}:
            params["event"] = dict(event=table, entity=key, created_at=now(), delivered=False)
            event = "CREATE graph_outbox CONTENT $event;"
        revision = " UPDATE graph_meta:revision SET value += 1;" if event else ""
        await self.db.query("BEGIN TRANSACTION; " + write + event + revision + " COMMIT TRANSACTION;", params)
        return await self.get(key)

    async def delete(self, key):
        assert key.split(":", 1)[0] in TABLES
        await self.db.query(
            "BEGIN TRANSACTION; DELETE $rid; CREATE graph_outbox CONTENT $event; "
            "UPDATE graph_meta:revision SET value += 1; COMMIT TRANSACTION;",
            {
                "rid": record(key),
                "event": dict(event="deleted", entity=key, created_at=now(), delivered=False),
            },
        )

    async def revision(self):
        rows = await self.db.rows("SELECT * FROM graph_meta:revision")
        return rows[0]["value"]
