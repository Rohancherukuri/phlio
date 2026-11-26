"""Phlio notifications: one feed for every platform, shown in the app's
"island" banner (frontend: shared/notifications/).

Each notification names its platform (dm, social, rooms, shop, news,
stream, book, pay, agent) so the app can show that platform's icon and
colour, plus what the banner needs to act on it right there:

    dm      message    {peer, message_id, attachment}     reply, react, GIF, sticker
    rooms   message    {room_id, room_name}                reply, react, GIF, sticker
    social  comment / reply / mention  {path, comment_id, content_title}
    shop    similar_items  {because, products:[{id, title, price…, image_url}]}  add to bag
    news    story      {path, ref, image_url, publisher}  bookmark → playlist
    stream  song       {path, ref, title, artist, image_url, media_url}  play
    stream  title      {path, ref, image_url, kind}       banner

Producers:
  * every DM sent through ``messaging_service.send`` (chats, shares,
    comment DMs) and every room message (``rooms_service.send_message``) —
    hooked once per container by :func:`install_hooks`;
  * comments and @mentions on Social / Stream / Shop / News content
    (``social_comments.create`` calls :func:`notify_comment`);
  * a gentle "pulse" when the app polls: at most one suggestion per poll,
    ≥12 min apart, each platform ≤ once every 6 h — a new News story, a song
    or a movie / show on Stream, similar Shop items.

Repeated messages from the same chat / room collapse into one unread
notification (``group``) whose text and count update.

Endpoints (``/api/v1/notifications``):
  GET    ?since=<iso>&limit=&pulse=      newest first, with ``unread``
  POST   /read      {ids?: [...], group?: "dm:<user id>"}
  POST   /read-all
  DELETE /{id}
  POST   /preview   one sample banner of each kind, for trying the island
"""

from __future__ import annotations

import asyncio
import datetime as dt
import logging
import random
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key
from app.domains.graph.store import now
from app.infrastructure import onesignal

router = APIRouter(prefix="/notifications", tags=["notifications"])
logger = logging.getLogger("phlio.notifications")

PLATFORMS = {"dm", "social", "rooms", "shop", "news", "stream", "book", "pay", "agent"}
PULSE_GAP = dt.timedelta(minutes=12)
PLATFORM_GAP = dt.timedelta(hours=6)
KEEP = 200  # per user


def _time(value) -> dt.datetime:
    t = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return t if t.tzinfo else t.replace(tzinfo=dt.UTC)


async def notify(c, user_id: str, platform: str, kind: str, title: str, body: str, *,
                 actor: str | None = None, data: dict | None = None, group: str | None = None,
                 push: bool = True) -> dict | None:
    """Adds (or, with ``group``, updates the unread) notification for
    ``user_id``, and sends it as a push when OneSignal is set up."""
    if platform not in PLATFORMS or not user_id or user_id == actor:
        return None
    if actor and await c.graph.blocked(user_id, actor):
        return None
    stamp = now()
    body = (body or "").strip()
    if len(body) > 300:
        body = body[:297] + "…"
    if group:
        rid = key("phlio_notification", user_id, group)
        existing = await c.graph.store.get(rid)
        if existing and not existing.get("read"):
            saved = await c.graph.store.put(rid, dict(
                existing, title=title, body=body, actor=actor, data=data or {}, kind=kind,
                count=int(existing.get("count") or 1) + 1, at=stamp))
            if push:
                _spawn(_push(c, saved))
            return saved
    else:
        rid = "phlio_notification:" + uuid.uuid4().hex
    saved = await c.graph.store.put(rid, dict(
        user_id=user_id, platform=platform, kind=kind, title=title, body=body, actor=actor,
        data=data or {}, group=group, count=1, read=False, created_at=stamp, at=stamp))
    await _trim(c, user_id)
    if push:
        _spawn(_push(c, saved))
    return saved


