"""Seeded demo moments are re-dated; real moments never are."""

import datetime as dt

from app.domains.graph import demo_refresh


async def test_refresh_redates_only_expired_seeded_live_moments(client):
    c = client._transport.app.state.container
    old = dt.datetime(2026, 1, 1, tzinfo=dt.UTC)
    rows = {
        "social_moment:seed_demo_001_live_0": dict(seed="moments-v1", author="demo_001"),
        "social_moment:seed_demo_001_h0_0": dict(seed="moments-v1", author="demo_001"),
        "social_moment:real_1": dict(author="usr_arjun"),
    }
    for mid, row in rows.items():
        await c.graph.store.put(mid, dict(row, created_at=old.isoformat(),
                                          expires_at=(old + dt.timedelta(hours=24)).isoformat()))
    now = dt.datetime(2026, 11, 11, 12, tzinfo=dt.UTC)
    assert await demo_refresh.refresh_once(c, now) == 1
    live = await c.graph.store.get("social_moment:seed_demo_001_live_0")
    created = dt.datetime.fromisoformat(live["created_at"])
    assert now - dt.timedelta(hours=20) <= created <= now - dt.timedelta(minutes=8)
    assert (await c.graph.store.get("social_moment:seed_demo_001_h0_0"))["created_at"] == old.isoformat()
    assert (await c.graph.store.get("social_moment:real_1"))["created_at"] == old.isoformat()
    assert await demo_refresh.refresh_once(c, now) == 0  # now fresh


async def test_deleted_account_token_is_401(client, auth_headers):
    c = client._transport.app.state.container
    async def gone(user_id):
        from app.common.exceptions import NotFoundError
        raise NotFoundError("User not found.")
    c.identity_service.get_user_or_raise = gone
    r = await client.get("/api/v1/auth/me", headers=auth_headers)
    assert r.status_code == 401
