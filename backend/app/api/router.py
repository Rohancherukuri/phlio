"""Top-level API router. `app/main.py` mounts this once under `settings.api_v1_prefix`."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1 import agent, auth, home, rooms, shop, social, users

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(home.router)
api_router.include_router(social.router)
api_router.include_router(rooms.router)
api_router.include_router(shop.router)
api_router.include_router(agent.router)
