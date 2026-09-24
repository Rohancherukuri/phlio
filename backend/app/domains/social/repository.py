"""Repository contract for the social domain."""

from __future__ import annotations

from typing import Protocol

from app.domains.social.entities import Comment, Post


class SocialRepository(Protocol):
    async def create_post(self, post: Post) -> Post: ...

    async def get_post(self, post_id: str) -> Post | None: ...

    async def list_feed(self, *, cursor: str | None, limit: int) -> tuple[list[Post], str | None]:
        """Returns (posts, next_cursor). `next_cursor` is None when the feed
        is exhausted."""
        ...

    async def list_posts_by_author(
        self, author_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[Post], str | None]: ...

    async def is_liked_by(self, post_id: str, user_id: str) -> bool: ...

    async def set_liked(self, post_id: str, user_id: str, liked: bool) -> Post: ...

    async def add_comment(self, comment: Comment) -> Comment: ...

    async def list_comments(
        self, post_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[Comment], str | None]: ...
