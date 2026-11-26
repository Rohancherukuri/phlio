"""Places in Phlio Social explore (Instagram's "Places" search and map).

    GET /explore/places/search?q=&lat=&lng=
        Places matching ``q``: first the ones people tagged on Phlio (with how
        many posts and a cover photo), then Google Maps results (when
        GOOGLE_MAPS_API_KEY is set) with any Phlio posts made near them.
    GET /explore/places/posts?lat=&lng=&name=&sort=top|recent
        A place's page: its posts (made within ~250 m or tagged with the same
        name), Top (most reactions) or Recent.
    GET /explore/places/area?lat=&lng=&radius_km=
        Posts with a location around a point, for the map ("Search this
        area"), each with its place name.

Posts with a location are Experiences (and snaps) shared with a place
(``social_memory.location``: name, address, lat, lng). Only posts the viewer
may see count, and snaps only while they last (24 h).
"""

from __future__ import annotations

import datetime as dt
import math

from fastapi import APIRouter, Depends, HTTPException, Query

from app.api.deps import get_container, get_current_user
from app.api.v1.places import search as google_search
from app.api.v1.snap_audience import can_view
from app.domains.graph.service import key

router = APIRouter(prefix="/explore/places", tags=["explore"])
NEAR_M = 250


def _metres(lat1, lng1, lat2, lng2) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _place_id(lat: float, lng: float) -> str:
    return f"{lat:.5f},{lng:.5f}"


async def _geotagged(c, viewer) -> list[dict]:
    """Every post with a location the viewer may see, newest first."""
    day_ago = dt.datetime.now(dt.UTC) - dt.timedelta(hours=24)
    out, people = [], {}
    for row in await c.graph.store.rows("social_memory"):
        loc = row.get("location")
        if not isinstance(loc, dict) or loc.get("lat") is None:
            continue
        mine = row["author"] == viewer or viewer in (row.get("collaborators") or [])
        if not mine and not await can_view(c, viewer, row):
            continue
        created = dt.datetime.fromisoformat(str(row["created_at"]).replace("Z", "+00:00"))
        if created.tzinfo is None:
            created = created.replace(tzinfo=dt.UTC)
        if row.get("kind") != "experience" and created < day_ago and not mine:
            continue  # snaps last a day
        if row["author"] not in people:
            person = await c.identity_repository.get_by_id(row["author"])
            people[row["author"]] = c.graph.profile(person) if person else None
        reactions = len(await c.graph.store.rows("memory_reaction", {"memory_id": row["id"]}))
        out.append(dict(
            id=row["id"], kind=row.get("kind") or "snap", image_url=row.get("image_url"),
            media_kind=row.get("media_kind", "image"), filter=row.get("filter"), filter_spec=row.get("filter_spec"),
            caption=row.get("caption") or "", author=people[row["author"]], created_at=row["created_at"],
            reactions=reactions, place=dict(name=loc.get("name") or "Location", address=loc.get("address") or "",
                                            lat=float(loc["lat"]), lng=float(loc["lng"]))))
    out.sort(key=lambda x: x["created_at"], reverse=True)
    return out


def _group(posts: list[dict]) -> list[dict]:
    """Posts folded into places (same name within ~100 m)."""
    places: list[dict] = []
    for post in posts:
        p = post["place"]
        hit = next((x for x in places if x["name"].lower() == p["name"].lower()
                    and _metres(x["lat"], x["lng"], p["lat"], p["lng"]) < 100), None)
        if hit is None:
            hit = dict(id=_place_id(p["lat"], p["lng"]), name=p["name"], address=p["address"], lat=p["lat"],
                       lng=p["lng"], posts=0, cover=post, source="phlio")
            places.append(hit)
        hit["posts"] += 1
    return places


def _near(posts: list[dict], lat: float, lng: float, name: str | None = None, radius: float = NEAR_M) -> list[dict]:
    low = (name or "").strip().lower()
    return [x for x in posts
            if _metres(lat, lng, x["place"]["lat"], x["place"]["lng"]) <= radius
            or (low and x["place"]["name"].lower() == low
                and _metres(lat, lng, x["place"]["lat"], x["place"]["lng"]) <= 5000)]


