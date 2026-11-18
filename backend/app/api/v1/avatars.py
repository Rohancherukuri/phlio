"""
Phlio avatars: a customisable low-poly 3D character (like Bitmoji) that
people build in the app and use as a sticker in Moments, snaps and chats.

The app builds and renders the 3D avatar from this small config (its own
low-poly renderer plus stage and toon-outline shaders), so storing it is
cheap and it can be re-rendered at any size, angle or pose.

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
    """The look of a low-poly 3D Phlio avatar (rendered in the app)."""

    skin: str = Field(default="#E0A47A", pattern=HEX)
    face: Literal["oval", "round", "square", "heart", "long", "angular", "soft"] = "oval"
    hair: Literal["none", "buzz", "short", "swept", "spiky", "quiff", "curly", "wavy", "long", "bun",
                  "ponytail", "afro", "mohawk", "side", "bob", "pigtails"] = "swept"
    hair_color: str = Field(default="#1E2230", pattern=HEX)
    eyes: Literal["round", "almond", "sleepy", "happy", "wink", "sharp", "wide", "cute"] = "round"
    eye_color: str = Field(default="#3B2416", pattern=HEX)
    brows: Literal["soft", "straight", "arched", "bold", "angry", "raised"] = "soft"
    mouth: Literal["smile", "grin", "open", "smirk", "neutral", "frown", "tongue", "cool"] = "smile"
    beard: Literal["none", "stubble", "short", "full", "goatee", "moustache", "van_dyke", "chinstrap"] = "none"
    glasses: Literal["none", "round", "square", "aviator", "sun", "round_tint", "visor"] = "none"
    top: Literal["tee", "hoodie", "shirt", "jacket", "kurta", "dress", "suit", "trench", "track"] = "suit"
    top_color: str = Field(default="#2F6FD6", pattern=HEX)
    accent_color: str = Field(default="#F08A2E", pattern=HEX)
    pants_color: str = Field(default="#2A3554", pattern=HEX)
    accessory: Literal["none", "earrings", "cap", "beanie", "headphones", "bindi", "nose_ring", "scarf", "cape", "crown"] = "none"
    background: Literal["studio", "gradient", "sunset", "mint", "night", "none"] = "studio"
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
