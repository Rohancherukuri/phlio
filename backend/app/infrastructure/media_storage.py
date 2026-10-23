"""Local media storage for room file uploads.

Files stream to disk in fixed-size chunks so multi-hundred-MB documents
never materialize in memory (FastAPI's UploadFile already spools to a
temp file; we shard it further while copying). Layout:

    <media_root>/rooms/<room_id>/<nanoid>-<safe-name>

The room scoping keeps listing/quota simple later; the id prefix makes
name collisions impossible without a stat round-trip. URLs stored on
attachments are origin-relative (`/media/...`) so the API stays
deploy-host agnostic; StaticFiles serves the directory (main.py).
"""

from __future__ import annotations

import re
import unicodedata
import uuid
from pathlib import Path

CHUNK = 1024 * 1024  # 1 MiB streaming chunks

_SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]+")
_MAX_NAME_LEN = 96


class MediaStorage:
    def __init__(self, root: Path) -> None:
        self._root = root

    @property
    def root(self) -> Path:
        return self._root

    def _dir_for(self, room_id: str) -> Path:
        # room ids are engine-generated (`rm_...`), but never trust that in
        # a filesystem path — keep the bare alnum tail.
        safe_room = _SAFE_NAME.sub("", room_id)[-32:] or "unknown"
        return self._root / "rooms" / safe_room

    @staticmethod
    def safe_name(name: str) -> str:
        name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
        name = _SAFE_NAME.sub("-", name).strip(".-")
        return (name or "file")[-_MAX_NAME_LEN:]

    async def save(self, *, room_id: str, filename: str, content) -> tuple[str, int]:
        """Stream a file object into the media root in 1 MiB chunks.

        Accepts async readers (FastAPI's UploadFile) and plain sync files
        (tests, local copies). Returns (origin-relative url, byte size).
        """
        import inspect

        target_dir = self._dir_for(room_id)
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / f"{uuid.uuid4().hex[:12]}-{self.safe_name(filename)}"
        written = 0

        with target.open("wb") as out:
            while True:
                result = content.read(CHUNK)
                chunk = await result if inspect.isawaitable(result) else result
                if not chunk:
                    break
                out.write(chunk)
                written += len(chunk)
        return f"/media/rooms/{target_dir.name}/{target.name}", written
