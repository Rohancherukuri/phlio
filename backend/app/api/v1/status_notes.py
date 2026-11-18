"""
Notes: short status bubbles above the DM inbox, like Instagram Notes.

A note is up to 60 characters of text with, optionally, a song, a GIF, a
place (stored at ~1 km precision), a bubble colour and an animated effect.
Each person has at most one active note; posting again replaces it,
and notes disappear 24 hours after they were posted. They are shown to
people who follow the author (``audience="followers"``) or only to people
the author follows back (``"mutuals"``). Others can like a note; replies go
to the author's DMs from the app.

Storage: graph table ``status_note``, one record per author
(``status_note:<user_id>``), so a new note simply overwrites the old one.

Endpoints, under ``/api/v1/social/notes``:

``GET    /``           ``{"mine": note|null, "items": [notes from people I follow]}``
``POST   /``           post or replace my note
``DELETE /mine``       remove my note
``PUT    /{author}/like`` / ``DELETE /{author}/like``  like / unlike a note
"""

from __future__ import annotations

import datetime as dt
import re
from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field, field_validator, model_validator

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key

router = APIRouter(prefix="/social/notes", tags=["social"])

LIFETIME = dt.timedelta(hours=24)
_GIF_HOST = re.compile(r"^https://(media\d*|i)\.giphy\.com/")
AUDIO_PREFIX = "/media/post_uploads/note_"
AUDIO_TYPES = {".mp3", ".m4a", ".aac", ".wav", ".ogg", ".flac", ".opus"}
MAX_AUDIO = 15 * 1024 * 1024


class NoteSong(BaseModel):
    """A song on a note, from one of three places:

    * ``stream``  — Phlio Stream catalogue (plays in the app)
    * ``spotify`` — a Spotify track link (opens Spotify; no audio is copied)
    * ``local``   — a clip uploaded from the phone via ``POST /social/notes/audio``
    """

    title: str = Field(min_length=1, max_length=120)
    artist: str = Field(default="", max_length=120)
    url: str = Field(max_length=500)  # stream URL, Spotify track link or uploaded clip
    image_url: str | None = Field(default=None, max_length=500)
    ref: str | None = Field(default=None, max_length=120)
    source: Literal["stream", "spotify", "local"] = "stream"
    # The part of the song that plays (chosen in the app's "New song" sheet).
    clip_start: float = Field(default=0, ge=0, le=7200)
    clip_length: int = Field(default=30, ge=5, le=30)
    explicit: bool = False

    @field_validator("url", "image_url")
    @classmethod
    def _safe_url(cls, value):
        if value and not (value.startswith("/media/") or value.startswith("https://")):
            raise ValueError("Use an https or /media/ link.")
        return value

    @model_validator(mode="after")
    def _matches_source(self):
        if self.source == "spotify" and not self.url.startswith("https://open.spotify.com/track/"):
            raise ValueError("Spotify songs need an open.spotify.com track link.")
        if self.source == "local" and not (self.url.startswith(AUDIO_PREFIX) and ".." not in self.url):
            raise ValueError("Upload the audio first.")
        return self


class NoteGif(BaseModel):
    url: str = Field(max_length=500)
    title: str = Field(default="GIF", max_length=120)

    @field_validator("url")
    @classmethod
    def _giphy_only(cls, value):
        if not _GIF_HOST.match(value):
            raise ValueError("Choose a GIF from GIPHY.")
        return value


class NotePlace(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    address: str = Field(default="", max_length=160)
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)


class NoteIn(BaseModel):
    text: str = Field(default="", max_length=60)
    music: NoteSong | None = None
    gif: NoteGif | None = None
    location: NotePlace | None = None
    audience: Literal["followers", "mutuals"] = "followers"
    # Bubble Editor: a bubble colour (#RRGGBB) and an animated effect drawn
    # by the app's note_effects shader.
    color: str | None = Field(default=None, pattern=r"^#[0-9A-Fa-f]{6}$")
    effect: Literal["confetti", "sparkles", "hearts", "fireworks", "glow", "snow", "fizz"] | None = None


def _coarse(place: NotePlace) -> dict:
    """Followers see the neighbourhood, not your exact spot: ~1 km precision."""
    out = place.model_dump()
    for axis in ("lat", "lng"):
        if out[axis] is not None:
            out[axis] = round(out[axis], 2)
    return out


def _now() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def _alive(row: dict, now: dt.datetime) -> bool:
    try:
        return dt.datetime.fromisoformat(row["expires_at"]) > now
    except (KeyError, ValueError):
        return False


async def _present(c, row: dict, viewer: str) -> dict | None:
    person = await c.identity_repository.get_by_id(row["author"])
    if not person:
        return None
    likes = row.get("likes") or []
    return dict(
        author=c.graph.profile(person), text=row.get("text", ""), music=row.get("music"),
        gif=row.get("gif"), location=row.get("location"), audience=row.get("audience", "followers"),
        color=row.get("color"), effect=row.get("effect"),
        created_at=row["created_at"], expires_at=row["expires_at"],
        like_count=len(likes) if row["author"] == viewer else None,  # only the author sees the count
        liked_by_me=viewer in likes,
    )


