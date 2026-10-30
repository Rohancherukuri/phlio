"""Authenticated SFU admission. Signing secrets never leave the API server."""
import asyncio
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
from app.core.container import media_root_path
from app.domains import spaces
from app.domains.spaces import recorder

router = APIRouter(prefix='/realtime', tags=['realtime'])
_background: set[asyncio.Task] = set()


def _spawn(coro):
    task = asyncio.create_task(coro)
    _background.add(task)
    task.add_done_callback(_background.discard)


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
              identity=None, display_name=None, data=None, role=None):
    s = configured(c)
    jwt = spaces.token(
        s, identity=identity or user.id, name=display_name or user.full_name, room=room,
        publish=publish, data=publish if data is None else data, audio_only=audio_only,
        role=role or (spaces.ROLE_HOST if host else spaces.ROLE_SPEAKER if publish else spaces.ROLE_LISTENER))
    return dict(url=s.livekit_url, token=jwt, room=room, can_publish=publish, host=host)


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


async def profile_by_id(c, identity):
    person = await c.identity_repository.get_by_id(identity)
    if not person:
        return None
    return dict(id=person.id, username=person.username, display_name=person.full_name,
                avatar_url=person.avatar_url)


async def profile_of(c, participant):
    return await profile_by_id(c, participant.identity)


@router.post('/live', status_code=201)
async def create_live(body: BroadcastIn, user=Depends(get_current_user), c=Depends(get_container)):
    name = 'social-' + uuid.uuid4().hex
    meta = dict(host_id=user.id, name=user.full_name, title=body.title, audio_only=body.audio_only,
                topics=body.topics, record=body.record, started_at=spaces.utcnow())
    async with server(c) as lk:
        await lk.room.create_room(api.CreateRoomRequest(name=name, empty_timeout=60,
                                                       metadata=json.dumps(meta)))
    try:
        await c.graph.store.put('live_session:'+name, dict(room=name, **meta, status='live',
                                                            ended_at=None, recording_url=None))
    except Exception:
        async with server(c) as lk:
            await lk.room.delete_room(api.DeleteRoomRequest(room=name))
        raise
    result = admission(c, user, name, host=True, audio_only=body.audio_only)
    if body.record and body.audio_only:
        # The recorder joins once the host is in; it waits quietly until then.
        _spawn(_start_recorder(c, name, meta))
    return dict(result, record=body.record, started_at=meta['started_at'])


async def _start_recorder(c, name, meta):
    await asyncio.sleep(1.5)
    await recorder.start(c.settings, c.graph.store, media_root_path(c.settings), name, meta,
                         lambda ident: profile_by_id(c, ident))


async def live_room(lk, name):
    if not name.startswith('social-'):
        raise HTTPException(404, 'Live session not found.')
    rooms = (await lk.room.list_rooms(api.ListRoomsRequest(names=[name]))).rooms
    if not rooms:
        raise HTTPException(404, 'This live session has ended.')
    return rooms[0], json.loads(rooms[0].metadata or '{}')


def _people(participants):
    return [p for p in participants if not spaces.is_system(p.identity)]


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
            people = _people(participants)
            anonymous = sum(p.identity.startswith('anon-') for p in participants)
            # Up to three faces for the Spaces pill: host first, then speakers.
            ordered = sorted(people, key=lambda p: (p.identity != meta['host_id'], not p.permission.can_publish))
            preview = [x for x in [await profile_of(c, p) for p in ordered[:3]] if x]
            speakers = sum(p.permission.can_publish for p in people)
            items.append(dict(id=room.name, **meta, viewers=max(0, len(people) + anonymous - 1),
                              participants_count=len(people) + anonymous, speakers_count=speakers,
                              listeners_count=len(people) + anonymous - speakers, preview=preview))
    # Biggest conversations first, your own Space always on top.
    items.sort(key=lambda i: (i['host_id'] != user.id, -i['participants_count']))
    return dict(items=items)


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
    labels = {spaces.ROLE_HOST: 'Host', spaces.ROLE_COHOST: 'Co-host',
              spaces.ROLE_SPEAKER: 'Speaker', spaces.ROLE_LISTENER: 'Listener'}
    for p in participants:
        if p.identity.startswith('anon-'):
            anonymous += 1
            continue
        if spaces.is_system(p.identity):
            continue
        profile = await profile_of(c, p)
        if not profile or await c.graph.blocked(user.id, p.identity):
            continue
        audio = [t for t in p.tracks if t.type == 0]  # TrackType.AUDIO
        role = labels[spaces.role_of(p, meta['host_id'])]
        people.append(dict(profile, role=role, muted=not audio or all(t.muted for t in audio)))
    order = {'Host': 0, 'Co-host': 1, 'Speaker': 2, 'Listener': 3}
    people.sort(key=lambda person: order[person['role']])
    return dict(items=people, anonymous=anonymous, title=meta.get('title'), host_id=meta['host_id'],
                record=meta.get('record', False), topics=meta.get('topics', []),
                started_at=meta.get('started_at'))


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
    extra = dict(record=meta.get('record', False), started_at=meta.get('started_at'),
                 host_id=meta['host_id'], title=meta.get('title'), topics=meta.get('topics', []))
    if anonymous and not host:
        # Listen anonymously: hidden identity, no speaking or reactions.
        token = hashlib.sha256(f'{user.id}:{name}'.encode()).hexdigest()[:20]
        return dict(admission(c, user, name, publish=False, host=False, audio_only=True, data=False,
                              identity='anon-' + token, display_name='Anonymous listener'),
                    anonymous=True, **extra)
    # Listeners can send reactions and requests (data), not audio.
    return dict(admission(c, user, name, publish=host, host=host, audio_only=meta.get("audio_only", False),
                          data=True), anonymous=False, **extra)


