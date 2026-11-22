"""Push notifications through OneSignal.

Every Phlio notification (app/api/v1/notifications.py) can also go out as a
push to the person's phones. The app logs in to OneSignal with the Phlio
user id as its *external id* (frontend: shared/notifications/push.dart), so
a push targets ``include_aliases.external_id = [user_id]``.

What a push carries, per platform:

  * the platform's own small icon (``ic_stat_<platform>``, drawables in the
    Android app) and accent colour, and its own Android group / iOS thread,
    so Messages, Rooms, Shop, News, Stream… stay apart in the shade;
  * the sender's photo as the large icon (DMs, rooms, comments);
  * a big picture for News stories, Stream titles and songs, Shop items;
  * action buttons — Reply / Like, Add to bag, Bookmark, Play — handled by
    the app when tapped (push.dart);
  * ``data``: the notification id, platform, kind and the in-app route.

Settings: ``ONESIGNAL_APP_ID`` and ``ONESIGNAL_REST_API_KEY`` (both needed;
push is off otherwise). Images need public https URLs: relative media paths
are joined to ``PUBLIC_BASE_URL`` / ``MEDIA_PUBLIC_URL`` /
``RENDER_EXTERNAL_URL``.
"""

from __future__ import annotations

import logging
import os
from urllib.parse import quote

import httpx

log = logging.getLogger("phlio.push")

API = "https://api.onesignal.com/notifications?c=push"

# Platform → (label, accent ARGB) — matches the app's NotifPlatform colours.
STYLE = {
    "dm": ("Messages", "FFFF5FA2"),
    "social": ("Social", "FF8D78FF"),
    "rooms": ("Rooms", "FF3DD6C6"),
    "shop": ("Shop", "FFFF9F5A"),
    "news": ("News", "FF4C9BFF"),
    "stream": ("Stream", "FFFF4D5E"),
    "book": ("Book", "FFE795D7"),
    "pay": ("Pay", "FFF6C343"),
    "agent": ("Foxy", "FFFFB58F"),
}


def enabled(settings) -> bool:
    return bool(settings.onesignal_app_id and settings.onesignal_rest_api_key)


def _base(settings) -> str:
    return (settings.public_base_url or os.environ.get("RENDER_EXTERNAL_URL", "")).rstrip("/")


def absolute(settings, url: str | None) -> str | None:
    """A public https URL for an image, or None when there's none to give."""
    if not url:
        return None
    if url.startswith(("http://", "https://")):
        return url if url.startswith("https://") else None  # Android blocks cleartext images
    path = url if url.startswith("/") else "/" + url
    if settings.media_public_url and path.startswith("/media/"):
        return settings.media_public_url.rstrip("/") + path.removeprefix("/media")
    base = _base(settings)
    return base + path if base.startswith("https://") else None


def route(row: dict) -> str | None:
    data = row.get("data") or {}
    platform = row.get("platform")
    if platform == "dm" and data.get("peer"):
        return "/dm/" + quote(str(data["peer"]), safe="")
    if platform == "rooms" and data.get("room_id"):
        return f"/rooms/{data['room_id']}"
    path = str(data.get("path") or "")
    if "/" in path:
        head, rest = path.split("/", 1)
        return f"/shared/{head}/{quote(rest, safe='')}"
    return None


def _buttons(row: dict) -> list[dict]:
    data = row.get("data") or {}
    platform, kind = row.get("platform"), row.get("kind")
    if platform in {"dm", "rooms"}:
        return [{"id": "reply", "text": "Reply"}, {"id": "react", "text": "❤️ Like"}]
    if kind in {"comment", "reply", "mention"} and data.get("comment_id"):
        return [{"id": "reply", "text": "Reply"}, {"id": "like", "text": "❤️ Like"}]
    if platform == "shop" and data.get("products"):
        return [{"id": "bag", "text": "Add to bag"}, {"id": "open", "text": "See all"}]
    if platform == "news" and data.get("ref"):
        return [{"id": "bookmark", "text": "Bookmark"}]
    if platform == "stream" and kind == "song":
        return [{"id": "play", "text": "▶ Play"}]
    return []


def payload(settings, row: dict, actor: dict | None = None) -> dict:
    data = row.get("data") or {}
    platform = row.get("platform") or "social"
    label, accent = STYLE.get(platform, STYLE["social"])
    picture = data.get("image_url")
    if not picture and data.get("products"):
        picture = (data["products"][0] or {}).get("image_url")
    picture = absolute(settings, picture)
    face = absolute(settings, (actor or {}).get("avatar_url"))
    group = row.get("group") or f"{platform}:{row['id']}"
    body = row.get("body") or ""
    if (row.get("count") or 1) > 1:
        body = f"{body}  ·  {row['count']} new"
    out = {
        "app_id": settings.onesignal_app_id,
        "target_channel": "push",
        "include_aliases": {"external_id": [row["user_id"]]},
        "headings": {"en": row.get("title") or label},
        "contents": {"en": body or label},
        "subtitle": {"en": label},  # iOS: the platform under the title
        "data": {
            "phlio": True,
            "notification_id": row["id"],
            "platform": platform,
            "kind": row.get("kind"),
            "route": route(row),
            # What the action buttons need (kept small: data must stay < 2 KB).
            "peer": data.get("peer"),
            "room_id": data.get("room_id"),
            "path": data.get("path"),
            "comment_id": data.get("comment_id"),
            "ref": data.get("ref"),
            "product_id": ((data.get("products") or [{}])[0] or {}).get("id"),
            "title": data.get("title"),
            "artist": data.get("artist"),
            "media_url": data.get("media_url"),
            "image_url": data.get("image_url"),
        },
        "small_icon": f"ic_stat_{platform}",
        "android_accent_color": accent,
        "android_group": f"phlio_{platform}",
        "thread_id": f"phlio_{platform}",
        # Grouped chats replace their earlier push instead of stacking.
        "collapse_id": group[:64],
        "ttl": 86400,
    }
    out["data"] = {k: v for k, v in out["data"].items() if v is not None}
    if face:
        out["large_icon"] = face
    if picture:
        out["big_picture"] = picture
        out["ios_attachments"] = {"image": picture}
    buttons = _buttons(row)
    if buttons:
        out["buttons"] = buttons
    return out


async def send(settings, row: dict, actor: dict | None = None) -> bool:
    """Sends ``row`` (a phlio_notification) as a push. Never raises."""
    if not enabled(settings):
        return False
    try:
        async with httpx.AsyncClient(timeout=10) as http:
            r = await http.post(API, json=payload(settings, row, actor), headers={
                "Authorization": f"Key {settings.onesignal_rest_api_key}",
                "Content-Type": "application/json",
            })
        if r.status_code >= 400:
            log.warning("push.failed status=%s body=%s", r.status_code, r.text[:300])
            return False
        body = r.json()
        if body.get("errors"):
            # e.g. "All included players are not subscribed" — the phone
            # hasn't logged in to OneSignal yet or denied permission.
            log.info("push.not_delivered user=%s errors=%s", row.get("user_id"), body["errors"])
            return False
        return True
    except Exception:
        log.exception("push.error")
        return False