async def _push(c, row: dict) -> None:
    if not onesignal.enabled(c.settings):
        return
    actor = None
    if row.get("actor"):
        person = await c.identity_repository.get_by_id(row["actor"])
        actor = c.graph.profile(person) if person else None
    await onesignal.send(c.settings, row, actor)


async def _trim(c, user_id):
    rows = await c.graph.store.rows("phlio_notification", {"user_id": user_id})
    if len(rows) > KEEP:
        for row in sorted(rows, key=lambda r: r["at"])[: len(rows) - KEEP]:
            await c.graph.store.delete(row["id"])


# -- producers ---------------------------------------------------------------------------

def _describe(text: str, attachments: list) -> tuple[str, str | None]:
    text = (text or "").strip()
    # Cards the app draws from markers: say what they are instead.
    if "phlio-blend:" in text:
        return "invited you to a Blend 🎬", None
    if "phlio-watch:" in text:
        return text.split("\n", 1)[0], None
    if text.startswith("phlio-system:pin:"):
        return "pinned a message 📌", None
    # Things shared from inside Phlio arrive as cards, not links.
    if "phlio://" in text:
        words = [line for line in text.split("\n") if "phlio://" not in line and line.strip()]
        shared = next((w[len("Shared: "):] for w in words if w.startswith("Shared: ")), None)
        rest = [w for w in words if not w.startswith("Shared: ")]
        if rest:
            return " ".join(rest)[:300], None
        if "phlio://profile/" in text or "phlio://app/creator/" in text:
            return "shared a profile", None
        if "phlio://app/moments/" in text:
            return "shared a moment", None
        return (f"shared “{shared}”" if shared else "shared a post"), None
    kinds = [str((a or {}).get("kind") or "") for a in attachments or []]
    if text:
        return text, (kinds[0] if kinds else None)
    label = {"gif": "sent a GIF", "sticker": "sent a sticker", "image": "sent a photo", "video": "sent a video",
             "audio": "sent a voice message", "document": "sent a file"}
    return (label.get(kinds[0], "sent an attachment") if kinds else "sent a message"), (kinds[0] if kinds else None)


async def notify_dm(c, sender: str, recipient: str, message: dict) -> None:
    try:
        person = await c.identity_repository.get_by_id(sender)
        if not person:
            return
        from app.api.v1.messaging import chat_pref
        if (await chat_pref(c, recipient, sender)).get("muted"):
            return  # the recipient muted this chat
        text, attachment = _describe(message.get("text", ""), message.get("attachments") or [])
        await notify(c, recipient, "dm", "message", person.full_name or person.username, text,
                     actor=sender, group=f"dm:{sender}",
                     data=dict(peer=person.username, message_id=message.get("id"), attachment=attachment))
    except Exception:  # a notification must never break sending
        logger.exception("notifications.dm_failed")


async def _room_members(c, room) -> set[str]:
    members: set[str] = set()
    obj_id = key("phlio_object", "rooms", room.id)
    for row in await c.graph.store.rows("graph_member", {"out": obj_id}):
        members.add(str(row["in"]).removeprefix("user:"))
    store = getattr(c.rooms_repository, "_members", None)  # in-memory backend
    if isinstance(store, dict):
        members |= set(store.get(room.id, set()))
    return members


async def notify_room(c, message) -> None:
    try:
        room = await c.rooms_repository.get_room(message.room_id)
        author = await c.identity_repository.get_by_id(message.author_id)
        if not room or not author:
            return
        text, attachment = _describe(message.text, [{"kind": a.kind} for a in message.attachments or []])
        for member in await _room_members(c, room):
            if member == message.author_id:
                continue
            await notify(c, member, "rooms", "message", room.name, f"{author.full_name}: {text}",
                         actor=message.author_id, group=f"room:{room.id}",
                         data=dict(room_id=room.id, room_name=room.name, message_id=message.id,
                                   attachment=attachment))
    except Exception:
        logger.exception("notifications.room_failed")


