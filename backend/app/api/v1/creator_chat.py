"""Public creator chat is separate from private direct messages."""

from fastapi import APIRouter, Depends, HTTPException

from app.api.deps import get_container, get_current_user
from app.api.v1.messaging import MessageIn, resolve_peer
from app.core.container import Container
from app.domains.identity.entities import User
from app.domains.messaging.media_policy import validate_pack

router = APIRouter(prefix="/social/creators", tags=["creator chat"])


@router.get("/{creator}/chat")
async def history(
    creator: str, user: User = Depends(get_current_user), c: Container = Depends(get_container)
):
    target = await resolve_peer(creator, c)
    return c.messaging_service.public_history(target.id)


@router.post("/{creator}/chat", status_code=201)
async def send(
    creator: str,
    body: MessageIn,
    user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
):
    target = await resolve_peer(creator, c)
    for item in body.attachments:
        if item.kind not in ("sticker", "gif") or item.url:
            raise HTTPException(422, "Public chat allows text, predefined stickers and GIFs only.")
        validate_pack(item.kind, item.value)
    return c.messaging_service.public_send(
        target.id, user.id, user.username, body.text, [a.model_dump() for a in body.attachments]
    )
