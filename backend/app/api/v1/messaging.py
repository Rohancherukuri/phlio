"""Authenticated DMs and participant-only WebRTC negotiation."""

from __future__ import annotations

import json
import uuid
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field, ValidationError, model_validator
from starlette.responses import FileResponse

from app.api.deps import get_container, get_current_user
from app.api.v1.rooms import AttachmentIn
from app.core.container import Container
from app.domains.identity.entities import User
from app.domains.messaging.media_policy import (
    VideoEdit,
    edit_video,
    media_type,
    validate_pack,
    validate_signature,
    validate_size,
)
from app.infrastructure.media_storage import MediaStorage

router = APIRouter(prefix="/messaging", tags=["messaging"])


async def resolve_peer(peer: str, container: Container) -> User:
    repo = container.identity_repository
    user = await repo.get_by_id(peer) or await repo.get_by_username(peer.lstrip("@").lower())
    if user is None:
        raise HTTPException(404, "User not found.")
    return user


def profile(user: User) -> dict:
    return dict(id=user.id, username=user.username, full_name=user.full_name, avatar_url=user.avatar_url)


class MessageIn(BaseModel):
    text: str = Field(default="", max_length=4000)
    attachments: list[AttachmentIn] = Field(default_factory=list, max_length=10)

    @model_validator(mode="after")
    def not_empty(self):
        if not self.text.strip() and not self.attachments:
            raise ValueError("Message cannot be empty.")
        return self


class CallIn(BaseModel):
    peer: str = Field(min_length=1, max_length=100)
    video: bool = False


class ReactionIn(BaseModel):
    kind: Literal["emoji"] = "emoji"
    value: str = Field(min_length=1, max_length=16)


class SignalIn(BaseModel):
    kind: Literal["offer", "answer", "candidate"]
    payload: dict

    @model_validator(mode="after")
    def valid_payload(self):
        import json

        if len(json.dumps(self.payload)) > 65536:
            raise ValueError("Signal too large.")
        if self.kind in ("offer", "answer"):
            if self.payload.get("type") != self.kind or not isinstance(self.payload.get("sdp"), str):
                raise ValueError("Invalid session description.")
        elif not isinstance(self.payload.get("candidate"), str):
            raise ValueError("Invalid ICE candidate.")
        return self


