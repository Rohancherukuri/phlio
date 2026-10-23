import json
from contextlib import asynccontextmanager
from types import SimpleNamespace
from unittest.mock import AsyncMock

import jwt
import pytest

pytestmark = pytest.mark.asyncio


@pytest.fixture
def rtc(monkeypatch):
    from app.api.v1 import realtime
    rooms = {}
    async def create(request):
        rooms[request.name] = SimpleNamespace(name=request.name, metadata=request.metadata, num_participants=1)
    async def listing(request):
        return SimpleNamespace(rooms=[r for k, r in rooms.items() if not request.names or k in request.names])
    async def delete(request):
        rooms.pop(request.room, None)
    client = SimpleNamespace(room=SimpleNamespace(create_room=AsyncMock(side_effect=create),
        list_rooms=AsyncMock(side_effect=listing), delete_room=AsyncMock(side_effect=delete)))
    @asynccontextmanager
    async def server(c):
        c.settings.livekit_url = 'ws://test:7880'
        c.settings.livekit_api_key = 'test-key'
        c.settings.livekit_api_secret = 's' * 32
        yield client
    monkeypatch.setattr(realtime, 'server', server)
    return client


async def other_headers(client):
    response = await client.post('/api/v1/auth/login', json={'identifier':'neha', 'password':'password123'})
    return {'Authorization': 'Bearer ' + response.json()['tokens']['access_token']}


async def test_live_host_and_audience_are_different_grants(client, auth_headers, rtc):
    response = await client.post('/api/v1/realtime/live', headers=auth_headers, json={'title':'My live'})
    assert response.status_code == 201, response.text
    data = response.json()
    claims = jwt.decode(data['token'], 's' * 32, algorithms=['HS256'])
    assert claims['video']['canPublish'] is True
    assert claims['video']['room'] == data['room']
    assert claims['exp'] - claims['nbf'] == 600
    viewer = await other_headers(client)
    response = await client.post(f"/api/v1/realtime/live/{data['room']}/join", headers=viewer)
    assert response.status_code == 200
    audience = jwt.decode(response.json()['token'], 's' * 32, algorithms=['HS256'])
    assert audience['video']['canPublish'] is False
    assert audience['video']['canPublishData'] is False
    assert (await client.delete(f"/api/v1/realtime/live/{data['room']}", headers=viewer)).status_code == 403
    assert (await client.delete(f"/api/v1/realtime/live/{data['room']}", headers=auth_headers)).status_code == 204
    assert (await client.post(f"/api/v1/realtime/live/{data['room']}/join", headers=viewer)).status_code == 404


async def test_voice_room_membership_and_auth(client, auth_headers, rtc):
    response = await client.post('/api/v1/rooms', headers=auth_headers, json={
        'name':'Private audio', 'category':'tech_and_ai', 'is_private':True})
    assert response.status_code == 201, response.text
    rid = response.json()['id']
    path = f'/api/v1/realtime/rooms/{rid}/join'
    assert (await client.post(path)).status_code == 401
    assert (await client.post(path, headers=await other_headers(client))).status_code == 403
    result = await client.post(path, headers=auth_headers)
    assert result.status_code == 200, result.text
    assert result.json()['can_publish']


async def test_call_requires_acceptance_and_participant_identity(client, auth_headers, rtc):
    response = await client.post('/api/v1/messaging/calls', headers=auth_headers, json={'peer':'neha','video':True})
    assert response.status_code == 201, response.text
    rid = response.json()['id']
    path = f'/api/v1/realtime/calls/{rid}/join'
    assert (await client.post(path, headers=auth_headers)).status_code == 409
    viewer = await other_headers(client)
    await client.post(f'/api/v1/messaging/calls/{rid}/actions/accept', headers=viewer)
    assert (await client.post(path, headers=auth_headers)).status_code == 200
    await client.post(f'/api/v1/messaging/calls/{rid}/actions/end', headers=auth_headers)
    assert (await client.post(path, headers=viewer)).status_code == 409

async def test_space_audio_grants_and_schedule(client,auth_headers,rtc):
    response=await client.post('/api/v1/realtime/live',headers=auth_headers,json={'title':'Music chat','audio_only':True,'topics':['Music']})
    assert response.status_code==201,response.text
    claims=jwt.decode(response.json()['token'],'s'*32,algorithms=['HS256'])
    assert claims['video']['canPublishSources']==['microphone']
    import datetime as dt
    created=await client.post('/api/v1/realtime/spaces/scheduled',headers=auth_headers,json={'title':'Tomorrow','topics':['Music'],'starts_at':(dt.datetime.now(dt.UTC)+dt.timedelta(days=1)).isoformat()})
    assert created.status_code==201,created.text
    sid=created.json()['id']
    other=await other_headers(client)
    assert (await client.post('/api/v1/realtime/spaces/scheduled/'+sid+'/start',headers=other)).status_code==404
    response=await client.post('/api/v1/realtime/spaces/scheduled/'+sid+'/start',headers=auth_headers)
    assert response.status_code==200,response.text
    claims=jwt.decode(response.json()['token'],'s'*32,algorithms=['HS256'])
    assert claims['video']['canPublishSources']==['microphone']
    assert (await client.post('/api/v1/realtime/spaces/scheduled/'+sid+'/start',headers=auth_headers)).status_code==409


async def test_ended_session_history_is_persistent_and_idempotent(client,auth_headers,rtc):
    created=await client.post('/api/v1/realtime/live',headers=auth_headers,json={'title':'Remember this session'})
    assert created.status_code==201
    room=created.json()['room']
    assert (await client.get('/api/v1/realtime/history',headers=auth_headers)).json()['items']==[]
    path='/api/v1/realtime/live/'+room
    for _ in range(2): assert (await client.delete(path,headers=auth_headers)).status_code==204
    history=await client.get('/api/v1/realtime/history',headers=auth_headers)
    assert len(history.json()['items'])==1
    saved=history.json()['items'][0]
    assert saved['title']=='Remember this session'
    assert saved['ended_at'] is not None
    assert saved['recording_url'] is None
    assert (await client.get('/api/v1/realtime/history',headers=auth_headers)).json()==history.json()
    assert (await client.get('/api/v1/realtime/history')).status_code==401
