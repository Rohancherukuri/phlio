"""Files the user hands Foxy in the Agent chat: photos, clips, audio and
documents (PDF, Word/Excel/PowerPoint, plain text, Markdown, CSV, JSON).

Uploads are stored privately per owner next to the DM media
(`<messaging_media_root>/agent/<id>` + a `<id>.json` sidecar). For
documents a short plain-text excerpt is pulled out at upload time so the
agent can talk about the file without re-reading it.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import uuid
import zipfile
from dataclasses import asdict, dataclass
from pathlib import Path

from fastapi import HTTPException

FORMATS: dict[str, tuple[str, str]] = {
    ".jpg": ("image", "image/jpeg"), ".jpeg": ("image", "image/jpeg"), ".png": ("image", "image/png"),
    ".gif": ("image", "image/gif"), ".webp": ("image", "image/webp"), ".heic": ("image", "image/heic"),
    ".mp4": ("video", "video/mp4"), ".mov": ("video", "video/quicktime"), ".webm": ("video", "video/webm"),
    ".m4v": ("video", "video/mp4"),
    ".mp3": ("audio", "audio/mpeg"), ".m4a": ("audio", "audio/mp4"), ".wav": ("audio", "audio/wav"),
    ".ogg": ("audio", "audio/ogg"), ".aac": ("audio", "audio/aac"),
    ".pdf": ("document", "application/pdf"),
    ".docx": ("document", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
    ".xlsx": ("document", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
    ".pptx": ("document", "application/vnd.openxmlformats-officedocument.presentationml.presentation"),
    ".txt": ("text", "text/plain"), ".md": ("text", "text/markdown"), ".csv": ("text", "text/csv"),
    ".json": ("text", "application/json"),
}
LIMITS = {"image": 10_000_000, "video": 100_000_000, "audio": 25_000_000,
          "document": 20_000_000, "text": 2_000_000}
EXCERPT = 4000


@dataclass(slots=True)
class AgentAttachment:
    id: str
    owner_id: str
    kind: str
    name: str
    mime: str
    size: int
    url: str
    pages: int | None = None
    words: int | None = None
    excerpt: str = ""

    def public(self) -> dict:
        data = asdict(self)
        data.pop("owner_id")
        data["excerpt"] = self.excerpt[:280]
        return data


def classify(name: str) -> tuple[str, str]:
    ext = Path(name).suffix.lower()
    if ext not in FORMATS:
        raise HTTPException(
            422, "Foxy can read photos, videos, audio, PDFs, Word/Excel/PowerPoint and text files.")
    return FORMATS[ext]


def check_size(kind: str, size: int) -> None:
    if size <= 0:
        raise HTTPException(422, "That file is empty.")
    if size > LIMITS[kind]:
        raise HTTPException(413, f"{kind.capitalize()} files must be {LIMITS[kind] // 1_000_000} MB or smaller.")


def check_signature(path: Path, mime: str, kind: str) -> None:
    head = path.open("rb").read(32)
    ok = {
        "image/jpeg": head.startswith(b"\xff\xd8\xff"),
        "image/png": head.startswith(b"\x89PNG\r\n\x1a\n"),
        "image/gif": head.startswith((b"GIF87a", b"GIF89a")),
        "image/webp": head.startswith(b"RIFF") and head[8:12] == b"WEBP",
        "image/heic": head[4:8] == b"ftyp",
        "video/mp4": head[4:8] == b"ftyp",
        "video/quicktime": head[4:8] in (b"ftyp", b"moov", b"wide", b"mdat"),
        "video/webm": head.startswith(b"\x1aE\xdf\xa3"),
        "audio/mp4": head[4:8] == b"ftyp",
        "audio/wav": head.startswith(b"RIFF") and head[8:12] == b"WAVE",
        "audio/ogg": head.startswith(b"OggS"),
        "audio/mpeg": head.startswith(b"ID3") or (len(head) > 1 and head[0] == 255 and head[1] & 224 == 224),
        "audio/aac": len(head) > 1 and head[0] == 255 and head[1] & 240 == 240,
        "application/pdf": head.startswith(b"%PDF"),
    }.get(mime)
    if ok is None and kind == "document":  # Office files are zip containers
        ok = head.startswith(b"PK\x03\x04")
    if ok is None and kind == "text":
        try:
            path.read_bytes()[:EXCERPT * 4].decode("utf-8")
            ok = b"\x00" not in head
        except UnicodeDecodeError:
            ok = False
    if not ok:
        raise HTTPException(422, "The file contents don't match its type.")


def _xml_text(data: bytes) -> str:
    text = re.sub(rb"</(w:p|a:p|row)>", b"\n", data)
    text = re.sub(rb"<[^>]+>", b" ", text)
    return re.sub(r"[ \t]+", " ", text.decode("utf-8", "ignore")).strip()


def read_document(path: Path, mime: str, kind: str) -> tuple[str, int | None]:
    """Best-effort plain text + page count. Never raises."""
    try:
        if kind == "text":
            return path.read_bytes()[: EXCERPT * 4].decode("utf-8", "ignore"), None
        if mime == "application/pdf":
            raw = path.read_bytes()
            pages = len(re.findall(rb"/Type\s*/Page[^s]", raw)) or None
            text = ""
            if shutil.which("pdftotext"):
                out = subprocess.run(["pdftotext", "-l", "8", "-enc", "UTF-8", str(path), "-"],
                                     capture_output=True, timeout=20)
                text = out.stdout.decode("utf-8", "ignore")
            return text, pages
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
            if "word/document.xml" in names:
                return _xml_text(z.read("word/document.xml")), None
            slides = sorted(n for n in names if re.fullmatch(r"ppt/slides/slide\d+\.xml", n))
            if slides:
                return "\n".join(_xml_text(z.read(n)) for n in slides[:30]), len(slides)
            if "xl/sharedStrings.xml" in names:
                return _xml_text(z.read("xl/sharedStrings.xml")), None
    except Exception:  # noqa: BLE001 — previews are best-effort
        pass
    return "", None


class AgentFileStore:
    def __init__(self, root: Path) -> None:
        self.root = root / "agent"

    def save(self, owner_id: str, name: str, source, url_prefix: str) -> AgentAttachment:
        kind, mime = classify(name)
        self.root.mkdir(parents=True, exist_ok=True)
        file_id = uuid.uuid4().hex
        path = self.root / file_id
        size = 0
        try:
            with path.open("wb") as out:
                while chunk := source.read(1024 * 1024):
                    size += len(chunk)
                    check_size(kind, size)
                    out.write(chunk)
            check_size(kind, size)
            check_signature(path, mime, kind)
        except BaseException:
            path.unlink(missing_ok=True)
            raise
        excerpt, pages = ("", None)
        if kind in ("document", "text"):
            excerpt, pages = read_document(path, mime, kind)
        excerpt = re.sub(r"\s+\n", "\n", excerpt).strip()
        safe = re.sub(r"[^\w.\- ()]+", "_", Path(name).name)[:120] or "file"
        item = AgentAttachment(
            id=file_id, owner_id=owner_id, kind=kind, name=safe, mime=mime, size=size,
            url=f"{url_prefix}/{file_id}", pages=pages,
            words=len(excerpt.split()) if excerpt else None, excerpt=excerpt[:EXCERPT])
        (self.root / f"{file_id}.json").write_text(json.dumps(asdict(item)))
        return item

    def get(self, owner_id: str, file_id: str) -> AgentAttachment | None:
        if not re.fullmatch(r"[0-9a-f]{32}", file_id):
            return None
        meta = self.root / f"{file_id}.json"
        if not meta.exists():
            return None
        item = AgentAttachment(**json.loads(meta.read_text()))
        return item if item.owner_id == owner_id else None

    def path(self, file_id: str) -> Path:
        return self.root / file_id


def describe(items: list[AgentAttachment], question: str) -> str:
    """Foxy's acknowledgement of what was attached (+ a quick look at docs)."""
    if not items:
        return ""
    counts: dict[str, int] = {}
    for a in items:
        counts[a.kind] = counts.get(a.kind, 0) + 1
    label = {"image": ("photo", "photos"), "video": ("clip", "clips"), "audio": ("audio file", "audio files"),
             "document": ("document", "documents"), "text": ("text file", "text files")}
    parts = [f"{n} {label[k][0] if n == 1 else label[k][1]}" for k, n in counts.items()]
    names = ", ".join(a.name for a in items[:3]) + ("…" if len(items) > 3 else "")
    lines = [f"Got {' and '.join(parts) if len(parts) < 3 else ', '.join(parts)} — {names}."]
    asks_summary = not question.strip() or re.search(r"summar|tl;?dr|what('s| is| does)|explain|read", question, re.I)
    for a in items:
        if a.kind not in ("document", "text"):
            continue
        meta = [f"{a.pages} pages" if a.pages else None, f"{a.words:,} words" if a.words else None]
        meta_s = " · ".join(m for m in meta if m)
        if a.excerpt and asks_summary:
            sentences = re.split(r"(?<=[.!?])\s+", re.sub(r"\s+", " ", a.excerpt))
            peek = " ".join(sentences[:2])[:320]
            lines.append(f"📄 {a.name}{f' ({meta_s})' if meta_s else ''}: “{peek}”")
        elif meta_s:
            lines.append(f"📄 {a.name}: {meta_s}.")
    if not question.strip():
        lines.append("What should I do with it — summarise, pull out dates and prices, or plan around it?")
    return "\n".join(lines)
