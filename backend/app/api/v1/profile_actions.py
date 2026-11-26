"""Profile bell and the ⋮ menu on someone's profile.

Bell: what you're notified about when someone posts.

    GET  /social/profiles/notify-defaults          your defaults ("All profiles you follow")
    PUT  /social/profiles/notify-defaults          {posts?, videos?, ...: all|relevant|off}
    GET  /social/profiles/{target}/notify          levels for one profile (falls back to defaults)
    PUT  /social/profiles/{target}/notify          {posts?, videos?, clips?, live?, moments?, snaps?, experiences?}

    all       every time they share that kind of thing
    relevant  at most one notification from them a day (default)
    off       none

``fanout(c, author_id, kind, ...)`` is called when a post, video, clip,
live, moment, snap or experience is shared; followers who can see it get a
``new_<kind>`` notification by those rules.

The ⋮ menu:

    GET    /social/profiles/{target}/about         joined date, followers, verified, mutuals
    GET    /social/profiles/{target}/shared        what you have in common
    PUT    /social/profiles/{target}/hide-moments  {hidden}: your moments (and snaps) skip them
    DELETE /social/profiles/{target}/follower      remove them as your follower
    PUT    /social/profiles/{target}/restrict      {restricted}
    POST   /social/profiles/{target}/report        {reason}
    GET    /social/profiles/{target}/relationship  hidden / restricted / follows you / you follow / blocked

Restricting someone: their DMs land in Requests without notifications, and
their comments on your content are visible only to them and you.
Block / unblock use the existing /social/blocks/{target}.
"""

from __future__ import annotations

import datetime as dt
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key
from app.domains.graph.store import now

router = APIRouter(prefix="/social/profiles", tags=["profile actions"])

KINDS = ("posts", "videos", "clips", "live", "moments", "snaps", "experiences")
LEVELS = ("all", "relevant", "off")
DEFAULT = "relevant"
RELEVANT_GAP = dt.timedelta(hours=24)
FANOUT_LIMIT = 2000

Level = Literal["all", "relevant", "off"]


class LevelsIn(BaseModel):
    posts: Level | None = None
    videos: Level | None = None
    clips: Level | None = None
    live: Level | None = None
    moments: Level | None = None
    snaps: Level | None = None
    experiences: Level | None = None


class FlagIn(BaseModel):
    hidden: bool | None = None
    restricted: bool | None = None


class ReportIn(BaseModel):
    reason: str = Field(default="Something else", min_length=1, max_length=300)


def _defaults_key(uid: str) -> str:
    return key("account_setting", uid, "profile_notify")


def _notify_key(owner: str, target: str) -> str:
    return key("profile_notify", owner, target)


async def _target(c, user, target: str):
    person = await c.graph.user(target.lstrip("@"))
    if person.id == user.id:
        raise HTTPException(422, "That's you.")
    if await c.graph.blocked(user.id, person.id):
        raise HTTPException(404, "Profile unavailable.")
    return person


async def _defaults(c, uid: str) -> dict:
    row = await c.graph.store.get(_defaults_key(uid)) or {}
    return {k: row.get(k) if row.get(k) in LEVELS else DEFAULT for k in KINDS}


async def _levels(c, uid: str, target_id: str) -> dict:
    base = await _defaults(c, uid)
    row = await c.graph.store.get(_notify_key(uid, target_id)) or {}
    return {k: row.get(k) if row.get(k) in LEVELS else base[k] for k in KINDS}


def _out(levels: dict) -> dict:
    return dict(levels=levels, all=any(v == "all" for v in levels.values()),
                off=all(v == "off" for v in levels.values()))


@router.get("/notify-defaults")
async def get_defaults(user=Depends(get_current_user), c=Depends(get_container)):
    return _out(await _defaults(c, user.id))


