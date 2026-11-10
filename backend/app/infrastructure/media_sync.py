"""Keeps a disk-less deployment (Render's free plan) in step with object storage.

Render's free web services lose their disk on every restart, sleep and
deploy. With ``OBJECT_STORE_*`` configured, this module makes the bucket the
durable copy of everything Phlio keeps on disk outside SurrealDB:

* **State** (``_state/`` in the *state* bucket, ``OBJECT_STORE_STATE_BUCKET``,
  which must be private; falls back to the media bucket for older setups):
  the SQLite databases (DM messages,
  social videos, music links, payments), DM attachments and snap photos
  (``media_private_memories``, never public). Restored on boot
  before the container opens them, then backed up every ``interval`` seconds
  and on shutdown (SQLite's online backup API, so writes in flight are safe).
* **Media** (bucket root, same paths as ``media/``): photos, videos and
  recordings. Files missing on disk are served by redirecting to
  ``MEDIA_PUBLIC_URL`` (see ``main.py``); files uploaded at runtime are pushed
  to the bucket on the next pass so they survive restarts too.

``scripts/publish_local_data.py`` seeds the bucket from a local machine.
"""
from __future__ import annotations

import asyncio
import logging
import sqlite3
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import suppress
from pathlib import Path

from app.config import Settings
from app.infrastructure.object_store import ObjectStore

log = logging.getLogger("phlio.media_sync")
BACKEND_ROOT = Path(__file__).resolve().parents[2]  # backend/
STATE_PREFIX = "_state/"


def store_from_settings(settings: Settings) -> ObjectStore | None:
    """The configured bucket, or None when object storage isn't set up."""
    if not (settings.object_store_endpoint and settings.object_store_bucket
            and settings.object_store_access_key and settings.object_store_secret_key):
        return None
    return ObjectStore(settings.object_store_endpoint, settings.object_store_bucket,
                       settings.object_store_access_key, settings.object_store_secret_key,
                       settings.object_store_region)


_warned_shared_state = False


def state_store_from_settings(settings: Settings) -> ObjectStore | None:
    """The bucket that holds private state: OBJECT_STORE_STATE_BUCKET when set.

    Falls back to the media bucket (how older deployments were set up) and
    warns once, because when that bucket is public its ``_state/`` objects
    (DMs, payments, private snaps) can be downloaded by anyone.
    """
    global _warned_shared_state
    store = store_from_settings(settings)
    if store is None or not settings.object_store_state_bucket:
        if store is not None and settings.media_public_url and not _warned_shared_state:
            _warned_shared_state = True
            log.warning("State is stored in the PUBLIC media bucket. Set OBJECT_STORE_STATE_BUCKET to a "
                        "private bucket and run `publish_local_data --only move-state`.")
        return store
    store.close()
    return ObjectStore(settings.object_store_endpoint, settings.object_store_state_bucket,
                       settings.object_store_access_key, settings.object_store_secret_key,
                       settings.object_store_region)


def _local(path: str) -> Path:
    """Resolves a settings path (relative ones are relative to backend/)."""
    p = Path(path)
    return p if p.is_absolute() else BACKEND_ROOT / p


def state_databases(settings: Settings) -> list[Path]:
    """SQLite files that live outside SurrealDB."""
    return [_local(p) for p in (settings.messaging_database, settings.social_video_database,
                                settings.music_database, settings.pay_gateway_database)]


def media_root(settings: Settings) -> Path:
    """The media folder served under /media."""
    return _local(settings.media_root)


def dm_root(settings: Settings) -> Path:
    """Where DM attachments are stored."""
    return _local(settings.messaging_media_root)


def private_memories_root(settings: Settings) -> Path:
    """Snap photos/videos: private, served only through the API (next to media/)."""
    root = media_root(settings)
    return root.parent / (root.name + "_private_memories")


def state_folders(settings: Settings) -> list[tuple[Path, str]]:
    """Private folders kept in the bucket under _state/: (local folder, bucket prefix)."""
    return [(dm_root(settings), STATE_PREFIX + "dm_files/"),
            (private_memories_root(settings), STATE_PREFIX + "private_memories/")]