async def notify_comment(c, user, obj: dict, comment: dict, mentioned: list[dict], parent: dict | None = None) -> None:
    """New comment: the content's owner, the comment replied to, and @mentions."""
    try:
        platform = obj.get("platform") or "social"
        path = f"{platform}/{obj.get('domain_ref')}"
        title_of = obj.get("title") or "your post"
        text = comment.get("text") or (
            "a voice note 🎙️" if comment.get("audio_url") else
            f"🎵 {comment['music']['title']}" if comment.get("music") else
            "a sticker" if comment.get("sticker_id") else "a photo")
        base = dict(path=path, comment_id=comment.get("id"), content_title=title_of)
        who = user.full_name or user.username
        target_platform = platform if platform in PLATFORMS else "social"
        done = {user.id}
        if parent and parent.get("author_id") and parent["author_id"] not in done:
            await notify(c, parent["author_id"], target_platform, "reply", who, f"replied to your comment: {text}",
                         actor=user.id, data=base)
            done.add(parent["author_id"])
        owner = obj.get("owner")
        if owner and owner not in done:
            await notify(c, owner, target_platform, "comment", who, f"commented: {text}", actor=user.id, data=base)
            done.add(owner)
        for person in mentioned:
            pid = person.get("id")
            if pid and pid not in done:
                await notify(c, pid, target_platform, "mention", who, f"mentioned you: {text}", actor=user.id, data=base)
                done.add(pid)
    except Exception:
        logger.exception("notifications.comment_failed")


_tasks: set = set()


def _spawn(coro) -> None:
    try:
        task = asyncio.get_running_loop().create_task(coro)
    except RuntimeError:
        coro.close()
        return
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


def install_hooks(c) -> None:
    """Every DM and room message notifies its recipients (once per container)."""
    ms = c.messaging_service
    if not getattr(ms, "_phlio_notify", False):
        original_send = ms.send

        def send(sender, recipient, text, attachments, reply_to=None):
            message = original_send(sender, recipient, text, attachments, reply_to=reply_to)
            _spawn(notify_dm(c, sender, recipient, message))
            return message

        ms.send = send
        ms._phlio_notify = True
    rs = c.rooms_service
    if not getattr(rs, "_phlio_notify", False):
        original_room = rs.send_message

        async def send_message(**kwargs):
            message = await original_room(**kwargs)
            _spawn(notify_room(c, message))
            return message

        rs.send_message = send_message
        rs._phlio_notify = True


# -- suggestions ("pulse") ------------------------------------------------------------------

async def _content_rows(c, platform: str, *, demo: bool = False) -> list[dict]:
    return [r for r in await c.graph.store.rows("platform_content", {"platform": platform})
            if demo or not (r.get("demo") and not r.get("source_url"))]


async def _pulse_news(c, user, seen: set) -> dict | None:
    rows = sorted(await _content_rows(c, "news"), key=lambda r: str(r.get("published_at") or ""), reverse=True)
    for row in rows[:60]:
        oid = row.get("object_id") or key("phlio_object", "news", row["domain_ref"])
        obj = await c.graph.store.get(oid)
        if not obj or oid in seen:
            continue
        seen.add(oid)
        return await notify(c, user.id, "news", "story", row.get("publisher") or "Phlio News", obj["title"],
                            data=dict(path=f"news/{row['domain_ref']}", ref=row["domain_ref"],
                                      image_url=row.get("image_url"), publisher=row.get("publisher")), push=False)
    return None


