from app.api.v1.snap_audience import SnapAudience, validate_audience, can_view
"""Cross-platform engagement, discovery and permission-checked sharing."""

import hashlib
import logging
import random
import uuid
from typing import Literal
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import TAXONOMY, key
from app.domains.graph.store import now

router = APIRouter(tags=["content and sharing"])


async def resolve(c, viewer, platform, ref):
    if platform not in TAXONOMY:
        raise HTTPException(404, "Content unavailable.")
    oid = key("phlio_object", platform, ref)
    obj = await c.graph.store.get(oid)
    if not obj:
        if platform == "social":
            post = await c.social_repository.get_post(ref)
            if post:
                obj = await c.graph.register_object(
                    post.author_id, "social.post", ref, post.text[:160] or "Media post"
                )
            else:
                # Seeded/imported videos and clips may predate graph objects:
                # register them on first use so likes, shares and comments work.
                video = c.social_video_service.db.execute(
                    "SELECT * FROM videos WHERE id=?", (ref,)
                ).fetchone()
                if video:
                    kind = video["kind"] if video["kind"] in ("video", "clip") else "video"
                    obj = await c.graph.register_object(
                        video["creator"], "social." + kind, ref, (video["title"] or "Video")[:160]
                    )
        elif platform == "rooms":
            room = await c.rooms_repository.get_room(ref)
            if room:
                obj = await c.graph.register_object(
                    room.created_by or "platform",
                    "rooms.room",
                    ref,
                    room.name,
                    audience="room" if room.is_private else "public",
                    room_id=ref,
                )
        elif platform == "shop":
            product = await c.shop_repository.get_product(ref)
            if product:
                seller = await c.shop_repository.get_seller(product.seller_id)
                obj = await c.graph.register_object(
                    seller.user_id if seller else "platform", "shop.product", ref, product.title
                )
        elif platform == "book":
            listing = await c.book_repository.get_listing(ref)
            if listing:
                obj = await c.graph.register_object("platform", "book.activity", ref, listing.title)
    if not obj:
        raise HTTPException(404, "Content unavailable.")
    return await c.graph.object_for(viewer, oid)


async def presentation(c, obj):
    details = await c.graph.store.get(key("platform_content", obj["platform"], obj["domain_ref"])) or {}
    result = dict(
        object_id=obj["id"],
        platform=obj["platform"],
        ref=obj["domain_ref"],
        title=obj["title"],
        description=details.get("description", ""),
        image_url=details.get("image_url"),
        media_url=details.get("media_url"),
        kind=details.get("kind"),
        demo=details.get("demo", False),
    )
    if obj["platform"] in {"news", "book", "shop", "stream"}:
        result.update({field: details.get(field) for field in ("publisher", "source_url", "published_at", "category")})
    if obj["platform"] == "stream":
        for field in ("provider", "attribution", "license_url", "genres", "language", "released",
                      "status", "runtime", "duration", "rating", "age_rating", "studio", "director",
                      "cast", "episodes", "episode_count", "watch_links", "trailer_url", "details_unavailable"):
            result[field] = details.get(field)
    if obj["object_type"] in {"social.video", "social.clip"}:
        video = c.social_video_service.db.execute(
            "SELECT * FROM videos WHERE id=?", (obj["domain_ref"],)
        ).fetchone()
        if video:
            result.update(media_url=video["url"], image_url=video["thumbnail_url"], kind=video["kind"])
    if obj["object_type"] == "social.post":
        post = await c.social_repository.get_post(obj["domain_ref"])
        if post:
            result["description"] = post.text
            if post.media:
                field = "media_url" if post.media[0].kind == "video" else "image_url"
                result[field] = post.media[0].url
    return result


@router.get("/content/{platform}")
async def discover(
    platform: str,
    cursor: str | None = None,
    limit: int = Query(30, ge=1, le=100),
    user=Depends(get_current_user),
    c=Depends(get_container),
):
    if platform not in TAXONOMY:
        raise HTTPException(404, "Platform unavailable.")
    if platform == "stream":
        from app.domains.stream.catalog import ensure_catalog
        await ensure_catalog(c)
    cache_key = f"catalog:{await c.graph.store.revision()}:{platform}"
    rows = await c.cache.get(cache_key)
    if rows is None:
        rows = await c.graph.store.rows("platform_content", {"platform": platform})
        await c.cache.put(cache_key, rows)
    rows = sorted(rows, key=lambda r: r["id"])
    if cursor:
        rows = [r for r in rows if r["id"] > cursor]
    items = []
    last = None
    for row in rows:
        last = row["id"]
        # Generated demo catalogs are retained for old shares/history, but no
        # longer appear beside sourced listings in public discovery.
        if platform != 'social' and row.get('demo') and not row.get('source_url'):
            continue
        try:
            obj = await c.graph.object_for(user.id, row.get('object_id') or key('phlio_object', platform, row['domain_ref']))
        except HTTPException:
            continue
        items.append(await presentation(c, obj))
        if len(items) == limit:
            break
    return dict(items=items, next_cursor=last if len(items) == limit else None)