@router.put("/notify-defaults")
async def put_defaults(body: LevelsIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await c.graph.store.get(_defaults_key(user.id)) or {}
    row.update({k: v for k, v in body.model_dump().items() if v is not None})
    await c.graph.store.put(_defaults_key(user.id), {k: v for k, v in dict(row, owner=user.id, updated_at=now()).items()
                                                     if k != "id"})
    return _out(await _defaults(c, user.id))


@router.get("/{target}/notify")
async def get_notify(target: str, user=Depends(get_current_user), c=Depends(get_container)):
    person = await _target(c, user, target)
    return _out(await _levels(c, user.id, person.id))


@router.put("/{target}/notify")
async def put_notify(target: str, body: LevelsIn, user=Depends(get_current_user), c=Depends(get_container)):
    person = await _target(c, user, target)
    row = await c.graph.store.get(_notify_key(user.id, person.id)) or {}
    row.update({k: v for k, v in body.model_dump().items() if v is not None})
    await c.graph.store.put(_notify_key(user.id, person.id),
                            {k: v for k, v in dict(row, owner=user.id, target=person.id, updated_at=now()).items()
                             if k != "id"})
    return _out(await _levels(c, user.id, person.id))


NOUNS = dict(posts="a new post", videos="a new video", clips="a new clip", live="is live now",
             moments="a new moment", snaps="a new snap", experiences="a new experience")


async def fanout(c, author_id: str, kind: str, *, data: dict | None = None, row: dict | None = None,
                 text: str = "") -> int:
    """Notify followers about something the author just shared. ``row`` (a
    moment / snap / experience) limits it to followers who can see it.
    Never raises: a failed fan-out must not fail the upload."""
    try:
        from app.api.v1.notifications import notify
        from app.api.v1.snap_audience import can_view

        author = await c.identity_repository.get_by_id(author_id)
        if author is None or kind not in KINDS:
            return 0
        followers = [e["in"].removeprefix("user:") for e in await c.graph.store.rows("follows", {"out": "user:" + author_id})]
        sent = 0
        nowish = dt.datetime.now(dt.UTC)
        for uid in followers[:FANOUT_LIMIT]:
            if uid == author_id or await c.graph.blocked(uid, author_id):
                continue
            if row is not None and not await can_view(c, uid, row):
                continue
            level = (await _levels(c, uid, author_id))[kind]
            if level == "off":
                continue
            mark = key("profile_notify_sent", uid, author_id)
            if level == "relevant":
                last = await c.graph.store.get(mark)
                if last and nowish - dt.datetime.fromisoformat(last["at"]) < RELEVANT_GAP:
                    continue
            name = author.full_name or author.username
            body = NOUNS[kind] if kind == "live" else f"shared {NOUNS[kind]}" + (f": {text[:80]}" if text else "")
            await notify(c, uid, "social", f"new_{kind.rstrip('s')}", name, body, actor=author_id,
                         data=dict(data or {}, creator=author.username, kind=kind))
            await c.graph.store.put(mark, dict(owner=uid, target=author_id, at=nowish.isoformat()))
            sent += 1
        return sent
    except Exception:  # noqa: BLE001
        return 0


# -- ⋮ menu ------------------------------------------------------------------------------------

async def _followers_of(c, uid):
    return {e["in"].removeprefix("user:") for e in await c.graph.store.rows("follows", {"out": "user:" + uid})}


async def _following_of(c, uid):
    return {e["out"].removeprefix("user:") for e in await c.graph.store.rows("follows", {"in": "user:" + uid})}


@router.get("/{target}/about")
async def about(target: str, user=Depends(get_current_user), c=Depends(get_container)):
    person = await _target(c, user, target)
    followers, following = await _followers_of(c, person.id), await _following_of(c, person.id)
    mine = await _following_of(c, user.id)
    created = getattr(person, "created_at", None)
    return dict(
        profile=c.graph.profile(person),
        joined=created.isoformat() if hasattr(created, "isoformat") else created,
        verified=bool(getattr(person, "is_verified", False)),
        followers=len(followers), following=len(following),
        mutual_followers=len((mine & followers) - {user.id}),
        username=person.username,
    )


@router.get("/{target}/shared")
async def shared(target: str, user=Depends(get_current_user), c=Depends(get_container)):
    """What you two have in common: people, likes, comments, chats."""
    person = await _target(c, user, target)
    mine, theirs = await _following_of(c, user.id), await _following_of(c, person.id)
    both = sorted((mine & theirs) - {user.id, person.id})
    people = []
    for uid in both[:30]:
        if await c.graph.blocked(user.id, uid):
            continue
        try:
            people.append(c.graph.profile(await c.graph.user(uid)))
        except HTTPException:
            continue
    posts, _ = await c.social_repository.list_posts_by_author(person.id, cursor=None, limit=100)
    liked = await c.social_repository.liked_post_ids([p.id for p in posts], user.id) if posts else set()
    messages = len(c.messaging_service.history(user.id, person.id))
    tagged = sum(1 for r in await c.graph.store.rows("social_moment", {"author": person.id})
                 if user.username in (r.get("mentions") or []))
    return dict(both_follow=dict(count=len(both), people=people), liked_posts=len(liked),
                messages=messages, moment_mentions=tagged,
                follows_you=person.id in await _followers_of(c, user.id), you_follow=person.id in mine)


@router.get("/{target}/relationship")
async def relationship(target: str, user=Depends(get_current_user), c=Depends(get_container)):
    person = await c.graph.user(target.lstrip("@"))
    return dict(
        hidden_moments=bool(await c.graph.store.get(key("moment_hide", user.id, person.id))),
        restricted=bool(await c.graph.store.get(key("restrict", user.id, person.id))),
        follows_you=bool(await c.graph.store.get(key("follows", person.id, user.id))),
        you_follow=bool(await c.graph.store.get(key("follows", user.id, person.id))),
        blocked=bool(await c.graph.store.get(key("block", user.id, person.id))),
    )


@router.put("/{target}/hide-moments")
async def hide_moments(target: str, body: FlagIn, user=Depends(get_current_user), c=Depends(get_container)):
    person = await _target(c, user, target)
    k = key("moment_hide", user.id, person.id)
    if body.hidden:
        await c.graph.store.put(k, dict(owner=user.id, target=person.id, created_at=now()))
    else:
        await c.graph.store.delete(k)
    return dict(hidden_moments=bool(body.hidden))


@router.delete("/{target}/follower", status_code=204)
async def remove_follower(target: str, user=Depends(get_current_user), c=Depends(get_container)):
    person = await _target(c, user, target)
    if not await c.graph.store.get(key("follows", person.id, user.id)):
        raise HTTPException(404, "They don't follow you.")
    await c.graph.store.delete(key("follows", person.id, user.id))


@router.put("/{target}/restrict")
async def restrict(target: str, body: FlagIn, user=Depends(get_current_user), c=Depends(get_container)):
    person = await _target(c, user, target)
    k = key("restrict", user.id, person.id)
    if body.restricted:
        await c.graph.store.put(k, dict(owner=user.id, target=person.id, created_at=now()))
    else:
        await c.graph.store.delete(k)
    return dict(restricted=bool(body.restricted))


@router.post("/{target}/report", status_code=204)
async def report(target: str, body: ReportIn, user=Depends(get_current_user), c=Depends(get_container)):
    person = await _target(c, user, target)
    await c.cache.rate_limit(user.id, "profile_report", 20)
    await c.graph.store.put(key("user_report", user.id, person.id),
                            dict(reporter=user.id, target=person.id, reason=body.reason.strip(), created_at=now()))


_tasks: set = set()


def fanout_later(c, author_id: str, kind: str, **kw) -> None:
    """Runs :func:`fanout` in the background so uploads return at once."""
    import asyncio
    task = asyncio.get_running_loop().create_task(fanout(c, author_id, kind, **kw))
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


async def restricted_by(c, owner: str) -> set[str]:
    """People ``owner`` has restricted."""
    return {r["target"] for r in await c.graph.store.rows("restrict", {"owner": owner})}


async def hidden_from(c, owner: str, viewer: str) -> bool:
    return bool(await c.graph.store.get(key("moment_hide", owner, viewer)))
