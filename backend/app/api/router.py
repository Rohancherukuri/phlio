"""Top-level API router. `app/main.py` mounts this once under `settings.api_v1_prefix`."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1 import (
    activity,
    agent,
    auth,
    book,
    creator_chat,
    graph,
    content,
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
# Moments before social: /social/moments/* must not hit social's catch-alls.
from app.api.v1 import moments
api_router.include_router(moments.router)
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

api_router.include_router(graph.router)

api_router.include_router(content.router)

from app.api.v1 import news
api_router.include_router(news.router)

from app.api.v1 import social_comments
api_router.include_router(social_comments.router)

from app.api.v1 import realtime
api_router.include_router(realtime.router)
from app.api.v1 import playlists
api_router.include_router(playlists.router)
from app.api.v1 import music
api_router.include_router(music.router)

from app.api.v1 import pay_gateway
api_router.include_router(pay_gateway.router)