@router.get("/conversations")
async def conversations(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    result = []
    for peer_id in c.messaging_service.peers(user.id):
        peer = await c.identity_repository.get_by_id(peer_id)
        if peer:
            messages = c.messaging_service.history(user.id, peer.id)
            result.append(dict(peer=profile(peer), last_message=messages[-1] if messages else None))
    return result


@router.get("/peers/{peer}")
async def get_peer(peer: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    return profile(await resolve_peer(peer, c))


@router.get("/peers/{peer}/messages")
async def messages(
    peer: str,
    before: str | None = None,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    target = await resolve_peer(peer, c)
    return c.messaging_service.history(user.id, target.id, before)


@router.post("/peers/{peer}/messages", status_code=201)
async def send(
    peer: str, body: MessageIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    target = await resolve_peer(peer, c)
    for a in body.attachments:
        if a.kind in ("sticker", "gif") and not a.url:
            validate_pack(a.kind, a.value)
            continue
        prefix = f"{c.settings.api_v1_prefix}/messaging/files/"
        if not a.url.startswith(prefix):
            raise HTTPException(422, "Use an uploaded conversation file.")
        uploaded = c.messaging_service.file(a.url.removeprefix(prefix), user.id)
        if uploaded["owner"] != user.id or uploaded["peer"] != target.id:
            raise HTTPException(403, "File belongs to another conversation.")
        kind, _ = media_type(uploaded["name"])
        a.size = Path(uploaded["path"]).stat().st_size
        validate_size(kind, a.size)
        a.name = uploaded["name"]
        a.mime = uploaded["mime"]
        a.kind = a.mime.split("/")[0] if a.mime.startswith(("image/", "video/", "audio/")) else "document"
    attachments = [dict(id=uuid.uuid4().hex, **a.model_dump()) for a in body.attachments]
    return c.messaging_service.send(user.id, target.id, body.text, attachments)


@router.post("/peers/{peer}/messages/{message_id}/reactions")
async def react_message(
    peer: str,
    message_id: str,
    body: ReactionIn,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    await resolve_peer(peer, c)
    return {"reactions": c.messaging_service.react(message_id, user.id, body.kind, body.value)}


@router.post("/peers/{peer}/files", status_code=201)
async def files(
    peer: str,
    files: list[UploadFile] = File(...),
    edits: str = Form(default="[]"),
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    target = await resolve_peer(peer, c)
    if not 1 <= len(files) <= 10:
        raise HTTPException(422, "Attach up to ten media files.")
    try:
        parsed = json.loads(edits)
        if not isinstance(parsed, list) or len(parsed) > len(files):
            raise ValueError()
        editing = [VideoEdit.model_validate(v) if v is not None else None for v in parsed]
        editing += [None] * (len(files) - len(editing))
    except (ValueError, TypeError, ValidationError) as exc:
        raise HTTPException(422, "Invalid video edits.") from exc
    root = Path(c.settings.messaging_media_root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    created = []
    records = []
    result = []
    try:
        for index, file in enumerate(files):
            kind, mime = media_type(file.filename or "")
            if file.size is not None:
                validate_size(kind, file.size)
            file_id = uuid.uuid4().hex
            path = root / file_id
            created.append(path)
            name = MediaStorage.safe_name(file.filename or "media")

            def copy(destination=path, source=file.file, category=kind):
                size = 0
                with destination.open("wb") as out:
                    while chunk := source.read(1024 * 1024):
                        size += len(chunk)
                        validate_size(category, size)
                        out.write(chunk)
                validate_size(category, size)

            await run_in_threadpool(copy)
            validate_signature(path, mime)
            if editing[index] is not None:
                if kind != "video":
                    raise HTTPException(422, "Video edits require a video attachment.")
                edited = root / (file_id + ".mp4")
                created.append(edited)
                await run_in_threadpool(edit_video, path, edited, editing[index])
                path.unlink()
                path = edited
                name = Path(name).stem + ".mp4"
                mime = "video/mp4"
            size = path.stat().st_size
            records.append((file_id, user.id, target.id, str(path), name, mime))
            url = f"{c.settings.api_v1_prefix}/messaging/files/{file_id}"
            result.append(dict(kind=kind, name=name, mime=mime, url=url, size=size))
        for record in records:
            c.messaging_service.store_file(*record)
    except BaseException:
        for path in created:
            path.unlink(missing_ok=True)
        raise
    return result


class StickerOverlay(BaseModel):
    value: str = Field(min_length=1, max_length=120)
    x: float = Field(default=0.5, ge=0, le=1, allow_inf_nan=False)
    y: float = Field(default=0.5, ge=0, le=1, allow_inf_nan=False)
    scale: float = Field(default=1, ge=0.5, le=2, allow_inf_nan=False)

    @model_validator(mode="after")
    def known_sticker(self):
        validate_pack("sticker", self.value)
        return self


class OverlaysIn(BaseModel):
    overlays: list[StickerOverlay] = Field(max_length=12)


@router.put("/peers/{peer}/messages/{message_id}/overlays")
async def set_overlays(
    peer: str,
    message_id: str,
    body: OverlaysIn,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    target = await resolve_peer(peer, c)
    return {
        "overlays": c.messaging_service.overlays(
            message_id, user.id, target.id, [v.model_dump() for v in body.overlays]
        )
    }


@router.get("/files/{file_id}")
async def private_file(
    file_id: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    row = c.messaging_service.file(file_id, user.id)
    return FileResponse(row["path"], media_type=row["mime"], filename=row["name"])


@router.get("/calls/config")
async def call_config(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    return {"iceServers": c.settings.calls_ice_servers}


@router.get("/calls/incoming")
async def incoming(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    result = []
    for call in c.messaging_service.incoming(user.id):
        caller = await resolve_peer(call["caller_id"], c)
        result.append(dict(**c.messaging_service.public_call(call), caller=profile(caller)))
    return result


@router.post("/calls", status_code=201)
async def create_call(
    body: CallIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    target = await resolve_peer(body.peer, c)
    return c.messaging_service.public_call(c.messaging_service.create_call(user.id, target.id, body.video))


@router.get("/calls/{call_id}")
async def get_call(
    call_id: str,
    after: int = Query(default=0, ge=0),
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    call = c.messaging_service.call(call_id, user.id)
    signals = [s for s in call["signals"] if s["seq"] > after and s["sender"] != user.id]
    return dict(**c.messaging_service.public_call(call), signals=signals)


@router.post("/calls/{call_id}/actions/{action}")
async def call_action(
    call_id: str,
    action: Literal["accept", "decline", "end"],
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    return c.messaging_service.public_call(c.messaging_service.transition(call_id, user.id, action))


@router.post("/calls/{call_id}/signals", status_code=204)
async def signal(
    call_id: str,
    body: SignalIn,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    c.messaging_service.signal(call_id, user.id, body.kind, body.payload)


class FriendIn(BaseModel):
    peer: str = Field(min_length=1, max_length=100)


@router.get("/friends")
async def friends(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    items = []
    for relation in c.messaging_service.friends(user.id):
        peer_id = relation["recipient"] if relation["sender"] == user.id else relation["sender"]
        peer = await c.identity_repository.get_by_id(peer_id)
        if peer:
            items.append(
                dict(peer=profile(peer), status=relation["status"], incoming=relation["recipient"] == user.id)
            )
    return items


@router.post("/friends", status_code=201)
async def add_friend(
    body: FriendIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    peer = await resolve_peer(body.peer, c)
    c.messaging_service.request_friend(user.id, peer.id)
    return {"status": "pending"}


@router.post("/friends/{peer}/{action}", status_code=204)
async def friend_action(
    peer: str,
    action: Literal["accept", "remove"],
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    target = await resolve_peer(peer, c)
    c.messaging_service.friend_action(user.id, target.id, action)


def matches_search(message: dict, query: str, kind: str) -> bool:
    import re

    attachments = message.get("attachments", [])
    text = message.get("text", "")
    if query.casefold() not in (text + " " + " ".join(a.get("name", "") for a in attachments)).casefold():
        return False
    kinds = {a.get("kind") for a in attachments}
    return (
        kind == "recent"
        or kind == "media"
        and bool(kinds & {"image", "video", "audio", "gif"})
        or kind == "images"
        and "image" in kinds
        or kind == "videos"
        and "video" in kinds
        or kind == "audio"
        and "audio" in kinds
        or kind == "files"
        and "document" in kinds
        or kind == "links"
        and bool(re.search(r"https?://[^\s]+", text))
    )


@router.get("/search")
async def search_rooms_content(
    q: str = Query(default="", max_length=200),
    kind: Literal[
        "recent", "people", "media", "pins", "links", "files", "images", "videos", "audio"
    ] = "recent",
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    from dataclasses import asdict

    q = q.strip()
    if kind == "people":
        people = await c.identity_repository.search_users(q)
        return [dict(type="person", peer=profile(peer)) for peer in people if peer.id != user.id]
    results = []
    if kind != "pins":
        for message in c.messaging_service.searchable_messages(user.id):
            if matches_search(message, q, kind):
                peer = await c.identity_repository.get_by_id(message["peer_id"])
                if peer:
                    results.append(dict(type="message", title=peer.full_name, **message))
                if len(results) >= 100:
                    break
    # Rooms search is restricted to memberships, including private rooms.
    for room in await c.rooms_service.my_rooms(user.id):
        if kind == "pins":
            if room.description and q.casefold() in (room.name + " " + room.description).casefold():
                results.append(
                    dict(
                        type="pin",
                        room_id=room.id,
                        title=room.name,
                        text=room.description,
                        attachments=[],
                        created_at=room.created_at.isoformat(),
                    )
                )
            continue
        cursor = None
        found = 0
        while True:
            messages, cursor = await c.rooms_repository.list_messages(room.id, cursor=cursor, limit=100)
            for message in messages:
                data = asdict(message)
                data["created_at"] = message.created_at.isoformat()
                if matches_search(data, q, kind):
                    results.append(dict(type="message", title=room.name, **data))
                    found += 1
            if cursor is None or found >= 100:
                break
    results.sort(key=lambda item: item["created_at"], reverse=True)
    return results[:100]
