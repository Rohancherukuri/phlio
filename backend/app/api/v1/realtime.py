"""Authenticated SFU admission. Signing secrets never leave the API server."""
import datetime as dt
import hashlib
import json
import uuid
from contextlib import asynccontextmanager
from aiohttp import ClientTimeout

from fastapi import APIRouter, Depends, HTTPException
from livekit import api
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user

router = APIRouter(prefix='/realtime', tags=['realtime'])


def configured(c):
    s = c.settings
    if not all((s.livekit_url, s.livekit_api_key, s.livekit_api_secret)):
        raise HTTPException(503, 'Audio and video server is not configured yet.')
    return s


@asynccontextmanager
async def server(c):
    s = configured(c)
    client = api.LiveKitAPI(s.livekit_api_url or s.livekit_url,
                           s.livekit_api_key, s.livekit_api_secret,
                           timeout=ClientTimeout(total=8))
    try:
        yield client
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, 'Audio and video server is temporarily unavailable.') from exc
    finally:
        await client.aclose()


def admission(c, user, room, publish=True, host=False):
    s = configured(c)
    token = (api.AccessToken(s.livekit_api_key, s.livekit_api_secret)
             .with_identity(user.id).with_name(user.full_name)
             .with_ttl(dt.timedelta(minutes=10))
             .with_grants(api.VideoGrants(room_join=True, room=room,
                 can_publish=publish, can_subscribe=True, can_publish_data=publish))
             .to_jwt())
    return dict(url=s.livekit_url, token=token, room=room, can_publish=publish, host=host)


@router.post('/rooms/{room_id}/join')
async def join_room(room_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    await c.rooms_service.get_room_or_raise(room_id)
    if not await c.rooms_repository.is_member(room_id, user.id):
        raise HTTPException(403, 'Join this room before entering its voice channel.')
    name = 'room-' + hashlib.sha256(room_id.encode()).hexdigest()[:32]
    async with server(c) as lk:
        await lk.room.create_room(api.CreateRoomRequest(name=name, empty_timeout=60,
                                                       max_participants=100))
    return admission(c, user, name)


@router.post('/calls/{call_id}/join')
async def join_call(call_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    call = c.messaging_service.call(call_id, user.id)
    if call['status'] != 'accepted':
        raise HTTPException(409, 'The call must be accepted first.')
    if await c.graph.blocked(call['caller_id'], call['recipient_id']):
        raise HTTPException(403, 'This call is unavailable.')
    name = 'call-' + call_id
    async with server(c) as lk:
        await lk.room.create_room(api.CreateRoomRequest(name=name, max_participants=2,
                                                       empty_timeout=30))
    return admission(c, user, name)


class BroadcastIn(BaseModel):
    title: str = Field(default='Live with me', min_length=1, max_length=120)


@router.post('/live', status_code=201)
async def create_live(body: BroadcastIn, user=Depends(get_current_user), c=Depends(get_container)):
    name = 'social-' + uuid.uuid4().hex
    async with server(c) as lk:
        await lk.room.create_room(api.CreateRoomRequest(name=name, empty_timeout=60,
            metadata=json.dumps(dict(host_id=user.id, name=user.full_name, title=body.title))))
    return admission(c, user, name, host=True)


async def live_room(lk, name):
    if not name.startswith('social-'):
        raise HTTPException(404, 'Live session not found.')
    rooms = (await lk.room.list_rooms(api.ListRoomsRequest(names=[name]))).rooms
    if not rooms:
        raise HTTPException(404, 'This live session has ended.')
    return rooms[0], json.loads(rooms[0].metadata or '{}')


@router.get('/live')
async def list_live(user=Depends(get_current_user), c=Depends(get_container)):
    async with server(c) as lk:
        rooms = (await lk.room.list_rooms(api.ListRoomsRequest())).rooms
        items = []
        for room in rooms:
            if not room.name.startswith('social-') or not room.num_participants:
                continue
            meta = json.loads(room.metadata or '{}')
            if not meta.get('host_id') or await c.graph.blocked(user.id, meta['host_id']):
                continue
            participants = (await lk.room.list_participants(api.ListParticipantsRequest(room=room.name))).participants
            if not any(p.identity == meta['host_id'] for p in participants):
                continue
            items.append(dict(id=room.name, **meta, viewers=max(0, room.num_participants - 1)))
    return dict(items=items)


@router.post('/live/{name}/join')
async def join_live(name: str, user=Depends(get_current_user), c=Depends(get_container)):
    async with server(c) as lk:
        _, meta = await live_room(lk, name)
        if await c.graph.blocked(user.id, meta['host_id']):
            raise HTTPException(404, 'This live session is unavailable.')
    host = user.id == meta['host_id']
    return admission(c, user, name, publish=host, host=host)


@router.delete('/live/{name}', status_code=204)
async def end_live(name: str, user=Depends(get_current_user), c=Depends(get_container)):
    async with server(c) as lk:
        _, meta = await live_room(lk, name)
        if user.id != meta['host_id']:
            raise HTTPException(403, 'Only the host can end this live session.')
        await lk.room.delete_room(api.DeleteRoomRequest(room=name))
