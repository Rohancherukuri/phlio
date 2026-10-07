"""Top-level API router. `app/main.py` mounts this once under `settings.api_v1_prefix`."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1 import (
    activity,
    agent,
    auth,
    book,
    creator_chat,
    home,
    messaging,
    pay,
    rooms,
    shop,
    social,
    social_videos,
    stickers,
    users,
)

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(home.router)
api_router.include_router(social.router)
api_router.include_router(social_videos.router)
api_router.include_router(rooms.router)
api_router.include_router(shop.router)
api_router.include_router(agent.router)
api_router.include_router(book.router)
api_router.include_router(pay.router)
api_router.include_router(activity.router)
api_router.include_router(stickers.router)

api_router.include_router(messaging.router)

api_router.include_router(creator_chat.router)
