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
async def comments(ref: str, user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c,user.id,'social',ref)
    cache_key = f'comments:{await c.graph.store.revision()}:{obj["id"]}'
    rows = await c.cache.get(cache_key)
    if rows is None:
        rows = await c.graph.store.rows('content_comment',{'object_id':obj['id']})
        await c.cache.put(cache_key,rows)
    # Retain existing post comments written through the original endpoint.
    if obj['object_type'] == 'social.post':
        legacy, _ = await c.social_service.get_comments(ref,cursor=None,limit=100)
        rows = rows + [dict(id=x.id,author_id=x.author_id,text=x.text,sticker_id=x.sticker_id,created_at=x.created_at.isoformat()) for x in legacy]
    result = []
    for row in sorted(rows,key=lambda r:r['created_at'],reverse=True)[:200]:
        if await c.graph.blocked(user.id,row['author_id']): continue
        person = await c.identity_repository.get_by_id(row['author_id'])
        if person: result.append(dict(row,author=c.graph.profile(person)))
    return dict(items=result,count=len(result))

@router.post('/content/{ref}/comments',status_code=201)
async def create(ref: str, text: str = Form('',max_length=2000), sticker_id: str | None = Form(None),
                 image: UploadFile | None = File(None), user=Depends(get_current_user), c=Depends(get_container)):
    obj = await resolve(c,user.id,'social',ref)
    await c.cache.rate_limit(user.id,'comment',30)
    text = text.strip()
    if not text and not sticker_id and not image: raise HTTPException(422,'Write a comment or choose an image, GIF or sticker.')
    if sticker_id and sticker_id not in STICKER_IDS: raise HTTPException(422,'Unknown sticker.')
    mentioned = []
    for handle in set(re.findall(r'@([A-Za-z0-9_]{1,50})',text)):
        person = await c.identity_repository.get_by_username(handle.lower())
        if person and not await c.graph.blocked(user.id,person.id): mentioned.append(c.graph.profile(person))
    cid = 'content_comment:' + uuid.uuid4().hex
    row = dict(object_id=obj['id'],author_id=user.id,text=text,sticker_id=sticker_id,mentions=mentioned,created_at=now(),image_url=None)
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
