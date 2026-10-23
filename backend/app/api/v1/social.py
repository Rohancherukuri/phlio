"""Phlio Social endpoints: feed, posting, likes, comments."""

from __future__ import annotations

import datetime as dt

from fastapi import Form, File, UploadFile, APIRouter, Depends, Query, status, HTTPException
from pydantic import BaseModel, Field

from app.api.deps import get_current_user, get_social_service, get_container
from app.common.pagination import clamp_limit
from app.common.schemas import Page, PageMeta
from app.domains.identity.entities import User
from app.domains.social.entities import Comment, MediaAttachment, MediaKind, Post
from app.domains.social.service import SocialService

router = APIRouter(prefix="/social", tags=["social"])


class MediaAttachmentSchema(BaseModel):
    url: str
    kind: MediaKind
    thumbnail_url: str | None = None


class PollChoice(BaseModel):
    text: str = Field(min_length=1, max_length=80)
    image_url: str | None = Field(default=None, max_length=500)

class PollInput(BaseModel):
    choices: list[PollChoice] = Field(min_length=2, max_length=4)
    minutes: int = Field(default=1440, ge=5, le=10080)

class CreatePostRequest(BaseModel):
    poll: PollInput | None = None
    music_id: str | None = Field(default=None, pattern=r"^(?:[A-Za-z0-9]{22}|local_[a-f0-9]{32})$")
    text: str = Field(default="", max_length=2000)
    media: list[MediaAttachmentSchema] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list, max_length=10)


class AuthorSummary(BaseModel):
    """Reserved for a future author-embedding change to `PostResponse`
    (currently clients resolve `author_id` via `GET /users/{username}` or
    their own local profile cache)."""

    id: str
    username: str


class PostResponse(BaseModel):
    id: str
    author_id: str
    text: str
    media: list[MediaAttachmentSchema]
    tags: list[str]
    like_count: int
    comment_count: int
    created_at: dt.datetime
    liked_by_me: bool

    @classmethod
    def from_entity(cls, post: Post, *, liked_by_me: bool) -> PostResponse:
        return cls(
            id=post.id,
            author_id=post.author_id,
            text=post.text,
            media=[MediaAttachmentSchema(url=m.url, kind=m.kind, thumbnail_url=m.thumbnail_url) for m in post.media],
            tags=post.tags,
            like_count=post.like_count,
            comment_count=post.comment_count,
            created_at=post.created_at,
            liked_by_me=liked_by_me,
        )


class CreateCommentRequest(BaseModel):
    text: str = Field(default="", max_length=1000)
    sticker_id: str | None = Field(default=None, max_length=40)


class CommentResponse(BaseModel):
    id: str
    post_id: str
    author_id: str
    text: str
    sticker_id: str | None = None
    created_at: dt.datetime

    @classmethod
    def from_entity(cls, comment: Comment) -> CommentResponse:
        return cls(
            id=comment.id,
            post_id=comment.post_id,
            author_id=comment.author_id,
            text=comment.text,
            sticker_id=comment.sticker_id,
            created_at=comment.created_at,
        )


@router.get("/feed", response_model=Page[PostResponse])
async def get_feed(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    social_service: SocialService = Depends(get_social_service),
    current_user: User = Depends(get_current_user),
    c=Depends(get_container),
) -> Page[PostResponse]:
    revision = await c.graph.store.revision()
    cache_key = f"feed:{revision}:{current_user.id}:{cursor}:{limit}"
    cached = await c.cache.get(cache_key)
    if cached is not None:
        return Page[PostResponse].model_validate(cached)
    posts, next_cursor = await social_service.get_feed(cursor=cursor, limit=clamp_limit(limit))
    posts, liked_ids = await social_service.feed_metadata(posts, current_user.id)
    items = [
        PostResponse.from_entity(p, liked_by_me=p.id in liked_ids)
        for p in posts
    ]
    page = Page(items=items, meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None))
    await c.cache.put(cache_key, page.model_dump(mode="json"))
    return page


