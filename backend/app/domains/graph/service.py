"""Authorization belongs here, independently of storage and Redis."""

import datetime as dt
import hashlib
import uuid
from collections import Counter

from fastapi import HTTPException

from app.domains.graph.store import now

TAXONOMY = {
    "social": {"post", "video", "clip", "live", "experience"},
    "rooms": {"room", "post", "event"},
    "book": {"restaurant", "place", "event", "hotel", "activity", "booking"},
    "shop": {"product", "store", "collection"},
    "stream": {"movie", "series", "episode", "scene", "track", "creator"},
    "news": {"article", "topic", "publisher"},
    "pay": {"merchant", "payment_request", "transaction_reference"},
}
GENERAL = {
    "liked",
    "saved",
    "reposted",
    "shared",
    "followed",
    "viewed",
    "commented",
    "reacted",
    "created",
    "reported",
    "muted",
}
SPECIFIC = {
    "social": {"watched"},
    "rooms": {"joined", "left", "invited", "attended"},
    "book": {"booked", "attended"},
    "shop": {"purchased", "added_to_cart", "reviewed"},
    "stream": {"watched", "listened"},
    "news": set(),
    "pay": {"paid", "requested_payment"},
}
ALIASES = {
    "like": "liked",
    "save": "saved",
    "share": "shared",
    "view": "viewed",
    "watch": "watched",
    "join": "joined",
    "book": "booked",
    "follow": "followed",
    "listen": "listened",
}
AUDIENCES = {"nobody", "selected_users", "close_friends", "friends", "followers", "room_members", "public"}
FOXY = {"none", "personal", "group", "both"}


def key(table, *parts):
    return table + ":" + hashlib.sha256("|".join(parts).encode()).hexdigest()[:32]


def expired(value):
    return bool(value and dt.datetime.fromisoformat(value.replace("Z", "+00:00")) <= dt.datetime.now(dt.UTC))


