import time
import httpx
import pytest
from fastapi import HTTPException
from urllib.parse import parse_qs, urlparse
from app.api.v1 import music

TRACK = dict(id='a'*22, name='Catalog song', artists=[{'name':'Artist'}], duration_ms=181000, album={'images':[]})

async def test_premium_restriction_does_not_request_reconnection(monkeypatch):
    class Client:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def request(self, *args, **kwargs):
            return httpx.Response(403, text='Active premium subscription required for the owner of the app.')
    monkeypatch.setattr(music.httpx, 'AsyncClient', Client)
    with pytest.raises(HTTPException) as error:
        await music.request('GET', 'https://api.spotify.com/v1/search')
    assert error.value.status_code == 403
    assert 'Premium subscription' in error.value.detail
    assert 'Reconnecting will not fix' in error.value.detail

async def test_oauth_pkce_one_time_and_encryption(client, auth_headers, settings, monkeypatch):
    settings.spotify_client_id = 'client'
    settings.spotify_callback_url = 'http://127.0.0.1:8000/auth/spotify/callback'
    async def fake(method, url, **kwargs):
        assert kwargs['data']['code_verifier']
        return dict(access_token='private-access',refresh_token='private-refresh',expires_in=3600)
    monkeypatch.setattr(music,'request',fake)
    response = await client.post('/api/v1/music/connect',headers=auth_headers)
    assert response.status_code == 200
    params = parse_qs(urlparse(response.json()['url']).query)
    assert params['code_challenge_method'] == ['S256']
    callback = {'state':params['state'][0],'code':'code'}
    response = await client.get('/auth/spotify/callback',params=callback)
    assert response.status_code == 200
    assert 'private-access' not in response.text
    assert response.headers['cache-control'] == 'no-store'
    assert (await client.get('/auth/spotify/callback',params=callback)).status_code == 400
    assert (await client.get('/api/v1/music/status',headers=auth_headers)).json()['connected']
    with music.MusicStore(settings).db() as db:
        assert b'private-access' not in db.execute('SELECT encrypted FROM spotify_tokens').fetchone()[0]
    await client.delete('/api/v1/music/connection',headers=auth_headers)
    assert not (await client.get('/api/v1/music/status',headers=auth_headers)).json()['connected']

async def test_saved_selection_and_publish(client,auth_headers,settings,monkeypatch):
    async def fake(c,uid,path,params=None):
        return TRACK if path.startswith('tracks/') else {'tracks':{'items':[TRACK],'next':None}}
    monkeypatch.setattr(music,'catalog',fake)
    r = await client.get('/api/v1/music/tracks',params={'q':'Artist'},headers=auth_headers)
    assert r.status_code == 200 and r.json()['items'][0]['title'] == TRACK['name']
    assert (await client.put('/api/v1/music/saved',json={'id':TRACK['id']},headers=auth_headers)).status_code == 200
    assert len((await client.get('/api/v1/music/tracks',params={'tab':'saved'},headers=auth_headers)).json()['items']) == 1
    await client.put('/api/v1/music/selection',json={'id':TRACK['id'],'context':'post'},headers=auth_headers)
    post = await client.post('/api/v1/social/posts',json={'text':'Music reference','music_id':TRACK['id']},headers=auth_headers)
    assert post.status_code == 201, post.text
    song = await client.get('/api/v1/music/content/post/'+post.json()['id'],headers=auth_headers)
    assert song.status_code == 200 and song.json()['id'] == TRACK['id'], song.text
    other = await client.post('/api/v1/auth/login',json={'identifier':'neha','password':'password123'})
    assert other.status_code == 200
    other_headers = {'Authorization':'Bearer '+other.json()['tokens']['access_token']}
    assert (await client.get('/api/v1/music/selection',params={'context':'post'},headers=other_headers)).json() is None
    assert (await client.get('/api/v1/music/tracks',params={'tab':'saved'},headers=other_headers)).json()['items'] == []
    note = await client.post('/api/v1/notes',json={'text':'Listen to this','recipients':['neha'],'music_id':TRACK['id']},headers=auth_headers)
    assert note.status_code == 201 and note.json()['music']['id'] == TRACK['id'], note.text
    notes = (await client.get('/api/v1/notes',headers=other_headers)).json()['items']
    assert any(n.get('music',{}).get('id') == TRACK['id'] for n in notes)
    assert (await client.get('/api/v1/music/tracks')).status_code == 401
    assert (await client.put('/api/v1/music/saved',json={'id':'bad'},headers=auth_headers)).status_code == 422
    await client.delete('/api/v1/music/saved/'+TRACK['id'],headers=auth_headers)
    assert (await client.get('/api/v1/music/tracks',params={'tab':'saved'},headers=auth_headers)).json()['items'] == []

async def test_expired_and_denied_oauth(client,settings):
    with music.MusicStore(settings).db() as db:
        db.execute('INSERT INTO spotify_oauth VALUES (?,?,?,?)',('expired','owner','verifier',time.time()-1))
        db.execute('INSERT INTO spotify_oauth VALUES (?,?,?,?)',('denied','owner','verifier',time.time()+100))
    assert (await client.get('/auth/spotify/callback',params={'state':'expired','code':'code'})).status_code == 400
    r = await client.get('/auth/spotify/callback',params={'state':'denied','error':'access_denied'})
    assert r.status_code == 200 and 'cancelled' in r.text
    assert (await client.get('/auth/spotify/callback',params={'state':'denied','code':'code'})).status_code == 400