@router.post("/posts", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_post(
    body: CreatePostRequest,
    social_service: SocialService = Depends(get_social_service),
    current_user: User = Depends(get_current_user),
    c=Depends(get_container),
) -> PostResponse:
    from app.api.v1.music import prepare_selection, attach_selection
    if body.poll:
        labels = [choice.text.strip() for choice in body.poll.choices]
        if not body.text.strip() or any(not label for label in labels) or len(set(label.casefold() for label in labels)) != len(labels):
            raise HTTPException(422, 'Add a question and at least two different choices.')
        for choice in body.poll.choices:
            if choice.image_url and not choice.image_url.startswith('/media/post_uploads/'):
                raise HTTPException(422, 'Use an uploaded image for poll choices.')
    music = await prepare_selection(c,current_user.id,"post",body.music_id)
    media = [MediaAttachment(url=m.url, kind=m.kind, thumbnail_url=m.thumbnail_url) for m in body.media]
    post = await social_service.create_post(
        author_id=current_user.id, text=body.text, media=media, tags=body.tags
    )
    if body.poll:
        await c.graph.store.put('social_poll:' + post.id.split(':')[-1], dict(
            post_id=post.id, choices=[dict(text=choice.text.strip(), image_url=choice.image_url) for choice in body.poll.choices],
            expires_at=(dt.datetime.now(dt.UTC)+dt.timedelta(minutes=body.poll.minutes)).isoformat()))
    attach_selection(c,current_user.id,"post",post.id,music)
    return PostResponse.from_entity(post, liked_by_me=False)


@router.get("/posts/{post_id}", response_model=PostResponse)
async def get_post(
    post_id: str,
    social_service: SocialService = Depends(get_social_service),
    current_user: User = Depends(get_current_user),
) -> PostResponse:
    post = await social_service.require_visible(post_id, current_user.id)
    liked = await social_service.is_liked_by(post_id, current_user.id)
    return PostResponse.from_entity(post, liked_by_me=liked)


@router.post("/posts/{post_id}/like", response_model=PostResponse)
async def toggle_like(
    post_id: str,
    social_service: SocialService = Depends(get_social_service),
    current_user: User = Depends(get_current_user),
) -> PostResponse:
    post = await social_service.toggle_like(post_id, current_user.id)
    liked = await social_service.is_liked_by(post_id, current_user.id)
    return PostResponse.from_entity(post, liked_by_me=liked)


@router.post("/posts/{post_id}/comments", response_model=CommentResponse, status_code=status.HTTP_201_CREATED)
async def add_comment(
    post_id: str,
    body: CreateCommentRequest,
    social_service: SocialService = Depends(get_social_service),
    current_user: User = Depends(get_current_user),
) -> CommentResponse:
    comment = await social_service.add_comment(
        post_id=post_id, author_id=current_user.id, text=body.text, sticker_id=body.sticker_id
    )
    return CommentResponse.from_entity(comment)


@router.get("/posts/{post_id}/comments", response_model=Page[CommentResponse])
async def list_comments(
    post_id: str,
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    social_service: SocialService = Depends(get_social_service),
    current_user: User = Depends(get_current_user),
) -> Page[CommentResponse]:
    await social_service.require_visible(post_id, current_user.id)
    comments, next_cursor = await social_service.get_comments(
        post_id, cursor=cursor, limit=clamp_limit(limit)
    )
    items = [CommentResponse.from_entity(c) for c in comments]
    return Page(items=items, meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None))


class EditContentRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)

async def owned_social_content(content_id, user, c):
    from app.domains.graph.service import key
    obj = await c.graph.store.get(key('phlio_object', 'social', content_id))
    if not obj or obj['state'] != 'active': raise HTTPException(404, 'Content unavailable.')
    if obj['owner'] != user.id: raise HTTPException(403, 'Only the creator can change this content.')
    if obj['object_type'] not in ('social.post','social.video','social.clip'):
        raise HTTPException(422, 'This content cannot be edited here.')
    return obj

@router.patch('/manage/{content_id}')
async def edit_content(content_id: str, body: EditContentRequest, user=Depends(get_current_user), c=Depends(get_container)):
    obj = await owned_social_content(content_id,user,c)
    text = body.text.strip()
    if not text: raise HTTPException(422, 'Enter text.')
    if obj['object_type'] == 'social.post':
        await c.social_repository.update_text(content_id,text)
    else:
        if len(text)>160: raise HTTPException(422,'Titles are limited to 160 characters.')
        c.social_video_service.db.execute('UPDATE videos SET title=? WHERE id=? AND creator=?',(text,content_id,user.id))
        c.social_video_service.db.commit()
    obj['title'] = text[:160]
    await c.graph.store.put(obj['id'],obj)
    return {'id':content_id,'text':text}

