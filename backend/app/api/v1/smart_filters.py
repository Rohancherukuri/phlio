"""
Snapchat-style smart filters for Moments and snaps, stored as data so they
stay editable.

A filter spec is the colour look and effect the app already draws live
("look+effect"), plus up to six *info overlays* captured when the photo was
taken — time, date, weather, place, speed, battery, day, greeting — each
with a style, colour, position, size and rotation:

    {"look": "clarendon", "effect": "grain", "strength": 0.8,
     "overlays": [{"type": "weather", "style": "big", "color": "#FFFFFF",
                   "x": 0.5, "y": 0.2, "scale": 1.2, "rotation": 0,
                   "data": {"temp": 27, "unit": "C", "icon": "☀️", "city": "Hyderabad"}}]}

Nothing is baked into the photo: the app draws the spec over the media, so
the author can change it after posting, and the spec is saved in the
database with the moment or snap.

Endpoints under ``/api/v1/social/filters``:

``GET    /presets``                  my saved filters ("My filters")
``POST   /presets``                  save one ``{name, spec}``
``PUT    /presets/{id}``             rename / change it
``DELETE /presets/{id}``
``PUT    /moments/{moment_id}``      change a posted moment's filter
``PUT    /memories/{memory_id}``     change a posted snap's filter

Moments (``POST /social/moments``) and snaps (``POST /social/memories``)
also take a ``filter_spec`` form field (JSON).
"""

from __future__ import annotations

import datetime as dt
import json
import re
import uuid
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, ValidationError, field_validator, model_validator

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key

router = APIRouter(prefix="/social/filters", tags=["social"])

OverlayType = Literal["time", "date", "weather", "place", "speed", "battery", "day", "greeting"]
STYLES = {
    "time": {"bold", "lcd", "pill"},
    "date": {"stamp", "card", "script"},
    "weather": {"big", "pill", "retro"},
    "place": {"banner", "pill", "outline"},
    "speed": {"gauge", "pill"},
    "battery": {"icon", "pill"},
    "day": {"script", "sticker"},
    "greeting": {"gradient", "pill"},
}
NAME = r"^[a-z0-9_]{1,24}$"
MAX_PRESETS = 20


class Overlay(BaseModel):
    type: OverlayType
    style: str = Field(max_length=16)
    color: str = Field(default="#FFFFFF", pattern=r"^#[0-9A-Fa-f]{6}$")
    x: float = Field(default=0.5, ge=0, le=1)
    y: float = Field(default=0.5, ge=0, le=1)
    scale: float = Field(default=1, ge=0.3, le=4)
    rotation: float = Field(default=0, ge=-3.2, le=3.2)
    # What was captured (temperature, place name, speed…), shown as-is.
    data: dict[str, str | int | float | bool | None] = Field(default_factory=dict)

    @field_validator("data")
    @classmethod
    def _small(cls, data):
        if len(data) > 10:
            raise ValueError("Too many values.")
        for k, v in data.items():
            if not re.match(r"^[a-z_]{1,16}$", k) or (isinstance(v, str) and len(v) > 80):
                raise ValueError("Invalid overlay value.")
        return data

    @model_validator(mode="after")
    def _style(self):
        if self.style not in STYLES[self.type]:
            raise ValueError(f"Unknown style for {self.type}.")
        return self


# Advanced editing sliders (Experience / Moment editors), each -1..1.
ADJUSTMENTS = {"exposure", "brightness", "contrast", "saturation", "warmth", "tint", "highlights",
               "shadows", "fade", "vignette", "grain", "sharpen", "clarity", "vibrance"}


class FilterSpec(BaseModel):
    look: str = Field(default="normal", pattern=NAME)
    effect: str | None = Field(default=None, pattern=NAME)
    strength: float = Field(default=1, ge=0, le=1)
    overlays: list[Overlay] = Field(default_factory=list, max_length=6)
    # Story effect from the effects catalogue (shared/media/story_fx_catalog.dart),
    # drawn live with Flutter shaders, and its intensity.
    fx: str | None = Field(default=None, pattern=r"^[a-z0-9_]{1,32}$")
    fx_amount: float = Field(default=1, ge=0, le=1)
    adjust: dict[str, float] = Field(default_factory=dict)
    # The filter baked into a photo, kept so viewers can still name it.
    applied_look: str | None = Field(default=None, pattern=NAME)

    @field_validator("adjust")
    @classmethod
    def _adjust(cls, values):
        if len(values) > len(ADJUSTMENTS) or any(k not in ADJUSTMENTS for k in values):
            raise ValueError("Unknown adjustment.")
        if any(not -1 <= v <= 1 for v in values.values()):
            raise ValueError("Adjustments go from -1 to 1.")
        return {k: round(float(v), 4) for k, v in values.items() if abs(v) > 1e-4}

    def legacy(self) -> str:
        """The old ``filter`` string ("look" or "look+effect")."""
        return self.look + (f"+{self.effect}" if self.effect else "")


