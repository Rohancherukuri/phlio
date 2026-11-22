"""Blend (Instagram-style): a shared feed of posts, videos and clips for two
people, made from what both of you like.

    POST   /blends {username}          invite someone (sends them a Blend card in
                                       your DM and a notification); returns the
                                       existing Blend if you already have one
    POST   /blends/{id}/accept         the invited person joins — the feed starts
    DELETE /blends/{id}                leave / decline / cancel
    GET    /blends                     your Blends (partner, status)
    GET    /blends/{id}?kind=all|post|video|clip
                                       the Blend and its feed

The feed mixes, for the two people:
  * things you both liked or saved                         ("You both liked")
  * things one of you liked, saved or shared and the other
    hasn't seen yet                                        ("Liked by Neha" / "You liked")
  * other posts / videos / clips with hashtags you both like ("You both like #travel")
Each item says why it's there and whose taste it came from. Only content
the viewer may see is included; nothing from blocked people.
"""

from __future__ import annotations

import collections
import datetime as dt
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.api.v1.content import presentation
from app.domains.graph.service import key

router = APIRouter(prefix="/blends", tags=["blend"])

STRONG = {"liked": 3, "saved": 3, "shared": 2, "reposted": 2, "commented": 2}
WEAK = {"viewed": 1, "watched": 1}
KINDS = {"post": "social.post", "video": "social.video", "clip": "social.clip"}


class BlendIn(BaseModel):
    username: str = Field(min_length=1, max_length=60)


def _now() -> str:
    return dt.datetime.now(dt.UTC).isoformat()


async def _get(c, blend_id: str, user_id: str) -> dict:
    row = await c.graph.store.get("social_blend:" + blend_id.removeprefix("social_blend:"))
    if not row or user_id not in row["members"]:
        raise HTTPException(404, "Blend not found.")
    return row


async def _out(c, row: dict, viewer: str) -> dict:
    partner_id = next(m for m in row["members"] if m != viewer)
    partner = await c.identity_repository.get_by_id(partner_id)
    me = await c.identity_repository.get_by_id(viewer)
    return dict(id=row["id"].removeprefix("social_blend:"), status=row["status"],
                invited_by_me=row["inviter"] == viewer, created_at=row["created_at"],
                partner=c.graph.profile(partner) if partner else None, me=c.graph.profile(me) if me else None)


async def _between(c, a: str, b: str) -> dict | None:
    for row in await c.graph.store.rows("social_blend"):
        if set(row["members"]) == {a, b}:
            return row
    return None


@router.post("", status_code=201)
async def create(body: BlendIn, user=Depends(get_current_user), c=Depends(get_container)):
    partner = await c.identity_repository.get_by_username(body.username.removeprefix("@"))
    if partner is None:
        raise HTTPException(404, "No one with that username.")
    if partner.id == user.id:
        raise HTTPException(422, "Blend with someone else.")
    if await c.graph.blocked(user.id, partner.id):
        raise HTTPException(403, "You can't Blend with this person.")
    existing = await _between(c, user.id, partner.id)
    if existing:
        return await _out(c, existing, user.id)
    bid = uuid.uuid4().hex[:16]
    row = await c.graph.store.put("social_blend:" + bid, dict(
        members=[user.id, partner.id], inviter=user.id, status="pending", created_at=_now()))
    # The invite arrives in your DM as a Blend card (and notifies them).
    try:
        c.messaging_service.send(user.id, partner.id, f"Let's make a Blend 🎬\nphlio-blend:{bid}", [])
    except Exception:  # the Blend still exists; they can find it under Blends
        pass
    return await _out(c, row, user.id)


@router.post("/{blend_id}/accept")
async def accept(blend_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, blend_id, user.id)
    if row["inviter"] == user.id and row["status"] == "pending":
        raise HTTPException(422, "Waiting for them to join.")
    if row["status"] != "active":
        row = await c.graph.store.put(row["id"], dict(row, status="active", joined_at=_now()))
        from app.api.v1.notifications import notify
        await notify(c, row["inviter"], "social", "blend", "Your Blend is ready",
                     f"{user.full_name or user.username} joined your Blend", actor=user.id,
                     data=dict(blend_id=row["id"].removeprefix("social_blend:")))
    return await _out(c, row, user.id)


@router.delete("/{blend_id}", status_code=204)
async def leave(blend_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, blend_id, user.id)
    await c.graph.store.delete(row["id"])


