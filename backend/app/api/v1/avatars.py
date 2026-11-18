"""
Phlio avatars: a customisable, shader-shaded character (like Bitmoji) that
people build in the app and use as a sticker in Moments, snaps and chats.

The app draws the avatar from this small config (layered vector parts lit
by the ``avatar_shade`` fragment shader), so storing it is cheap and it can
be re-rendered at any size or pose.

``GET /api/v1/social/avatar``             mine (null until created)
``PUT /api/v1/social/avatar``             save mine
``DELETE /api/v1/social/avatar``
``GET /api/v1/social/avatar/u/{username}`` someone's (if they made one)
"""

from __future__ import annotations

import datetime as dt
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key

router = APIRouter(prefix="/social/avatar", tags=["social"])
HEX = r"^#[0-9A-Fa-f]{6}$"


class AvatarConfig(BaseModel):
    skin: str = Field(default="#C68A62", pattern=HEX)
    face: Literal["oval", "round", "square", "heart", "long"] = "oval"
    hair: Literal["none", "buzz", "short", "quiff", "curly", "wavy", "long", "bun", "ponytail", "afro", "side"] = "short"
    hair_color: str = Field(default="#2B1B12", pattern=HEX)
    eyes: Literal["round", "almond", "sleepy", "happy", "wink"] = "round"
    eye_color: str = Field(default="#3B2416", pattern=HEX)
    brows: Literal["soft", "straight", "arched", "bold"] = "soft"
    mouth: Literal["smile", "grin", "open", "smirk", "neutral"] = "smile"
    beard: Literal["none", "stubble", "short", "full", "goatee", "moustache"] = "none"
    glasses: Literal["none", "round", "square", "aviator", "sun"] = "none"
    top: Literal["tee", "hoodie", "shirt", "jacket", "kurta", "dress"] = "tee"
    top_color: str = Field(default="#8D78FF", pattern=HEX)
    accessory: Literal["none", "earrings", "cap", "beanie", "headphones", "bindi", "nose_ring"] = "none"
    background: Literal["none", "gradient", "sunset", "mint", "night"] = "gradient"
    blush: bool = True
    freckles: bool = False


def _now() -> str:
    return dt.datetime.now(dt.UTC).isoformat()


async def _get(c, user_id: str) -> dict | None:
    row = await c.graph.store.get(key("avatar_config", user_id))
    return row.get("config") if row else None


@router.get("")
async def mine(user=Depends(get_current_user), c=Depends(get_container)):
    return {"avatar": await _get(c, user.id)}


@router.put("")
async def save(body: AvatarConfig, user=Depends(get_current_user), c=Depends(get_container)):
    await c.cache.rate_limit(user.id, "avatar-save", 30)
    await c.graph.store.put(key("avatar_config", user.id),
                            dict(owner=user.id, config=body.model_dump(), updated_at=_now()))
    return {"avatar": body.model_dump()}


@router.delete("", status_code=204)
async def remove(user=Depends(get_current_user), c=Depends(get_container)):
    if await c.graph.store.get(key("avatar_config", user.id)):
        await c.graph.store.delete(key("avatar_config", user.id))


@router.get("/u/{username}")
async def theirs(username: str, user=Depends(get_current_user), c=Depends(get_container)):
    person = await c.identity_repository.get_by_username(username.lower())
    if person is None:
        raise HTTPException(404, "Not found.")
    if await c.graph.blocked(user.id, person.id):
        raise HTTPException(404, "Not found.")
    return {"avatar": await _get(c, person.id)}
