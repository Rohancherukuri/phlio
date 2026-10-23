"""Spotify catalog references (never downloads or synchronizes Spotify audio)."""
import base64
import hashlib
import json
import logging
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Literal
from urllib.parse import urlencode

import httpx
from cryptography.fernet import Fernet, InvalidToken
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from app.api.deps import get_container, get_current_user

router = APIRouter(prefix='/music', tags=['music'])
callback_router = APIRouter()

class CallbackLogFilter(logging.Filter):
    def filter(self, record):
        # Uvicorn otherwise includes the one-time OAuth code in access logs.
        if isinstance(record.args, tuple) and len(record.args) == 5:
            address, method, path, version, status = record.args
            if isinstance(path, str) and path.startswith('/auth/spotify/callback?'):
                record.args = (address, method, path.split('?', 1)[0], version, status)
        return True

logging.getLogger('uvicorn.access').addFilter(CallbackLogFilter())

class MusicStore:
    def __init__(self, settings):
        path = Path(settings.music_database)
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = str(path)
        self.cipher = Fernet(base64.urlsafe_b64encode(hashlib.sha256(settings.jwt_secret.encode()).digest()))
        with self.db() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS spotify_tokens(owner TEXT PRIMARY KEY, encrypted BLOB);
                CREATE TABLE IF NOT EXISTS spotify_oauth(state TEXT PRIMARY KEY, owner TEXT, verifier TEXT, expires REAL);
                CREATE TABLE IF NOT EXISTS music_saved(owner TEXT, track TEXT, payload TEXT, PRIMARY KEY(owner,track));
                CREATE TABLE IF NOT EXISTS music_selection(owner TEXT, context TEXT, target TEXT, payload TEXT, PRIMARY KEY(owner,context,target));
            """)
    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=10)
        try:
            with db:
                yield db
        finally:
            db.close()
    def token(self, owner):
        with self.db() as db:
            row = db.execute('SELECT encrypted FROM spotify_tokens WHERE owner=?', (owner,)).fetchone()
        try:
            return json.loads(self.cipher.decrypt(row[0])) if row else None
        except InvalidToken:
            return None
    def save_token(self, owner, value):
        with self.db() as db:
            db.execute('INSERT OR REPLACE INTO spotify_tokens VALUES (?,?)', (owner,self.cipher.encrypt(json.dumps(value).encode())))

async def request(method, url, **kwargs):
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.request(method,url,**kwargs)
    except httpx.RequestError:
        raise HTTPException(503,'Spotify could not be reached. Try again.')
    if response.status_code == 429:
        raise HTTPException(429,'Spotify is busy. Please try again later.')
    if response.status_code == 403:
        reason = response.text.lower()
        if 'premium' in reason and 'owner' in reason:
            raise HTTPException(403, 'Spotify is connected, but Spotify requires an active Premium subscription for the owner of this developer app. After activation, Spotify says access may take a few hours. Reconnecting will not fix this restriction.')
        if 'scope' in reason:
            raise HTTPException(409, 'Reconnect Spotify to grant the required music permissions.')
        raise HTTPException(403, 'Spotify is connected, but access is restricted by Spotify. Check this app’s developer access and allowed users in the Spotify dashboard.')
    if response.status_code in (400,401):
        raise HTTPException(409,'Reconnect Spotify. Check that your account is allowed in the Spotify developer dashboard.')
    if response.status_code >= 400:
        raise HTTPException(502,'Spotify could not load this music.')
    return response.json()

async def access(c, uid):
    store = MusicStore(c.settings)
    token = store.token(uid)
    if not token:
        raise HTTPException(409,'Connect Spotify to browse music.')
    if token['expires_at'] < time.time()+30:
        data = await request('POST','https://accounts.spotify.com/api/token',data={
            'grant_type':'refresh_token','refresh_token':token['refresh_token'],
            'client_id':c.settings.spotify_client_id})
        token.update(data, expires_at=time.time()+data.get('expires_in',3600))
        store.save_token(uid,token)
    return token['access_token']

async def catalog(c, uid, path, params=None):
    token = await access(c,uid)
    cache_key = 'spotify:' + hashlib.sha256(json.dumps([uid,path,params],sort_keys=True).encode()).hexdigest()
    cached = await c.cache.get(cache_key)
    if cached is not None:
        return cached
    result = await request('GET','https://api.spotify.com/v1/'+path,
                           headers={'Authorization':'Bearer '+token},params=params)
    await c.cache.put(cache_key,result,ttl=60)
    return result

def track(item):
    images = item.get('album',{}).get('images',[])
    return dict(id=item['id'],title=item['name'],artist=', '.join(a['name'] for a in item.get('artists',[])),
                image_url=images[-2 if len(images)>1 else 0]['url'] if images else None,
                duration_ms=item.get('duration_ms',0),explicit=item.get('explicit',False),
                url='https://open.spotify.com/track/'+item['id'],source='spotify')

@router.get('/status')
async def status(user=Depends(get_current_user),c=Depends(get_container)):
    return dict(configured=bool(c.settings.spotify_client_id and c.settings.spotify_callback_url),
                connected=MusicStore(c.settings).token(user.id) is not None)

@router.post('/connect')
async def connect(user=Depends(get_current_user),c=Depends(get_container)):
    if not c.settings.spotify_client_id or not c.settings.spotify_callback_url:
        raise HTTPException(503,'Spotify has not been configured.')
    await c.cache.rate_limit(user.id,'spotify_connect',10)
    state, verifier = secrets.token_urlsafe(32), secrets.token_urlsafe(64)
    challenge=base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
    with MusicStore(c.settings).db() as db:
        db.execute('DELETE FROM spotify_oauth WHERE expires<?',(time.time(),))
        db.execute('INSERT INTO spotify_oauth VALUES (?,?,?,?)',(state,user.id,verifier,time.time()+600))
    return {'url':'https://accounts.spotify.com/authorize?'+urlencode(dict(client_id=c.settings.spotify_client_id,
        response_type='code',redirect_uri=c.settings.spotify_callback_url,state=state,
        code_challenge_method='S256',code_challenge=challenge,scope='user-top-read'))}

@callback_router.get('/auth/spotify/callback',response_class=HTMLResponse)
async def callback(state: str=Query(...,max_length=200),code: str|None=Query(None,max_length=2000),
                   error: str|None=None,c=Depends(get_container)):
    store=MusicStore(c.settings)
    with store.db() as db:
        db.execute('BEGIN IMMEDIATE')
        row=db.execute('SELECT owner,verifier,expires FROM spotify_oauth WHERE state=?',(state,)).fetchone()
        db.execute('DELETE FROM spotify_oauth WHERE state=?',(state,))
    if not row or row[2]<time.time():
        raise HTTPException(400,'This connection request expired. Return to Phlio and try again.')
    if error or not code:
        return HTMLResponse('<h2>Spotify connection cancelled</h2><p>Return to Phlio to try again.</p>',headers={'Cache-Control':'no-store','Referrer-Policy':'no-referrer'})
    token=await request('POST','https://accounts.spotify.com/api/token',data=dict(grant_type='authorization_code',
        code=code,client_id=c.settings.spotify_client_id,redirect_uri=c.settings.spotify_callback_url,code_verifier=row[1]))
    token['expires_at']=time.time()+token.get('expires_in',3600)
    store.save_token(row[0],token)
    return HTMLResponse('<h2>Spotify connected</h2><p>Return to Phlio to choose a song.</p>',headers={'Cache-Control':'no-store','Referrer-Policy':'no-referrer'})

@router.delete('/connection',status_code=204)
async def disconnect(user=Depends(get_current_user),c=Depends(get_container)):
    with MusicStore(c.settings).db() as db:
        db.execute('DELETE FROM spotify_tokens WHERE owner=?',(user.id,))
        db.execute('DELETE FROM spotify_oauth WHERE owner=?',(user.id,))

@router.get('/tracks')
async def tracks(q: str=Query('',max_length=120), tab: Literal['for_you','trending','saved','original']='for_you',
                 offset:int=Query(0,ge=0,le=1000),user=Depends(get_current_user),c=Depends(get_container)):
    await c.cache.rate_limit(user.id,'spotify_catalog',60)
    with MusicStore(c.settings).db() as db:
        saved={r[0] for r in db.execute('SELECT track FROM music_saved WHERE owner=?',(user.id,))}
        if not q and tab in ('saved','trending','original'):
            if tab=='original': return {'items':[], 'has_more':False}
            if tab=='saved':
                rows=db.execute('SELECT payload FROM music_saved WHERE owner=? ORDER BY rowid DESC LIMIT 10 OFFSET ?',(user.id,offset)).fetchall()
            else:
                rows=db.execute('SELECT payload FROM music_saved GROUP BY track ORDER BY COUNT(*) DESC LIMIT 10 OFFSET ?',(offset,)).fetchall()
            items=[json.loads(r[0]) for r in rows]
            return {'items':[dict(t,saved=t['id'] in saved) for t in items],'has_more':len(items)==10}
    if q.strip():
        data=await catalog(c,user.id,'search',{'q':q.strip(),'type':'track','limit':10,'offset':offset})
        page=data.get('tracks',{})
    else:
        page=await catalog(c,user.id,'me/top/tracks',{'limit':10,'offset':offset,'time_range':'short_term'})
    return {'items':[dict(track(t),saved=t['id'] in saved) for t in page.get('items',[]) if t and t.get('id')],
            'has_more':bool(page.get('next'))}

class TrackId(BaseModel):
    id: str=Field(pattern=r'^[A-Za-z0-9]{22}$')

@router.put('/saved')
async def save(body:TrackId,user=Depends(get_current_user),c=Depends(get_container)):
    item=track(await catalog(c,user.id,'tracks/'+body.id))
    with MusicStore(c.settings).db() as db:
        db.execute('INSERT OR REPLACE INTO music_saved VALUES (?,?,?)',(user.id,body.id,json.dumps(item)))
    return dict(item,saved=True)

@router.delete('/saved/{tid}',status_code=204)
async def unsave(tid:str,user=Depends(get_current_user),c=Depends(get_container)):
    with MusicStore(c.settings).db() as db:
        db.execute('DELETE FROM music_saved WHERE owner=? AND track=?',(user.id,tid))

class Selection(TrackId):
    context: Literal['profile','post','video','clip','moment','experience','note']
    target: str=Field(default='draft',max_length=180)

@router.put('/selection')
async def select(body:Selection,user=Depends(get_current_user),c=Depends(get_container)):
    # Owner-scoped selection; never permits changing another creator's content.
    item=track(await catalog(c,user.id,'tracks/'+body.id))
    with MusicStore(c.settings).db() as db:
        db.execute('INSERT OR REPLACE INTO music_selection VALUES (?,?,?,?)',
                   (user.id,body.context,body.target,json.dumps(item)))
    return item

@router.get('/selection')
async def selection(context:str,target:str='draft',user=Depends(get_current_user),c=Depends(get_container)):
    with MusicStore(c.settings).db() as db:
        row=db.execute('SELECT payload FROM music_selection WHERE owner=? AND context=? AND target=?',(user.id,context,target)).fetchone()
    return json.loads(row[0]) if row else None

@router.delete('/selection',status_code=204)
async def clear_selection(context:str,target:str='draft',user=Depends(get_current_user),c=Depends(get_container)):
    with MusicStore(c.settings).db() as db:
        db.execute('DELETE FROM music_selection WHERE owner=? AND context=? AND target=?',(user.id,context,target))

async def prepare_selection(c,uid,context,tid):
    if not tid: return None
    if not tid.startswith("local_"): TrackId(id=tid)
    with MusicStore(c.settings).db() as db:
        row=db.execute('SELECT payload FROM music_selection WHERE owner=? AND context=? AND target=?',(uid,context,'draft')).fetchone()
    if row:
        item=json.loads(row[0])
        if item['id']==tid:return item
    if tid.startswith('local_'):
        with MusicStore(c.settings).db() as db:
            row = db.execute('SELECT payload FROM music_selection WHERE owner=? AND context=? AND target=?', (uid,context,tid)).fetchone()
        if row: return json.loads(row[0])
        raise HTTPException(404, 'Uploaded song is no longer available.')
    return track(await catalog(c,uid,'tracks/'+tid))

def attach_selection(c,uid,context,target,item):
    if item:
        with MusicStore(c.settings).db() as db:
            db.execute('INSERT OR REPLACE INTO music_selection VALUES (?,?,?,?)',(uid,context,target,json.dumps(item)))

@router.get('/content/{context}/{target}')
async def content_selection(context:Literal['post','video','clip'],target:str,user=Depends(get_current_user),c=Depends(get_container)):
    from app.api.v1.content import resolve
    obj=await resolve(c,user.id,'social',target)
    if obj['object_type']!='social.'+context:raise HTTPException(404,'Content unavailable.')
    with MusicStore(c.settings).db() as db:
        row=db.execute('SELECT payload FROM music_selection WHERE context=? AND target=? AND owner=?',(context,target,obj['owner'])).fetchone()
    return json.loads(row[0]) if row else None