def restore_state(settings: Settings, workers: int = 8) -> None:
    """Downloads missing SQLite databases and DM attachments from the bucket.

    Runs at startup, before anything opens the databases. Files that already
    exist locally are left alone (local development keeps its own copies).

    Boot time is the time until the API answers its first request, so the
    downloads run in parallel (``workers`` connections, one bucket client per
    thread so TLS connections are reused) instead of one file after another.
    """
    store = state_store_from_settings(settings)
    if store is None:
        return
    jobs: list[tuple[str, Path]] = []
    try:
        jobs += [(STATE_PREFIX + db.name, db) for db in state_databases(settings) if not db.exists()]
        for root, prefix in state_folders(settings):
            for obj in store.list(prefix):
                target = root / obj.key.removeprefix(prefix)
                if not target.exists():
                    jobs.append((obj.key, target))
    finally:
        store.close()
    if not jobs:
        return

    local = threading.local()
    clients: list[ObjectStore] = []
    lock = threading.Lock()

    def fetch(job: tuple[str, Path]) -> bool:
        client = getattr(local, "store", None)
        if client is None:
            client = local.store = state_store_from_settings(settings)
            with lock:
                clients.append(client)
        key, target = job
        try:
            return bool(client.get_file(key, target))
        except Exception:  # one bad object must not stop the boot
            log.exception("Could not restore %s", key)
            return False

    started = time.time()
    try:
        with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
            restored = sum(pool.map(fetch, jobs))
    finally:
        for client in clients:
            client.close()
    log.info("Restored %d/%d state files from object storage in %.1fs",
             restored, len(jobs), time.time() - started)


class StateSync:
    """Uploads changed state and new media to the bucket."""

    def __init__(self, settings: Settings) -> None:
        """Remembers what's on disk at boot so only new or changed files upload."""
        self.settings = settings
        self.started = time.time()
        self._seen: dict[Path, tuple[int, float]] = {}  # path -> (size, mtime) last uploaded
        for root in (media_root(settings), *(folder for folder, _ in state_folders(settings))):
            for path in _files(root):
                st = path.stat()
                self._seen[path] = (st.st_size, st.st_mtime)  # already in the bucket (or local-only)
        self._db_marks: dict[Path, tuple[int, float]] = {}

    def run_once(self) -> int:
        """One pass: back up changed databases, push new media and DM files. Returns uploads made."""
        store = store_from_settings(self.settings)
        if store is None:
            return 0
        state = state_store_from_settings(self.settings) or store
        uploads = 0
        try:
            for db in state_databases(self.settings):
                if not db.exists():
                    continue
                st = db.stat()
                wal = db.with_name(db.name + "-wal")
                mark = (st.st_size + (wal.stat().st_size if wal.exists() else 0),
                        max(st.st_mtime, wal.stat().st_mtime if wal.exists() else 0))
                if self._db_marks.get(db) == mark:
                    continue
                with tempfile.TemporaryDirectory() as tmp:
                    copy = Path(tmp) / db.name
                    _backup(db, copy)
                    state.put_file(STATE_PREFIX + db.name, copy, "application/vnd.sqlite3")
                self._db_marks[db] = mark
                uploads += 1
            targets = [(media_root(self.settings), "", store),
                       *((root, prefix, state) for root, prefix in state_folders(self.settings))]
            for root, prefix, target in targets:
                for path in _files(root):
                    st = path.stat()
                    if self._seen.get(path) == (st.st_size, st.st_mtime) or time.time() - st.st_mtime < 3:
                        continue  # unchanged, or still being written
                    target.put_file(prefix + path.relative_to(root).as_posix(), path)
                    self._seen[path] = (st.st_size, st.st_mtime)
                    uploads += 1
        finally:
            if state is not store:
                state.close()
            store.close()
        return uploads


def _files(root: Path) -> list[Path]:
    """Regular files under ``root`` (skipping temp / partial files)."""
    if not root.exists():
        return []
    return [p for p in root.rglob("*") if p.is_file() and not p.name.endswith((".part", ".tmp"))]


def _backup(source: Path, target: Path) -> None:
    """Consistent copy of a live SQLite database (online backup API)."""
    src = sqlite3.connect(source)
    dst = sqlite3.connect(target)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()


async def run(settings: Settings, interval: float = 60) -> None:
    """Background task: sync every ``interval`` seconds, and once more when cancelled."""
    if store_from_settings(settings) is None:
        return
    sync = StateSync(settings)
    try:
        while True:
            await asyncio.sleep(interval)
            try:
                n = await asyncio.to_thread(sync.run_once)
                if n:
                    log.info("Synced %d files to object storage", n)
            except Exception:  # keep syncing after a network blip
                log.exception("Object storage sync failed")
    except asyncio.CancelledError:
        with suppress(Exception):
            await asyncio.to_thread(sync.run_once)  # final backup on shutdown
        raise
