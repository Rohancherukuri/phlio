"""Phlio Sticker catalog endpoint.

The Flutter app bundles the Foxy sticker pack under `assets/stickers/`; this
endpoint is the server-side source of truth for *which* stickers exist and
how they're labelled, so the client's picker stays in sync without an app
update when the pack grows. Asset bytes themselves ship with the app (they
are brand IP, tiny, and needed offline).
"""

from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from app.domains.stickers import FOXY_STICKER_CATALOG

router = APIRouter(prefix="/stickers", tags=["stickers"])


class StickerResponse(BaseModel):
    id: str
    label: str
    pack: str


@router.get("", response_model=list[StickerResponse])
async def list_stickers() -> list[StickerResponse]:
    return [StickerResponse(**s) for s in FOXY_STICKER_CATALOG]