async def _pulse_stream(c, user, seen: set) -> dict | None:
    rows = await _content_rows(c, "stream")
    songs = [r for r in rows if r.get("kind") == "song" and r.get("media_url")]
    titles = [r for r in rows if r.get("kind") in {"movie", "series"} and r.get("image_url")]
    pools = [p for p in ([songs, titles] if random.random() < .5 else [titles, songs]) if p]
    for pool in pools:
        random.shuffle(pool)
        for row in pool[:40]:
            oid = row.get("object_id") or key("phlio_object", "stream", row["domain_ref"])
            obj = await c.graph.store.get(oid)
            if not obj or oid in seen:
                continue
            seen.add(oid)
            path = f"stream/{row['domain_ref']}"
            if row.get("kind") == "song":
                return await notify(c, user.id, "stream", "song", "Song for you", f"{obj['title']} · {row.get('publisher') or ''}",
                                    data=dict(path=path, ref=row["domain_ref"], title=obj["title"],
                                              artist=row.get("publisher") or "", image_url=row.get("image_url"),
                                              media_url=row.get("media_url")), push=False)
            label = "New series to watch" if row.get("kind") == "series" else "Movie night"
            return await notify(c, user.id, "stream", "title", label, obj["title"],
                                data=dict(path=path, ref=row["domain_ref"], image_url=row.get("image_url"),
                                          kind=row.get("kind"), category=row.get("category")), push=False)
    return None


def _product(p) -> dict:
    return dict(id=p.id, title=p.title, price_minor_units=p.price_minor_units, currency=p.currency,
                image_url=(p.image_urls or [None])[0], category=str(p.category))


async def _pulse_shop(c, user, seen: set, push: bool = False) -> dict | None:
    cart = [r["product_id"] for r in await c.graph.store.rows("shop_cart", {"user_id": user.id})]
    anchor = None
    for pid in cart:
        anchor = await c.shop_repository.get_product(pid)
        if anchor:
            break
    products, _ = await c.shop_repository.list_products(
        category=anchor.category if anchor else None, max_price_minor_units=None, cursor=None, limit=40)
    pool = [p for p in products if p.id not in cart and (not anchor or p.id != anchor.id) and p.id not in seen]
    if len(pool) < 2 and anchor:  # nothing left in that category: anything new
        products, _ = await c.shop_repository.list_products(category=None, max_price_minor_units=None, cursor=None, limit=40)
        pool = [p for p in products if p.id not in cart and p.id not in seen]
    if not pool:
        return None
    random.shuffle(pool)
    picks = pool[:4]
    seen.update(p.id for p in picks)
    because = anchor.title if anchor else None
    return await notify(c, user.id, "shop", "similar_items",
                        "Similar to your bag" if anchor else "Picked for you",
                        f"Like “{because}”" if because else "New finds on Phlio Shop",
                        data=dict(because=because, products=[_product(p) for p in picks]), push=push)


async def _pulse(c, user) -> None:
    sid = key("notification_state", user.id)
    state = await c.graph.store.get(sid)
    moment = dt.datetime.now(dt.UTC)
    if not state:
        # First poll: the first suggestion comes a couple of minutes later.
        state = dict(user_id=user.id, last_pulse=(moment - PULSE_GAP + dt.timedelta(minutes=2)).isoformat(),
                     platforms={}, seen=[])
        await c.graph.store.put(sid, state)
        return
    if moment - _time(state["last_pulse"]) < PULSE_GAP:
        return
    seen = set(state.get("seen") or [])
    makers = {"news": _pulse_news, "stream": _pulse_stream, "shop": _pulse_shop}
    order = sorted(makers, key=lambda p: state["platforms"].get(p, ""))
    for platform in order:
        last = state["platforms"].get(platform)
        if last and moment - _time(last) < PLATFORM_GAP:
            continue
        try:
            made = await makers[platform](c, user, seen)
        except Exception:
            logger.exception("notifications.pulse_failed platform=%s", platform)
            made = None
        state["platforms"][platform] = moment.isoformat()
        if made:
            break
    state["last_pulse"] = moment.isoformat()
    state["seen"] = list(seen)[-300:]
    await c.graph.store.put(sid, state)


# -- API -------------------------------------------------------------------------------------

