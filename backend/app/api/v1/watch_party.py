"""Watch together: one synced player for everyone in a chat or call.

Contexts (``/watch/{ctx}/{target}``):
    dm/{username}      a Phlio Social DM — posts, videos and clips
    call/{call_id}     the DM call (same party as the DM)
    room/{room_id}     a Phlio Room (text or voice) — posts, videos, clips
                       and all of Phlio Stream: movies, series, anime, music

    GET    /watch/{ctx}/{target}                 the party now (position computed
                                                 from the last update), or null
    POST   /watch/{ctx}/{target}/start           {platform, ref} — start / switch title
    POST   /watch/{ctx}/{target}/control         {action: play|pause|seek, position_ms}
    POST   /watch/{ctx}/{target}/react           {emoji} — floats over everyone's player
    POST   /watch/{ctx}/{target}/join | /leave
    DELETE /watch/{ctx}/{target}                 end it
    GET    /watch/library?ctx=dm|room&q=&kind=   what can be watched there

Anyone in the party can play, pause and seek (Instagram / Discord style);
clients poll the state about once a second and correct drift > 1.5 s.
Starting a party posts a card in the chat ("🍿 Watching X together · Join").
"""

from __future__ import annotations

import datetime as dt
import time
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.api.v1.content import presentation, resolve
from app.domains.graph.service import key

router = APIRouter(prefix="/watch", tags=["watch together"])

SOCIAL = {"social.post", "social.video", "social.clip"}
STREAM = {"stream.movie", "stream.series", "stream.episode", "stream.track", "stream.scene"}
ALLOWED = {"dm": SOCIAL, "room": SOCIAL | STREAM}


class StartIn(BaseModel):
    platform: str = Field(pattern="^(social|stream)$")
    ref: str = Field(min_length=1, max_length=200)


class ControlIn(BaseModel):
    action: str = Field(pattern="^(play|pause|seek)$")
    position_ms: int = Field(default=0, ge=0, le=12 * 3600 * 1000)


class ReactIn(BaseModel):
    emoji: str = Field(min_length=1, max_length=16)


def _ms() -> int:
    return int(time.time() * 1000)


async def _context(c, user, ctx: str, target: str) -> tuple[str, str, list[str], dict]:
    """(kind, party key, members, info) — and checks you belong there."""
    if ctx in {"dm", "call"}:
        if ctx == "call":
            call = c.messaging_service.call(target, user.id)
            peer_id = call["recipient_id"] if call["caller_id"] == user.id else call["caller_id"]
            peer = await c.identity_repository.get_by_id(peer_id)
        else:
            peer = await c.identity_repository.get_by_username(target)
        if peer is None or peer.id == user.id:
            raise HTTPException(404, "Chat not found.")
        if await c.graph.blocked(user.id, peer.id):
            raise HTTPException(403, "You can't watch with this person.")
        a, b = sorted([user.id, peer.id])
        return "dm", f"watch_party:dm_{a}_{b}", [user.id, peer.id], dict(peer=peer)
    if ctx == "room":
        room = await c.rooms_repository.get_room(target)
        if room is None:
            raise HTTPException(404, "Room not found.")
        if not await c.rooms_repository.is_member(target, user.id):
            raise HTTPException(403, "Join the room to watch together.")
        return "room", f"watch_party:room_{target}", [], dict(room=room)
    raise HTTPException(404, "Unknown chat.")


def _state(row: dict | None) -> dict | None:
    if not row:
        return None
    now = _ms()
    position = row["position_ms"] + (now - row["updated_ms"] if row["playing"] else 0)
    duration = (row.get("item") or {}).get("duration_ms")
    if duration and position >= duration:
        position = duration
    reactions = [r for r in row.get("reactions", []) if now - r["at_ms"] < 8000]
    return dict(id=row["id"], kind=row["kind"], item=row["item"], playing=row["playing"], position_ms=position,
                server_ms=now, started_by=row["started_by"], viewers=row.get("viewers", []),
                reactions=reactions, updated_by=row.get("updated_by"), version=row.get("version", 0))


async def _viewers(c, ids: list[str]) -> list[dict]:
    out = []
    for uid in ids[:12]:
        person = await c.identity_repository.get_by_id(uid)
        if person:
            out.append(c.graph.profile(person))
    return out


