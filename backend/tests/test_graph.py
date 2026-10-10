"""Privacy matrix, directional relationships and cache revocation regression tests."""

import datetime as dt

import pytest
from fastapi import HTTPException

from app.core.container import build_container
from app.core.seed import seed_memory_backend
from app.domains.graph.service import key


@pytest.fixture
async def graph(settings):
    c = await build_container(settings)
    await seed_memory_backend(c)
    yield c.graph
    await c.cache.close()
    c.messaging_service.db.close()
    c.social_video_service.db.close()


async def users(g):
    result = await g.identity.search_users("", 30)
    return result[0].id, result[1].id, result[2].id


async def policy(g, owner, **kwargs):
    data = dict(
        platform="social",
        object_type="*",
        verb="*",
        audience="friends",
        identity_mode="identified",
        foxy_access="both",
        selected_users=[],
    )
    data.update(kwargs)
    return await g.set_policy(owner, data)


@pytest.mark.asyncio
async def test_friend_acceptance_direction_and_block(graph):
    a, b, _ = await users(graph)
    await graph.relationship(a, b, "request")
    with pytest.raises(HTTPException):
        await graph.relationship(a, b, "accept")
    await graph.relationship(b, a, "accept")
    await graph.relationship(a, b, "follow")
    assert await graph.friends(a, b)
    assert len((await graph.connections(a))["following"]) == 1
    assert (await graph.connections(b))["following"] == []
    await graph.relationship(b, a, "block")
    assert not await graph.friends(a, b)
    assert (await graph.connections(a))["following"] == []
    with pytest.raises(HTTPException):
        await graph.relationship(a, b, "request")


@pytest.mark.asyncio
async def test_activity_default_private_anonymous_revocation_and_foxy(graph):
    a, b, c = await users(graph)
    await graph.relationship(a, b, "request")
    await graph.relationship(b, a, "accept")
    obj = await graph.register_object(a, "social.post", "privacy-test", "An experiment")
    await graph.action(b, obj["id"], "liked")
    assert (await graph.social_context(a, obj["id"]))["signals"] == []
    await policy(graph, b, identity_mode="anonymous")
    signal = (await graph.social_context(a, obj["id"]))["signals"][0]
    assert signal["actor"] is None and b not in str(signal)
    assert (await graph.social_context(c, obj["id"]))["signals"] == []
    assert len((await graph.foxy_context(a, [b], "social", "group", ["liked"]))["signals"]) == 1
    revision = await graph.store.revision()
    await graph.foxy_context(a, [b], "social", "group", ["liked"])
    assert await graph.store.revision() == revision
    await policy(graph, b, identity_mode="hidden", foxy_access="none")
    assert (await graph.social_context(a, obj["id"]))["signals"] == []
    assert (await graph.foxy_context(a, [b], "social", "group", ["liked"]))["signals"] == []


@pytest.mark.asyncio
async def test_expiry_notes_private_objects_and_pay(graph):
    a, b, c = await users(graph)
    obj = await graph.register_object(a, "pay.transaction_reference", "private-payment", "Payment reference")
    assert obj["audience"] == "private"
    with pytest.raises(HTTPException):
        await graph.object_for(b, obj["id"])
    with pytest.raises(HTTPException):
        await graph.action(a, obj["id"], "paid")
    await graph.action(a, obj["id"], "paid", trusted=True)
    await graph.set_policy(
        a,
        dict(
            platform="pay",
            object_type="*",
            verb="*",
            audience="public",
            identity_mode="identified",
            foxy_access="both",
            selected_users=[],
        ),
    )
    assert (await graph.social_context(a, obj["id"]))["signals"] == []
    with pytest.raises(HTTPException):
        await graph.create_note(a, "secret", [b], object_id=obj["id"])
    await graph.create_note(a, "Hello", [b])
    assert (await graph.notes(b))[0]["text"] == "Hello"
    assert "recipients" not in (await graph.notes(b))[0]
    assert await graph.notes(c) == []
    await graph.relationship(b, a, "block")
    assert await graph.notes(b) == []


@pytest.mark.asyncio
async def test_policy_expiry_is_checked_after_cache_warm(graph):
    a, b, _ = await users(graph)
    await graph.relationship(a, b, "request")
    await graph.relationship(b, a, "accept")
    obj = await graph.register_object(a, "social.post", "expiry", "Expiry test")
    await policy(graph, b)
    await graph.action(b, obj["id"], "liked")
    assert (await graph.social_context(a, obj["id"]))["signals"]
    # Simulate time passing without changing the graph revision or cached candidates.
    pid = key("privacy_policy", b, "social", "*", "*")
    graph.store.data["privacy_policy"][pid]["expires_at"] = (
        dt.datetime.now(dt.UTC) - dt.timedelta(seconds=1)
    ).isoformat()
    assert (await graph.social_context(a, obj["id"]))["signals"] == []


@pytest.mark.asyncio
async def test_tombstone_hides_domain_post_and_prevents_mutation(client, auth_headers):
    response = await client.post(
        "/api/v1/social/posts", headers=auth_headers, json={"text": "Lifecycle test"}
    )
    assert response.status_code == 201
    post_id = response.json()["id"]
    object_id = key("phlio_object", "social", post_id)
    response = await client.patch(
        "/api/v1/objects/" + object_id, headers=auth_headers, json={"state": "tombstone"}
    )
    assert response.status_code == 200
    feed = (await client.get("/api/v1/social/feed", headers=auth_headers)).json()["items"]
    assert all(post["id"] != post_id for post in feed)
    assert (await client.get("/api/v1/social/posts/" + post_id, headers=auth_headers)).status_code == 404
    assert (
        await client.post("/api/v1/social/posts/" + post_id + "/like", headers=auth_headers)
    ).status_code == 404
    assert (
        await client.post(
            "/api/v1/social/posts/" + post_id + "/comments", headers=auth_headers, json={"text": "Hidden"}
        )
    ).status_code == 404
