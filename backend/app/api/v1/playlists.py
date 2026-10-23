"""Private, durable News/Stream bookmark collections."""
import uuid
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from app.api.deps import get_container, get_current_user
from app.api.v1.content import presentation
from app.domains.graph.service import key
from app.domains.graph.store import now

router = APIRouter(prefix='/playlists', tags=['playlists'])

class Name(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    @field_validator('name')
    @classmethod
    def nonblank(cls, value):
        if not value.strip(): raise ValueError('Enter a playlist name.')
        return value.strip()

class Create(Name):
    platform: Literal['news','stream','shop','book','social','rooms','pay','foxy']
    media_mode: Literal['audio','video'] | None = None

class Item(BaseModel):
    object_id: str = Field(min_length=1, max_length=250)

async def owned(c, uid, pid):
    if not pid.startswith('playlist:'): raise HTTPException(404,'Playlist unavailable.')
    row = await c.graph.store.get(pid)
    if not row or row['owner_id'] != uid: raise HTTPException(404,'Playlist unavailable.')
    return row

@router.get('')
async def playlists(platform: Literal['news','stream','shop','book','social','rooms','pay','foxy'], user=Depends(get_current_user), c=Depends(get_container)):
    rows = await c.graph.store.rows('playlist', {'owner_id':user.id, 'platform':platform})
    return {'items':sorted(rows, key=lambda r:r['created_at'], reverse=True)}

@router.post('', status_code=201)
async def create(body: Create, user=Depends(get_current_user), c=Depends(get_container)):
    return await c.graph.store.put('playlist:'+uuid.uuid4().hex,dict(owner_id=user.id,platform=body.platform,media_mode=body.media_mode if body.platform == "stream" else None,name=body.name,created_at=now()))

@router.patch('/{pid}')
async def rename(pid: str, body: Name, user=Depends(get_current_user), c=Depends(get_container)):
    row = await owned(c,user.id,pid)
    row['name'] = body.name
    return await c.graph.store.put(pid,row)

@router.delete('/{pid}', status_code=204)
async def delete(pid: str, user=Depends(get_current_user), c=Depends(get_container)):
    await owned(c,user.id,pid)
    for row in await c.graph.store.rows('playlist_item', {'playlist_id':pid}):
        await c.graph.store.delete(row['id'])
    await c.graph.store.delete(pid)

@router.get('/{pid}/items')
async def items(pid: str, user=Depends(get_current_user), c=Depends(get_container)):
    playlist = await owned(c,user.id,pid)
    rows = await c.graph.store.rows('playlist_item', {'playlist_id':pid})
    result = []
    for row in sorted(rows,key=lambda r:r['created_at']):
        try:
            obj = await c.graph.object_for(user.id,row['object_id'])
            saved = await c.graph.store.get(key('activity',user.id,obj['id'],'saved'))
            if saved and obj['platform'] == playlist['platform']:
                result.append(await presentation(c,obj))
        except HTTPException: continue
    return {'items':result}

@router.put('/{pid}/items')
async def add(pid: str, body: Item, user=Depends(get_current_user), c=Depends(get_container)):
    playlist = await owned(c,user.id,pid)
    obj = await c.graph.object_for(user.id,body.object_id)
    if obj['platform'] != playlist['platform']: raise HTTPException(422,'Choose a bookmark from the same platform.')
    if playlist.get('media_mode'):
        detail = await presentation(c,obj)
        kind = str(detail.get('kind') or '').lower() + ' ' + str(detail.get('category') or '').lower()
        mode = 'audio' if any(word in kind for word in ('audio','music','song','podcast')) else 'video'
        if mode != playlist['media_mode']: raise HTTPException(422,'Choose content matching this playlist type.')
    if not await c.graph.store.get(key('activity',user.id,obj['id'],'saved')):
        raise HTTPException(422,'Bookmark this content before adding it.')
    rid = key('playlist_item',pid,obj['id'])
    if not await c.graph.store.get(rid):
        await c.graph.store.put(rid,dict(playlist_id=pid,object_id=obj['id'],created_at=now()))
    return await items(pid,user,c)

@router.delete('/{pid}/items/{object_id}', status_code=204)
async def remove(pid: str, object_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    await owned(c,user.id,pid)
    await c.graph.store.delete(key('playlist_item',pid,object_id))

class SaveBookmark(BaseModel):
    platform: str
    ref: str
    playlist_id: str | None = None
    move: bool = True

@router.post('/save/bookmark')
async def save_bookmark(body: SaveBookmark, user=Depends(get_current_user), c=Depends(get_container)):
    from app.api.v1.content import resolve
    obj = await resolve(c, user.id, body.platform, body.ref)
    if body.playlist_id:
        playlist = await owned(c, user.id, body.playlist_id)
        if playlist['platform'] != body.platform:
            raise HTTPException(422, 'Choose a playlist from this platform.')
        if playlist.get('media_mode'):
            detail = await presentation(c, obj)
            kind = (str(detail.get('kind') or '') + ' ' + str(detail.get('category') or '')).lower()
            mode = 'audio' if any(word in kind for word in ('audio','music','song','podcast')) else 'video'
            if mode != playlist['media_mode']: raise HTTPException(422, 'Choose a matching playlist type.')
    else:
        pid = key('playlist', user.id, body.platform, 'default')
        playlist = await c.graph.store.get(pid)
        if not playlist:
            playlist = await c.graph.store.put(pid, dict(owner_id=user.id, platform=body.platform, name='Saved', created_at=now()))
    if not await c.graph.store.get(key('activity', user.id, obj['id'], 'saved')):
        await c.graph.action(user.id, obj['id'], 'saved')
    pid = playlist['id']
    await c.graph.store.put(key('playlist_item', pid, obj['id']), dict(playlist_id=pid, object_id=obj['id'], created_at=now()))
    if body.move:
        for other in await c.graph.store.rows('playlist', {'owner_id':user.id,'platform':body.platform}):
            if other['id'] != pid:
                await c.graph.store.delete(key('playlist_item', other['id'], obj['id']))
    return playlist