async def _post(c, kind: str, info: dict, user, text: str) -> None:
    """The party card in the chat."""
    try:
        if kind == "dm":
            c.messaging_service.send(user.id, info["peer"].id, text, [])
        else:
            await c.rooms_service.send_message(room_id=info["room"].id, author_id=user.id, text=text, attachments=[])
    except Exception:
        pass


@router.get("/library")
async def library(ctx: str = Query(pattern="^(dm|call|room)$"), q: str = Query("", max_length=80),
                  kind: str = Query("all", max_length=20), user=Depends(get_current_user), c=Depends(get_container)):
    """What you can watch together here, newest first. ``playable`` says
    whether Phlio has the media itself (others open their page)."""
    allowed = ALLOWED["room" if ctx == "room" else "dm"]
    words = q.lower().split()
    items = []
    platforms = ["social", "stream"] if ctx == "room" else ["social"]
    for platform in platforms:
        rows = await c.graph.store.rows("platform_content", {"platform": platform})
        objects = {o["id"]: o for o in await c.graph.store.get_many(
            [key("phlio_object", platform, r["domain_ref"]) for r in rows])}
        for row in rows:
            obj = objects.get(key("phlio_object", platform, row["domain_ref"]))
            if not obj or obj.get("object_type") not in allowed:
                continue
            row_kind = "anime" if row.get("category") == "anime" else row.get("kind")
            if kind != "all" and kind != row_kind:
                continue
            title = str(obj.get("title") or row.get("description") or "")
            hay = f"{title} {row.get('publisher') or ''} {' '.join(row.get('tags') or [])} {row.get('category') or ''}".lower()
            if words and not all(w in hay for w in words):
                continue
            items.append(dict(platform=platform, ref=row["domain_ref"], kind=row_kind,
                              category=row.get("category"), title=title[:120], image_url=row.get("image_url"),
                              publisher=row.get("publisher"), playable=bool(row.get("media_url")),
                              created=str(row.get("published_at") or row.get("created_at") or "")))
    # Phlio Social posts.
    if kind in {"all", "post"}:
        posts, _ = await c.social_repository.list_feed(cursor=None, limit=60)
        for post in posts:
            if words and not all(w in post.text.lower() for w in words):
                continue
            media = post.media[0] if post.media else None
            items.append(dict(platform="social", ref=post.id, kind="post", category=None,
                              title=(post.text or "Media post")[:120],
                              image_url=media.url if media and media.kind != "video" else None,
                              publisher=None, playable=True, created=post.created_at.isoformat()))
    # Social videos and clips live in their own table.
    for v in c.social_video_service.videos(None):
        k = v.get("kind") if v.get("kind") in {"video", "clip"} else "video"
        if kind not in {"all", k}:
            continue
        if words and not all(w in (v.get("title") or "").lower() for w in words):
            continue
        if any(i["platform"] == "social" and i["ref"] == v["id"] for i in items):
            continue
        items.append(dict(platform="social", ref=v["id"], kind=k, category=None, title=(v.get("title") or "")[:120],
                          image_url=v.get("thumbnail_url"), publisher=None, playable=bool(v.get("url")),
                          created=v.get("created_at") or ""))
    items.sort(key=lambda i: (i["playable"], i["created"]), reverse=True)
    return {"items": items[:120]}


@router.get("/{ctx}/{target}")
async def get_party(ctx: str, target: str, user=Depends(get_current_user), c=Depends(get_container)):
    _, pid, _, _ = await _context(c, user, ctx, target)
    return {"party": _state(await c.graph.store.get(pid))}


