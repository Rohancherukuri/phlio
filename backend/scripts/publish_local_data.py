"""Copy everything the local Phlio backend has into the cloud, for the Render deploy.

Three parts, each optional:

1. **Database**: exports the local SurrealDB (``phlio_graph_dev``, the one
   Start-GraphDemo.ps1 runs on port 8001) with the ``surreal`` CLI and imports
   it into a Surreal Cloud instance.
2. **Media**: uploads ``backend/media`` (photos, videos, recordings, seeded
   Spaces…) to the object storage bucket, at the same paths, so the deployed
   API can redirect ``/media/...`` to the bucket's public URL. Resumable:
   files already uploaded with the same size are skipped.
3. **State**: uploads consistent copies of the SQLite databases (DMs, social
   videos, music, payments) and the DM attachments to ``_state/`` in the
   bucket. The deployed API restores them on boot and keeps backing them up.

Credentials come from ``backend/.env.publish`` (never commit it) or the
environment. Keep them out of ``backend/.env``: that file configures the
local API, and object storage settings there would make your local API sync
to the cloud too.

    OBJECT_STORE_ENDPOINT=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
    OBJECT_STORE_BUCKET=phlio-media
    OBJECT_STORE_ACCESS_KEY=...
    OBJECT_STORE_SECRET_KEY=...
    SURREAL_CLOUD_ENDPOINT=wss://<instance>.surreal.cloud
    SURREAL_CLOUD_USER=...            (a root/system user created in Surreal Cloud)
    SURREAL_CLOUD_PASSWORD=...

Run from ``backend/`` with the local stack started (Start-GraphDemo.ps1):

    uv run python -m scripts.publish_local_data            # everything
    uv run python -m scripts.publish_local_data --only db  # or media / state
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import httpx

from app.config import Settings
from app.infrastructure.media_sync import STATE_PREFIX, dm_root, media_root, state_databases
from app.infrastructure.object_store import ObjectStore

BACKEND = Path(__file__).resolve().parent.parent
EXPORT_DIR = BACKEND / "data" / "export"
SKIP_NAMES = {"desktop.ini", "Thumbs.db", ".DS_Store"}
_RELATION_FIELD = re.compile(r"^DEFINE FIELD (in|out) ON ")


def load_publish_env(path: Path) -> None:
    """Adds KEY=VALUE lines from ``path`` to os.environ (existing variables win)."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def need(name: str) -> str:
    """An environment variable that must be set, or a clear exit message."""
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"Set {name} in backend/.env.publish (see the top of this script).")
    return value


def bucket() -> ObjectStore:
    """The object storage bucket from OBJECT_STORE_* variables."""
    return ObjectStore(need("OBJECT_STORE_ENDPOINT"), need("OBJECT_STORE_BUCKET"),
                       need("OBJECT_STORE_ACCESS_KEY"), need("OBJECT_STORE_SECRET_KEY"),
                       os.environ.get("OBJECT_STORE_REGION", "auto"))


def human(n: float) -> str:
    """Bytes as KB / MB / GB."""
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024
    return f"{n:.1f} GB"


# -- 1. database --------------------------------------------------------------------


_RECORD_START = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*:⟨")
_ID_END_NEXT = set(",]}); \t\r\n")


def _fix_bracket_ids(line: str) -> str:
    """Rewrites record ids like ``t:⟨⟨x\⟩⟩`` as ``t:`⟨x⟩```.

    Older API builds read ids back as ``t:⟨x⟩`` and re-used that text as a key,
    so some ids (live sessions) collected nested ⟨⟩ with ``\⟩`` escapes, which
    neither SurrealDB 2.x nor 3.x can parse back. Back-ticked ids need no ⟩
    escaping. Ids without a backslash are left exactly as exported.
    """
    out: list[str] = []
    pos = 0
    for match in _RECORD_START.finditer(line):
        if match.start() < pos:
            continue
        end = match.end()
        # The id ends at a ⟩ that isn't escaped and is followed by , ] } ) or space.
        while end < len(line) and not (
                line[end] == "⟩" and line[end - 1] != "\\" and (end + 1 == len(line) or line[end + 1] in _ID_END_NEXT)):
            end += 1
        inner = line[match.end():end]
        if end >= len(line) or "\\" not in inner:
            continue
        text = re.sub(r"\\(.)", r"\1", inner).replace("\\", "\\\\").replace("`", "\\`")
        out += [line[pos:match.start()], match.group(0)[:-1], "`", text, "`"]
        pos = end + 1
    out.append(line[pos:])
    return "".join(out)


