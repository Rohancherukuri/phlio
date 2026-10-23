"""Rich, authorized comments shared by Social posts, videos and clips."""
import io
import re
import uuid
from PIL import Image, UnidentifiedImageError
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, Query
from app.api.deps import get_container, get_current_user
from app.api.v1.content import resolve
from app.core.container import media_root_path
from app.domains.graph.store import now
from app.domains.stickers import STICKER_IDS

router = APIRouter(prefix='/social', tags=['social comments'])

@router.get('/comment-mentions')
async def mentions(q: str = Query('', max_length=80), user=Depends(get_current_user), c=Depends(get_container)):
    return [c.graph.profile(p) for p in await c.identity_repository.search_users(q.lstrip('@'), 12) if not await c.graph.blocked(user.id,p.id)]

@router.get('/content/{ref}/comments')
async def comments(ref: str, platform: str = 'social', user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c,user.id,platform,ref)
    cache_key = f'comments:{await c.graph.store.revision()}:{obj["id"]}'
    rows = await c.cache.get(cache_key)
    if rows is None:
        rows = await c.graph.store.rows('content_comment',{'object_id':obj['id']})
        await c.cache.put(cache_key,rows)
    # Retain existing post comments written through the original endpoint.
    if obj['object_type'] == 'social.post':
        legacy, _ = await c.social_service.get_comments(ref,cursor=None,limit=100)
        removed = await deleted_comment_ids(c, obj['id'])
        rows = rows + [dict(id=x.id,author_id=x.author_id,text=x.text,sticker_id=x.sticker_id,created_at=x.created_at.isoformat()) for x in legacy if x.id not in removed]
    result = []
    for row in sorted(rows,key=lambda r:r['created_at'],reverse=True)[:200]:
        if await c.graph.blocked(user.id,row['author_id']): continue
        person = await c.identity_repository.get_by_id(row['author_id'])
        if person:
            reactions = await c.graph.store.rows('comment_reaction', {'comment_id': row['id']})
            reactions = [r for r in reactions if not await c.graph.blocked(user.id, r['user_id'])]
            result.append(dict(row,author=c.graph.profile(person),likes_count=len(reactions),liked_by_me=any(r['user_id']==user.id for r in reactions)))
    return dict(items=result,count=len(result))

@router.post('/content/{ref}/comments',status_code=201)
async def create(ref: str, text: str = Form('',max_length=2000), sticker_id: str | None = Form(None),
                 image: UploadFile | None = File(None), parent_id: str | None = Form(None), platform: str = 'social', user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c,user.id,platform,ref)
    await c.cache.rate_limit(user.id,'comment',30)
    text = text.strip()
    if not text and not sticker_id and not image: raise HTTPException(422,'Write a comment or choose an image, GIF or sticker.')
    if sticker_id and sticker_id not in STICKER_IDS and not re.fullmatch(r'giphy:(gif|sticker):[A-Za-z0-9]{1,80}', sticker_id): raise HTTPException(422,'Unknown sticker.')
    if parent_id:
        existing = await comments(ref, platform, user, c)
        if not any(r['id'] == parent_id for r in existing['items']):
            raise HTTPException(404, 'Reply target is no longer available.')
    mentioned = []
    for handle in set(re.findall(r'@([A-Za-z0-9_]{1,50})',text)):
        person = await c.identity_repository.get_by_username(handle.lower())
        if person and not await c.graph.blocked(user.id,person.id): mentioned.append(c.graph.profile(person))
    cid = 'content_comment:' + uuid.uuid4().hex
    row = dict(parent_id=parent_id,object_id=obj['id'],author_id=user.id,text=text,sticker_id=sticker_id,mentions=mentioned,created_at=now(),image_url=None)
    target = None
    try:
        if image:
            raw = await image.read(10*1024*1024+1)
            if len(raw)>10*1024*1024: raise HTTPException(413,'Images and GIFs must be under 10 MB.')
            try:
                with Image.open(io.BytesIO(raw)) as picture:
                    fmt=picture.format
                    if fmt not in {'JPEG','PNG','WEBP','GIF'} or picture.width*picture.height>20_000_000: raise ValueError()
                    picture.verify()
            except (UnidentifiedImageError,OSError,ValueError,Image.DecompressionBombError):
                raise HTTPException(422,'Choose a valid JPEG, PNG, WebP or GIF image.')
            folder=media_root_path(c.settings)/'social_comments';folder.mkdir(exist_ok=True,parents=True)
            target=folder/(uuid.uuid4().hex+'.'+{'JPEG':'jpg','PNG':'png','WEBP':'webp','GIF':'gif'}[fmt])
            target.write_bytes(raw)
            row['image_url']='/media/social_comments/'+target.name
        saved=await c.graph.store.put(cid,row)
        return dict(saved,author=c.graph.profile(user))
    except Exception:
        if target: target.unlink(missing_ok=True)
        raise