async def _out(c, row: dict, cache: dict) -> dict:
    actor = None
    if row.get("actor"):
        if row["actor"] not in cache:
            person = await c.identity_repository.get_by_id(row["actor"])
            cache[row["actor"]] = c.graph.profile(person) if person else None
        actor = cache[row["actor"]]
    return dict(id=row["id"], platform=row["platform"], kind=row["kind"], title=row["title"], body=row["body"],
                actor=actor, data=row.get("data") or {}, group=row.get("group"), count=row.get("count", 1),
                read=bool(row.get("read")), at=row["at"], created_at=row["created_at"])


@router.get("")
async def feed(since: str | None = Query(default=None, max_length=40), limit: int = Query(default=40, ge=1, le=100),
               platform: str | None = Query(default=None, max_length=20), pulse: bool = True,
               user=Depends(get_current_user), c=Depends(get_container)):
    install_hooks(c)
    if pulse:
        await _pulse(c, user)
    rows = await c.graph.store.rows("phlio_notification", {"user_id": user.id})
    unread = sum(1 for r in rows if not r.get("read"))
    if platform:
        rows = [r for r in rows if r["platform"] == platform]
    if since:
        try:
            after = _time(since)
        except ValueError:
            raise HTTPException(422, "Invalid time.")
        rows = [r for r in rows if _time(r["at"]) > after]
    rows.sort(key=lambda r: r["at"], reverse=True)
    cache: dict = {}
    items = []
    for row in rows[:limit]:
        if row.get("actor") and await c.graph.blocked(user.id, row["actor"]):
            continue
        items.append(await _out(c, row, cache))
    return dict(items=items, unread=unread, server_time=now())


class ReadIn(BaseModel):
    ids: list[str] = Field(default_factory=list, max_length=200)
    group: str | None = Field(default=None, max_length=120)


@router.post("/read", status_code=204)
async def mark_read(body: ReadIn, user=Depends(get_current_user), c=Depends(get_container)):
    targets = set(body.ids)
    for row in await c.graph.store.rows("phlio_notification", {"user_id": user.id}):
        if row.get("read"):
            continue
        if row["id"] in targets or (body.group and row.get("group") == body.group):
            await c.graph.store.put(row["id"], dict(row, read=True))


@router.post("/read-all", status_code=204)
async def read_all(user=Depends(get_current_user), c=Depends(get_container)):
    for row in await c.graph.store.rows("phlio_notification", {"user_id": user.id}):
        if not row.get("read"):
            await c.graph.store.put(row["id"], dict(row, read=True))