@router.get("")
async def list_notes(user=Depends(get_current_user), c=Depends(get_container)):
    """My note and the active notes of people I follow (newest first)."""
    now = _now()
    following = {e["out"].removeprefix("user:") for e in await c.graph.store.rows("follows", {"in": "user:" + user.id})}
    followers = {e["in"].removeprefix("user:") for e in await c.graph.store.rows("follows", {"out": "user:" + user.id})}
    mine = await c.graph.store.get(key("status_note", user.id))
    items = []
    for row in await c.graph.store.rows("status_note"):
        author = row.get("author")
        if author == user.id or author not in following or not _alive(row, now):
            continue
        if row.get("audience") == "mutuals" and author not in followers:
            continue
        if await c.graph.blocked(user.id, author):
            continue
        shown = await _present(c, row, user.id)
        if shown:
            items.append(shown)
    items.sort(key=lambda n: n["created_at"], reverse=True)
    return dict(mine=await _present(c, mine, user.id) if mine and _alive(mine, now) else None, items=items)


@router.post("", status_code=201)
async def post_note(body: NoteIn, user=Depends(get_current_user), c=Depends(get_container)):
    """Posts (or replaces) my note for the next 24 hours."""
    text = " ".join(body.text.split())
    if not text and not body.music and not body.gif and not body.location:
        raise HTTPException(422, "Write something or add a song, GIF or place.")
    await c.cache.rate_limit(user.id, "status-note", 20)
    now = _now()
    row = dict(author=user.id, text=text, audience=body.audience, likes=[],
               music=body.music.model_dump() if body.music else None,
               gif=body.gif.model_dump() if body.gif else None,
               location=_coarse(body.location) if body.location else None,
               color=body.color.upper() if body.color else None, effect=body.effect,
               created_at=now.isoformat(), expires_at=(now + LIFETIME).isoformat())
    saved = await c.graph.store.put(key("status_note", user.id), row)
    return await _present(c, saved or row, user.id)


@router.post("/audio", status_code=201)
async def upload_note_audio(file: UploadFile = File(...), user=Depends(get_current_user), c=Depends(get_container)):
    """A song from the phone for a note. Checked with ffprobe; returns the
    ``music`` object to post with the note (``source="local"``)."""
    import asyncio
    import uuid
    from pathlib import Path

    from app.core.container import media_root_path

    await c.cache.rate_limit(user.id, "note-audio", 10)
    extension = Path(file.filename or "").suffix.lower()
    if extension not in AUDIO_TYPES:
        raise HTTPException(422, "Choose an MP3, M4A, AAC, WAV, OGG, FLAC or OPUS file.")
    raw = await file.read(MAX_AUDIO + 1)
    if len(raw) > MAX_AUDIO:
        raise HTTPException(413, "Choose a song under 15 MB.")
    folder = media_root_path(c.settings) / "post_uploads"
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"note_{uuid.uuid4().hex}{extension}"
    target.write_bytes(raw)
    try:
        process = await asyncio.create_subprocess_exec(
            "ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_type",
            "-of", "csv=p=0", str(target), stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        output, _ = await asyncio.wait_for(process.communicate(), timeout=10)
        if process.returncode != 0 or b"audio" not in output:
            raise ValueError
    except FileNotFoundError:
        pass  # no ffprobe on this machine (tests / minimal hosts): extension check only
    except Exception:
        target.unlink(missing_ok=True)
        raise HTTPException(422, "Could not read this audio file.")
    title = Path(file.filename or "Original audio").stem.replace("_", " ").strip()[:120] or "Original audio"
    return dict(title=title, artist=user.username, url="/media/post_uploads/" + target.name, source="local")


@router.delete("/mine", status_code=204)
async def delete_note(user=Depends(get_current_user), c=Depends(get_container)):
    if await c.graph.store.get(key("status_note", user.id)):
        await c.graph.store.delete(key("status_note", user.id))


async def _visible_note(c, viewer: str, author: str) -> dict:
    row = await c.graph.store.get(key("status_note", author))
    if not row or not _alive(row, _now()) or await c.graph.blocked(viewer, author):
        raise HTTPException(404, "This note has expired.")
    return row


@router.put("/{author}/like")
async def like_note(author: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _visible_note(c, user.id, author)
    likes = list(dict.fromkeys([*(row.get("likes") or []), user.id]))
    await c.graph.store.put(key("status_note", author), dict(row, likes=likes))
    return {"liked": True}


@router.delete("/{author}/like")
async def unlike_note(author: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _visible_note(c, user.id, author)
    likes = [u for u in row.get("likes") or [] if u != user.id]
    await c.graph.store.put(key("status_note", author), dict(row, likes=likes))
    return {"liked": False}
