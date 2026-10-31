"""Authenticated DMs and participant-only WebRTC negotiation."""

from __future__ import annotations

import json
import asyncio
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
    reply_to: str | None = Field(default=None, max_length=64)

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
        if peer and not await c.graph.blocked(user.id, peer.id):
            messages = c.messaging_service.history(user.id, peer.id)
            state = c.messaging_service.inbox_state(user.id, peer.id)
            unread, replied = c.messaging_service.inbox_counts(user.id, peer.id, state['read_at'])
            folder = state['folder'] or ('primary' if replied or await c.graph.friends(user.id,peer.id) else 'requests')
            result.append(dict(peer=profile(peer), last_message=messages[-1] if messages else None,folder=folder,unread_count=unread))
    return sorted(result,key=lambda row:(row['last_message'] or {}).get('created_at',''),reverse=True)


class GiphySelection(BaseModel):
    giphy_id: str = Field(pattern=r'^[A-Za-z0-9]{1,80}$')
    kind: Literal['gif', 'sticker']


@router.get('/giphy/config')
async def giphy_config(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    from fastapi.responses import JSONResponse
    # This is a client API credential: searches and media loads go directly to GIPHY.
    return JSONResponse({'api_key': c.settings.giphy_api_key}, headers={'Cache-Control': 'no-store'})


@router.post('/giphy/recents')
async def save_giphy(body: GiphySelection, user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    from app.domains.graph.service import key
    from app.domains.graph.store import now
    # Store references only. GIPHY media and URLs remain on GIPHY.
    await c.graph.store.put(key('giphy_selection', user.id, body.kind, body.giphy_id),
        dict(owner=user.id, giphy_id=body.giphy_id, kind=body.kind, selected_at=now()))
    return {'saved': True}


@router.get('/giphy/recents')
async def recent_giphy(kind: Literal['gif', 'sticker'], user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    rows = await c.graph.store.rows('giphy_selection', {'owner': user.id, 'kind': kind})
    return sorted(rows, key=lambda r: r['selected_at'], reverse=True)[:24]


class InboxUpdate(BaseModel):
    folder: Literal['primary','general','requests'] | None = None
    read: bool = False


@router.patch('/peers/{peer}/inbox')
async def update_inbox(peer: str, body: InboxUpdate, user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    target = await resolve_peer(peer,c)
    if target.id not in c.messaging_service.peers(user.id) or await c.graph.blocked(user.id,target.id):
        raise HTTPException(404,'Conversation unavailable.')
    c.messaging_service.update_inbox(user.id,target.id,body.folder,body.read)
    return {'ok':True}


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
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, "This conversation is unavailable.")
    # Dio sends `?before` with no value for null, which arrives as "" and
    # would filter out every message (created_at < "").
    return c.messaging_service.history(user.id, target.id, before or None)


@router.post("/peers/{peer}/messages", status_code=201)
async def send(
    peer: str, body: MessageIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    target = await resolve_peer(peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, "This conversation is unavailable.")
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
    return c.messaging_service.send(user.id, target.id, body.text, attachments, reply_to=body.reply_to)


@router.delete("/peers/{peer}/messages/{message_id}", status_code=204)
async def delete_message(
    peer: str,
    message_id: str,
    scope: Literal["me", "everyone"] = "me",
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    """`scope=me` is "Delete for you"; `scope=everyone` is Unsend (sender only)."""
    target = await resolve_peer(peer, c)
    if scope == "everyone":
        c.messaging_service.unsend(message_id, user.id, target.id)
    else:
        c.messaging_service.hide(message_id, user.id, target.id)


class PinIn(BaseModel):
    pinned: bool = True


@router.put("/peers/{peer}/messages/{message_id}/pin")
async def pin_message(
    peer: str,
    message_id: str,
    body: PinIn,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    target = await resolve_peer(peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, "This conversation is unavailable.")
    return {"pinned": c.messaging_service.pin(message_id, user.id, target.id, body.pinned)}


class ForwardIn(BaseModel):
    to: list[str] = Field(min_length=1, max_length=20)


@router.post("/peers/{peer}/messages/{message_id}/forward")
async def forward_message(
    peer: str,
    message_id: str,
    body: ForwardIn,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    await resolve_peer(peer, c)
    prefix = f"{c.settings.api_v1_prefix}/messaging/files/"
    sent, failed = [], []
    for handle in dict.fromkeys(body.to):
        try:
            recipient = await resolve_peer(handle, c)
            if recipient.id == user.id or await c.graph.blocked(user.id, recipient.id):
                raise HTTPException(403, "Unavailable.")
            c.messaging_service.forward(message_id, user.id, recipient.id, prefix)
            sent.append(recipient.username)
        except HTTPException:
            failed.append(handle)
    if not sent:
        raise HTTPException(404, "Could not forward this message.")
    return {"sent": sent, "failed": failed}


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
    purpose: str = Form(default="message"),
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    # Phlio Studio sources (clips, music, overlays) may be larger than a
    # message attachment; they are only ever sent after rendering.
    studio = purpose == "studio"
    target = await resolve_peer(peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, "This conversation is unavailable.")
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
                validate_size(kind, file.size, studio)
            file_id = uuid.uuid4().hex
            path = root / file_id
            created.append(path)
            name = MediaStorage.safe_name(file.filename or "media")

            def copy(destination=path, source=file.file, category=kind):
                size = 0
                with destination.open("wb") as out:
                    while chunk := source.read(1024 * 1024):
                        size += len(chunk)
                        validate_size(category, size, studio)
                        out.write(chunk)
                validate_size(category, size, studio)

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
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, "This conversation is unavailable.")
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
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, "This conversation is unavailable.")
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
    call = c.messaging_service.transition(call_id, user.id, action)
    if action == 'end' and c.settings.livekit_url:
        from app.api.v1.realtime import server
        from livekit import api
        try:
            async with server(c) as lk:
                await lk.room.delete_room(api.DeleteRoomRequest(room='call-' + call_id))
        except HTTPException:
            pass  # Local call state is ended even if the SFU is unreachable.
    return c.messaging_service.public_call(call)


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
    items = (await c.graph.connections(user.id))["friends"]
    for item in items:
        item["peer"]["full_name"] = item["peer"].pop("display_name")
    return items


@router.post("/friends", status_code=201)
async def add_friend(
    body: FriendIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    peer = await resolve_peer(body.peer, c)
    await c.graph.relationship(user.id, peer.id, "request")
    return {"status": "pending"}


@router.post("/friends/{peer}/{action}", status_code=204)
async def friend_action(
    peer: str,
    action: Literal["accept", "remove"],
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    target = await resolve_peer(peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, "This conversation is unavailable.")
    await c.graph.relationship(user.id, target.id, action)


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


_audio_enhancement_lock = asyncio.Lock()

class EnhanceVoiceIn(BaseModel):
    attachment_id: str = Field(min_length=1, max_length=64)
    restore: bool = False


@router.post('/peers/{peer}/messages/{message_id}/improve-audio')
async def improve_audio(peer: str, message_id: str, body: EnhanceVoiceIn,
                        user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    from app.domains.messaging.audio_enhancement import enhance_audio
    target = await resolve_peer(peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, 'This conversation is unavailable.')
    service = c.messaging_service
    row = service._participant_message(message_id, user.id, target.id)
    if row['sender'] != user.id:
        raise HTTPException(403, 'You can only improve your own voice messages.')
    attachments = json.loads(row['attachments'])
    audio = next((a for a in attachments if a.get('id') == body.attachment_id and a.get('kind') == 'audio'), None)
    if audio is None:
        raise HTTPException(404, 'Voice message not found.')
    if body.restore:
        original = audio.get('original_audio')
        if original:
            audio.clear()
            audio.update(original)
            service.db.execute('UPDATE messages SET attachments=? WHERE id=?', (json.dumps(attachments), message_id))
            service.db.commit()
        return {'improved': False}
    if audio.get('enhanced_by'):
        return {'improved': True}
    await c.cache.rate_limit(user.id, 'improve_voice', 5)
    if _audio_enhancement_lock.locked():
        raise HTTPException(429, 'Foxy is improving another recording. Please try again shortly.')
    async with _audio_enhancement_lock:
        prefix = f'{c.settings.api_v1_prefix}/messaging/files/'
        url = audio.get('url', '')
        if not url.startswith(prefix):
            raise HTTPException(422, 'Use an uploaded voice message.')
        source = service.file(url.removeprefix(prefix), user.id)
        if source['owner'] != user.id or source['peer'] != target.id:
            raise HTTPException(403, 'File belongs to another conversation.')
        root = Path(c.settings.messaging_media_root).resolve()
        file_id = uuid.uuid4().hex
        destination = root / (file_id + '.m4a')
        try:
            await run_in_threadpool(enhance_audio, Path(source['path']), destination)
            # Recheck after inference: an unsent message must not be recreated.
            latest = service._participant_message(message_id, user.id, target.id)
            if latest['attachments'] != row['attachments'] or await c.graph.blocked(user.id, target.id):
                raise HTTPException(409, 'Message changed while processing. Please try again.')
            original = dict(audio)
            audio.update(id=uuid.uuid4().hex, url=prefix+file_id, mime='audio/mp4',
                         name='Voice message - Foxy AI.m4a', size=destination.stat().st_size,
                         original_audio=original, enhanced_by='DeepFilterNet3')
            service.store_file(file_id, user.id, target.id, str(destination), audio['name'], audio['mime'])
            service.db.execute('UPDATE messages SET attachments=? WHERE id=?', (json.dumps(attachments), message_id))
            service.db.commit()
        except BaseException:
            destination.unlink(missing_ok=True)
            raise
    return {'improved': True}


from app.domains.messaging.media_studio import (LIBRARY_PREFIXES, StudioPlan, extract_speech, filmstrip,
                                                render_studio, waveform)
from app.domains.messaging import studio_speech

_studio_lock = asyncio.Lock()
_studio_jobs: dict[str, dict] = {}
_studio_tasks: set = set()


def _studio_file(c, user, target, file_id, kinds):
    row = c.messaging_service.file(file_id, user.id)
    if row['owner'] != user.id or row['peer'] != target.id:
        raise HTTPException(403, 'File belongs to another conversation.')
    if not row['mime'].startswith(kinds):
        raise HTTPException(422, 'Unsupported source media.')
    return dict(row)


def _library_path(c, url: str) -> str:
    from app.core.container import media_root_path
    root = media_root_path(c.settings).resolve()
    path = (root / url.removeprefix('/media/')).resolve()
    allowed = [(root / p.strip('/').removeprefix('media/')).resolve() for p in LIBRARY_PREFIXES]
    if not any(lib in path.parents for lib in allowed) or not path.is_file():
        raise HTTPException(404, 'That sound is no longer available.')
    return str(path)


def _studio_inputs(c, user, target, body: StudioPlan):
    sources = [_studio_file(c, user, target, clip.file_id, ('image/', 'video/')) for clip in body.clips]
    music = _studio_file(c, user, target, body.music_id, ('audio/',)) if body.music_id else None
    overlays = [_studio_file(c, user, target, o.file_id, ('image/',)) for o in body.overlays]
    audios = []
    for spec in body.audios:
        if spec.file_id:
            path = _studio_file(c, user, target, spec.file_id, ('audio/', 'video/'))['path']
        else:
            path = _library_path(c, spec.library_url)
        audios.append(dict(path=path, spec=spec))
    pips = []
    for spec in body.pips:
        row = _studio_file(c, user, target, spec.file_id, ('image/', 'video/'))
        if spec.mask_id:
            row['mask_path'] = _studio_file(c, user, target, spec.mask_id, ('image/',))['path']
        pips.append(row)
    extras = {}
    if body.cover and (body.cover.time is not None or body.cover.file_id):
        cover = {}
        if body.cover.file_id:
            cover['path'] = _studio_file(c, user, target, body.cover.file_id, ('image/',))['path']
        if body.cover.overlay_id:
            cover['overlay'] = _studio_file(c, user, target, body.cover.overlay_id, ('image/',))['path']
        extras['cover'] = cover
    return sources, music, overlays, audios, pips, extras


async def _studio_render(c, user, target, body: StudioPlan, report=None):
    sources, music, overlays, audios, pips, extras = _studio_inputs(c, user, target, body)
    image = body.image_only and sources[0]['mime'].startswith('image/')
    file_id = uuid.uuid4().hex
    name = ('edited.' + body.image_format) if image else 'edited.mp4'
    mime = ('image/png' if body.image_format == 'png' else 'image/jpeg') if image else 'video/mp4'
    path = Path(c.settings.messaging_media_root).resolve() / (file_id + Path(name).suffix)
    try:
        kind = await run_in_threadpool(render_studio, sources, music, body, path, overlays, audios, report,
                                       pips, extras)
        validate_size(kind, path.stat().st_size, True)
        if await c.graph.blocked(user.id, target.id):
            raise HTTPException(403, 'Conversation unavailable.')
        c.messaging_service.store_file(file_id, user.id, target.id, str(path), name, mime)
        return dict(kind=kind, name=name, mime=mime, size=path.stat().st_size,
                    url=f'{c.settings.api_v1_prefix}/messaging/files/{file_id}')
    except BaseException:
        path.unlink(missing_ok=True)
        raise


@router.post('/peers/{peer}/studio/render')
async def studio_render(peer: str, body: StudioPlan, user=Depends(get_current_user), c=Depends(get_container)):
    """Synchronous export (v1 editor)."""
    target = await resolve_peer(peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, 'Conversation unavailable.')
    _studio_inputs(c, user, target, body)
    await c.cache.rate_limit(user.id, 'studio_render', 10)
    if _studio_lock.locked():
        raise HTTPException(429, 'Another export is running. Try again shortly.')
    async with _studio_lock:
        return await _studio_render(c, user, target, body)


@router.post('/peers/{peer}/studio/jobs', status_code=202)
async def studio_job(peer: str, body: StudioPlan, user=Depends(get_current_user), c=Depends(get_container)):
    """Start an export; poll GET .../studio/jobs/{id} for progress."""
    target = await resolve_peer(peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, 'Conversation unavailable.')
    _studio_inputs(c, user, target, body)  # fail fast on bad sources
    await c.cache.rate_limit(user.id, 'studio_render', 20)
    if sum(j['owner'] == user.id and j['status'] in ('queued', 'running') for j in _studio_jobs.values()) >= 2:
        raise HTTPException(429, 'You already have exports running.')
    job_id = uuid.uuid4().hex
    job = dict(id=job_id, owner=user.id, status='queued', progress=0.0,
               stage='Waiting for another export to finish' if _studio_lock.locked() else 'Starting')
    _studio_jobs[job_id] = job

    def report(value, stage):
        job.update(progress=round(min(.99, max(job['progress'], value)), 3), stage=stage)

    async def work():
        try:
            async with _studio_lock:
                job.update(status='running', stage='Preparing')
                job['result'] = await _studio_render(c, user, target, body, report)
                job.update(status='done', progress=1.0, stage='Done')
        except HTTPException as exc:
            job.update(status='failed', error=exc.detail)
        except Exception:
            job.update(status='failed', error='Could not render this project. Try again.')
        finally:
            # Forget finished jobs after a while.
            await asyncio.sleep(1800)
            _studio_jobs.pop(job_id, None)

    task = asyncio.create_task(work())
    _studio_tasks.add(task)
    task.add_done_callback(_studio_tasks.discard)
    return {k: v for k, v in job.items() if k != 'owner'}


@router.get('/peers/{peer}/studio/jobs/{job_id}')
async def studio_job_status(peer: str, job_id: str, user=Depends(get_current_user)):
    job = _studio_jobs.get(job_id)
    if not job or job['owner'] != user.id:
        raise HTTPException(404, 'Export not found.')
    return {k: v for k, v in job.items() if k != 'owner'}


@router.get('/peers/{peer}/studio/filmstrip/{file_id}')
async def studio_filmstrip(peer: str, file_id: str, frames: int = Query(default=12, ge=1, le=40),
                           user=Depends(get_current_user), c=Depends(get_container)):
    """Thumbnail strip for the timeline (cached next to the file)."""
    row = c.messaging_service.file(file_id, user.id)
    if row['owner'] != user.id or not row['mime'].startswith(('image/', 'video/')):
        raise HTTPException(404, 'File not found.')
    strip = Path(row['path'] + f'.strip{frames}.jpg')
    if not strip.exists():
        try:
            await run_in_threadpool(filmstrip, row['path'], row['mime'], strip, frames)
        except Exception as exc:
            strip.unlink(missing_ok=True)
            raise HTTPException(422, 'Could not preview this clip.') from exc
    return FileResponse(str(strip), media_type='image/jpeg', headers={'Cache-Control': 'private, max-age=86400'})


@router.get('/peers/{peer}/studio/waveform/{file_id}')
async def studio_waveform(peer: str, file_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = c.messaging_service.file(file_id, user.id)
    if row['owner'] != user.id or not row['mime'].startswith(('audio/', 'video/')):
        raise HTTPException(404, 'File not found.')
    try:
        return await run_in_threadpool(waveform, row['path'])
    except Exception as exc:
        raise HTTPException(422, 'Could not read this audio.') from exc


@router.get('/studio/library-waveform')
async def studio_library_waveform(url: str, user=Depends(get_current_user), c=Depends(get_container)):
    if not url.startswith(LIBRARY_PREFIXES):
        raise HTTPException(404, 'Track not found.')
    path = _library_path(c, url)
    key = f'studio-wave:{url}'
    cached = await c.cache.get(key)
    if cached is not None:
        return cached
    result = await run_in_threadpool(waveform, path)
    await c.cache.put(key, result, ttl=86400)
    return result


@router.get('/studio/sounds')
async def studio_sounds(user=Depends(get_current_user), c=Depends(get_container)):
    """Built-in sound effects."""
    from app.core.container import media_root_path
    index = media_root_path(c.settings) / 'studio_sfx' / 'index.json'
    if not index.is_file():
        return {'items': []}
    return {'items': json.loads(index.read_text(encoding='utf-8'))}


@router.get('/studio/voices')
async def studio_voices(user=Depends(get_current_user)):
    return {'items': [dict(id=k, name=v[2], tone=v[3]) for k, v in studio_speech.VOICES.items()]}


class StudioSpeech(BaseModel):
    text: str = Field(min_length=1, max_length=600)
    voice: str = Field(default='nova', max_length=20)
    speed: float = Field(default=1, ge=.5, le=2, allow_inf_nan=False)


@router.post('/peers/{peer}/studio/tts')
async def studio_tts(peer: str, body: StudioSpeech, user=Depends(get_current_user), c=Depends(get_container)):
    """Text to audio: returns an audio file usable on the timeline."""
    target = await resolve_peer(peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, 'Conversation unavailable.')
    if body.voice not in studio_speech.VOICES:
        raise HTTPException(422, 'Unknown voice.')
    await c.cache.rate_limit(user.id, 'studio_tts', 30)
    file_id = uuid.uuid4().hex
    path = Path(c.settings.messaging_media_root).resolve() / (file_id + '.m4a')
    try:
        duration = await run_in_threadpool(studio_speech.speak, body.text, body.voice, body.speed, path)
        c.messaging_service.store_file(file_id, user.id, target.id, str(path), 'speech.m4a', 'audio/mp4')
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return dict(id=file_id, duration=duration, mime='audio/mp4', name='speech.m4a',
                url=f'{c.settings.api_v1_prefix}/messaging/files/{file_id}')


class StudioCaptionSource(BaseModel):
    file_id: str = Field(pattern=r'^[a-f0-9]{32}$')
    at: float = Field(default=0, ge=0, le=3600, allow_inf_nan=False)  # timeline position
    start: float = Field(default=0, ge=0, le=7200, allow_inf_nan=False)
    end: float = Field(gt=0, le=7200, allow_inf_nan=False)
    speed: float = Field(default=1, ge=.1, le=10, allow_inf_nan=False)


class StudioCaptions(BaseModel):
    sources: list[StudioCaptionSource] = Field(min_length=1, max_length=40)
    language: str | None = Field(default=None, pattern=r'^[a-z]{2}$')


@router.post('/peers/{peer}/studio/captions')
async def studio_captions(peer: str, body: StudioCaptions, user=Depends(get_current_user),
                          c=Depends(get_container)):
    """Auto captions: speech in clips / audio → timed lines on the timeline."""
    target = await resolve_peer(peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, 'Conversation unavailable.')
    if sum(s.end - s.start for s in body.sources) > 600:
        raise HTTPException(422, 'Captions work on up to ten minutes of audio.')
    rows = [_studio_file(c, user, target, s.file_id, ('audio/', 'video/')) for s in body.sources]
    await c.cache.rate_limit(user.id, 'studio_captions', 10)
    lines = []

    def run():
        import tempfile
        with tempfile.TemporaryDirectory(prefix='phlio-captions-') as temp:
            for i, (row, src) in enumerate(zip(rows, body.sources)):
                wav = Path(temp) / f'{i}.wav'
                try:
                    extract_speech(row['path'], src.start, src.end, src.speed, wav)
                except Exception:
                    continue  # no audio stream
                for line in studio_speech.transcribe(wav, body.language):
                    shift = src.at
                    line['start'] = round(line['start'] + shift, 3)
                    line['end'] = round(line['end'] + shift, 3)
                    for w in line['words']:
                        w['start'] = round(w['start'] + shift, 3)
                        w['end'] = round(w['end'] + shift, 3)
                    lines.append(line)

    async with _studio_lock:
        await run_in_threadpool(run)
    lines.sort(key=lambda l: l['start'])
    return {'lines': lines}


# -- live location ------------------------------------------------------------------------
#
# "Share live location" in a DM: the sender opens a session for a while (15
# minutes to 8 hours), the app pushes positions while it runs, and both
# people read the latest one. The chat message carries the session id
# (`phlio-live:<id>`); the session row keeps a short trail for the map.

LIVE_MINUTES = (15, 60, 480)


class LivePosition(BaseModel):
    """A position fix from the sharer's phone."""

    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracy: float = Field(default=0, ge=0, le=100000)


class LiveStartIn(LivePosition):
    peer: str = Field(min_length=1, max_length=80)
    minutes: int = Field(default=60)


def _live_public(row: dict) -> dict:
    """What either participant sees: position, trail, until and whether it's still live."""
    import datetime as dt
    until = dt.datetime.fromisoformat(row["until"])
    active = row.get("stopped_at") is None and until > dt.datetime.now(dt.UTC)
    return dict(id=row["id"].split(":", 1)[1], owner=row["owner"], peer=row["peer"], lat=row["lat"], lng=row["lng"],
                accuracy=row.get("accuracy", 0), updated_at=row["updated_at"], until=row["until"], active=active,
                trail=row.get("trail", [])[-50:])


async def _live_row(c: Container, session_id: str, user: User) -> dict:
    """The session if `user` is one of its two participants, else 404."""
    row = await c.graph.store.get("live_location:" + session_id)
    if not row or user.id not in (row["owner"], row["peer"]):
        raise HTTPException(404, "Live location unavailable.")
    return row


@router.post("/live", status_code=201)
async def start_live(body: LiveStartIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    """Starts sharing live location with one person for `minutes`."""
    import datetime as dt
    from app.domains.graph.store import now
    if body.minutes not in LIVE_MINUTES:
        raise HTTPException(422, "Share for 15 minutes, 1 hour or 8 hours.")
    target = await resolve_peer(body.peer, c)
    if await c.graph.blocked(user.id, target.id):
        raise HTTPException(403, "This conversation is unavailable.")
    await c.cache.rate_limit(user.id, "live_location_start", 20)
    session = uuid.uuid4().hex[:20]
    stamp = now()
    until = (dt.datetime.now(dt.UTC) + dt.timedelta(minutes=body.minutes)).isoformat()
    row = await c.graph.store.put("live_location:" + session, dict(
        owner=user.id, peer=target.id, lat=body.lat, lng=body.lng, accuracy=body.accuracy,
        started_at=stamp, updated_at=stamp, until=until, stopped_at=None,
        trail=[dict(lat=body.lat, lng=body.lng, at=stamp)]))
    return _live_public(row)


@router.put("/live/{session_id}")
async def update_live(session_id: str, body: LivePosition, user: User = Depends(get_current_user),
                      c: Container = Depends(get_container)):
    """A new position from the sharer (ignored once the session has ended)."""
    from app.domains.graph.store import now
    row = await _live_row(c, session_id, user)
    if row["owner"] != user.id:
        raise HTTPException(403, "Only the sharer can move this location.")
    if not _live_public(row)["active"]:
        return _live_public(row)
    stamp = now()
    trail = [*row.get("trail", []), dict(lat=body.lat, lng=body.lng, at=stamp)][-50:]
    row = await c.graph.store.put(row["id"], dict(row, lat=body.lat, lng=body.lng, accuracy=body.accuracy,
                                                  updated_at=stamp, trail=trail))
    return _live_public(row)


@router.get("/live/{session_id}")
async def get_live(session_id: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    """Latest position for either participant."""
    return _live_public(await _live_row(c, session_id, user))


@router.delete("/live/{session_id}")
async def stop_live(session_id: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    """Stops sharing (the sharer, or the other person hiding it for both)."""
    from app.domains.graph.store import now
    row = await _live_row(c, session_id, user)
    if row.get("stopped_at") is None:
        row = await c.graph.store.put(row["id"], dict(row, stopped_at=now()))
    return _live_public(row)