def parse_filter_spec(raw: str | None) -> dict | None:
    """Validates the ``filter_spec`` form field; None when empty."""
    if not raw or not raw.strip():
        return None
    if len(raw) > 8000:
        raise HTTPException(422, "Filter is too large.")
    try:
        return FilterSpec.model_validate(json.loads(raw)).model_dump()
    except (ValueError, ValidationError) as exc:
        raise HTTPException(422, "Invalid filter.") from exc


class PresetIn(BaseModel):
    name: str = Field(min_length=1, max_length=40)
    spec: FilterSpec


class SpecIn(BaseModel):
    spec: FilterSpec


def _now() -> str:
    return dt.datetime.now(dt.UTC).isoformat()


def _preset_out(row: dict) -> dict:
    return dict(id=row["preset_id"], name=row["name"], spec=row["spec"], updated_at=row["updated_at"])


@router.get("/presets")
async def presets(user=Depends(get_current_user), c=Depends(get_container)):
    rows = await c.graph.store.rows("filter_preset", {"owner": user.id})
    rows.sort(key=lambda r: r["updated_at"], reverse=True)
    return {"items": [_preset_out(r) for r in rows]}


@router.post("/presets", status_code=201)
async def save_preset(body: PresetIn, user=Depends(get_current_user), c=Depends(get_container)):
    rows = await c.graph.store.rows("filter_preset", {"owner": user.id})
    if len(rows) >= MAX_PRESETS:
        raise HTTPException(409, f"You can keep up to {MAX_PRESETS} filters. Delete one first.")
    preset_id = uuid.uuid4().hex[:16]
    # Saved presets keep styles and positions, not the captured values.
    spec = body.spec.model_dump()
    for o in spec["overlays"]:
        o["data"] = {}
    row = dict(preset_id=preset_id, owner=user.id, name=body.name.strip(), spec=spec, updated_at=_now())
    await c.graph.store.put(key("filter_preset", user.id, preset_id), row)
    return _preset_out(row)


async def _mine(c, user_id: str, preset_id: str) -> dict:
    row = await c.graph.store.get(key("filter_preset", user_id, preset_id)) if re.match(r"^[a-f0-9]{16}$", preset_id) else None
    if not row:
        raise HTTPException(404, "Filter not found.")
    return row


@router.put("/presets/{preset_id}")
async def update_preset(preset_id: str, body: PresetIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _mine(c, user.id, preset_id)
    spec = body.spec.model_dump()
    for o in spec["overlays"]:
        o["data"] = {}
    row = {**{k: v for k, v in row.items() if k != "id"}, "name": body.name.strip(), "spec": spec, "updated_at": _now()}
    await c.graph.store.put(key("filter_preset", user.id, preset_id), row)
    return _preset_out(row)


@router.delete("/presets/{preset_id}", status_code=204)
async def delete_preset(preset_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    await _mine(c, user.id, preset_id)
    await c.graph.store.delete(key("filter_preset", user.id, preset_id))


async def _update(c, record_id: str, prefix: str, user_id: str, spec: FilterSpec) -> dict:
    if not record_id.startswith(prefix):
        raise HTTPException(404, "Not found.")
    row = await c.graph.store.get(record_id)
    if not row:
        raise HTTPException(404, "Not found.")
    if row.get("author") != user_id:
        raise HTTPException(403, "Only the author can change the filter.")
    updated = {**{k: v for k, v in row.items() if k != "id"}, "filter_spec": spec.model_dump(),
               "filter": spec.legacy(), "filter_edited_at": _now()}
    await c.graph.store.put(record_id, updated)
    return {"filter": updated["filter"], "filter_spec": updated["filter_spec"]}


@router.put("/moments/{moment_id}")
async def edit_moment(moment_id: str, body: SpecIn, user=Depends(get_current_user), c=Depends(get_container)):
    return await _update(c, moment_id, "social_moment:", user.id, body.spec)


@router.put("/memories/{memory_id}")
async def edit_memory(memory_id: str, body: SpecIn, user=Depends(get_current_user), c=Depends(get_container)):
    return await _update(c, memory_id, "social_memory:", user.id, body.spec)
