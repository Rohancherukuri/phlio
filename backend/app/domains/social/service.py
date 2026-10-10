"""Social domain service: feed assembly, posting, likes, and comments."""

from __future__ import annotations

import logging

from app.common.exceptions import NotFoundError, ValidationAppError
from app.domains.social.entities import Comment, MediaAttachment, Post
from app.domains.social.repository import SocialRepository
from app.domains.stickers import STICKER_IDS
from app.infrastructure.core_engine.client import CoreEngineClient

logger = logging.getLogger("phlio.social")

MAX_POST_LENGTH = 2_000


class SocialService:
    def __init__(self, repository: SocialRepository, core_engine: CoreEngineClient, graph=None) -> None:
        self.graph = graph
        self._repository = repository
        self._core_engine = core_engine

    async def create_post(
        self, *, author_id: str, text: str, media: list[MediaAttachment], tags: list[str]
    ) -> Post:
        text = text.strip()
        if not text and not media:
            raise ValidationAppError("A post needs text or media.")
        if len(text) > MAX_POST_LENGTH:
            raise ValidationAppError(f"Posts are limited to {MAX_POST_LENGTH} characters.")

        post = Post(
            id=await self._core_engine.generate_id("pst"),
            author_id=author_id,
            text=text,
            media=media,
            tags=[tag.lower().lstrip("#") for tag in tags],
        )
        created = await self._repository.create_post(post)
        logger.info("social.post_created post_id=%s author_id=%s", created.id, author_id)
        if self.graph:
            obj = await self.graph.register_object(
                author_id, "social.post", created.id, text[:160] or "Media post"
            )
            await self.graph.action(author_id, obj["id"], "created", trusted=True)
        return created

    async def get_feed(self, *, cursor: str | None, limit: int) -> tuple[list[Post], str | None]:
        return await self._repository.list_feed(cursor=cursor, limit=limit)

    async def get_profile_posts(
        self, author_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[Post], str | None]:
        return await self._repository.list_posts_by_author(author_id, cursor=cursor, limit=limit)

    async def get_post_or_raise(self, post_id: str) -> Post:
        post = await self._repository.get_post(post_id)
        if post is None:
            raise NotFoundError("Post not found.")
        return post

    async def is_liked_by(self, post_id: str, user_id: str) -> bool:
        return await self._repository.is_liked_by(post_id, user_id)

    async def visible_to(self, post, viewer):
        if not self.graph:
            return True
        from app.domains.graph.service import key

        if await self.graph.blocked(viewer, post.author_id):
            return False
        obj = await self.graph.store.get(key("phlio_object", "social", post.id))
        return not obj or obj["state"] == "active"

    async def require_visible(self, post_id, viewer):
        post = await self.get_post_or_raise(post_id)
        if not await self.visible_to(post, viewer):
            raise NotFoundError("Post unavailable.")
        return post

    async def toggle_like(self, post_id: str, user_id: str) -> Post:
        await self.require_visible(post_id, user_id)
        currently_liked = await self._repository.is_liked_by(post_id, user_id)
        post = await self._repository.set_liked(post_id, user_id, not currently_liked)
        logger.debug(
            "social.like_toggled post_id=%s user_id=%s liked=%s", post_id, user_id, not currently_liked
        )
        if self.graph:
            from app.domains.graph.service import key

            obj = await self.graph.register_object(
                post.author_id, "social.post", post.id, post.text[:160] or "Media post"
            )
            if not currently_liked:
                await self.graph.action(user_id, obj["id"], "liked")
            else:
                await self.graph.store.delete(key("activity", user_id, obj["id"], "liked"))
        return post

    async def add_comment(
        self, *, post_id: str, author_id: str, text: str, sticker_id: str | None = None
    ) -> Comment:
        await self.require_visible(post_id, author_id)
        text = text.strip()
        if not text and not sticker_id:
            raise ValidationAppError("Comment cannot be empty.")
        if sticker_id and sticker_id not in STICKER_IDS:
            raise ValidationAppError("Unknown sticker.")
        comment = Comment(
            id=await self._core_engine.generate_id("cmt"),
            post_id=post_id,
            author_id=author_id,
            text=text,
            sticker_id=sticker_id,
        )
        result = await self._repository.add_comment(comment)
        if self.graph:
            post = await self.get_post_or_raise(post_id)
            obj = await self.graph.register_object(
                post.author_id, "social.post", post.id, post.text[:160] or "Media post"
            )
            await self.graph.action(author_id, obj["id"], "commented")
        return result

    async def get_comments(
        self, post_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[Comment], str | None]:
        await self.get_post_or_raise(post_id)
        return await self._repository.list_comments(post_id, cursor=cursor, limit=limit)