@router.delete('/manage/{content_id}', status_code=204)
async def delete_content(content_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    obj = await owned_social_content(content_id,user,c)
    obj['state'] = 'deleted'
    await c.graph.store.put(obj['id'],obj)


@router.post('/composer/upload')
async def composer_upload(file: UploadFile = File(...), user=Depends(get_current_user), c=Depends(get_container)):
    import io, uuid, json, asyncio
    from pathlib import Path
    from PIL import Image, UnidentifiedImageError
    from app.core.container import media_root_path
    from app.api.v1.music import MusicStore
    raw = await file.read(20 * 1024 * 1024 + 1)
    if len(raw) > 20 * 1024 * 1024: raise HTTPException(413, 'Choose a file under 20 MB.')
    extension = Path(file.filename or '').suffix.lower()
    audio = extension in {'.mp3', '.m4a', '.wav', '.ogg', '.aac', '.flac'}
    if not audio:
        try:
            with Image.open(io.BytesIO(raw)) as picture:
                fmt = picture.format
                if picture.width * picture.height > 20_000_000 or fmt not in {'JPEG','PNG','WEBP','GIF'}: raise ValueError()
                picture.verify()
            extension = {'JPEG':'.jpg','PNG':'.png','WEBP':'.webp','GIF':'.gif'}[fmt]
        except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
            raise HTTPException(422, 'Choose an image, GIF or audio file.')
    folder = media_root_path(c.settings) / 'post_uploads'
    folder.mkdir(parents=True, exist_ok=True)
    identifier = uuid.uuid4().hex
    target = folder / (identifier + extension)
    target.write_bytes(raw)
    url = '/media/post_uploads/' + target.name
    if audio:
        try:
            process = await asyncio.create_subprocess_exec('ffprobe','-v','error','-select_streams','a:0','-show_entries','stream=codec_type','-of','csv=p=0',str(target),stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.DEVNULL)
            output, _ = await asyncio.wait_for(process.communicate(), timeout=10)
            if process.returncode != 0 or b'audio' not in output: raise ValueError()
        except Exception:
            if 'process' in locals() and process.returncode is None:
                process.kill()
                await process.wait()
            target.unlink(missing_ok=True)
            raise HTTPException(422, 'Could not read this audio file.')
        item = dict(id='local_'+identifier, title=Path(file.filename or 'Original audio').stem[:120], artist=user.username, url=url, source='local')
        with MusicStore(c.settings).db() as db:
            db.execute('INSERT OR REPLACE INTO music_selection VALUES (?,?,?,?)',(user.id,'post','draft',json.dumps(item)))
            db.execute('INSERT OR REPLACE INTO music_selection VALUES (?,?,?,?)',(user.id,'post',item['id'],json.dumps(item)))
        return item
    return dict(url=url,kind='image')


async def poll_result(post_id, user_id, c):
    poll = await c.graph.store.get('social_poll:' + post_id.split(':')[-1])
    if not poll: return None
    votes = await c.graph.store.rows('social_poll_vote', {'post_id': post_id})
    counts = [sum(v['choice'] == i for v in votes) for i in range(len(poll['choices']))]
    selected = next((v['choice'] for v in votes if v['user_id'] == user_id), None)
    return dict(poll, counts=counts, total=len(votes), selected=selected,
                closed=dt.datetime.fromisoformat(poll['expires_at']) <= dt.datetime.now(dt.UTC))

@router.get('/posts/{post_id}/poll')
async def get_poll(post_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    await c.social_service.require_visible(post_id,user.id)
    return await poll_result(post_id,user.id,c)

class PollVote(BaseModel):
    choice: int = Field(ge=0, le=3)

@router.put('/posts/{post_id}/poll/vote')
async def vote_poll(post_id: str, body: PollVote, user=Depends(get_current_user), c=Depends(get_container)):
    import hashlib
    await c.social_service.require_visible(post_id,user.id)
    poll = await poll_result(post_id,user.id,c)
    if not poll: raise HTTPException(404, 'Poll not found.')
    if poll['closed']: raise HTTPException(409, 'This poll has ended.')
    if body.choice >= len(poll['choices']): raise HTTPException(422, 'Unknown choice.')
    key = hashlib.sha256((post_id+'|'+user.id).encode()).hexdigest()
    await c.graph.store.put('social_poll_vote:'+key,dict(post_id=post_id,user_id=user.id,choice=body.choice))
    return await poll_result(post_id,user.id,c)


@router.post('/memories', status_code=201)
async def create_memory(file: UploadFile = File(...), caption: str = Form(default='', max_length=500),
                        audience: str = Form(default='friends'), recipients: str = Form(default='[]'),
                        kind: str = Form(default='snap'),
                        user=Depends(get_current_user), c=Depends(get_container)):
    import uuid
    from app.domains.graph.store import now
    import json
    from pydantic import ValidationError
    from app.api.v1.snap_audience import SnapAudience, validate_audience
    from app.core.container import media_root_path
    if kind not in {'snap', 'moment', 'experience'}:
        raise HTTPException(422, 'Unknown content type.')
    try:
        choice = SnapAudience(audience=audience, recipients=json.loads(recipients))
    except (ValueError, TypeError, ValidationError):
        raise HTTPException(422, 'Invalid audience.')
    policy = await validate_audience(c, user.id, choice)
    await c.cache.rate_limit(user.id, 'create_memory', 20)
    if not (file.content_type or '').startswith('image/'):
        raise HTTPException(422, 'Choose a photo for your memory.')
    uploaded = await composer_upload(file, user, c)
    if uploaded.get('kind') != 'image':
        raise HTTPException(422, 'Choose a photo for your memory.')
    memory_id = 'social_memory:' + uuid.uuid4().hex
    root = media_root_path(c.settings).resolve()
    source = root / uploaded['url'].removeprefix('/media/')
    private = root.parent / (root.name + '_private_memories')
    private.mkdir(parents=True, exist_ok=True)
    source.replace(private / source.name)
    return await c.graph.store.put(memory_id, dict(
        author=user.id, image_url='/social/memories/' + memory_id + '/photo',
        private_file=source.name, caption=caption.strip(), kind=kind, **policy, created_at=now()))



@router.get('/memories')
async def memories(user=Depends(get_current_user), c=Depends(get_container)):
    import datetime as dt
    from app.api.v1.snap_audience import can_view
    cutoff = dt.datetime.now(dt.UTC) - dt.timedelta(hours=24)
    result = []
    for row in sorted(await c.graph.store.rows('social_memory'), key=lambda r: r['created_at'], reverse=True):
        if not await can_view(c, user.id, row):
            continue
        if row['author'] != user.id and dt.datetime.fromisoformat(row['created_at']) < cutoff:
            continue
        from app.domains.graph.service import key
        seen = await c.graph.store.get(key('memory_seen', user.id, row['id']))
        reactions = await c.graph.store.rows('memory_reaction', {'memory_id': row['id']})
        safe = {k: v for k, v in row.items() if k not in {'private_file', 'recipients'}}
        result.append(dict(safe, author=c.graph.profile(await c.graph.user(row['author'])),
            unread=row['author'] != user.id and not seen, reactions=reactions))
    return result


@router.delete('/memories/{memory_id}', status_code=204)
async def delete_memory(memory_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    if not memory_id.startswith('social_memory:'):
        raise HTTPException(404, 'Memory unavailable.')
    row = await c.graph.store.get(memory_id)
    if not row or row['author'] != user.id:
        raise HTTPException(404, 'Memory unavailable.')
    await c.graph.store.delete(memory_id)


@router.put('/memories/{memory_id}/seen', status_code=204)
async def memory_seen(memory_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    from app.domains.graph.service import key
    from app.domains.graph.store import now
    if not any(row['id'] == memory_id for row in await memories(user, c)):
        raise HTTPException(404, 'Memory unavailable.')
    await c.graph.store.put(key('memory_seen', user.id, memory_id), dict(user_id=user.id, memory_id=memory_id, seen_at=now()))


class MemoryReaction(BaseModel):
    emoji: str = Field(min_length=1, max_length=12)


@router.put('/memories/{memory_id}/reaction', status_code=204)
async def memory_react(memory_id: str, body: MemoryReaction, user=Depends(get_current_user), c=Depends(get_container)):
    from app.domains.graph.service import key
    if not any(row['id'] == memory_id for row in await memories(user, c)):
        raise HTTPException(404, 'Memory unavailable.')
    await c.graph.store.put(key('memory_reaction', user.id, memory_id), dict(user_id=user.id, memory_id=memory_id, emoji=body.emoji))


@router.get('/memories/{memory_id}/photo')
async def memory_photo(memory_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    from fastapi.responses import FileResponse
    from app.core.container import media_root_path
    if not memory_id.startswith('social_memory:') or not any(row['id'] == memory_id for row in await memories(user, c)):
        raise HTTPException(404, 'Memory unavailable.')
    row = await c.graph.store.get(memory_id)
    root = media_root_path(c.settings).resolve()
    folder = root.parent / (root.name + '_private_memories')
    filename = row.get('private_file', '')
    from pathlib import Path
    if not filename or Path(filename).name != filename or not (folder / filename).is_file():
        raise HTTPException(404, 'Photo unavailable.')
    return FileResponse(folder / filename, headers={'Cache-Control': 'private, no-store'})
