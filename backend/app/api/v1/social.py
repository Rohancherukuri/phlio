"""Phlio Social endpoints: feed, posting, likes, comments."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Query, status
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


class CreatePostRequest(BaseModel):
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
            media=[MediaAttachmentSchema(url=m.url, kind=m.kind) for m in post.media],
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
    posts = [p for p in posts if await social_service.visible_to(p, current_user.id)]
    items = [
        PostResponse.from_entity(p, liked_by_me=await social_service.is_liked_by(p.id, current_user.id))
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
) -> PostResponse:
    media = [MediaAttachment(url=m.url, kind=m.kind) for m in body.media]
    post = await social_service.create_post(
        author_id=current_user.id, text=body.text, media=media, tags=body.tags
    )
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
