import asyncio
import random
import time

import copy
import datetime as dt
import uuid

from app.infrastructure.database.surreal.client import record

TABLES = {
    "avatar_config",
    "filter_preset",
    "fact_note",
    "fact_rating",
    "membership_plan",
    "membership",
    "membership_order",
    "shop_tracking",
    "status_note",
    "stream_catalog_state",
    "memory_seen",
    "memory_reaction",
    "social_memory",
    "clip_feedback",
    "content_report",
    "live_session",
    "live_recording",
    "scheduled_space",
    "social_poll",
    "social_poll_vote",
    "giphy_selection",
    "playlist",
    "playlist_item",
    "shop_cart",
    "content_comment",
    "comment_tombstone",
    "comment_edit",
    "share_event",
    "space_report",
    "space_request",
    "space_recording",
    "comment_reaction",
    "shared_story",
    "social_moment",
    "moment_view",
    "moment_highlight",
    "moment_mute",
    "moment_response",
    "moment_reaction",
    "moment_comment",
    "phlio_notification",
    "notification_state",
    "saved_place",
    "room_reply",
    "room_pin",
    "social_blend",
    "watch_party",
    "timeline_task",
    "phlio_activity",
    "activity_kudos",
    "live_location",
    "profile_style",
    "chat_theme",
    "account_setting",
    "two_factor",
    "oauth_identity",
    "snap_list",
    "room_profile",
    "suggestion_hidden",
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

    async def get_many(self, keys):
        return [value for key in keys if (value := await self.get(key)) is not None]

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
    """Graph store on SurrealDB.

    Read caching (why): a hosted database is a network round trip away (about
    65 ms from Render Singapore to Surreal Cloud Mumbai), and screens such as
    Stream or a post's engagement bar read the same records many times per
    request. Two small in-process caches remove most of those round trips:

    * ``revision()`` (used as a cache key all over the API) is reused for
      ``REVISION_TTL`` seconds;
    * ``get(key)`` results are reused for ``READ_TTL`` seconds.

    Every write through this store (``put``/``delete``) drops the cached record
    and revision first, so this process always reads its own writes. Writes
    made by *other* processes (a seeding script) become visible within the
    TTL, which is the same freshness the API's response caches already have.
    """

    REVISION_TTL = 1.0
    READ_TTL = 2.0
    READ_CACHE_MAX = 20_000

    def __init__(self, db):
        self.db = db
        self._write_lock = asyncio.Lock()
        self._revision: tuple[float, object] | None = None
        self._reads: dict[str, tuple[float, object]] = {}

    def _forget(self, key=None):
        self._revision = None
        if key is not None:
            self._reads.pop(key, None)

    async def _transaction(self, query, params):
        # All graph writes touch the shared revision record. Serialise this
        # process, then back off for competing API/seeder processes. Retry only
        # explicit commit conflicts (rolled back), never ambiguous network errors.
        async with self._write_lock:
            for attempt in range(8):
                try:
                    return await self.db.query(query, params)
                except RuntimeError as exc:
                    message = str(exc).lower()
                    conflict = ('failed to commit transaction' in message
                                and 'read or write conflict' in message)
                    if not conflict or attempt == 7:
                        raise
                    await asyncio.sleep(random.uniform(.5, 1.0) * min(.025 * 2**attempt, .8))

    async def get(self, key):
        assert key.split(":", 1)[0] in TABLES
        hit = self._reads.get(key)
        if hit and time.monotonic() - hit[0] < self.READ_TTL:
            return copy.deepcopy(hit[1])
        value = await self.db.select(key)
        value = value[0] if isinstance(value, list) and value else value or None
        if len(self._reads) >= self.READ_CACHE_MAX:
            self._reads.clear()  # rare; cheaper than tracking LRU order
        self._reads[key] = (time.monotonic(), copy.deepcopy(value))
        return value

    async def get_many(self, keys):
        if not keys:
            return []
        table = keys[0].split(':', 1)[0]
        assert table in TABLES and all(k.split(':', 1)[0] == table for k in keys)
        return await self.db.rows(f'SELECT * FROM {table} WHERE id IN $ids',
                                  {'ids': [record(k) for k in keys]})

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
        self._forget(key)
        try:
            await self._transaction("BEGIN TRANSACTION; " + write + event + revision + " COMMIT TRANSACTION;", params)
        finally:
            self._forget(key)
        return await self.get(key)

    async def delete(self, key):
        assert key.split(":", 1)[0] in TABLES
        self._forget(key)
        await self._transaction(
            "BEGIN TRANSACTION; DELETE $rid; CREATE graph_outbox CONTENT $event; "
            "UPDATE graph_meta:revision SET value += 1; COMMIT TRANSACTION;",
            {
                "rid": record(key),
                "event": dict(event="deleted", entity=key, created_at=now(), delivered=False),
            },
        )
        self._forget(key)

    async def revision(self):
        hit = self._revision
        if hit and time.monotonic() - hit[0] < self.REVISION_TTL:
            return hit[1]
        rows = await self.db.rows("SELECT * FROM graph_meta:revision")
        value = rows[0]["value"]
        self._revision = (time.monotonic(), value)
        return value