@router.get("/content/{platform}/{ref}")
async def content(platform: str, ref: str, user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c, user.id, platform, ref)
    if platform == "stream":
        from app.domains.stream.catalog import details
        await details(c, ref)
    result = await presentation(c, obj)
    # Author header for shared-content cards in DMs.
    owner = obj.get("owner")
    person = await c.identity_repository.get_by_id(owner) if owner else None
    if person:
        result["author"] = c.graph.profile(person)
    return result


# Demo engagement baseline: the dev graph only has 100 synthetic accounts and
# most of their activity is friends-only, so real counts read as 0 for a new
# viewer. Every object gets stable, deterministic "artificial" numbers (same
# value on every screen and after restarts) that real activity is added on top
# of, plus a few synthetic demo accounts to fill the three-avatar like stack.
DEMO_ENGAGEMENT = True
_demo_profiles: dict = {}


def _baseline(object_id):
    rng = random.Random(hashlib.sha256(object_id.encode()).hexdigest())
    likes = min(48000, 14 + int(rng.lognormvariate(5.0, 1.1)))
    return dict(
        likes=likes,
        views_count=likes * rng.randint(9, 28) + rng.randint(0, 999),
        bookmarks_count=max(1, likes * rng.randint(4, 14) // 100),
        shares_count=max(1, likes * rng.randint(3, 12) // 100),
        reposts_count=likes * rng.randint(2, 9) // 100,
        likers=[f"demo_{n:03}" for n in rng.sample(range(20, 100), 12)],
    )


async def _demo_profile(c, uid):
    if uid not in _demo_profiles:
        person = await c.identity_repository.get_by_id(uid)
        _demo_profiles[uid] = c.graph.profile(person) if person else None
    return _demo_profiles[uid]


async def _blocked_ids(c, viewer):
    """Everyone the viewer blocked or was blocked by, in two queries (instead
    of two lookups per person — engagement reads run for every card)."""
    outgoing = await c.graph.store.rows("block", {"in": "user:" + viewer})
    incoming = await c.graph.store.rows("block", {"out": "user:" + viewer})
    return {str(r["out"]).removeprefix("user:") for r in outgoing} | {
        str(r["in"]).removeprefix("user:") for r in incoming}


def _visible_total(viewer, rows, blocked):
    """Totals count everyone except blocked accounts; privacy settings only
    hide *who* acted, never the number (as on other social apps)."""
    return sum(1 for row in rows
               if (actor := row["in"].removeprefix("user:")) == viewer or actor not in blocked)


@router.get("/content/{platform}/{ref}/engagement")
async def engagement(platform: str, ref: str, user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c, user.id, platform, ref)
    blocked = await _blocked_ids(c, user.id)
    actors = {}
    mine = False
    cache_key = f"likes:{await c.graph.store.revision()}:{obj['id']}"
    activities = await c.cache.get(cache_key)
    if activities is None:
        activities = await c.graph.store.rows("activity", {"out": obj["id"], "verb": "liked"})
        await c.cache.put(cache_key, activities)
    # Reauthorize cached candidates on every read, including policy expiry.
    for activity in activities:
        if activity["in"] == "user:" + user.id:
            mine = True
        signal = await c.graph.signal(user.id, activity)
        if signal and signal["actor"]:
            actors[signal["actor"]["id"]] = signal["actor"]
    count = _visible_total(user.id, activities, blocked)
    people = list(actors.values())
    # Keep the viewer's visible like in the three-avatar preview, even when
    # many other people liked first. Privacy filtering above still applies.
    people.sort(key=lambda person: person['id'] != user.id)
    followers = {edge['in'].removeprefix('user:') for edge in
                 await c.graph.store.rows('follows', {'out': 'user:' + user.id})}
    follower_people = [person for person in people if person['id'] == user.id or person['id'] in followers]

    base = _baseline(obj["id"]) if DEMO_ENGAGEMENT else None
    metrics = {}
    for verb, label in [("saved", "bookmarks"), ("shared", "shares"), ("viewed", "views"), ("reposted", "reposts")]:
        metric_key = f"engagement:{await c.graph.store.revision()}:{obj['id']}:{verb}"
        rows = await c.cache.get(metric_key)
        if rows is None:
            rows = await c.graph.store.rows("activity", {"out": obj["id"], "verb": verb})
            await c.cache.put(metric_key, rows)
        metrics[label + "_count"] = _visible_total(user.id, rows, blocked)
        metrics[verb + "_by_me"] = any(row["in"] == "user:" + user.id for row in rows)
    # Extra counters must never take down the like preview (avatar stack).
    metrics["comments_count"] = 0
    try:
        # Every share counts (not just one per person), like other social apps.
        share_events = await c.graph.store.rows("share_event", {"object_id": obj["id"]})
        metrics["shares_count"] = max(metrics["shares_count"], len(share_events))
        # Comment count for the engagement bar — mirrors the visibility rules of
        # GET /social/content/{ref}/comments (blocked authors are hidden).
        comment_key = f"comments:{await c.graph.store.revision()}:{obj['id']}"
        comment_rows = await c.cache.get(comment_key)
        if comment_rows is None:
            comment_rows = await c.graph.store.rows("content_comment", {"object_id": obj["id"]})
            await c.cache.put(comment_key, comment_rows)
        authors = [row["author_id"] for row in comment_rows]
        if obj["object_type"] == "social.post":
            legacy, _ = await c.social_service.get_comments(ref, cursor=None, limit=100)
            removed = {row["comment_id"] for row in await c.graph.store.rows("comment_tombstone", {"object_id": obj["id"]})}
            authors += [comment.author_id for comment in legacy if comment.id not in removed]
        metrics["comments_count"] = sum(author not in blocked for author in authors)
    except Exception:
        logging.getLogger(__name__).exception("engagement extras failed for %s", obj["id"])

    if base:
        count += base["likes"]
        for name in ("views_count", "bookmarks_count", "shares_count", "reposts_count"):
            metrics[name] += base[name]
        seen = {person["id"] for person in people}
        for uid in base["likers"]:
            if uid in seen or uid == obj.get("owner") or uid == user.id:
                continue
            if uid in blocked:
                continue
            try:
                profile = await _demo_profile(c, uid)
            except Exception:
                profile = None
            if profile:
                people.append(profile)
                seen.add(uid)
    # Likers you follow ("liked by people you know" bubbles on clips).
    following = {edge["out"].removeprefix("user:") for edge in
                 await c.graph.store.rows("follows", {"in": "user:" + user.id})}
    following_people = [person for person in people if person["id"] in following]
    return dict(
        **metrics,
        count=count,
        following_avatars=following_people[:3],
        avatars=people[:3],
        follower_avatars=follower_people[:3],
        follower_like_count=sum(person["id"] != user.id for person in follower_people),
        people=people,
        more_count=max(0, count - min(3, len(people))),
        liked_by_me=mine,
    )


@router.put("/content/{platform}/{ref}/like")
async def like(platform: str, ref: str, user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c, user.id, platform, ref)
    aid = key("activity", user.id, obj["id"], "liked")
    if platform == "social" and obj["object_type"] == "social.post":
        await c.social_service.toggle_like(ref, user.id)
    elif await c.graph.store.get(aid):
        await c.graph.store.delete(aid)
    else:
        await c.graph.action(user.id, obj["id"], "liked")
    return await engagement(platform, ref, user, c)


@router.put("/content/{platform}/{ref}/actions/{verb}")
async def interact(platform: str, ref: str, verb: Literal["saved", "reposted", "viewed", "shared"],
                   user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c, user.id, platform, ref)
    aid = key("activity", user.id, obj["id"], verb)
    existing = await c.graph.store.get(aid)
    if verb == "shared":
        await record_share(c, user.id, obj["id"])
    if existing and verb not in {"viewed", "shared"}:
        await c.graph.store.delete(aid)
    elif not existing:
        await c.graph.action(user.id, obj["id"], verb)
    return await engagement(platform, ref, user, c)


class ShareIn(BaseModel):
    destination: Literal["dm", "group", "new_group", "room"]
    target: str | None = None
    members: list[str] = Field(default_factory=list, max_length=20)
    name: str = Field(default="Shared plans", min_length=1, max_length=80)
    message: str | None = Field(default=None, max_length=1000)


async def group_for(c, user, gid):
    if not gid.startswith("graph_group:"):
        raise HTTPException(404, "Group unavailable.")
    group = await c.graph.store.get(gid)
    if not group or user not in group["members"]:
        raise HTTPException(404, "Group unavailable.")
    return group


@router.get("/sharing/destinations")
async def destinations(user=Depends(get_current_user), c=Depends(get_container)):
    # Instagram order: recent chats, then people you're connected with
    # (mutuals, followers, following, friends), then suggestions. Each person
    # carries a `relation` line so it's clear who you're sending to.
    blocked = await _blocked_ids(c, user.id)
    connections = await c.graph.connections(user.id)
    followers = {p["id"]: p for p in connections["followers"]}
    following = {p["id"]: p for p in connections["following"]}
    friends = {f["peer"]["id"]: f["peer"] for f in connections["friends"] if f["status"] == "accepted"}

    def relation(pid):
        if pid in followers and pid in following:
            return "Follows each other"
        if pid in followers:
            return "Follows you"
        if pid in following:
            return "Following"
        if pid in friends:
            return "Friend"
        return "Suggested"

    ordered = {}

    def add(person, recent=False):
        pid = person["id"]
        if pid == user.id or pid in blocked or pid in ordered:
            return
        ordered[pid] = dict(person, relation=relation(pid), recent=recent)

    for peer_id in c.messaging_service.peers(user.id)[:12]:
        person = await c.identity_repository.get_by_id(peer_id)
        if person:
            add(c.graph.profile(person), recent=True)
    for group in (
        [p for pid, p in followers.items() if pid in following],
        list(followers.values()),
        list(following.values()),
        list(friends.values()),
    ):
        for person in sorted(group, key=lambda p: (p.get("display_name") or "").lower()):
            add(person)
    for person in await c.identity_repository.search_users("", 60):
        add(c.graph.profile(person))
    people = list(ordered.values())
    rooms = [dict(id=r.id, name=r.name) for r in await c.rooms_repository.list_member_rooms(user.id)]
    groups = []
    for g in await c.graph.store.rows("graph_group"):
        if user.id not in g["members"]:
            continue
        # Two member faces for the group's stacked avatar in the share sheet.
        faces = []
        for member in [m for m in g["members"] if m != user.id][:2]:
            person = await c.identity_repository.get_by_id(member)
            if person:
                faces.append(c.graph.profile(person))
        groups.append(dict(id=g["id"], name=g["name"], avatars=faces))
    return dict(people=people, rooms=rooms, groups=groups)


@router.post("/content/{platform}/{ref}/share", status_code=201)
async def share(
    platform: str, ref: str, body: ShareIn, user=Depends(get_current_user), c=Depends(get_container)
):
    obj = await resolve(c, user.id, platform, ref)
    if obj["platform"] == "pay" and obj["object_type"] != "pay.merchant":
        raise HTTPException(403, "Financial records cannot be shared.")
    await c.cache.rate_limit(user.id, "share", 30)
    link = f"phlio://content/{platform}/{quote(ref, safe='')}"
    text = f"Shared: {obj['title']}\n{link}"
    group = None
    if body.destination == "dm":
        peer = await c.graph.user(body.target or "")
        if await c.graph.blocked(user.id, peer.id):
            raise HTTPException(403, "Recipient unavailable.")
        await c.graph.object_for(peer.id, obj["id"])
        c.messaging_service.send(user.id, peer.id, text, [])
        if body.message and body.message.strip():
            c.messaging_service.send(user.id, peer.id, body.message.strip(), [])
        target = peer.username
    elif body.destination == "room":
        target = body.target or ""
        if not await c.rooms_repository.is_member(target, user.id):
            raise HTTPException(403, "Join this room first.")
        if obj["audience"] != "public" and obj.get("room_id") != target:
            raise HTTPException(403, "Content is not visible to this room.")
        await c.rooms_service.send_message(room_id=target, author_id=user.id, text=text)
        if body.message and body.message.strip():
            await c.rooms_service.send_message(room_id=target, author_id=user.id, text=body.message.strip())
    else:
        if body.destination == "new_group":
            members = {user.id}
            for member in body.members:
                members.add((await c.graph.user(member)).id)
            if len(members) < 3:
                raise HTTPException(422, "Choose at least two other people.")
            for a in members:
                await c.graph.object_for(a, obj["id"])
                for b in members:
                    if a != b and await c.graph.blocked(a, b):
                        raise HTTPException(403, "These members cannot share a group.")
            group = dict(
                name=body.name.strip() or "Shared plans",
                owner=user.id,
                members=sorted(members),
                created_at=now(),
            )
            target = "graph_group:" + uuid.uuid4().hex
        else:
            target = body.target or ""
            group = await group_for(c, user.id, target)
        for member in group["members"]:
            if await c.graph.blocked(user.id, member):
                raise HTTPException(403, "Group sharing unavailable.")
            await c.graph.object_for(member, obj["id"])
        if body.destination == "new_group":
            await c.graph.store.put(target, group)
        await c.graph.store.put(
            "graph_group_message:" + uuid.uuid4().hex,
            dict(group_id=target, author=user.id, text=text, object_id=obj["id"], created_at=now()),
        )
        if body.message and body.message.strip():
            await c.graph.store.put(
                "graph_group_message:" + uuid.uuid4().hex,
                dict(group_id=target, author=user.id, text=body.message.strip(), created_at=now()),
            )
    await c.graph.action(user.id, obj["id"], "shared")
    await record_share(c, user.id, obj["id"])
    return dict(destination=body.destination, target=target, shared=True)


async def record_share(c, user_id, object_id):
    await c.graph.store.put("share_event:" + uuid.uuid4().hex,
                            dict(object_id=object_id, user_id=user_id, created_at=now()))


class GroupMessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


@router.get("/messaging/groups")
async def groups(user=Depends(get_current_user), c=Depends(get_container)):
    return [g for g in await c.graph.store.rows("graph_group") if user.id in g["members"]]


class CreateGroupIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    members: list[str] = Field(min_length=2, max_length=20)


@router.post("/messaging/groups", status_code=201)
async def create_group(body: CreateGroupIn, user=Depends(get_current_user), c=Depends(get_container)):
    if not body.name.strip():
        raise HTTPException(422, "Enter a group name.")
    members = {user.id}
    for member in body.members:
        members.add((await c.graph.user(member)).id)
    if len(members) < 3:
        raise HTTPException(422, "Choose at least two other people.")
    for a in members:
        for b in members:
            if a != b and await c.graph.blocked(a, b):
                raise HTTPException(403, "These members cannot share a group.")
    await c.cache.rate_limit(user.id, "create_group", 20)
    gid = "graph_group:" + uuid.uuid4().hex
    await c.graph.store.put(gid, dict(name=body.name.strip(), owner=user.id,
        members=sorted(members), created_at=now()))
    return dict(id=gid, name=body.name.strip())


@router.get("/messaging/groups/{gid}/messages")
async def group_messages(gid: str, user=Depends(get_current_user), c=Depends(get_container)):
    group = await group_for(c, user.id, gid)
    items = []
    rows = sorted(
        await c.graph.store.rows("graph_group_message", {"group_id": gid}),
        key=lambda r: (r["created_at"], r["id"]),
    )[-100:]
    for row in rows:
        if await c.graph.blocked(user.id, row["author"]):
            continue
        item = dict(row)
        item["author_profile"] = c.graph.profile(await c.graph.user(row["author"]))
        if row.get("object_id"):
            try:
                item["content"] = await presentation(c, await c.graph.object_for(user.id, row["object_id"]))
            except HTTPException:
                item["text"] = "Shared content is no longer available."
        items.append(item)
    return dict(name=group["name"], items=items)


@router.post("/messaging/groups/{gid}/messages", status_code=201)
async def group_send(
    gid: str, body: GroupMessageIn, user=Depends(get_current_user), c=Depends(get_container)
):
    group = await group_for(c, user.id, gid)
    for member in group["members"]:
        if await c.graph.blocked(user.id, member):
            raise HTTPException(403, "Group messaging unavailable.")
    await c.cache.rate_limit(user.id, "group_message", 60)
    if not body.text.strip():
        raise HTTPException(422, "Write a message.")
    return await c.graph.store.put(
        "graph_group_message:" + uuid.uuid4().hex,
        dict(group_id=gid, author=user.id, text=body.text.strip(), created_at=now()),
    )


async def accepted_friends(c, uid):
    result = set()
    for field in ("in", "out"):
        for edge in await c.graph.store.rows("friend", {field: "user:" + uid, "status": "accepted"}):
            result.add(edge["out" if field == "in" else "in"].removeprefix("user:"))
    return result


@router.get("/social/creators/{target}/mutuals")
async def mutuals(target: str, user=Depends(get_current_user), c=Depends(get_container)):
    peer = await c.graph.user(target)
    if await c.graph.blocked(user.id, peer.id):
        raise HTTPException(404, "Profile unavailable.")
    shared = await accepted_friends(c, user.id) & await accepted_friends(c, peer.id)
    people = []
    for uid in sorted(shared - {user.id, peer.id}):
        if not await c.graph.blocked(user.id, uid) and not await c.graph.blocked(peer.id, uid):
            people.append(c.graph.profile(await c.graph.user(uid)))
    # Instagram-style known followers: people the viewer follows or has
    # accepted as friends who also follow this profile. Never expose blocks.
    known = await accepted_friends(c, user.id)
    known.update(
        edge["out"].removeprefix("user:")
        for edge in await c.graph.store.rows("follows", {"in": "user:" + user.id})
    )
    followers = {
        edge["in"].removeprefix("user:")
        for edge in await c.graph.store.rows("follows", {"out": "user:" + peer.id})
    }
    familiar = []
    for uid in sorted((known & followers) - {user.id, peer.id}):
        if not await c.graph.blocked(user.id, uid) and not await c.graph.blocked(peer.id, uid):
            familiar.append(c.graph.profile(await c.graph.user(uid)))
    return dict(
        count=len(people),
        avatars=people[:3],
        follower_avatars=follower_people[:3],
        follower_like_count=sum(person["id"] != user.id for person in follower_people),
        people=people,
        followed_by=dict(count=len(familiar), avatars=familiar[:3], people=familiar),
    )


@router.post("/content/{platform}/{ref}/story", status_code=201)
async def share_story(platform: str, ref: str, user=Depends(get_current_user), c=Depends(get_container), body: SnapAudience | None = None):
    import datetime as dt

    obj = await resolve(c, user.id, platform, ref)
    if obj["audience"] != "public" or (platform == "pay" and obj["object_type"] != "pay.merchant"):
        raise HTTPException(403, "Only public content can be added to a story.")
    policy = await validate_audience(c, user.id, body) if body else {}
    await c.cache.rate_limit(user.id, "share_story", 20)
    return await c.graph.store.put(
        "shared_story:" + uuid.uuid4().hex,
        dict(
            author=user.id,
            **policy,
            object_id=obj["id"],
            created_at=now(),
            expires_at=(dt.datetime.now(dt.UTC) + dt.timedelta(hours=24)).isoformat(),
        ),
    )


@router.get("/social/shared-stories")
async def shared_stories(user=Depends(get_current_user), c=Depends(get_container)):
    import datetime as dt

    visible = await accepted_friends(c, user.id) | {user.id}
    visible.update(
        row["out"].removeprefix("user:")
        for row in await c.graph.store.rows("follows", {"in": "user:" + user.id})
    )
    items = []
    for row in sorted(
        await c.graph.store.rows("shared_story"), key=lambda r: str(r["created_at"]), reverse=True
    ):
        expiry = dt.datetime.fromisoformat(str(row["expires_at"]).replace("Z", "+00:00"))
        if (
            expiry <= dt.datetime.now(dt.UTC)
            or (not await can_view(c, user.id, row) if "audience" in row else row["author"] not in visible)
            or await c.graph.blocked(user.id, row["author"])
        ):
            continue
        try:
            obj = await c.graph.object_for(user.id, row["object_id"])
        except HTTPException:
            continue
        items.append(
            dict(
                id=row["id"],
                author=c.graph.profile(await c.graph.user(row["author"])),
                content=await presentation(c, obj),
                expires_at=row["expires_at"],
            )
        )
    from app.api.v1.social import memories
    for memory in await memories(user, c):
        if memory.get('kind') in {'moment', 'experience'}:
            expiry = dt.datetime.fromisoformat(memory['created_at']) + dt.timedelta(hours=24)
            if expiry > dt.datetime.now(dt.UTC):
                items.append(dict(id=memory['id'], author=memory['author'], expires_at=expiry.isoformat(),
                    content=dict(title=memory['caption'], image_url=memory['image_url'], kind=memory['kind'])))
    return items


@router.get("/library/{verb}")
async def library(verb: Literal["saved", "reposted"], user=Depends(get_current_user), c=Depends(get_container)):
    rows = await c.graph.store.rows("activity", {"in": "user:" + user.id, "verb": verb})
    result = []
    for row in sorted(rows, key=lambda r: r.get("created_at", ""), reverse=True):
        try:
            result.append(await presentation(c, await c.graph.object_for(user.id, row["out"])))
        except HTTPException:
            continue
    return {"items": result}