class GraphService:
    def __init__(self, store, identity, rooms, cache):
        self.store, self.identity, self.rooms, self.cache = store, identity, rooms, cache
        self.metrics = Counter()

    async def user(self, identifier):
        identifier = identifier.removeprefix("user:")
        user = await self.identity.get_by_id(identifier) or await self.identity.get_by_username(
            identifier.lstrip("@").lower()
        )
        if not user:
            raise HTTPException(404, "User not found.")
        return user

    @staticmethod
    def profile(user):
        return dict(
            id=user.id, username=user.username, display_name=user.full_name, avatar_url=user.avatar_url
        )

    async def blocked(self, a, b):
        return bool(await self.store.get(key("block", a, b)) or await self.store.get(key("block", b, a)))

    async def friendship(self, a, b):
        return await self.store.get(key("friend", *sorted([a, b])))

    async def friends(self, a, b):
        relation = await self.friendship(a, b)
        return bool(relation and relation["status"] == "accepted" and not await self.blocked(a, b))

    async def relationship(self, actor, target_id, action):
        target = await self.user(target_id)
        other = target.id
        if actor == other:
            raise HTTPException(422, "Choose another user.")
        await self.cache.rate_limit(actor, "relationship", 60)
        if action == "block":
            await self.store.put(
                key("block", actor, other),
                {
                    "in": "user:" + actor,
                    "out": "user:" + other,
                    "created_at": now(),
                    "reason_code": "user_requested",
                },
            )
            for record_id in [
                key("friend", *sorted([actor, other])),
                key("follows", actor, other),
                key("follows", other, actor),
            ]:
                await self.store.delete(record_id)
            return {"status": "blocked"}
        if action == "unblock":
            await self.store.delete(key("block", actor, other))
            return {"status": "removed"}
        if await self.blocked(actor, other):
            raise HTTPException(403, "This relationship is unavailable.")
        if action in {"follow", "unfollow"}:
            record_id = key("follows", actor, other)
            if action == "unfollow":
                await self.store.delete(record_id)
            else:
                await self.store.put(
                    record_id, {"in": "user:" + actor, "out": "user:" + other, "created_at": now()}
                )
            return {"status": "following" if action == "follow" else "removed"}
        record_id = key("friend", *sorted([actor, other]))
        existing = await self.store.get(record_id)
        if action == "request":
            if existing:
                raise HTTPException(409, "A friendship or request already exists.")
            existing = {
                "in": "user:" + min(actor, other),
                "out": "user:" + max(actor, other),
                "status": "pending",
                "requested_by": actor,
                "created_at": now(),
            }
        elif action == "accept":
            if not existing or existing["status"] != "pending" or existing["requested_by"] == actor:
                raise HTTPException(404, "Pending request not found.")
            existing.update(status="accepted", accepted_at=now())
        elif action in {"remove", "decline"}:
            if action == "decline" and existing and existing["requested_by"] == actor:
                raise HTTPException(403, "Only the recipient can decline.")
            await self.store.delete(record_id)
            return {"status": "removed"}
        else:
            raise HTTPException(400, "Unknown relationship action.")
        await self.store.put(record_id, existing)
        return {"relationship_id": record_id, "status": existing["status"], "target": self.profile(target)}

    async def connections(self, actor):
        result = []
        for field in ("in", "out"):
            for relation in await self.store.rows("friend", {field: "user:" + actor}):
                other = relation["out" if field == "in" else "in"].removeprefix("user:")
                if not await self.blocked(actor, other):
                    result.append(
                        dict(
                            peer=self.profile(await self.user(other)),
                            status=relation["status"],
                            incoming=relation["requested_by"] != actor,
                        )
                    )
        following = []
        for relation in await self.store.rows("follows", {"in": "user:" + actor}):
            other = relation["out"].removeprefix("user:")
            if not await self.blocked(actor, other):
                following.append(self.profile(await self.user(other)))
        return dict(friends=result, following=following)

    async def register_object(
        self, owner, object_type, domain_ref, title, audience="public", room_id=None, parent_id=None
    ):
        platform, _, subtype = object_type.partition(".")
        if subtype not in TAXONOMY.get(platform, set()):
            raise HTTPException(400, "Unknown object type.")
        if audience not in {"public", "private", "room"}:
            raise HTTPException(400, "Invalid object audience.")
        if platform == "pay" and subtype != "merchant":
            audience = "private"
        if audience == "room" and not room_id:
            raise HTTPException(400, "Room-scoped objects need a room.")
        record_id = key("phlio_object", platform, domain_ref)
        existing = await self.store.get(record_id)
        if existing and existing["owner"] != owner:
            raise HTTPException(403, "Object belongs to another owner.")
        if parent_id:
            await self.object_for(owner, parent_id)
        value = await self.store.put(
            record_id,
            dict(
                owner=owner,
                object_type=object_type,
                platform=platform,
                domain_ref=domain_ref,
                title=title,
                state=existing["state"] if existing else "active",
                audience=audience,
                room_id=room_id,
                parent_id=parent_id,
                created_at=existing["created_at"] if existing else now(),
            ),
        )
        if parent_id:
            await self.store.put(
                key("object_link", record_id, parent_id),
                {"in": record_id, "out": parent_id, "kind": "part_of"},
            )
        return value

    async def bind_alias(self, owner, object_id, provider, external_id):
        obj = await self.object_for(owner, object_id)
        if obj["owner"] != owner:
            raise HTTPException(403, "Only the object owner can manage aliases.")
        alias_id = key("object_alias", provider, external_id)
        existing = await self.store.get(alias_id)
        if existing and existing["object_id"] != object_id:
            raise HTTPException(409, "Alias already belongs to another object.")
        return await self.store.put(
            alias_id, dict(provider=provider, external_id=external_id, object_id=object_id)
        )

    async def related_objects(self, viewer, object_id):
        await self.object_for(viewer, object_id)
        result = []
        for edge in await self.store.rows("object_link", {"out": object_id}):
            try:
                result.append(await self.object_for(viewer, edge["in"]))
            except HTTPException:
                continue
        return result

    async def object_for(self, viewer, object_id):
        if not object_id.startswith("phlio_object:"):
            raise HTTPException(404, "Object unavailable.")
        obj = await self.store.get(object_id)
        if not obj or obj["state"] != "active" or await self.blocked(viewer, obj["owner"]):
            raise HTTPException(404, "Object unavailable.")
        allowed = obj["owner"] == viewer or obj["audience"] == "public"
        if obj["audience"] == "room" and obj.get("room_id"):
            allowed = allowed or await self.rooms.is_member(obj["room_id"], viewer)
        if not allowed:
            raise HTTPException(404, "Object unavailable.")
        return obj

    async def set_policy(self, actor, policy):
        if (
            policy["audience"] not in AUDIENCES
            or policy["identity_mode"] not in {"identified", "anonymous", "hidden"}
            or policy["foxy_access"] not in FOXY
        ):
            raise HTTPException(400, "Invalid policy.")
        platform, object_type, verb = policy["platform"], policy["object_type"], policy["verb"]
        if platform not in {*TAXONOMY, "*"} or (
            verb != "*" and verb not in GENERAL.union(*SPECIFIC.values())
        ):
            raise HTTPException(400, "Invalid policy scope.")
        if object_type != "*" and object_type not in {
            f"{p}.{t}" for p, types in TAXONOMY.items() for t in types
        }:
            raise HTTPException(400, "Invalid object class.")
        policy.update(owner=actor, updated_at=now())
        return await self.store.put(key("privacy_policy", actor, platform, object_type, verb), policy)

    async def policy(self, actor, obj, verb):
        candidates = await self.store.rows("privacy_policy", {"owner": actor})
        candidates = [
            p
            for p in candidates
            if not expired(p.get("expires_at"))
            and p["platform"] in {"*", obj["platform"]}
            and p["object_type"] in {"*", obj["object_type"]}
            and p["verb"] in {"*", verb}
        ]
        if not candidates:
            return dict(audience="nobody", identity_mode="hidden", foxy_access="none", selected_users=[])
        return max(
            candidates,
            key=lambda p: (p["object_type"] != "*", p["verb"] != "*", p["platform"] != "*", p["updated_at"]),
        )

    async def audience_allows(self, viewer, actor, obj, policy):
        if viewer == actor:
            return True
        if await self.blocked(viewer, actor):
            return False
        audience = policy["audience"]
        if audience == "public":
            return True
        if audience == "selected_users":
            return viewer in policy.get("selected_users", [])
        if audience == "friends":
            return await self.friends(viewer, actor)
        if audience == "close_friends":
            return viewer in policy.get("selected_users", []) and await self.friends(viewer, actor)
        if audience == "followers":
            return bool(await self.store.get(key("follows", viewer, actor)))
        if audience == "room_members" and obj.get("room_id"):
            return await self.rooms.is_member(obj["room_id"], viewer)
        return False

    async def action(self, actor, object_id, verb, *, trusted=False):
        obj = await self.object_for(actor, object_id)
        verb = ALIASES.get(verb, verb)
        if verb not in GENERAL | SPECIFIC[obj["platform"]]:
            raise HTTPException(400, "Action is not valid for this object.")
        if (
            verb in {"paid", "purchased", "booked", "requested_payment", "created", "joined", "left"}
            and not trusted
        ):
            raise HTTPException(403, "This action must come from the authorized domain workflow.")
        await self.cache.rate_limit(actor, "activity", 240)
        policy = await self.policy(actor, obj, verb)
        record_id = key("activity", actor, object_id, verb)
        await self.store.put(
            record_id,
            {
                "in": "user:" + actor,
                "out": object_id,
                "verb": verb,
                "created_at": now(),
                "visibility_class": policy["audience"] + "_" + policy["identity_mode"],
            },
        )
        return dict(
            object_id=object_id,
            action=verb,
            recorded=True,
            social_signal=dict(mode=policy["identity_mode"], audience=policy["audience"]),
        )

    async def signal(self, viewer, activity, purpose=None):
        actor = activity["in"].removeprefix("user:")
        try:
            obj = await self.object_for(viewer, activity["out"])
        except HTTPException:
            return None
        policy = await self.policy(actor, obj, activity["verb"])
        own = viewer == actor
        # Financial activity never enters a social signal or group context.
        if obj["platform"] == "pay" and obj["object_type"] != "pay.merchant" and (not own or purpose != "personal"):
            return None
        if not own and (
            policy["identity_mode"] == "hidden" or not await self.audience_allows(viewer, actor, obj, policy)
        ):
            self.metrics["privacy_denials"] += 1
            return None
        if purpose and policy["foxy_access"] not in {purpose, "both"}:
            self.metrics["foxy_denials"] += 1
            return None
        identified = own or policy["identity_mode"] == "identified"
        user = await self.user(actor) if identified else None
        return dict(
            object={"id": obj["id"], "type": obj["object_type"], "title": obj["title"]},
            action=activity["verb"],
            identity_mode="identified" if identified else "anonymous",
            actor=self.profile(user) if user else None,
            label=f"{user.full_name if user else 'Someone'} {activity['verb']} {obj['title']}",
        )

    async def social_context(self, viewer, object_id):
        await self.object_for(viewer, object_id)
        revision = await self.store.revision()
        cache_key = f"context:{revision}:{viewer}:{object_id}"
        # Cache candidate activity rows, never an authorization decision. Expiry is checked on every read.
        activities = await self.cache.get(cache_key)
        if activities is None:
            activities = await self.store.rows("activity", {"out": object_id})
            await self.cache.put(cache_key, activities)
        signals = []
        friends = set()
        for activity in activities:
            signal = await self.signal(viewer, activity)
            if signal:
                signals.append(signal)
                actor = activity["in"].removeprefix("user:")
                if await self.friends(viewer, actor):
                    friends.add(actor)
        result = dict(
            object_id=object_id,
            summary=dict(friend_count=len(friends), signal_count=len(signals)),
            signals=signals,
        )
        return result

    async def activity_feed(self, viewer, platform=None, cursor=None, limit=20):
        connections = await self.connections(viewer)
        actors = [p["peer"]["id"] for p in connections["friends"] if p["status"] == "accepted"]
        activities = []
        for actor in actors:
            activities.extend(await self.store.rows("activity", {"in": "user:" + actor}))
        activities.sort(key=lambda a: (a["created_at"], a["id"]), reverse=True)
        if cursor:
            index = next((i for i, a in enumerate(activities) if a["id"] == cursor), None)
            activities = activities[index + 1 :] if index is not None else []
        items = []
        next_cursor = None
        for index, activity in enumerate(activities):
            signal = await self.signal(viewer, activity)
            if signal and (not platform or signal["object"]["type"].startswith(platform + ".")):
                items.append(signal)
                if len(items) == limit:
                    next_cursor = activity["id"] if index < len(activities) - 1 else None
                    break
        result = dict(items=items, next_cursor=next_cursor)
        return result

    async def create_note(self, actor, text, recipients, object_id=None, room_id=None, expires_at=None):
        await self.cache.rate_limit(actor, "note", 30)
        if not text.strip() or not (recipients or room_id):
            raise HTTPException(422, "Add text and a recipient or room.")
        if expires_at and expired(expires_at):
            raise HTTPException(422, "Expiry must be in the future.")
        obj = await self.object_for(actor, object_id) if object_id else None
        resolved = []
        for target in recipients:
            user = await self.user(target)
            if await self.blocked(actor, user.id):
                raise HTTPException(403, "Recipient unavailable.")
            if obj:
                await self.object_for(user.id, object_id)
            resolved.append(user.id)
        if room_id:
            if not await self.rooms.is_member(room_id, actor):
                raise HTTPException(403, "Join the room first.")
            if obj and obj["audience"] != "public" and obj.get("room_id") != room_id:
                raise HTTPException(403, "Object cannot be shared into this room.")
        return await self.store.put(
            "phlio_note:" + uuid.uuid4().hex,
            dict(
                author=actor,
                text=text.strip(),
                recipients=sorted(set(resolved)),
                object_id=object_id,
                room_id=room_id,
                expires_at=expires_at,
                created_at=now(),
            ),
        )

    async def notes(self, viewer, object_id=None):
        result = []
        for note in await self.store.rows("phlio_note"):
            if expired(note.get("expires_at")) or await self.blocked(viewer, note["author"]):
                continue
            if object_id and object_id != note.get("object_id"):
                continue
            allowed = viewer == note["author"] or viewer in note["recipients"]
            if note.get("room_id"):
                allowed = allowed or await self.rooms.is_member(note["room_id"], viewer)
            if allowed:
                if note.get("object_id"):
                    try:
                        await self.object_for(viewer, note["object_id"])
                    except HTTPException:
                        continue
                # Other recipients are private to the author.
                result.append(
                    {k: v for k, v in note.items() if k != "recipients" or viewer == note["author"]}
                )
        return sorted(result, key=lambda n: (n["created_at"], n["id"]), reverse=True)

    async def foxy_context(self, viewer, participants, platform, purpose, verbs):
        if purpose not in {"personal", "group"} or platform not in TAXONOMY:
            raise HTTPException(400, "Choose a valid context purpose and platform.")
        participants = [(await self.user(p)).id for p in participants]
        if purpose == "personal" and any(p != viewer for p in participants):
            raise HTTPException(403, "Personal context only covers your account.")
        await self.cache.rate_limit(viewer, "foxy_context", 30)
        allowed = []
        for participant in sorted(set(participants or [viewer])):
            participant = (await self.user(participant)).id
            if participant != viewer and not await self.friends(viewer, participant):
                raise HTTPException(403, "Group context requires accepted friends.")
            for activity in await self.store.rows("activity", {"in": "user:" + participant}):
                if activity["verb"] not in verbs:
                    continue
                signal = await self.signal(viewer, activity, purpose)
                if signal and signal["object"]["type"].startswith(platform + "."):
                    # Group evidence never labels anonymous participants.
                    allowed.append(
                        dict(
                            object=signal["object"],
                            verb=signal["action"],
                            source="self" if participant == viewer else "friend_authorized",
                        )
                    )
        allowed = allowed[:100]
        await self.store.put(
            "graph_audit:" + uuid.uuid4().hex,
            dict(
                requester=viewer,
                tool="get_shared_object_preferences",
                purpose=purpose,
                scope=platform,
                result_class="minimal_authorized",
                result_count=len(allowed),
                created_at=now(),
            ),
        )
        self.metrics["foxy_tool_calls"] += 1
        return dict(allowed=True, participants=len(set(participants or [viewer])), signals=allowed)