# -- Speaking: requests, invitations, stepping down ------------------------------

async def _host_only(lk, c, name, user):
    _, meta = await live_room(lk, name)
    if user.id != meta['host_id']:
        raise HTTPException(403, 'Only the host can manage speakers.')
    return meta


@router.post('/live/{name}/requests', status_code=202)
async def request_to_speak(name: str, user=Depends(get_current_user), c=Depends(get_container)):
    async with server(c) as lk:
        _, meta = await live_room(lk, name)
        if user.id == meta['host_id']:
            return dict(status='approved')
        key = spaces.request_key(name, user.id)
        await c.graph.store.put(key, dict(room=name, user_id=user.id, status='pending',
                                          created_at=spaces.utcnow()))
        profile = await profile_by_id(c, user.id)
        await spaces.send(lk, name, dict(type='request', user=profile), to=[meta['host_id']])
    return dict(status='pending')


@router.delete('/live/{name}/requests', status_code=204)
async def cancel_request(name: str, user=Depends(get_current_user), c=Depends(get_container)):
    key = spaces.request_key(name, user.id)
    row = await c.graph.store.get(key)
    if row and row['status'] == 'pending':
        await c.graph.store.put(key, dict(row, status='cancelled'))
        async with server(c) as lk:
            _, meta = await live_room(lk, name)
            await spaces.send(lk, name, dict(type='request_cancelled', user_id=user.id), to=[meta['host_id']])


@router.get('/live/{name}/requests')
async def speak_requests(name: str, user=Depends(get_current_user), c=Depends(get_container)):
    async with server(c) as lk:
        await _host_only(lk, c, name, user)
    items = []
    for row in await c.graph.store.rows('space_request', {'room': name, 'status': 'pending'}):
        profile = await profile_by_id(c, row['user_id'])
        if profile:
            items.append(dict(profile, requested_at=row['created_at']))
    items.sort(key=lambda r: r['requested_at'])
    return dict(items=items)


class RoleIn(BaseModel):
    role: str = Field(default=spaces.ROLE_SPEAKER, pattern='^(speaker|cohost)$')


@router.post('/live/{name}/speakers/{user_id}')
async def add_speaker(name: str, user_id: str, body: RoleIn | None = None, user=Depends(get_current_user),
                      c=Depends(get_container)):
    role = (body or RoleIn()).role
    async with server(c) as lk:
        await _host_only(lk, c, name, user)
        try:
            await spaces.set_role(lk, name, user_id, role)
        except Exception as exc:
            raise HTTPException(404, 'They have left the Space.') from exc
        await spaces.send(lk, name, dict(type='approved', user_id=user_id, role=role), to=[user_id])
    key = spaces.request_key(name, user_id)
    row = await c.graph.store.get(key)
    if row:
        await c.graph.store.put(key, dict(row, status='approved', decided_at=spaces.utcnow()))
    return dict(user_id=user_id, role=role)