@router.delete("/{notification_id}", status_code=204)
async def remove(notification_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await c.graph.store.get(notification_id) if notification_id.startswith("phlio_notification:") else None
    if not row or row["user_id"] != user.id:
        raise HTTPException(404, "Notification unavailable.")
    await c.graph.store.delete(notification_id)


# -- preview ------------------------------------------------------------------------------------

_PREVIEW_PEOPLE = ("artbykiara", "neha", "arjun", "meera", "kabir", "zara")


async def _make_preview(c, user, *, push: bool) -> list[str]:

    made: list[str] = []
    friend = None
    for name in _PREVIEW_PEOPLE:
        person = await c.identity_repository.get_by_username(name)
        if person and person.id != user.id:
            friend = person
            break
    if friend is None:
        friend = next((p for p in await c.identity_repository.search_users("a", limit=10) if p.id != user.id), None)
    if friend:
        await notify(c, user.id, "dm", "message", friend.full_name or friend.username,
                     "Are we still on for tonight? 🍿", actor=friend.id, group=f"preview:dm:{uuid.uuid4().hex[:6]}",
                     data=dict(peer=friend.username, message_id=None, attachment=None, preview=True), push=push)
        made.append("dm")
    try:
        rooms = await c.rooms_service.my_rooms(user.id)
    except Exception:
        rooms = []
    if rooms:
        room = rooms[0]
        others = [m for m in await _room_members(c, room) if m != user.id]
        author = (await c.identity_repository.get_by_id(others[0])) if others else friend
        if author:
            await notify(c, user.id, "rooms", "message", room.name,
                         f"{author.full_name or author.username}: who's joining the call later?",
                         actor=author.id, group=f"preview:room:{uuid.uuid4().hex[:6]}",
                         data=dict(room_id=room.id, room_name=room.name, message_id=None, attachment=None,
                                   preview=True), push=push)
            made.append("rooms")
    seen: set = set()
    try:
        if await _pulse_shop(c, user, seen, push=push):
            made.append("shop")
    except Exception:
        logger.exception("notifications.preview_failed platform=shop")
    news = sorted(await _content_rows(c, "news", demo=True), key=lambda r: str(r.get("published_at") or ""), reverse=True)
    for row in news[:20]:
        oid = row.get("object_id") or key("phlio_object", "news", row["domain_ref"])
        obj = await c.graph.store.get(oid)
        if obj:
            await notify(c, user.id, "news", "story", row.get("publisher") or "Phlio News", obj["title"],
                         data=dict(path=f"news/{row['domain_ref']}", ref=row["domain_ref"],
                                   image_url=row.get("image_url"), publisher=row.get("publisher")), push=push)
            made.append("news")
            break
    # One song and one movie / show.
    rows = await _content_rows(c, "stream", demo=True)
    for want in ("song", "title"):
        if want == "song":
            pool = [r for r in rows if r.get("kind") == "song" and r.get("media_url")]
        else:
            pool = [r for r in rows if r.get("kind") in {"movie", "series"} and r.get("image_url")]
        random.shuffle(pool)
        for row in pool[:20]:
            oid = row.get("object_id") or key("phlio_object", "stream", row["domain_ref"])
            obj = await c.graph.store.get(oid)
            if not obj:
                continue
            path = f"stream/{row['domain_ref']}"
            if want == "song":
                await notify(c, user.id, "stream", "song", "Song for you", f"{obj['title']} · {row.get('publisher') or ''}",
                             data=dict(path=path, ref=row["domain_ref"], title=obj["title"],
                                       artist=row.get("publisher") or "", image_url=row.get("image_url"),
                                       media_url=row.get("media_url")), push=push)
            else:
                await notify(c, user.id, "stream", "title",
                             "New series to watch" if row.get("kind") == "series" else "Movie night", obj["title"],
                             data=dict(path=path, ref=row["domain_ref"], image_url=row.get("image_url"),
                                       kind=row.get("kind"), category=row.get("category")), push=push)
            made.append(f"stream:{want}")
            break
    return made


@router.post("/preview")
async def preview(user=Depends(get_current_user), c=Depends(get_container)):
    """A sample of every kind of banner, for trying the island out.

    Only notification rows are created for *you* — nobody else is messaged.
    Replies you send from them are real (to that person / your room); the
    News, Stream and Shop ones use real catalogue items.
    """
    return {"created": await _make_preview(c, user, push=False)}


class PushTestIn(BaseModel):
    delay_seconds: int = Field(default=10, ge=0, le=120)


@router.get("/push/status")
async def push_status(c=Depends(get_container)):
    """Whether the server can send pushes, and the OneSignal app id the app
    should use (public; the REST key never leaves the server)."""
    return {"enabled": onesignal.enabled(c.settings), "app_id": c.settings.onesignal_app_id or None}


@router.post("/push/test")
async def push_test(body: PushTestIn, user=Depends(get_current_user), c=Depends(get_container)):
    """The same samples as /preview, sent as real pushes after
    ``delay_seconds`` — time to lock the phone or leave the app."""
    if not onesignal.enabled(c.settings):
        raise HTTPException(503, "Push isn't set up on the server: add ONESIGNAL_APP_ID and ONESIGNAL_REST_API_KEY.")

    async def later():
        await asyncio.sleep(body.delay_seconds)
        await _make_preview(c, user, push=True)

    _spawn(later())
    return {"scheduled": True, "delay_seconds": body.delay_seconds}
