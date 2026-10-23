"""Cross-platform sharing, recipient authorization and graph avatar visibility."""

import pytest

pytestmark = pytest.mark.asyncio


async def login(client, name):
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    assert r.status_code == 200, r.text
    return {"Authorization": "Bearer " + r.json()["tokens"]["access_token"]}


async def make_post(client, headers):
    r = await client.post("/api/v1/social/posts", headers=headers, json={"text": "A shareable weekend plan"})
    assert r.status_code == 201, r.text
    return r.json()["id"]


async def test_share_dm_group_and_membership(client, auth_headers):
    pid = await make_post(client, auth_headers)
    path = f"/api/v1/content/social/{pid}"
    destinations = await client.get("/api/v1/sharing/destinations", headers=auth_headers)
    assert destinations.status_code == 200, destinations.text
    r = await client.post(path + "/share", headers=auth_headers, json={"destination": "dm", "target": "neha"})
    assert r.status_code == 201, r.text
    messages = await client.get("/api/v1/messaging/peers/neha/messages", headers=auth_headers)
    assert "phlio://content/social/" + pid in messages.text
    r = await client.post(
        path + "/share", headers=auth_headers, json={"destination": "new_group", "members": ["neha"]}
    )
    assert r.status_code == 422
    r = await client.post(
        path + "/share",
        headers=auth_headers,
        json={"destination": "new_group", "members": ["neha", "artbykiara"], "name": "Weekend"},
    )
    assert r.status_code == 201, r.text
    gid = r.json()["target"]
    peer = await login(client, "neha")
    r = await client.get(f"/api/v1/messaging/groups/{gid}/messages", headers=peer)
    assert r.status_code == 200, r.text
    assert r.json()["items"][0]["content"]["ref"] == pid
    r = await client.post(
        f"/api/v1/messaging/groups/{gid}/messages", headers=peer, json={"text": "Count me in"}
    )
    assert r.status_code == 201, r.text
    # Register a fourth account: being authenticated is not group membership.
    r = await client.post(
        "/api/v1/auth/register",
        json={
            "username": "outsider",
            "email": "outsider@example.com",
            "password": "Testing!123456",
            "full_name": "Test Outsider",
        },
    )
    assert r.status_code == 201, r.text
    outsider = {"Authorization": "Bearer " + r.json()["tokens"]["access_token"]}
    assert (await client.get(f"/api/v1/messaging/groups/{gid}/messages", headers=outsider)).status_code == 404
    assert (
        await client.post(
            f"/api/v1/messaging/groups/{gid}/messages", headers=outsider, json={"text": "No access"}
        )
    ).status_code == 404
    assert (
        await client.post(path + "/share", headers=outsider, json={"destination": "group", "target": gid})
    ).status_code == 404


async def test_avatars_privacy_and_revocation(client, auth_headers):
    pid = await make_post(client, auth_headers)
    path = f"/api/v1/content/social/{pid}"
    peer = await login(client, "neha")
    public = {"platform": "social", "verb": "liked", "audience": "public", "identity_mode": "identified"}
    r = await client.put("/api/v1/privacy/activity", headers=peer, json=public)
    assert r.status_code == 200, r.text
    r = await client.put(path + "/like", headers=peer)
    assert r.status_code == 200, r.text
    visible = (await client.get(path + "/engagement", headers=auth_headers)).json()
    assert visible["count"] == 1 and len(visible["avatars"]) == 1
    public["identity_mode"] = "anonymous"
    assert (await client.put("/api/v1/privacy/activity", headers=peer, json=public)).status_code == 200
    hidden = (await client.get(path + "/engagement", headers=auth_headers)).json()
    assert hidden["count"] == 1 and hidden["avatars"] == []
    public["audience"] = "nobody"
    public["identity_mode"] = "hidden"
    await client.put("/api/v1/privacy/activity", headers=peer, json=public)
    hidden = (await client.get(path + "/engagement", headers=auth_headers)).json()
    assert hidden["count"] == 0 and hidden["avatars"] == []


async def test_room_join_and_block_checks(client, auth_headers):
    pid = await make_post(client, auth_headers)
    path = f"/api/v1/content/social/{pid}"
    r = await client.post(
        path + "/share", headers=auth_headers, json={"destination": "room", "target": "missing"}
    )
    assert r.status_code == 403
    peer = await login(client, "neha")
    r = await client.put("/api/v1/social/blocks/arjun", headers=peer)
    assert r.status_code == 200, r.text
    r = await client.post(path + "/share", headers=auth_headers, json={"destination": "dm", "target": "neha"})
    assert r.status_code == 403
    assert (await client.get("/api/v1/content/not_a_platform", headers=auth_headers)).status_code == 404


async def test_mutuals_only_accepted_and_not_blocked(client, auth_headers):
    neha = await login(client, "neha")
    kiara = await login(client, "artbykiara")
    # All three seed users are distinct. Both viewer and target befriend Kiara.
    await client.post(
        "/api/v1/social/friendships", headers=auth_headers, json={"target_user_id": "artbykiara"}
    )
    await client.post("/api/v1/social/friendships/usr_arjun/accept", headers=kiara)
    await client.post("/api/v1/social/friendships", headers=neha, json={"target_user_id": "artbykiara"})
    before = await client.get("/api/v1/social/creators/neha/mutuals", headers=auth_headers)
    assert before.status_code == 200 and before.json()["count"] == 0
    await client.post("/api/v1/social/friendships/usr_neha/accept", headers=kiara)
    shared = (await client.get("/api/v1/social/creators/neha/mutuals", headers=auth_headers)).json()
    assert shared["count"] == 1 and shared["avatars"][0]["username"] == "artbykiara"
    await client.put("/api/v1/social/blocks/artbykiara", headers=auth_headers)
    assert (await client.get("/api/v1/social/creators/neha/mutuals", headers=auth_headers)).json()[
        "count"
    ] == 0


async def test_shared_story_expires_and_checks_access(client, auth_headers):
    import datetime as dt

    post = await make_post(client, auth_headers)
    result = await client.post(f"/api/v1/content/social/{post}/story", headers=auth_headers)
    assert result.status_code == 201, result.text
    story = result.json()
    assert len((await client.get("/api/v1/social/shared-stories", headers=auth_headers)).json()) == 1
    neha = await login(client, "neha")
    assert (await client.get("/api/v1/social/shared-stories", headers=neha)).json() == []
    await client.put("/api/v1/social/creators/arjun/follow", headers=neha)
    assert len((await client.get("/api/v1/social/shared-stories", headers=neha)).json()) == 1
    c = client._transport.app.state.container
    story["expires_at"] = (dt.datetime.now(dt.UTC) - dt.timedelta(seconds=1)).isoformat()
    await c.graph.store.put(story["id"], story)
    assert (await client.get("/api/v1/social/shared-stories", headers=neha)).json() == []


async def test_mutual_followers_match_instagram_style_context(client, auth_headers):
    kiara = await login(client, "artbykiara")
    await client.put("/api/v1/social/creators/artbykiara/follow", headers=auth_headers)
    await client.put("/api/v1/social/creators/neha/follow", headers=kiara)
    data = (await client.get("/api/v1/social/creators/neha/mutuals", headers=auth_headers)).json()
    assert data["followed_by"]["count"] == 1
    assert data["followed_by"]["avatars"][0]["username"] == "artbykiara"
    await client.put("/api/v1/social/blocks/artbykiara", headers=auth_headers)
    data = (await client.get("/api/v1/social/creators/neha/mutuals", headers=auth_headers)).json()
    assert data["followed_by"]["count"] == 0
