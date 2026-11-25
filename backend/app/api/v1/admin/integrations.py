"""Third-party analytics integrations, managed from the admin panel.

    GET  /admin/integrations                    every provider, secrets masked
    PUT  /admin/integrations/{provider}         {enabled, ...fields} (admin+)
    POST /admin/integrations/{provider}/test    send one test event (admin+)
    GET  /analytics/config                      public client config (no auth)

Providers: Google Analytics 4 and the open-source PostHog, Plausible, Umami
and Matomo. Server-side events (see app/middleware/analytics.py) go to every
enabled provider; /analytics/config gives the web admin panel and the app
the public ids they need to load each tool's own client script or SDK.
Secret fields (GA4 API secret, Matomo token) are never sent back out.
"""

from __future__ import annotations

from typing import Any

import httpx
from fastapi import APIRouter, Body, Depends, HTTPException, Request

from app.api.deps import get_container
from app.api.v1.admin.auth import audit, require
from app.domains.graph.service import key
from app.domains.graph.store import now
from app.infrastructure.analytics_bridge import PROVIDERS
from app.middleware.analytics import bridge_for

router = APIRouter(tags=["admin"])
TABLE = "admin_integration"
MASK = "••••••••"


def _mask(provider: str, row: dict | None, bridge) -> dict[str, Any]:
    spec = PROVIDERS[provider]
    row = row or {}
    fields = {}
    for name, secret in spec["fields"].items():
        value = row.get(name) or ""
        fields[name] = (MASK if value else "") if secret else value
    return {
        "id": provider, "label": spec["label"], "open_source": spec["open_source"], "docs": spec["docs"],
        "enabled": bool(row.get("enabled")), "fields": fields,
        "secret_fields": [n for n, s in spec["fields"].items() if s],
        "updated_at": row.get("updated_at"), "updated_by": row.get("updated_by"),
        "sent": bridge.sent.get(provider, 0), "failed": bridge.failed.get(provider, 0),
    }


async def _rows(c) -> dict[str, dict]:
    return {r["provider"]: r for r in await c.graph.store.rows(TABLE) if r.get("provider") in PROVIDERS}


def _provider(provider: str) -> str:
    if provider not in PROVIDERS:
        raise HTTPException(404, "Unknown analytics provider.")
    return provider


@router.get("/admin/integrations")
async def list_integrations(request: Request, admin=Depends(require()), c=Depends(get_container)):
    rows, bridge = await _rows(c), bridge_for(request.app)
    return {"items": [_mask(p, rows.get(p), bridge) for p in PROVIDERS]}


@router.put("/admin/integrations/{provider}")
async def save_integration(provider: str, request: Request, body: dict = Body(...),
                           admin=Depends(require("admin")), c=Depends(get_container)):
    _provider(provider)
    spec = PROVIDERS[provider]
    current = (await _rows(c)).get(provider) or {}
    row = {"provider": provider, "enabled": bool(body.get("enabled", current.get("enabled", False)))}
    for name, secret in spec["fields"].items():
        value = body.get(name, current.get(name, ""))
        value = "" if value is None else str(value).strip()
        if secret and value == MASK:
            value = current.get(name, "")
        if name == "host" and value and not value.startswith(("https://", "http://")):
            raise HTTPException(422, "The host must start with https://")
        if len(value) > 300:
            raise HTTPException(422, f"{name} is too long.")
        row[name] = value
    row.update(updated_at=now(), updated_by=admin["email"])
    await c.graph.store.put(key(TABLE, provider), row)
    bridge = bridge_for(request.app)
    bridge.set_configs(await _rows(c))
    await audit(c, admin, "integration", provider=provider, enabled=row["enabled"])
    return _mask(provider, row, bridge)


@router.post("/admin/integrations/{provider}/test")
async def test_integration(provider: str, request: Request, admin=Depends(require("admin")), c=Depends(get_container)):
    _provider(provider)
    row = (await _rows(c)).get(provider)
    if not row:
        raise HTTPException(400, "Save this integration first.")
    bridge = bridge_for(request.app)
    try:
        response = await bridge.send(provider, row, "phlio_admin_test", bridge.pseudonym("admin-test"),
                                     {"platform": "admin", "source": "admin_panel"}, debug=True)
    except (httpx.HTTPError, OSError) as error:
        return {"ok": False, "status": None, "message": f"Couldn't reach {PROVIDERS[provider]['label']}: {error.__class__.__name__}"}
    if response is None:
        return {"ok": False, "status": None, "message": "Fill in the required fields first."}
    ok = response.status_code < 400
    message = "Test event accepted." if ok else f"{PROVIDERS[provider]['label']} answered {response.status_code}."
    if provider == "ga4" and ok:
        try:
            problems = response.json().get("validationMessages") or []
        except ValueError:
            problems = []
        if problems:
            ok, message = False, problems[0].get("description", "GA4 rejected the event.")
    return {"ok": ok, "status": response.status_code, "message": message}


@router.get("/analytics/config")
async def public_config(c=Depends(get_container)):
    """Public ids for the client-side scripts/SDKs of each enabled provider."""
    out = {}
    for provider, row in (await _rows(c)).items():
        if row.get("enabled"):
            out[provider] = {f: row.get(f, "") for f in PROVIDERS[provider]["public"]}
    return {"providers": out}