def prepare_dump(source: Path, target: Path, drop_tables: set[str], v3: bool) -> None:
    """Copies a ``surreal export`` file so it imports cleanly into a fresh database.

    * Relation tables (``TYPE RELATION``) already define their ``in`` / ``out``
      fields, so the export's own ``DEFINE FIELD in|out`` lines would fail the
      import; they're rewritten as ``DEFINE FIELD OVERWRITE``.
    * Record ids with escaped nested ⟨⟩ are rewritten (see ``_fix_bracket_ids``).
    * For SurrealDB 3.x (``v3``): 2.x exports mark relation records with
      ``__: true``, which 3.x rejects on SCHEMAFULL tables; the marker is removed.
    * Records of ``drop_tables`` are left out. Exports mark each table's
      records with a ``-- TABLE DATA: <name>`` header; everything from there to
      the next ``-- TABLE:`` header is skipped. Definitions stay (empty tables).
    """
    skipping = False
    with source.open(encoding="utf-8") as src, target.open("w", encoding="utf-8") as out:
        for line in src:
            if line.startswith("-- TABLE DATA:"):
                skipping = line.split(":", 1)[1].strip() in drop_tables
            elif line.startswith("-- TABLE:"):
                skipping = False
            if skipping:
                continue
            line = _RELATION_FIELD.sub(r"DEFINE FIELD OVERWRITE \1 ON ", line)
            if "⟨" in line:
                line = _fix_bracket_ids(line)
            if v3 and line.startswith("INSERT RELATION"):
                line = line.replace("{ __: true, ", "{ ")
            out.write(line)


def _major(version: str) -> int | None:
    """Major version from "surrealdb-2.3.10" / "2.3.10 for windows on x86_64"."""
    found = re.search(r"(\d+)\.\d+\.\d+", version)
    return int(found.group(1)) if found else None


def check_cloud(cli: str, endpoint: str, auth: list[str]) -> int:
    """Checks the Surreal Cloud instance before importing; returns its major version.

    ``surreal import`` only reports "400 Bad Request", which hides the real
    reason. This asks the instance directly:

    * ``GET /version``: the instance must be awake, and the local ``surreal``
      CLI must have the same major version (a 2.x CLI can't talk to 3.x).
    * ``POST /signin``: the user and password must be a root (system) user
      of the instance; the server's own message is shown if they aren't.
    """
    try:
        with httpx.Client(timeout=30) as http:
            server = http.get(f"{endpoint}/version").text.strip()
            print(f"  local CLI {cli or '?'} · cloud {server or '?'}")
            cli_major, server_major = _major(cli), _major(server)
            if server_major is None:
                sys.exit(f"\n{endpoint} didn't answer like SurrealDB ({server[:120]!r}). Check SURREAL_CLOUD_ENDPOINT.")
            if cli_major is not None and cli_major != server_major:
                fix = (r"Run .\scripts\Upgrade-SurrealDB3.ps1 (moves your local database to 3.x and installs the 3.x CLI), "
                       "then run this again." if server_major >= 3 > cli_major else
                       f"Create the Surreal Cloud instance with SurrealDB {cli_major}.x instead.")
                sys.exit(f"\nVersion mismatch: your surreal CLI is {cli} but the cloud instance runs {server}.\n{fix}")
            if "--token" not in auth:
                user, password = auth[auth.index("--username") + 1], auth[auth.index("--password") + 1]
                res = http.post(f"{endpoint}/signin", json={"user": user, "pass": password},
                                headers={"Accept": "application/json"})
                if res.status_code != 200:
                    sys.exit(
                        f"\nSurreal Cloud refused the sign-in ({res.status_code}): {res.text.strip()[:300]}\n"
                        "SURREAL_CLOUD_USER / SURREAL_CLOUD_PASSWORD must be a root (system) user of this instance:\n"
                        "in Surreal Cloud open the instance → Authentication (or Users) → add a user at Root level\n"
                        "with the Owner role, and put its name and password in backend/.env.publish.")
                print("  signed in")
            return server_major
    except httpx.HTTPError as error:
        sys.exit(f"\nCan't reach {endpoint}: {error}\n"
                 "Check SURREAL_CLOUD_ENDPOINT and that the instance isn't paused (Resume it in Surreal Cloud).")


def export_database(settings: Settings, surreal: str, slim: bool, v3: bool) -> Path:
    """Exports the local SurrealDB and returns the file prepared for import."""
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    dump = EXPORT_DIR / f"{settings.surreal_database}.surql"
    local = settings.surreal_url.replace("ws://", "http://").replace("wss://", "https://").removesuffix("/rpc")
    print(f"Exporting {settings.surreal_namespace}/{settings.surreal_database} from {local} …")
    subprocess.run([surreal, "export", "--endpoint", local, "--username", settings.surreal_user,
                    "--password", settings.surreal_password, "--namespace", settings.surreal_namespace,
                    "--database", settings.surreal_database, str(dump)], check=True)
    print(f"  export: {human(dump.stat().st_size)}")
    # Delivered event-outbox rows are history only; --slim leaves them out to
    # stay well inside Surreal Cloud's free 1 GB.
    prepared = dump.with_name(f"{dump.stem}{'.slim' if slim else ''}.v{3 if v3 else 2}.import.surql")
    prepare_dump(dump, prepared, {"graph_outbox"} if slim else set(), v3)
    print(f"  ready to import into SurrealDB {3 if v3 else 2}.x: {prepared} ({human(prepared.stat().st_size)})")
    if prepared.stat().st_size > 900 * 1024 * 1024:
        print("  Warning: this is close to the free 1 GB limit; try --slim.")
    return prepared