@router.delete('/live/{name}/requests/{user_id}', status_code=204)
async def decline_request(name: str, user_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    async with server(c) as lk:
        await _host_only(lk, c, name, user)
        key = spaces.request_key(name, user_id)
        row = await c.graph.store.get(key)
        if row:
            await c.graph.store.put(key, dict(row, status='declined', decided_at=spaces.utcnow()))
        await spaces.send(lk, name, dict(type='declined', user_id=user_id), to=[user_id])


@router.delete('/live/{name}/speakers/{user_id}', status_code=204)
async def remove_speaker(name: str, user_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    """The host moves a speaker back to listening, or a speaker steps down."""
    async with server(c) as lk:
        _, meta = await live_room(lk, name)
        if user.id not in (meta['host_id'], user_id) or user_id == meta['host_id']:
            raise HTTPException(403, 'Only the host can manage speakers.')
        try:
            await spaces.set_role(lk, name, user_id, spaces.ROLE_LISTENER)
        except Exception as exc:
            raise HTTPException(404, 'They have left the Space.') from exc
        if user.id != user_id:
            await spaces.send(lk, name, dict(type='removed', user_id=user_id), to=[user_id])


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
        if rooms:
            with_space = rooms[0]
            await spaces.send(lk, name, dict(type='ended', record=json.loads(with_space.metadata or '{}').get('record', False)))
            await lk.room.delete_room(api.DeleteRoomRequest(room=name))
    if saved:
        await c.graph.store.put(saved['id'],dict(saved,status='ended',ended_at=dt.datetime.now(dt.UTC).isoformat()))
    # Encoding can take a few seconds; the recording appears when it's ready.
    _spawn(recorder.stop(name))


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


# -- Recorded Spaces --------------------------------------------------------------

@router.get('/spaces/recordings')
async def space_recordings(user=Depends(get_current_user), c=Depends(get_container)):
    items = []
    for row in await c.graph.store.rows('space_recording', {'status': 'ready'}):
        if row.get('host_id') and await c.graph.blocked(user.id, row['host_id']):
            continue
        items.append({k: v for k, v in row.items() if k != 'timeline'})
    items.sort(key=lambda r: r.get('ended_at') or '', reverse=True)
    return dict(items=items[:100])


@router.get('/spaces/recordings/{rid}')
async def space_recording(rid: str, user=Depends(get_current_user), c=Depends(get_container)):
    if not rid.startswith('space_recording:'):
        rid = 'space_recording:' + rid
    row = await c.graph.store.get(rid)
    if not row or (row.get('host_id') and await c.graph.blocked(user.id, row['host_id'])):
        raise HTTPException(404, 'Recording not found.')
    return row


@router.post('/spaces/recordings/{rid}/play', status_code=204)
async def played(rid: str, user=Depends(get_current_user), c=Depends(get_container)):
    if not rid.startswith('space_recording:'):
        rid = 'space_recording:' + rid
    row = await c.graph.store.get(rid)
    if row:
        await c.graph.store.put(rid, dict(row, plays=int(row.get('plays') or 0) + 1))


class ScheduledSpaceIn(BaseModel):
    title: str = Field(min_length=1,max_length=120)
    topics: list[str] = Field(default_factory=list,max_length=3)
    starts_at: dt.datetime
    record: bool = False

@router.post('/spaces/scheduled',status_code=201)
async def schedule_space(body:ScheduledSpaceIn,user=Depends(get_current_user),c=Depends(get_container)):
    if body.starts_at.tzinfo is None or body.starts_at <= dt.datetime.now(dt.UTC):
        raise HTTPException(422,'Choose a future date and time.')
    if not body.title.strip(): raise HTTPException(422,'Add a Space title.')
    return await c.graph.store.put('scheduled_space:'+uuid.uuid4().hex,dict(owner=user.id,title=body.title.strip(),topics=body.topics,starts_at=body.starts_at.isoformat(),status='scheduled',record=body.record))

@router.get('/spaces/scheduled')
async def scheduled_spaces(user=Depends(get_current_user),c=Depends(get_container)):
    items=await c.graph.store.rows('scheduled_space',{'owner':user.id,'status':'scheduled'})
    return dict(items=sorted(items,key=lambda r:r['starts_at']))

@router.post('/spaces/scheduled/{space_id}/start')
async def start_scheduled_space(space_id:str,user=Depends(get_current_user),c=Depends(get_container)):
    if not space_id.startswith('scheduled_space:'): raise HTTPException(404,'Space not found.')
    item=await c.graph.store.get(space_id)
    if not space_id.startswith('scheduled_space:') or not item or item['owner']!=user.id:
        raise HTTPException(404,'Space not found.')
    if item['status']!='scheduled': raise HTTPException(409,'This Space has already started.')
    result=await create_live(BroadcastIn(title=item['title'],audio_only=True,topics=item['topics'],record=bool(item.get('record'))),user,c)
    await c.graph.store.put(space_id,dict(item,status='started',room=result['room']))
    return result
