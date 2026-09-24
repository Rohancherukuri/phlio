"""In-memory implementation of `SocialRepository`."""

from __future__ import annotations

import asyncio

from app.domains.social.entities import Comment, Post


def _paginate(items: list, *, cursor: str | None, limit: int, key: str = "id"):
    """Shared cursor-pagination helper for newest-first lists.

    `items` must already be sorted newest-first. The cursor is the id of the
    last item the caller has already seen; we return the slice strictly
    after it.
    """
    start = 0
    if cursor is not None:
        for i, item in enumerate(items):
            if getattr(item, key) == cursor:
                start = i + 1
                break
        else:
            start = len(items)  # unknown cursor -> treat as exhausted
    page = items[start : start + limit]
    next_cursor = getattr(page[-1], key) if len(page) == limit and start + limit < len(items) else None
    return page, next_cursor


class InMemorySocialRepository:
    def __init__(self) -> None:
        self._posts: dict[str, Post] = {}
        self._posts_newest_first: list[Post] = []  # maintained in insertion order (reversed)
        self._comments_by_post: dict[str, list[Comment]] = {}
        self._likes: set[tuple[str, str]] = set()  # (post_id, user_id)
        self._lock = asyncio.Lock()

    async def create_post(self, post: Post) -> Post:
        async with self._lock:
            self._posts[post.id] = post
            self._posts_newest_first.append(post)
            # Sorted by `created_at` (not just insertion order) so seeded,
            # backdated demo posts and organically-created posts interleave
            # correctly — the same guarantee the SurrealDB repository gets
            # for free from `ORDER BY created_at DESC`.
            self._posts_newest_first.sort(key=lambda p: p.created_at, reverse=True)
            return post

    async def get_post(self, post_id: str) -> Post | None:
        return self._posts.get(post_id)

    async def list_feed(self, *, cursor: str | None, limit: int) -> tuple[list[Post], str | None]:
        return _paginate(self._posts_newest_first, cursor=cursor, limit=limit)

    async def list_posts_by_author(
        self, author_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[Post], str | None]:
        mine = [p for p in self._posts_newest_first if p.author_id == author_id]
        return _paginate(mine, cursor=cursor, limit=limit)

    async def is_liked_by(self, post_id: str, user_id: str) -> bool:
        return (post_id, user_id) in self._likes

    async def set_liked(self, post_id: str, user_id: str, liked: bool) -> Post:
        async with self._lock:
            post = self._posts[post_id]
            key = (post_id, user_id)
            if liked and key not in self._likes:
                self._likes.add(key)
                post.like_count += 1
            elif not liked and key in self._likes:
                self._likes.discard(key)
                post.like_count = max(0, post.like_count - 1)
            return post

    async def add_comment(self, comment: Comment) -> Comment:
        async with self._lock:
            comments = self._comments_by_post.setdefault(comment.post_id, [])
            comments.append(comment)
            comments.sort(key=lambda c: c.created_at, reverse=True)
            post = self._posts.get(comment.post_id)
            if post is not None:
                post.comment_count += 1
            return comment

    async def list_comments(
        self, post_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[Comment], str | None]:
        comments = self._comments_by_post.get(post_id, [])
        return _paginate(comments, cursor=cursor, limit=limit)