async def deleted_comment_ids(c, object_id):
    """Legacy post comments can't be removed from the social repository, so
    deletions are recorded as tombstones and filtered on read."""
    return {row['comment_id'] for row in await c.graph.store.rows('comment_tombstone', {'object_id': object_id})}

@router.delete('/content/{ref}/comments/{comment_id}', status_code=204)
async def delete_comment(ref: str, comment_id: str, platform: str = 'social', user=Depends(get_current_user), c=Depends(get_container)):
    """Delete a comment (its author or the content owner) and its replies."""
    obj = await resolve(c,user.id,platform,ref)
    visible = await comments(ref, platform, user, c)
    target = next((row for row in visible['items'] if row['id'] == comment_id), None)
    if not target:
        raise HTTPException(404, 'Comment is no longer available.')
    if target['author_id'] != user.id and obj.get('owner') != user.id:
        raise HTTPException(403, 'You can only delete your own comments.')
    for child in await c.graph.store.rows('content_comment', {'parent_id': comment_id}):
        await c.graph.store.delete(child['id'])
    for reaction in await c.graph.store.rows('comment_reaction', {'comment_id': comment_id}):
        await c.graph.store.delete(reaction['id'])
    if await c.graph.store.get(comment_id):
        await c.graph.store.delete(comment_id)
    else:
        from app.domains.graph.service import key
        await c.graph.store.put(key('comment_tombstone', comment_id), dict(comment_id=comment_id, object_id=obj['id'], deleted_by=user.id, created_at=now()))

@router.put('/content/{ref}/comments/{comment_id}/like')
async def like_comment(ref: str, comment_id: str, liked: bool = True, platform: str = 'social', user=Depends(get_current_user), c=Depends(get_container)):
    from app.domains.graph.service import key
    await c.cache.rate_limit(user.id, 'comment_like', 120)
    visible = await comments(ref, platform, user, c)
    if not any(row['id'] == comment_id for row in visible['items']):
        raise HTTPException(404, 'Comment is no longer available.')
    rid = key('comment_reaction', user.id, comment_id)
    if liked:
        await c.graph.store.put(rid, dict(user_id=user.id, comment_id=comment_id))
    else:
        await c.graph.store.delete(rid)
    return {'liked_by_me': liked}

@router.post('/content/{ref}/comments/{comment_id}/report', status_code=204)
async def report_comment(ref: str, comment_id: str, platform: str = 'social', user=Depends(get_current_user), c=Depends(get_container)):
    from app.domains.graph.service import key
    await c.cache.rate_limit(user.id, 'comment_report', 30)
    visible = await comments(ref, platform, user, c)
    if not any(row['id'] == comment_id for row in visible['items']):
        raise HTTPException(404, 'Comment is no longer available.')
    await c.graph.store.put(key('content_report', user.id, comment_id), dict(reporter_id=user.id, comment_id=comment_id, platform=platform, ref=ref, status='pending', created_at=now()))

@router.post('/content/{ref}/comments/{comment_id}/translate')
async def translate_comment(ref: str, comment_id: str, platform: str = 'social', user=Depends(get_current_user), c=Depends(get_container)):
    import hashlib
    import httpx
    # Re-check access before every cache read, including after deletion/blocking.
    visible = await comments(ref, platform, user, c)
    row = next((r for r in visible['items'] if r['id'] == comment_id), None)
    if row is None: raise HTTPException(404, 'Comment is no longer available.')
    text = (row.get('text') or '').strip()
    if not text: raise HTTPException(422, 'This comment has no text to translate.')
    await c.cache.rate_limit(user.id, 'comment_translate', 20)
    digest = hashlib.sha256(text.encode()).hexdigest()
    cache_key = 'translation:madlad400-c32ad0cf:en:' + digest
    cached = await c.cache.get(cache_key)
    if cached is not None: return cached
    try:
        async with httpx.AsyncClient(timeout=120) as client:
            response = await client.post('http://127.0.0.1:8010/translate', json={'text':text})
        if response.status_code != 200:
            raise HTTPException(503, 'Translation is temporarily busy. Try again shortly.')
        result = response.json()
        if not isinstance(result.get('text'), str) or not result['text'].strip():
            raise HTTPException(503, 'Translation unavailable. Please retry.')
    except httpx.HTTPError:
        raise HTTPException(503, 'Translation service is starting or unavailable. Please retry.') from None
    await c.cache.put(cache_key, result, ttl=86400)
    return result
