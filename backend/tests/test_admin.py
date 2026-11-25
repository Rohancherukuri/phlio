"""Admin panel: signup/login, roles, analytics across platforms, live stream
and analytics integrations."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.infrastructure.analytics_bridge import build_request, event_name, platform_for

pytestmark = pytest.mark.asyncio
A = "/api/v1/admin"


async def _owner(client: AsyncClient) -> dict:
    r = await client.post(f"{A}/auth/signup", json={"email": "Owner@Phlio.app", "name": "Owner",
                                                    "password": "correct-horse-battery"})
    assert r.status_code == 201, r.text
    return {"Authorization": "Bearer " + r.json()["tokens"]["access_token"]}


async def test_admin_auth_and_roles(client: AsyncClient, auth_headers: dict) -> None:
    s = (await client.get(f"{A}/auth/status")).json()
    assert s == {"has_admins": False, "signup": "bootstrap", "code_required": False}
    owner = await _owner(client)
    assert (await client.get(f"{A}/auth/me", headers=owner)).json()["role"] == "owner"

    # After the owner, signups need an invite.
    body = {"email": "ana@phlio.app", "name": "Ana", "password": "another-long-pass"}
    assert (await client.post(f"{A}/auth/signup", json=body)).status_code == 403
    inv = (await client.post(f"{A}/team/invites", headers=owner, json={"role": "viewer", "email": "ana@phlio.app"})).json()
    assert (await client.post(f"{A}/auth/signup", json=dict(body, email="x@phlio.app", code=inv["code"]))).status_code == 403
    r = await client.post(f"{A}/auth/signup", json=dict(body, code=inv["code"]))
    assert r.status_code == 201 and r.json()["admin"]["role"] == "viewer"
    assert (await client.post(f"{A}/auth/signup", json=dict(body, email="b@phlio.app", code=inv["code"]))).status_code == 403

    bad = await client.post(f"{A}/auth/login", json={"email": "ana@phlio.app", "password": "wrong-password"})
    assert bad.status_code == 401
    r = await client.post(f"{A}/auth/login", json={"email": "ANA@phlio.app", "password": "another-long-pass"})
    viewer = {"Authorization": "Bearer " + r.json()["tokens"]["access_token"]}

    # Tokens don't cross: app tokens can't open the admin API and vice versa.
    assert (await client.get(f"{A}/overview", headers=auth_headers)).status_code == 401
    assert (await client.get("/api/v1/fitness/day", headers=owner)).status_code == 401

    # Viewers read dashboards, can't manage the team or integrations; emails masked.
    assert (await client.get(f"{A}/overview", headers=viewer)).status_code == 200
    assert (await client.get(f"{A}/team", headers=viewer)).status_code == 403
    assert (await client.put(f"{A}/integrations/ga4", headers=viewer, json={"enabled": True})).status_code == 403
    users = (await client.get(f"{A}/users", headers=viewer)).json()
    assert users["total"] > 0 and "•••@" in users["items"][0]["email"]

    team = (await client.get(f"{A}/team", headers=owner)).json()
    ana = next(m for m in team["members"] if m["email"] == "ana@phlio.app")
    assert any(a["action"] == "signup" for a in team["audit"])
    r = await client.patch(f"{A}/team/{ana['id']}", headers=owner, json={"disabled": True})
    assert r.json()["disabled"] is True
    assert (await client.get(f"{A}/auth/me", headers=viewer)).status_code == 401


async def test_signup_code(client: AsyncClient, settings) -> None:
    settings.admin_signup_code = "let-me-in-please"
    assert (await client.get(f"{A}/auth/status")).json()["code_required"] is True
    body = {"email": "o@phlio.app", "name": "O", "password": "correct-horse-battery"}
    assert (await client.post(f"{A}/auth/signup", json=dict(body, code="nope"))).status_code == 403
    assert (await client.post(f"{A}/auth/signup", json=dict(body, code="let-me-in-please"))).status_code == 201


async def test_overview_platforms_traffic_and_live(client: AsyncClient, auth_headers: dict) -> None:
    owner = await _owner(client)
    # Some product traffic and a mutation in Phlio Fit and Move.
    await client.post("/api/v1/fitness/water", headers=auth_headers, json={"ml": 250})
    await client.get("/api/v1/social/feed", headers=auth_headers)

    o = (await client.get(f"{A}/overview", headers=owner, params={"days": 14})).json()
    kpis = {k["id"]: k for k in o["kpis"]}
    assert kpis["users"]["value"] > 0 and len(kpis["events"]["series"]) == 14
    ids = [p["id"] for p in o["platforms"]]
    assert ids == ["social", "dm", "rooms", "pay", "book", "shop", "stream", "news", "agent"]
    agent = next(p for p in o["platforms"] if p["id"] == "agent")
    assert any(m["id"] == "fit_days" and m["value"] >= 1 for m in agent["metrics"])
    assert len(o["daily"]) == 14 and "social" in o["daily"][0]

    p = (await client.get(f"{A}/platforms/social", headers=owner, params={"days": 30})).json()
    assert p["id"] == "social" and len(p["by_hour"]) == 24 and p["metrics"]
    assert (await client.get(f"{A}/platforms/nope", headers=owner)).status_code == 404

    t = (await client.get(f"{A}/traffic", headers=owner, params={"hours": 6})).json()
    assert len(t["series"]) == 6 and t["series"][-1]["total"] >= 2

    snap = (await client.get(f"{A}/live/snapshot", headers=owner)).json()
    assert snap["type"] == "live" and snap["active_users"] >= 1 and snap["totals"]["users"] > 0
    assert any(f["event"] == "agent_water_create" for f in snap["feed"])


async def test_live_websocket(settings) -> None:
    from starlette.testclient import TestClient

    from app.core.container import build_container
    from app.core.seed import seed_memory_backend
    from app.main import create_app

    app = create_app(settings)
    app.state.container = await build_container(settings)
    await seed_memory_backend(app.state.container)
    http = TestClient(app)  # no lifespan: keep the seeded in-memory container
    if True:
        r = http.post(f"{A}/auth/signup", json={"email": "w@phlio.app", "name": "W", "password": "correct-horse-battery"})
        token = r.json()["tokens"]["access_token"]
        with http.websocket_connect(f"{A}/live") as ws:
            ws.send_json({"token": token})
            msg = ws.receive_json()
            assert msg["type"] == "live" and len(msg["series"]) == 30
        with http.websocket_connect(f"{A}/live") as ws:
            ws.send_json({"token": "bad"})
            with pytest.raises(Exception):
                ws.receive_json()


async def test_integrations(client: AsyncClient) -> None:
    owner = await _owner(client)
    items = (await client.get(f"{A}/integrations", headers=owner)).json()["items"]
    assert [i["id"] for i in items] == ["ga4", "posthog", "plausible", "umami", "matomo"]

    r = await client.put(f"{A}/integrations/ga4", headers=owner,
                         json={"enabled": True, "measurement_id": "G-TEST123", "api_secret": "s3cret-value"})
    assert r.status_code == 200 and r.json()["fields"]["api_secret"] == "••••••••"
    # Saving the mask back keeps the stored secret.
    r = await client.put(f"{A}/integrations/ga4", headers=owner, json={"api_secret": "••••••••"})
    assert r.json()["fields"]["api_secret"] == "••••••••"
    assert (await client.put(f"{A}/integrations/umami", headers=owner, json={"host": "ftp://x"})).status_code == 422
    assert (await client.put(f"{A}/integrations/nope", headers=owner, json={})).status_code == 404

    public = (await client.get("/api/v1/analytics/config")).json()["providers"]
    assert public == {"ga4": {"measurement_id": "G-TEST123"}}


def test_event_helpers() -> None:
    assert platform_for("/api/v1/social/posts") == "social"
    assert platform_for("/api/v1/messaging/threads") == "dm"
    assert platform_for("/api/v1/admin/overview") is None and platform_for("/media/x.jpg") is None
    assert event_name("POST", "/api/v1/social/posts/p_123abc/like") == "social_posts_like"
    assert event_name("GET", "/api/v1/social/feed") is None

    method, url, kw = build_request("ga4", {"measurement_id": "G-1", "api_secret": "x"}, "social_posts_like", "cid", {"a": 1})
    assert url.endswith("/mp/collect") and kw["json"]["events"][0]["name"] == "social_posts_like"
    assert build_request("ga4", {"measurement_id": "G-1"}, "e", "cid", {}) is None
    _, url, kw = build_request("posthog", {"project_api_key": "phc_x"}, "e", "cid", {})
    assert url == "https://us.i.posthog.com/capture/" and kw["json"]["distinct_id"] == "cid"
    _, url, _ = build_request("umami", {"host": "https://u.example.com/", "website_id": "w"}, "e", "cid", {})
    assert url == "https://u.example.com/api/send"
    _, url, kw = build_request("matomo", {"host": "https://m.example.com", "site_id": "1"}, "social_like", "cid", {})
    assert url.endswith("/matomo.php") and kw["data"]["e_c"] == "social"
