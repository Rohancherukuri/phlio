"""SurrealDB implementation of `SocialRepository`.

Table shape (see `data/surrealdb/schema/social.surql`):

    DEFINE TABLE post SCHEMAFULL;
    DEFINE FIELD author_id     ON post TYPE record<user>;
    DEFINE FIELD text          ON post TYPE string;
    DEFINE FIELD media         ON post TYPE array<object>;
    DEFINE FIELD tags          ON post TYPE array<string>;
    DEFINE FIELD like_count    ON post TYPE int DEFAULT 0;
    DEFINE FIELD comment_count ON post TYPE int DEFAULT 0;
    DEFINE FIELD created_at    ON post TYPE datetime DEFAULT time::now();

    DEFINE TABLE comment SCHEMAFULL;
    DEFINE FIELD post_id    ON comment TYPE record<post>;
    DEFINE FIELD author_id  ON comment TYPE record<user>;
    DEFINE FIELD text       ON comment TYPE string;
    DEFINE FIELD created_at ON comment TYPE datetime DEFAULT time::now();

    -- Likes are modelled as a graph edge rather than a join table, which is
    -- where SurrealDB's graph features genuinely pay off (section 11):
    --     RELATE user:usr_x->liked->post:pst_y;
    DEFINE TABLE liked TYPE RELATION FROM user TO post;
"""

from __future__ import annotations

from surrealdb import Surreal

from app.domains.social.entities import Comment, MediaAttachment, Post

_POSTS = "post"
_COMMENTS = "comment"


def _strip_prefix(record_id: str) -> str:
    return record_id.split(":", 1)[1] if ":" in record_id else record_id


def _row_to_post(row: dict) -> Post:
    return Post(
        id=_strip_prefix(row["id"]),
        author_id=_strip_prefix(row["author_id"]),
        text=row["text"],
        media=[MediaAttachment(**m) for m in row.get("media", [])],
        tags=row.get("tags", []),
        like_count=row.get("like_count", 0),
        comment_count=row.get("comment_count", 0),
        created_at=row["created_at"],
    )


def _row_to_comment(row: dict) -> Comment:
    return Comment(
        id=_strip_prefix(row["id"]),
        post_id=_strip_prefix(row["post_id"]),
        author_id=_strip_prefix(row["author_id"]),
        text=row["text"],
        created_at=row["created_at"],
    )


class SurrealSocialRepository:
    """See module docstring for the SurrealQL schema this assumes.

    Cursor pagination here uses `created_at < $cursor_ts` rather than an id
    comparison, since SurrealDB record ids aren't inherently orderable —
    the repository's `cursor` string encodes the ISO timestamp of the last
    item seen.
    """

    def __init__(self, db: Surreal) -> None:
        self._db = db

    async def create_post(self, post: Post) -> Post:
        record_id = f"{_POSTS}:{post.id}"
        row = await self._db.create(
            record_id,
            {
                "author_id": f"user:{post.author_id}",
                "text": post.text,
                "media": [m.__dict__ for m in post.media],
                "tags": post.tags,
                "like_count": 0,
                "comment_count": 0,
                "created_at": post.created_at,
            },
        )
        return _row_to_post(row[0] if isinstance(row, list) else row)

    async def get_post(self, post_id: str) -> Post | None:
        row = await self._db.select(f"{_POSTS}:{post_id}")
        if not row:
            return None
        return _row_to_post(row[0] if isinstance(row, list) else row)

    async def list_feed(self, *, cursor: str | None, limit: int) -> tuple[list[Post], str | None]:
        query = f"SELECT * FROM {_POSTS} "
        params: dict = {"limit": limit + 1}
        if cursor:
            query += "WHERE created_at < $cursor "
            params["cursor"] = cursor
        query += "ORDER BY created_at DESC LIMIT $limit"

        result = await self._db.query(query, params)
        records = result[0]["result"] if result and result[0].get("result") else []
        has_more = len(records) > limit
        page = records[:limit]
        next_cursor = page[-1]["created_at"].isoformat() if has_more and page else None
        return [_row_to_post(r) for r in page], next_cursor

    async def list_posts_by_author(
        self, author_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[Post], str | None]:
        query = f"SELECT * FROM {_POSTS} WHERE author_id = $author "
        params: dict = {"author": f"user:{author_id}", "limit": limit + 1}
        if cursor:
            query += "AND created_at < $cursor "
            params["cursor"] = cursor
        query += "ORDER BY created_at DESC LIMIT $limit"

        result = await self._db.query(query, params)
        records = result[0]["result"] if result and result[0].get("result") else []
        has_more = len(records) > limit
        page = records[:limit]
        next_cursor = page[-1]["created_at"].isoformat() if has_more and page else None
        return [_row_to_post(r) for r in page], next_cursor

    async def is_liked_by(self, post_id: str, user_id: str) -> bool:
        result = await self._db.query(
            "SELECT VALUE count() FROM liked WHERE in = $user AND out = $post",
            {"user": f"user:{user_id}", "post": f"{_POSTS}:{post_id}"},
        )
        records = result[0]["result"] if result and result[0].get("result") else []
        return bool(records and records[0])

    async def set_liked(self, post_id: str, user_id: str, liked: bool) -> Post:
        if liked:
            await self._db.query(
                "RELATE $user->liked->$post",
                {"user": f"user:{user_id}", "post": f"{_POSTS}:{post_id}"},
            )
            await self._db.query(
                f"UPDATE {_POSTS}:{post_id} SET like_count += 1"
            )
        else:
            await self._db.query(
                "DELETE liked WHERE in = $user AND out = $post",
                {"user": f"user:{user_id}", "post": f"{_POSTS}:{post_id}"},
            )
            await self._db.query(
                f"UPDATE {_POSTS}:{post_id} SET like_count = math::max([like_count - 1, 0])"
            )
        return await self.get_post(post_id)  # type: ignore[return-value]

    async def add_comment(self, comment: Comment) -> Comment:
        record_id = f"{_COMMENTS}:{comment.id}"
        row = await self._db.create(
            record_id,
            {
                "post_id": f"{_POSTS}:{comment.post_id}",
                "author_id": f"user:{comment.author_id}",
                "text": comment.text,
                "created_at": comment.created_at,
            },
        )
        await self._db.query(f"UPDATE {_POSTS}:{comment.post_id} SET comment_count += 1")
        return _row_to_comment(row[0] if isinstance(row, list) else row)

    async def list_comments(
        self, post_id: str, *, cursor: str | None, limit: int
    ) -> tuple[list[Comment], str | None]:
        query = f"SELECT * FROM {_COMMENTS} WHERE post_id = $post "
        params: dict = {"post": f"{_POSTS}:{post_id}", "limit": limit + 1}
        if cursor:
            query += "AND created_at < $cursor "
            params["cursor"] = cursor
        query += "ORDER BY created_at DESC LIMIT $limit"

        result = await self._db.query(query, params)
        records = result[0]["result"] if result and result[0].get("result") else []
        has_more = len(records) > limit
        page = records[:limit]
        next_cursor = page[-1]["created_at"].isoformat() if has_more and page else None
        return [_row_to_comment(r) for r in page], next_cursor
