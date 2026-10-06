"""Phlio Activity endpoints: the cross-domain notification feed."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.api.deps import get_activity_service, get_current_user
from app.common.pagination import clamp_limit
from app.common.schemas import Page, PageMeta
from app.domains.activity.entities import ActivityItem, ActivityKind
from app.domains.activity.service import ActivityService
from app.domains.identity.entities import User

router = APIRouter(prefix="/activity", tags=["activity"])


class ActivityResponse(BaseModel):
    id: str
    kind: ActivityKind
    title: str
    body: str
    icon: str
    ref_id: str | None
    created_at: dt.datetime
    is_read: bool

    @classmethod
    def from_entity(cls, item: ActivityItem) -> ActivityResponse:
        return cls(
            id=item.id,
            kind=item.kind,
            title=item.title,
            body=item.body,
            icon=item.icon,
            ref_id=item.ref_id,
            created_at=item.created_at,
            is_read=item.is_read,
        )


@router.get("", response_model=Page[ActivityResponse])
async def activity_feed(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=30, ge=1, le=100),
    activity_service: ActivityService = Depends(get_activity_service),
    current_user: User = Depends(get_current_user),
) -> Page[ActivityResponse]:
    items, next_cursor = await activity_service.list_feed(
        user_id=current_user.id, cursor=cursor, limit=clamp_limit(limit)
    )
    return Page(
        items=[ActivityResponse.from_entity(i) for i in items],
        meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None),
    )


@router.post("/read-all", status_code=204)
async def mark_all_read(
    activity_service: ActivityService = Depends(get_activity_service),
    current_user: User = Depends(get_current_user),
) -> None:
    await activity_service.mark_all_read(current_user.id)
