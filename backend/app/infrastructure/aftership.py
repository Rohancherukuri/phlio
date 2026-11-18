"""
AfterShip Tracking API client (https://www.aftership.com/docs/tracking).

Phlio Shop lets people paste a tracking number from any retailer and follow
the parcel in the app. We talk to AfterShip from the server only; the key
(``AFTERSHIP_API_KEY``, sent as the ``as-api-key`` header) never reaches the
phone. ``AFTERSHIP_API_ENDPOINT`` pins the API version (default 2026-07).

From API version 2025-07 on, request bodies are flat (no ``"tracking"``
wrapper), trackings are addressed by ``id`` and checkpoints use
``country_region``; :func:`normalize` also accepts the older shapes so a
version bump doesn't break the app.
"""

from __future__ import annotations

import httpx

DEFAULT_ENDPOINT = "https://api.aftership.com/tracking/2026-07"

# AfterShip delivery tags, in the order a parcel moves through them.
TAGS = {
    "Pending": "Waiting for the carrier",
    "InfoReceived": "Label created",
    "InTransit": "In transit",
    "OutForDelivery": "Out for delivery",
    "AttemptFail": "Delivery attempt failed",
    "AvailableForPickup": "Ready for pickup",
    "Delivered": "Delivered",
    "Exception": "Problem with delivery",
    "Expired": "No recent updates",
}
PROGRESS = ["InfoReceived", "InTransit", "OutForDelivery", "Delivered"]


class TrackingUnavailable(Exception):
    """AfterShip isn't configured, rejected the request or is down."""

    def __init__(self, message: str, status: int = 502):
        super().__init__(message)
        self.status = status


class AfterShip:
    def __init__(self, api_key: str, endpoint: str = DEFAULT_ENDPOINT, transport: httpx.AsyncBaseTransport | None = None):
        self.api_key = api_key.strip()
        self.endpoint = (endpoint or DEFAULT_ENDPOINT).rstrip("/")
        self.transport = transport

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    async def _call(self, method: str, path: str, **kwargs) -> dict:
        if not self.configured:
            raise TrackingUnavailable("Parcel tracking isn't set up on this server.", 503)
        async with httpx.AsyncClient(
            base_url=self.endpoint, timeout=15, transport=self.transport,
            headers={"as-api-key": self.api_key, "Content-Type": "application/json", "User-Agent": "Phlio/1.0"},
        ) as client:
            try:
                r = await client.request(method, path, **kwargs)
            except httpx.HTTPError as exc:
                raise TrackingUnavailable("Couldn't reach the tracking service. Try again soon.") from exc
        try:
            body = r.json()
        except ValueError:
            body = {}
        if r.status_code >= 400:
            meta = body.get("meta") or {}
            message = meta.get("message") or "The tracking service rejected the request."
            err = TrackingUnavailable(message, 404 if r.status_code == 404 else 400 if r.status_code < 500 else 502)
            err.code = meta.get("code")  # type: ignore[attr-defined]
            raise err
        return body.get("data") if isinstance(body.get("data"), dict) else body

    async def create(self, tracking_number: str, slug: str | None = None, title: str | None = None) -> dict:
        body = {"tracking_number": tracking_number}
        if slug:
            body["slug"] = slug
        if title:
            body["title"] = title
        return _unwrap(await self._call("POST", "/trackings", json=body))

    async def find(self, tracking_number: str) -> dict | None:
        data = await self._call("GET", "/trackings", params={"tracking_numbers": tracking_number, "limit": 5})
        rows = data.get("trackings") or []
        return rows[0] if rows else None

    async def get(self, tracking_id: str) -> dict:
        return _unwrap(await self._call("GET", f"/trackings/{tracking_id}"))

    async def detect(self, tracking_number: str) -> list[dict]:
        data = await self._call("POST", "/couriers/detect", json={"tracking_number": tracking_number})
        return [dict(slug=c.get("slug"), name=c.get("name")) for c in data.get("couriers") or [] if c.get("slug")]


def _unwrap(data: dict) -> dict:
    return data.get("tracking") if isinstance(data.get("tracking"), dict) else data


def _eta(t: dict) -> str | None:
    latest = t.get("latest_estimated_delivery") or {}
    if latest.get("datetime") or latest.get("datetime_max"):
        return latest.get("datetime") or latest.get("datetime_max")
    courier = t.get("courier_estimated_delivery_date")
    if isinstance(courier, dict) and courier:
        return courier.get("estimated_delivery_date") or courier.get("estimated_delivery_date_max")
    return t.get("expected_delivery") or (courier if isinstance(courier, str) else None)


def normalize(t: dict) -> dict:
    """The parts of an AfterShip tracking the app shows."""
    tag = t.get("tag") or "Pending"
    checkpoints = []
    for c in t.get("checkpoints") or []:
        where = c.get("location") or ", ".join(
            x for x in (c.get("city"), c.get("state"), c.get("country_region_name") or c.get("country_name")) if x)
        checkpoints.append(dict(
            time=c.get("checkpoint_time"), message=c.get("message") or c.get("subtag_message") or "",
            location=where or None, tag=c.get("tag")))
    checkpoints.sort(key=lambda c: c["time"] or "", reverse=True)
    return dict(
        aftership_id=t.get("id"), tracking_number=t.get("tracking_number"), slug=t.get("slug"),
        courier=(t.get("courier") or {}).get("name") if isinstance(t.get("courier"), dict) else t.get("slug"),
        title=t.get("title") if t.get("title") and t.get("title") != t.get("tracking_number") else None,
        tag=tag, status=TAGS.get(tag, tag), detail=t.get("subtag_message") or None,
        step=PROGRESS.index(tag) + 1 if tag in PROGRESS else (0 if tag == "Pending" else None),
        eta=_eta(t), courier_link=t.get("courier_tracking_link") or None,
        checkpoints=checkpoints[:50],
    )
