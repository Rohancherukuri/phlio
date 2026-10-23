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


def admission(c, user, room, publish=True, host=False, audio_only=False,
              identity=None, display_name=None):
    s = configured(c)
    token = (api.AccessToken(s.livekit_api_key, s.livekit_api_secret)
             .with_identity(identity or user.id).with_name(display_name or user.full_name)
             .with_ttl(dt.timedelta(minutes=10))
             .with_grants(api.VideoGrants(room_join=True, room=room,
                 can_publish=publish, can_subscribe=True, can_publish_data=publish,
                 can_publish_sources=["microphone"] if audio_only else None))
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
    audio_only: bool = False
    record: bool = False
    topics: list[str] = Field(default_factory=list, max_length=3)
    title: str = Field(default='Live with me', min_length=1, max_length=120)


@router.post('/live', status_code=201)
async def create_live(body: BroadcastIn, user=Depends(get_current_user), c=Depends(get_container)):
    name = 'social-' + uuid.uuid4().hex
    async with server(c) as lk:
        await lk.room.create_room(api.CreateRoomRequest(name=name, empty_timeout=60,
            metadata=json.dumps(dict(host_id=user.id, name=user.full_name, title=body.title, audio_only=body.audio_only, topics=body.topics, record=body.record))))
    try:
        await c.graph.store.put('live_session:'+name,dict(room=name,host_id=user.id,name=user.full_name,title=body.title,
            audio_only=body.audio_only,topics=body.topics,record=body.record,status='live',started_at=dt.datetime.now(dt.UTC).isoformat(),ended_at=None,recording_url=None))
    except Exception:
        async with server(c) as lk:
            await lk.room.delete_room(api.DeleteRoomRequest(room=name))
        raise
    return admission(c, user, name, host=True, audio_only=body.audio_only)


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
        # Reconcile rooms that expired after an abrupt host disconnect.
        names = {r.name for r in rooms}
        for saved in await c.graph.store.rows('live_session', {'status':'live'}):
            if saved['room'] not in names and (dt.datetime.now(dt.UTC)-dt.datetime.fromisoformat(saved['started_at'])).total_seconds()>90:
                await c.graph.store.put(saved['id'],dict(saved,status='ended',ended_at=dt.datetime.now(dt.UTC).isoformat()))
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
            # Up to three faces for the Spaces pill: host first, then speakers.
            ordered = sorted((p for p in participants if not p.identity.startswith('anon-')),
                             key=lambda p: (p.identity != meta['host_id'], not p.permission.can_publish))
            preview = [x for x in [await profile_of(c, p) for p in ordered[:3]] if x]
            items.append(dict(id=room.name, **meta, viewers=max(0, room.num_participants - 1),
                              participants_count=room.num_participants, preview=preview))
    return dict(items=items)


async def profile_of(c, participant):
    person = await c.identity_repository.get_by_id(participant.identity)
    if not person:
        return None
    return dict(id=person.id, username=person.username, display_name=person.full_name,
                avatar_url=person.avatar_url)


@router.get('/live/{name}/participants')
async def live_participants(name: str, user=Depends(get_current_user), c=Depends(get_container)):
    """Who is in a Space: host, co-hosts/speakers (can publish) and
    listeners, with mic state. Anonymous listeners are only counted."""
    async with server(c) as lk:
        _, meta = await live_room(lk, name)
        if await c.graph.blocked(user.id, meta['host_id']):
            raise HTTPException(404, 'This Space is unavailable.')
        participants = (await lk.room.list_participants(api.ListParticipantsRequest(room=name))).participants
    people, anonymous = [], 0
    for p in participants:
        if p.identity.startswith('anon-'):
            anonymous += 1
            continue
        profile = await profile_of(c, p)
        if not profile or await c.graph.blocked(user.id, p.identity):
            continue
        audio = [t for t in p.tracks if t.type == 0]  # TrackType.AUDIO
        role = 'Host' if p.identity == meta['host_id'] else 'Speaker' if p.permission.can_publish else 'Listener'
        people.append(dict(profile, role=role, muted=not audio or all(t.muted for t in audio)))
    order = {'Host': 0, 'Speaker': 1, 'Listener': 2}
    people.sort(key=lambda person: order[person['role']])
    return dict(items=people, anonymous=anonymous, title=meta.get('title'),
                record=meta.get('record', False), topics=meta.get('topics', []))


@router.post('/live/{name}/report', status_code=204)
async def report_live(name: str, user=Depends(get_current_user), c=Depends(get_container)):
    await c.graph.store.put('space_report:' + uuid.uuid4().hex, dict(
        room=name, reporter_id=user.id, status='pending', created_at=dt.datetime.now(dt.UTC).isoformat()))


@router.post('/live/{name}/join')
async def join_live(name: str, anonymous: bool = False, user=Depends(get_current_user), c=Depends(get_container)):
    async with server(c) as lk:
        _, meta = await live_room(lk, name)
        if await c.graph.blocked(user.id, meta['host_id']):
            raise HTTPException(404, 'This live session is unavailable.')
    host = user.id == meta['host_id']
    if anonymous and not host:
        # Listen anonymously: hidden identity, no speaking or reactions.
        token = hashlib.sha256(f'{user.id}:{name}'.encode()).hexdigest()[:20]
        return admission(c, user, name, publish=False, host=False, audio_only=True,
                         identity='anon-' + token, display_name='Anonymous listener')
    return admission(c, user, name, publish=host, host=host, audio_only=meta.get("audio_only",False))


@router.delete('/live/{name}', status_code=204)
async def end_live(name: str, user=Depends(get_current_user), c=Depends(get_container)):
    saved = await c.graph.store.get('live_session:'+name)
    if saved and saved['host_id'] != user.id:
        raise HTTPException(403, 'Only the host can end this live session.')
    if saved and saved['status']=='ended': return
    async with server(c) as lk:
        if not saved:
            _, meta = await live_room(lk,name)
            if user.id != meta['host_id']: raise HTTPException(403,'Only the host can end this live session.')
        rooms = (await lk.room.list_rooms(api.ListRoomsRequest(names=[name]))).rooms
        if rooms: await lk.room.delete_room(api.DeleteRoomRequest(room=name))
    if saved:
        await c.graph.store.put(saved['id'],dict(saved,status='ended',ended_at=dt.datetime.now(dt.UTC).isoformat()))


@router.get('/history')
async def live_history(user=Depends(get_current_user),c=Depends(get_container)):
    revision=await c.graph.store.revision()
    cache_key=f'live-history:{revision}:{user.id}'
    cached=await c.cache.get(cache_key)
    if cached is not None: return cached
    sessions=[]
    for row in await c.graph.store.rows('live_session',{'status':'ended'}):
        if not await c.graph.blocked(user.id,row['host_id']): sessions.append(row)
    result=dict(items=sorted(sessions,key=lambda r:r['started_at'],reverse=True)[:100])
    await c.cache.put(cache_key,result,ttl=60)
    return result

@router.get('/recordings')
async def recordings(user=Depends(get_current_user),c=Depends(get_container)):
    key=f'live-recordings:{await c.graph.store.revision()}'
    cached=await c.cache.get(key)
    if cached is not None: return cached
    result=dict(items=await c.graph.store.rows('live_recording'))
    await c.cache.put(key,result,ttl=300)
    return result


class ScheduledSpaceIn(BaseModel):
    title: str = Field(min_length=1,max_length=120)
    topics: list[str] = Field(default_factory=list,max_length=3)
    starts_at: dt.datetime

@router.post('/spaces/scheduled',status_code=201)
async def schedule_space(body:ScheduledSpaceIn,user=Depends(get_current_user),c=Depends(get_container)):
    if body.starts_at.tzinfo is None or body.starts_at <= dt.datetime.now(dt.UTC):
        raise HTTPException(422,'Choose a future date and time.')
    if not body.title.strip(): raise HTTPException(422,'Add a Space title.')
    return await c.graph.store.put('scheduled_space:'+uuid.uuid4().hex,dict(owner=user.id,title=body.title.strip(),topics=body.topics,starts_at=body.starts_at.isoformat(),status='scheduled'))

@router.get('/spaces/scheduled')
async def scheduled_spaces(user=Depends(get_current_user),c=Depends(get_container)):
    return dict(items=await c.graph.store.rows('scheduled_space',{'owner':user.id,'status':'scheduled'}))

@router.post('/spaces/scheduled/{space_id}/start')
async def start_scheduled_space(space_id:str,user=Depends(get_current_user),c=Depends(get_container)):
    if not space_id.startswith('scheduled_space:'): raise HTTPException(404,'Space not found.')
    item=await c.graph.store.get(space_id)
    if not space_id.startswith('scheduled_space:') or not item or item['owner']!=user.id:
        raise HTTPException(404,'Space not found.')
    if item['status']!='scheduled': raise HTTPException(409,'This Space has already started.')
    result=await create_live(BroadcastIn(title=item['title'],audio_only=True,topics=item['topics']),user,c)
    await c.graph.store.put(space_id,dict(item,status='started',room=result['room']))
    return result
