"""Cross-platform engagement, discovery and permission-checked sharing."""

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
    if obj["platform"] == "news":
        result.update({field: details.get(field) for field in ("publisher", "source_url", "published_at", "category")})
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
        try:
            obj = await c.graph.object_for(user.id, row["object_id"])
        except HTTPException:
            continue
        items.append(await presentation(c, obj))
        if len(items) == limit:
            break
    return dict(items=items, next_cursor=last if len(items) == limit else None)


@router.get("/content/{platform}/{ref}")
async def content(platform: str, ref: str, user=Depends(get_current_user), c=Depends(get_container)):
    return await presentation(c, await resolve(c, user.id, platform, ref))


@router.get("/content/{platform}/{ref}/engagement")
async def engagement(platform: str, ref: str, user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c, user.id, platform, ref)
    actors = {}
    count = 0
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
        if signal:
            count += 1
            if signal["actor"]:
                actors[signal["actor"]["id"]] = signal["actor"]
    people = list(actors.values())
    metrics = {}
    for verb, label in [("saved", "bookmarks"), ("shared", "shares"), ("viewed", "views"), ("reposted", "reposts")]:
        metric_key = f"engagement:{await c.graph.store.revision()}:{obj['id']}:{verb}"
        rows = await c.cache.get(metric_key)
        if rows is None:
            rows = await c.graph.store.rows("activity", {"out": obj["id"], "verb": verb})
            await c.cache.put(metric_key, rows)
        metrics[label + "_count"] = sum([bool(await c.graph.signal(user.id, row)) for row in rows])
        metrics[verb + "_by_me"] = any(row["in"] == "user:" + user.id for row in rows)
    return dict(
        **metrics,
        count=count,
        avatars=people[:3],
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
async def interact(platform: str, ref: str, verb: Literal["saved", "reposted", "viewed"],
                   user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c, user.id, platform, ref)
    aid = key("activity", user.id, obj["id"], verb)
    existing = await c.graph.store.get(aid)
    if existing and verb != "viewed":
        await c.graph.store.delete(aid)
    elif not existing:
        await c.graph.action(user.id, obj["id"], verb)
    return await engagement(platform, ref, user, c)


class ShareIn(BaseModel):
    destination: Literal["dm", "group", "new_group", "room"]
    target: str | None = None
    members: list[str] = Field(default_factory=list, max_length=20)
    name: str = Field(default="Shared plans", min_length=1, max_length=80)


async def group_for(c, user, gid):
    if not gid.startswith("graph_group:"):
        raise HTTPException(404, "Group unavailable.")
    group = await c.graph.store.get(gid)
    if not group or user not in group["members"]:
        raise HTTPException(404, "Group unavailable.")
    return group


@router.get("/sharing/destinations")
async def destinations(user=Depends(get_current_user), c=Depends(get_container)):
    people = [
        c.graph.profile(p)
        for p in await c.identity_repository.search_users("", 100)
        if p.id != user.id and not await c.graph.blocked(user.id, p.id)
    ]
    rooms = [dict(id=r.id, name=r.name) for r in await c.rooms_repository.list_member_rooms(user.id)]
    groups = [
        dict(id=g["id"], name=g["name"])
        for g in await c.graph.store.rows("graph_group")
        if user.id in g["members"]
    ]
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
        target = peer.username
    elif body.destination == "room":
        target = body.target or ""
        if not await c.rooms_repository.is_member(target, user.id):
            raise HTTPException(403, "Join this room first.")
        if obj["audience"] != "public" and obj.get("room_id") != target:
            raise HTTPException(403, "Content is not visible to this room.")
        await c.rooms_service.send_message(room_id=target, author_id=user.id, text=text)
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
    await c.graph.action(user.id, obj["id"], "shared")
    return dict(destination=body.destination, target=target, shared=True)


class GroupMessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


@router.get("/messaging/groups")
async def groups(user=Depends(get_current_user), c=Depends(get_container)):
    return [g for g in await c.graph.store.rows("graph_group") if user.id in g["members"]]


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
        people=people,
        followed_by=dict(count=len(familiar), avatars=familiar[:3], people=familiar),
    )


@router.post("/content/{platform}/{ref}/story", status_code=201)
async def share_story(platform: str, ref: str, user=Depends(get_current_user), c=Depends(get_container)):
    import datetime as dt

    obj = await resolve(c, user.id, platform, ref)
    if obj["audience"] != "public" or (platform == "pay" and obj["object_type"] != "pay.merchant"):
        raise HTTPException(403, "Only public content can be added to a story.")
    await c.cache.rate_limit(user.id, "share_story", 20)
    return await c.graph.store.put(
        "shared_story:" + uuid.uuid4().hex,
        dict(
            author=user.id,
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
            or row["author"] not in visible
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