def surreal_cli() -> tuple[str, str]:
    """Path and version text of the ``surreal`` CLI on PATH."""
    surreal = shutil.which("surreal")
    if not surreal:
        sys.exit("The surreal CLI isn't on PATH (Start-GraphDemo.ps1 uses the same one).")
    return surreal, subprocess.run([surreal, "version"], capture_output=True, text=True).stdout.strip()


def publish_database(settings: Settings, slim: bool) -> None:
    """Exports the local SurrealDB and imports it into Surreal Cloud."""
    surreal, cli = surreal_cli()
    # The CLI imports over HTTP(S); accept the wss:// address Surreal Cloud shows too.
    endpoint = need("SURREAL_CLOUD_ENDPOINT").replace("wss://", "https://").replace("ws://", "http://").removesuffix("/rpc")
    auth = (["--token", os.environ["SURREAL_CLOUD_TOKEN"]] if os.environ.get("SURREAL_CLOUD_TOKEN")
            else ["--username", need("SURREAL_CLOUD_USER"), "--password", need("SURREAL_CLOUD_PASSWORD")])
    print(f"Checking {endpoint} …")
    major = check_cloud(cli, endpoint, auth)
    dump = export_database(settings, surreal, slim, v3=major >= 3)
    print(f"Importing into {endpoint} …")
    subprocess.run([surreal, "import", "--endpoint", endpoint, *auth, "--namespace", settings.surreal_namespace,
                    "--database", settings.surreal_database, str(dump)], check=True)
    print("  database imported")


# -- 2. media -----------------------------------------------------------------------


def publish_media(settings: Settings, workers: int) -> None:
    """Uploads backend/media to the bucket root (skips files already there)."""
    root = media_root(settings)
    files = [p for p in root.rglob("*") if p.is_file() and p.name not in SKIP_NAMES and not p.name.endswith(".part")]
    total = sum(p.stat().st_size for p in files)
    print(f"Media: {len(files)} files, {human(total)} in {root}")
    done = skipped = 0
    sent = 0
    started = time.time()

    def upload(path: Path) -> tuple[Path, bool]:
        """Uploads one file unless the bucket already has it at the same size."""
        store = bucket()
        try:
            key = path.relative_to(root).as_posix()
            if store.head(key) == path.stat().st_size:
                return path, False
            store.put_file(key, path)
            return path, True
        finally:
            store.close()

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for future in as_completed(pool.submit(upload, p) for p in files):
            path, uploaded = future.result()
            done += 1
            if uploaded:
                sent += path.stat().st_size
            else:
                skipped += 1
            rate = sent / max(1.0, time.time() - started)
            print(f"\r  {done}/{len(files)} files · {human(sent)} sent · {human(rate)}/s · {skipped} already there",
                  end="", flush=True)
    print()


# -- 3. state -----------------------------------------------------------------------


def publish_state(settings: Settings) -> None:
    """Uploads SQLite snapshots and DM attachments to _state/ in the bucket."""
    store = bucket()
    try:
        with tempfile.TemporaryDirectory() as tmp:
            for db in state_databases(settings):
                if not db.exists():
                    print(f"  (no {db.name} yet)")
                    continue
                copy = Path(tmp) / db.name
                src, dst = sqlite3.connect(db), sqlite3.connect(copy)
                try:
                    src.backup(dst)  # consistent even while the local API is running
                finally:
                    dst.close()
                    src.close()
                store.put_file(STATE_PREFIX + db.name, copy, "application/vnd.sqlite3")
                print(f"  {db.name}: {human(copy.stat().st_size)}")
        root = dm_root(settings)
        files = [p for p in root.rglob("*") if p.is_file()] if root.exists() else []
        for path in files:
            store.put_file(STATE_PREFIX + "dm_files/" + path.relative_to(root).as_posix(), path)
        print(f"  DM attachments: {len(files)}")
    finally:
        store.close()


def main() -> None:
    """Parses arguments and runs the chosen parts."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", choices=["db", "media", "state"], action="append",
                        help="run only these parts (repeatable); default: all three")
    parser.add_argument("--slim", action="store_true", help="leave event-outbox history out of the database import")
    parser.add_argument("--workers", type=int, default=4, help="parallel media uploads")
    parser.add_argument("--export-only", choices=["2", "3"],
                        help="only export the local database, prepared for SurrealDB 2.x or 3.x (no upload)")
    args = parser.parse_args()
    os.chdir(BACKEND)  # Settings() reads backend/.env; relative paths are relative to backend/
    load_publish_env(BACKEND / ".env.publish")
    settings = Settings()
    if args.export_only:
        surreal, _ = surreal_cli()
        export_database(settings, surreal, args.slim, v3=args.export_only == "3")
        return
    parts = set(args.only or ["db", "media", "state"])
    if "db" in parts:
        publish_database(settings, args.slim)
    if "state" in parts:
        print("State (SQLite databases + DM files):")
        publish_state(settings)
    if "media" in parts:
        publish_media(settings, args.workers)
    print("Done.")


if __name__ == "__main__":
    main()
