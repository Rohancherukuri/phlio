import datetime as dt
from fastapi import HTTPException
from pydantic import BaseModel, Field
from typing import Literal
from app.domains.graph.service import key

class SnapAudience(BaseModel):
    audience: Literal['friends', 'everyone', 'close_friends'] = 'friends'
    recipients: list[str] = Field(default_factory=list, max_length=200)

async def validate_audience(c, owner, choice):
    selected = list(dict.fromkeys(choice.recipients)) if choice.audience == 'close_friends' else []
    if choice.audience == 'close_friends' and not selected:
        raise HTTPException(422, 'Select at least one follower.')
    for uid in selected:
        if uid == owner or await c.graph.blocked(owner, uid) or not await c.graph.store.get(key('follows', uid, owner)):
            raise HTTPException(422, 'Choose profiles who follow you.')
    return dict(audience=choice.audience, recipients=selected)

async def can_view(c, viewer, row):
    owner = row['author']
    if viewer == owner:
        return True
    if await c.graph.blocked(viewer, owner):
        return False
    audience = row.get('audience', 'friends')
    if audience == 'everyone':
        return True
    if audience == 'close_friends':
        return viewer in row.get('recipients', []) and bool(await c.graph.store.get(key('follows', viewer, owner)))
    return await c.graph.friends(viewer, owner)
