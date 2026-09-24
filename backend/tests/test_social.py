"""Tests for the social feed: posting, feed retrieval, likes, comments."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_feed_returns_seeded_posts(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get("/api/v1/social/feed", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 3
    # newest first
    assert body["items"][0]["created_at"] >= body["items"][-1]["created_at"]


async def test_create_post_appears_in_feed(client: AsyncClient, auth_headers: dict) -> None:
    create = await client.post(
        "/api/v1/social/posts",
        headers=auth_headers,
        json={"text": "Hello Phlio!", "tags": ["intro"]},
    )
    assert create.status_code == 201, create.text
    post_id = create.json()["id"]

    feed = await client.get("/api/v1/social/feed", headers=auth_headers)
    ids = [item["id"] for item in feed.json()["items"]]
    assert post_id in ids


async def test_empty_post_is_rejected(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.post("/api/v1/social/posts", headers=auth_headers, json={"text": "  "})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


async def test_like_is_idempotent_toggle(client: AsyncClient, auth_headers: dict) -> None:
    feed = await client.get("/api/v1/social/feed", headers=auth_headers)
    post_id = feed.json()["items"][0]["id"]
    before_likes = feed.json()["items"][0]["like_count"]

    liked = await client.post(f"/api/v1/social/posts/{post_id}/like", headers=auth_headers)
    assert liked.json()["like_count"] == before_likes + 1
    assert liked.json()["liked_by_me"] is True

    unliked = await client.post(f"/api/v1/social/posts/{post_id}/like", headers=auth_headers)
    assert unliked.json()["like_count"] == before_likes
    assert unliked.json()["liked_by_me"] is False


async def test_comment_increments_comment_count(client: AsyncClient, auth_headers: dict) -> None:
    feed = await client.get("/api/v1/social/feed", headers=auth_headers)
    post_id = feed.json()["items"][0]["id"]

    comment = await client.post(
        f"/api/v1/social/posts/{post_id}/comments", headers=auth_headers, json={"text": "Nice!"}
    )
    assert comment.status_code == 201, comment.text

    refreshed = await client.get(f"/api/v1/social/posts/{post_id}", headers=auth_headers)
    assert refreshed.json()["comment_count"] == 1


async def test_comment_on_missing_post_is_404(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.post(
        "/api/v1/social/posts/pst_does_not_exist/comments",
        headers=auth_headers,
        json={"text": "Hi"},
    )
    assert response.status_code == 404