@router.get("")
async def mine(user=Depends(get_current_user), c=Depends(get_container)):
    rows = [r for r in await c.graph.store.rows("social_blend") if user.id in r["members"]]
    rows.sort(key=lambda r: r["created_at"], reverse=True)
    return {"items": [await _out(c, r, user.id) for r in rows]}


async def _taste(c, user_id: str) -> tuple[dict[str, float], dict[str, set], collections.Counter]:
    """Social objects a person engaged with (score), the verbs, and their hashtags."""
    scores: dict[str, float] = collections.defaultdict(float)
    verbs: dict[str, set] = collections.defaultdict(set)
    for edge in await c.graph.store.rows("activity", {"in": "user:" + user_id}):
        verb = edge.get("verb")
        if verb in STRONG or verb in WEAK:
            scores[edge["out"]] += STRONG.get(verb, WEAK.get(verb, 0))
            verbs[edge["out"]].add(verb)
    tags: collections.Counter = collections.Counter()
    for oid, score in scores.items():
        if score < 2:
            continue
        obj = await c.graph.store.get(oid)
        if not obj or obj.get("platform") != "social":
            continue
        details = await c.graph.store.get(key("platform_content", "social", obj["domain_ref"])) or {}
        tags.update(t.lower() for t in details.get("tags") or [] if t.lower() not in {"fyp", "4you", "phlio"})
        if obj.get("object_type") == "social.post":
            post = await c.social_repository.get_post(obj["domain_ref"])
            if post:
                tags.update(t.lower() for t in post.tags)
    return scores, verbs, tags


@router.get("/{blend_id}")
async def feed(blend_id: str, kind: str = Query("all", pattern="^(all|post|video|clip)$"),
               user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, blend_id, user.id)
    out = await _out(c, row, user.id)
    if row["status"] != "active":
        return dict(out, items=[], shared_tags=[])
    partner_id = next(m for m in row["members"] if m != user.id)
    (mine_s, mine_v, mine_t), (theirs_s, theirs_v, theirs_t) = await _taste(c, user.id), await _taste(c, partner_id)
    shared_tags = [t for t, _ in (mine_t & theirs_t).most_common(8)]
    wanted = {KINDS[kind]} if kind != "all" else set(KINDS.values())
    me, partner = out["me"], out["partner"]

    candidates: dict[str, dict] = {}

    def add(oid: str, score: float, reason: str, by: list):
        hit = candidates.get(oid)
        if hit is None or score > hit["score"]:
            candidates[oid] = dict(score=score, reason=reason, by=by)

    for oid in set(mine_s) | set(theirs_s):
        a, b = mine_s.get(oid, 0), theirs_s.get(oid, 0)
        a_strong = bool(mine_v.get(oid, set()) & STRONG.keys())
        b_strong = bool(theirs_v.get(oid, set()) & STRONG.keys())
        if a_strong and b_strong:
            add(oid, 10 + a + b, "You both liked", [me, partner])
        elif b_strong and a == 0:
            add(oid, 6 + b, f"Liked by {partner['display_name'] or partner['username']}", [partner])
        elif a_strong and b == 0:
            add(oid, 5 + a, "You liked", [me])
    if shared_tags:
        for details in await c.graph.store.rows("platform_content", {"platform": "social"}):
            tags = {t.lower() for t in details.get("tags") or []}
            common = [t for t in shared_tags if t in tags]
            if not common:
                continue
            oid = key("phlio_object", "social", details["domain_ref"])
            if oid in mine_s or oid in theirs_s:
                continue
            add(oid, 2 + len(common), f"You both like #{common[0]}", [me, partner])

    items = []
    for oid, meta in sorted(candidates.items(), key=lambda kv: kv[1]["score"], reverse=True):
        obj = await c.graph.store.get(oid)
        if not obj or obj.get("platform") != "social" or obj.get("object_type") not in wanted:
            continue
        if obj.get("state", "active") != "active":
            continue
        try:
            visible = await c.graph.object_for(user.id, oid)
        except HTTPException:
            continue
        if obj.get("owner") and await c.graph.blocked(user.id, obj["owner"]):
            continue
        shown = await presentation(c, visible)
        items.append(dict(shown, object_type=obj["object_type"], reason=meta["reason"], by=meta["by"]))
        if len(items) >= 60:
            break
    return dict(out, items=items, shared_tags=shared_tags)