@router.get("/search")
async def search(q: str = Query(min_length=1, max_length=80), lat: float | None = Query(None, ge=-90, le=90),
                 lng: float | None = Query(None, ge=-180, le=180),
                 user=Depends(get_current_user), c=Depends(get_container)):
    words = " ".join(q.lower().split())
    posts = await _geotagged(c, user.id)
    phlio = [p for p in _group(posts) if words in f"{p['name']} {p['address']}".lower()]
    phlio.sort(key=lambda p: p["posts"], reverse=True)
    external, source = [], "none"
    if len(words) >= 2:
        try:
            found = await google_search(q=q, lat=lat, lng=lng, user=user, c=c)
            source = found.get("source", "google")
            for g in found.get("items") or []:
                if any(_metres(g["lat"], g["lng"], p["lat"], p["lng"]) < 80 for p in phlio):
                    continue  # already listed with its Phlio posts
                nearby = _near(posts, g["lat"], g["lng"], g["name"], radius=150)
                external.append(dict(id=_place_id(g["lat"], g["lng"]), name=g["name"], address=g.get("address") or "",
                                     lat=g["lat"], lng=g["lng"], kind=g.get("kind"), posts=len(nearby),
                                     cover=nearby[0] if nearby else None, source=source))
        except HTTPException:
            source = "unavailable"  # the app falls back to OpenStreetMap
    items = phlio + external
    if lat is not None and lng is not None:
        for p in items:
            p["distance"] = round(_metres(lat, lng, p["lat"], p["lng"]))
    return {"items": items[:40], "external": source}


@router.get("/posts")
async def place_posts(lat: float = Query(ge=-90, le=90), lng: float = Query(ge=-180, le=180),
                      name: str | None = Query(None, max_length=120), sort: str = Query("top", pattern="^(top|recent)$"),
                      user=Depends(get_current_user), c=Depends(get_container)):
    posts = _near(await _geotagged(c, user.id), lat, lng, name)
    if sort == "top":
        posts.sort(key=lambda x: (x["reactions"], x["created_at"]), reverse=True)
    people = {x["author"]["id"]: x["author"] for x in posts if x.get("author")}
    saved = bool(await c.graph.store.get(key("saved_place", user.id, _place_id(lat, lng))))
    return {"place": dict(id=_place_id(lat, lng), name=name or (posts[0]["place"]["name"] if posts else "Location"),
                          address=posts[0]["place"]["address"] if posts else "", lat=lat, lng=lng,
                          posts=len(posts), people=list(people.values())[:6], saved=saved),
            "items": posts[:90]}


@router.get("/area")
async def area(lat: float = Query(ge=-90, le=90), lng: float = Query(ge=-180, le=180),
               radius_km: float = Query(8, gt=0, le=60), user=Depends(get_current_user), c=Depends(get_container)):
    posts = [x for x in await _geotagged(c, user.id)
             if _metres(lat, lng, x["place"]["lat"], x["place"]["lng"]) <= radius_km * 1000]
    return {"items": posts[:150], "places": _group(posts)[:60]}


@router.put("/saved")
async def save_place(body: dict, user=Depends(get_current_user), c=Depends(get_container)):
    """Bookmark a place (toggle): ``{lat, lng, name, address, saved}``."""
    try:
        lat, lng = float(body["lat"]), float(body["lng"])
    except (KeyError, TypeError, ValueError) as exc:
        raise HTTPException(422, "lat and lng are required.") from exc
    rid = key("saved_place", user.id, _place_id(lat, lng))
    if body.get("saved", True):
        await c.graph.store.put(rid, dict(user_id=user.id, lat=lat, lng=lng, name=str(body.get("name") or "")[:120],
                                          address=str(body.get("address") or "")[:200],
                                          created_at=dt.datetime.now(dt.UTC).isoformat()))
    else:
        await c.graph.store.delete(rid)
    return {"saved": bool(body.get("saved", True))}


# -- sharing a place to people, groups and rooms ---------------------------------------------------

from urllib.parse import urlencode  # noqa: E402

from app.api.v1.content import ShareIn, deliver_text  # noqa: E402


def place_link(name: str, lat: float, lng: float, address: str = "", cover: str | None = None) -> str:
    """``phlio://place?...``: the app draws it as a place card that opens the map."""
    fields = {"name": name, "lat": f"{lat:.6f}", "lng": f"{lng:.6f}"}
    if address:
        fields["address"] = address
    if cover:
        fields["cover"] = cover
    return "phlio://place?" + urlencode(fields)


@router.post("/share", status_code=201)
async def share_place(
    body: ShareIn,
    name: str = Query(..., min_length=1, max_length=120),
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    address: str = Query("", max_length=240),
    cover: str | None = Query(None, max_length=600),
    user=Depends(get_current_user),
    c=Depends(get_container),
):
    """Sends a place as a card to a DM, a group, a new group or a room (same
    body as content shares). Tapping the card opens the place on the map."""
    await c.cache.rate_limit(user.id, "share", 30)
    if cover and not (cover.startswith("/media/") or cover.startswith("https://")):
        cover = None
    name = " ".join(name.split())
    text = f"Shared: 📍 {name}\n{place_link(name, lat, lng, ' '.join(address.split()), cover)}"
    return await deliver_text(c, user, body, text)
