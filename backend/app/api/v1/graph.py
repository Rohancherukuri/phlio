"""Product APIs for the shared graph; no raw query language crosses this boundary."""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import AwareDatetime, BaseModel, Field

from app.api.deps import get_agent_tools, get_container, get_current_user
from app.core.container import Container
from app.domains.identity.entities import User

router = APIRouter(tags=["social graph"])


class RelationshipIn(BaseModel):
    target_user_id: str = Field(min_length=1, max_length=100)


class ObjectIn(BaseModel):
    object_type: str
    domain_ref: str = Field(min_length=1, max_length=150)


class ActionIn(BaseModel):
    action: str = Field(min_length=1, max_length=30)


class PolicyIn(BaseModel):
    platform: str = "*"
    object_type: str = "*"
    verb: str = "*"
    audience: Literal[
        "nobody", "selected_users", "close_friends", "friends", "followers", "room_members", "public"
    ] = "nobody"
    identity_mode: Literal["identified", "anonymous", "hidden"] = "hidden"
    foxy_access: Literal["none", "personal", "group", "both"] = "none"
    selected_users: list[str] = Field(default_factory=list, max_length=100)
    expires_at: AwareDatetime | None = None


class NoteIn(BaseModel):
    object_id: str | None = None
    recipients: list[str] = Field(default_factory=list, max_length=50)
    room_id: str | None = None
    text: str = Field(min_length=1, max_length=4000)
    expires_at: AwareDatetime | None = None


class ContextIn(BaseModel):
    participants: list[str] = Field(default_factory=list, max_length=20)
    platform: str
    purpose: Literal["personal", "group"]
    verbs: list[str] = Field(default_factory=lambda: ["liked", "saved", "watched"], max_length=10)


@router.post("/social/friendships", status_code=201)
async def request_friend(
    body: RelationshipIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    return await c.graph.relationship(user.id, body.target_user_id, "request")


@router.post("/social/friendships/{target}/{action}")
async def change_friend(
    target: str,
    action: Literal["accept", "decline", "remove"],
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    return await c.graph.relationship(user.id, target, action)


@router.put("/social/blocks/{target}")
async def block(target: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    return await c.graph.relationship(user.id, target, "block")


@router.delete("/social/blocks/{target}")
async def unblock(target: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    return await c.graph.relationship(user.id, target, "unblock")


@router.get("/social/connections")
async def connections(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    return await c.graph.connections(user.id)


@router.post("/objects", status_code=201)
async def register_object(
    body: ObjectIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    # Objects wrap real domain records. Clients cannot invent bookings, payments, or other people's posts.
    if body.object_type == "social.post":
        post = await c.social_repository.get_post(body.domain_ref)
        if not post or post.author_id != user.id:
            raise HTTPException(403, "Choose a post you own.")
        return await c.graph.register_object(user.id, body.object_type, body.domain_ref, post.text[:160])
    if body.object_type == "rooms.room":
        room = await c.rooms_repository.get_room(body.domain_ref)
        if not room or room.created_by != user.id:
            raise HTTPException(403, "Choose a room you own.")
        return await c.graph.register_object(
            user.id,
            body.object_type,
            body.domain_ref,
            room.name,
            audience="room" if room.is_private else "public",
            room_id=room.id,
        )
    raise HTTPException(400, "This object type is registered by its domain workflow.")


@router.get("/objects/{object_id}")
async def get_object(
    object_id: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    return await c.graph.object_for(user.id, object_id)


@router.post("/objects/{object_id}/actions")
async def action(
    object_id: str,
    body: ActionIn,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    return await c.graph.action(user.id, object_id, body.action)


@router.get("/objects/{object_id}/social-context")
async def social_context(
    object_id: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    return await c.graph.social_context(user.id, object_id)


@router.put("/privacy/activity")
async def policy(
    body: PolicyIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    return await c.graph.set_policy(user.id, body.model_dump(mode="json"))


@router.get("/privacy/activity")
async def policies(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    return await c.graph.store.rows("privacy_policy", {"owner": user.id})


@router.get("/activity/friends")
async def activity_feed(
    platform: str | None = None,
    cursor: str | None = None,
    limit: int = Query(20, ge=1, le=100),
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    return await c.graph.activity_feed(user.id, platform, cursor, limit)


@router.post("/notes", status_code=201)
async def note(body: NoteIn, user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    return await c.graph.create_note(user.id, **body.model_dump(mode="json"))


@router.get("/notes")
async def notes(
    object_id: str | None = None,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    return {"items": await c.graph.notes(user.id, object_id)}


@router.post("/agent/context")
async def context(body: ContextIn, tools=Depends(get_agent_tools)):
    return await tools.get_shared_object_preferences(**body.model_dump())


@router.get("/social/creators")
async def creators(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    candidates = await c.identity_repository.search_users("", 100)
    return {
        "items": [
            dict(c.graph.profile(candidate), is_creator=candidate.is_creator)
            for candidate in candidates
            if candidate.is_creator and not await c.graph.blocked(user.id, candidate.id)
        ]
    }


@router.get("/social/graph-status")
async def graph_status(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    if c.settings.app_env not in {"development", "testing"}:
        raise HTTPException(404, "Not found.")
    return {
        "database": c.settings.database_backend,
        "revision": await c.graph.store.revision(),
        "cache": dict(c.cache.stats),
        "privacy": dict(c.graph.metrics),
    }


class LifecycleIn(BaseModel):
    state: Literal["active", "tombstone"]


@router.patch("/objects/{object_id}")
async def lifecycle(
    object_id: str,
    body: LifecycleIn,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    obj = await c.graph.store.get(object_id) if object_id.startswith("phlio_object:") else None
    if not obj or obj["owner"] != user.id:
        raise HTTPException(404, "Object unavailable.")
    obj["state"] = body.state
    return await c.graph.store.put(object_id, obj)


class AliasIn(BaseModel):
    provider: str = Field(min_length=1, max_length=80)
    external_id: str = Field(min_length=1, max_length=200)


@router.put("/objects/{object_id}/aliases")
async def alias(
    object_id: str,
    body: AliasIn,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    return await c.graph.bind_alias(user.id, object_id, body.provider, body.external_id)


@router.get("/objects/{object_id}/children")
async def children(
    object_id: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    return {"items": await c.graph.related_objects(user.id, object_id)}
