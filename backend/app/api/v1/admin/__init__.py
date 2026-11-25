"""Phlio admin panel API (the web dashboard lives in /admin at the repo root)."""

from fastapi import APIRouter

from app.api.v1.admin import analytics, auth, integrations

router = APIRouter()
router.include_router(auth.router)
router.include_router(analytics.router)
router.include_router(integrations.router)