@router.post("/{ctx}/{target}/start")
async def start(ctx: str, target: str, body: StartIn, user=Depends(get_current_user), c=Depends(get_container)):
    kind, pid, members, info = await _context(c, user, ctx, target)
    obj = await resolve(c, user.id, body.platform, body.ref)
    if obj["object_type"] not in ALLOWED[kind]:
        raise HTTPException(422, "Rooms can watch Phlio Stream too; DMs watch posts, videos and clips."
                            if kind == "dm" else "That can't be watched together.")
    shown = await presentation(c, obj)
    item = dict(platform=shown["platform"], ref=shown["ref"], title=shown["title"], kind=shown.get("kind"),
                object_type=obj["object_type"], image_url=shown.get("image_url"), media_url=shown.get("media_url"),
                description=(shown.get("description") or "")[:300], publisher=shown.get("publisher"),
                category=shown.get("category"), trailer_url=shown.get("trailer_url"),
                duration_ms=int((shown.get("runtime") or 0) * 60000) or None)
    existing = await c.graph.store.get(pid)
    viewers = list(dict.fromkeys([user.id, *((existing or {}).get("viewer_ids") or [])]))
    row = await c.graph.store.put(pid, dict(
        id=pid, kind=kind, context=target, item=item, playing=bool(item["media_url"]), position_ms=0,
        updated_ms=_ms(), started_by=c.graph.profile(user), started_at=dt.datetime.now(dt.UTC).isoformat(),
        viewer_ids=viewers, viewers=await _viewers(c, viewers), reactions=[], updated_by=user.id,
        version=int((existing or {}).get("version", 0)) + 1, party=uuid.uuid4().hex[:8]))
    await _post(c, kind, info, user, f"🍿 Watching “{item['title']}” together\nphlio-watch:{ctx if ctx != 'call' else 'dm'}")
    return {"party": _state(row)}


@router.post("/{ctx}/{target}/control")
async def control(ctx: str, target: str, body: ControlIn, user=Depends(get_current_user), c=Depends(get_container)):
    _, pid, _, _ = await _context(c, user, ctx, target)
    row = await c.graph.store.get(pid)
    if not row:
        raise HTTPException(404, "Nothing is playing.")
    now_state = _state(row)
    position = body.position_ms if body.action == "seek" else (body.position_ms or now_state["position_ms"])
    playing = {"play": True, "pause": False}.get(body.action, row["playing"])
    row = await c.graph.store.put(pid, dict(row, playing=playing, position_ms=position, updated_ms=_ms(),
                                            updated_by=user.id, version=int(row.get("version", 0)) + 1))
    return {"party": _state(row)}


@router.post("/{ctx}/{target}/react")
async def react(ctx: str, target: str, body: ReactIn, user=Depends(get_current_user), c=Depends(get_container)):
    _, pid, _, _ = await _context(c, user, ctx, target)
    row = await c.graph.store.get(pid)
    if not row:
        raise HTTPException(404, "Nothing is playing.")
    now = _ms()
    reactions = [r for r in row.get("reactions", []) if now - r["at_ms"] < 8000][-30:]
    reactions.append(dict(emoji=body.emoji, by=c.graph.profile(user), at_ms=now, id=uuid.uuid4().hex[:8]))
    row = await c.graph.store.put(pid, dict(row, reactions=reactions))
    return {"party": _state(row)}


@router.post("/{ctx}/{target}/join")
async def join(ctx: str, target: str, user=Depends(get_current_user), c=Depends(get_container)):
    _, pid, _, _ = await _context(c, user, ctx, target)
    row = await c.graph.store.get(pid)
    if not row:
        raise HTTPException(404, "Nothing is playing.")
    ids = list(dict.fromkeys([*(row.get("viewer_ids") or []), user.id]))
    row = await c.graph.store.put(pid, dict(row, viewer_ids=ids, viewers=await _viewers(c, ids)))
    return {"party": _state(row)}


@router.post("/{ctx}/{target}/leave")
async def leave(ctx: str, target: str, user=Depends(get_current_user), c=Depends(get_container)):
    _, pid, _, _ = await _context(c, user, ctx, target)
    row = await c.graph.store.get(pid)
    if not row:
        return {"party": None}
    ids = [i for i in row.get("viewer_ids") or [] if i != user.id]
    if not ids:
        await c.graph.store.delete(pid)
        return {"party": None}
    row = await c.graph.store.put(pid, dict(row, viewer_ids=ids, viewers=await _viewers(c, ids)))
    return {"party": _state(row)}


@router.delete("/{ctx}/{target}", status_code=204)
async def end(ctx: str, target: str, user=Depends(get_current_user), c=Depends(get_container)):
    _, pid, _, _ = await _context(c, user, ctx, target)
    await c.graph.store.delete(pid)
