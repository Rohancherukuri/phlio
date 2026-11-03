"""Snap friend lists: Close friends plus lists you make ("Roomies", "Gym crew").

The snap "Send to…" screen shows them after "All": tap a list and the snap
goes to its members only (audience ``close_friends`` with those recipients).
Members have to follow you, the same rule as picking people one by one.

* ``GET    /social/snap-lists``        your lists, Close friends first
* ``POST   /social/snap-lists``        ``{name, members}`` → a new list
* ``PUT    /social/snap-lists/{id}``   ``{name?, members?}`` (``close`` = Close friends)
* ``DELETE /social/snap-lists/{id}``   remove a list (Close friends can only be emptied)
"""
from __future__ import annotations

import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key
from app.domains.graph.store import now

router = APIRouter(prefix="/social/snap-lists", tags=["snap lists"])

CLOSE = "close"
MAX_LISTS = 20


class ListIn(BaseModel):
    name: str = Field(min_length=1, max_length=40)
    members: list[str] = Field(default_factory=list, max_length=200)


class ListUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=40)
    members: list[str] | None = Field(default=None, max_length=200)


def _record(owner: str, list_id: str) -> str:
    return key("snap_list", owner, list_id)


async def _check_members(c: Any, owner: str, members: list[str]) -> list[str]:
    """De-duplicated members, each someone who follows you and isn't blocked."""
    clean = list(dict.fromkeys(m.removeprefix("user:") for m in members))
    for uid in clean:
        if uid == owner or await c.graph.blocked(owner, uid) or not await c.graph.store.get(key("follows", uid, owner)):
            raise HTTPException(422, "Choose people who follow you.")
    return clean


async def _public(c: Any, row: dict) -> dict:
    """A list with its members' profiles (people who unfollowed are skipped)."""
    people = []
    for uid in row.get("members", []):
        try:
            people.append(c.graph.profile(await c.graph.user(uid)))
        except HTTPException:
            continue
    return dict(id=row["list_id"], name=row["name"], close=row["list_id"] == CLOSE,
                members=people, member_ids=[p["id"] for p in people], updated_at=row.get("updated_at"))


async def _get(c: Any, owner: str, list_id: str) -> dict | None:
    return await c.graph.store.get(_record(owner, list_id))


@router.get("")
async def my_lists(user=Depends(get_current_user), c=Depends(get_container)):
    rows = await c.graph.store.rows("snap_list", {"owner": user.id})
    if not any(r["list_id"] == CLOSE for r in rows):
        rows.append(dict(list_id=CLOSE, name="Close friends", members=[], owner=user.id))
    rows.sort(key=lambda r: (r["list_id"] != CLOSE, r.get("created_at", "")))
    return [await _public(c, r) for r in rows]


@router.post("", status_code=201)
async def create_list(body: ListIn, user=Depends(get_current_user), c=Depends(get_container)):
    if len(await c.graph.store.rows("snap_list", {"owner": user.id})) >= MAX_LISTS:
        raise HTTPException(409, f"You can have up to {MAX_LISTS} lists.")
    await c.cache.rate_limit(user.id, "snap_list", 30)
    list_id = uuid.uuid4().hex[:16]
    row = dict(owner=user.id, list_id=list_id, name=body.name.strip(),
               members=await _check_members(c, user.id, body.members), created_at=now(), updated_at=now())
    return await _public(c, await c.graph.store.put(_record(user.id, list_id), row))


@router.put("/{list_id}")
async def update_list(list_id: str, body: ListUpdate, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, user.id, list_id)
    if row is None:
        if list_id != CLOSE:
            raise HTTPException(404, "List not found.")
        row = dict(owner=user.id, list_id=CLOSE, name="Close friends", members=[], created_at=now())
    if body.name is not None and list_id != CLOSE:
        row["name"] = body.name.strip()
    if body.members is not None:
        row["members"] = await _check_members(c, user.id, body.members)
    row["updated_at"] = now()
    return await _public(c, await c.graph.store.put(_record(user.id, list_id), row))


@router.delete("/{list_id}", status_code=204)
async def delete_list(list_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, user.id, list_id)
    if row is None:
        raise HTTPException(404, "List not found.")
    if list_id == CLOSE:
        row.update(members=[], updated_at=now())  # Close friends stays, empty
        await c.graph.store.put(_record(user.id, list_id), row)
        return
    await c.graph.store.delete(_record(user.id, list_id))
