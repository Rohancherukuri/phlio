"""Phlio Book endpoints: listing discovery, booking creation, my bookings.

Mounted at `/book`. Public discovery (like Rooms), authenticated booking —
creating a booking mutates state, so it requires a token per the platform's
blanket rule that mutations go through `get_current_user`.
"""

from __future__ import annotations

import datetime as dt
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.deps import get_activity_service, get_book_service, get_current_user, get_container
from app.core.container import Container
from app.common.pagination import clamp_limit
from app.common.schemas import Page, PageMeta
from app.domains.activity.entities import ActivityKind
from app.domains.activity.service import ActivityService
from app.domains.book.entities import BookCategory, BookListing, Booking, BookingStatus
from app.domains.book.service import BookService
from app.domains.graph.service import key
from app.domains.identity.entities import User

router = APIRouter(prefix="/book", tags=["book"])


class ListingResponse(BaseModel):
    id: str
    title: str
    category: BookCategory
    venue: str
    location_note: str
    description: str
    price_min_minor_units: int
    price_max_minor_units: int
    currency: str
    duration_label: str
    rating: float | None
    starts_at: dt.datetime | None
    is_free: bool
    tags: list[str]
    image_url: str | None = None
    source_url: str | None = None
    source_name: str | None = None
    # Phlio Book verticals (sports, doctor, flight, train, bus, bike, auto,
    # cab, movies, events, concerts, festive, meetups) and how they book:
    # slot | ride | trip | ticket | rsvp | external (provider link).
    vertical: str = "events"
    kind: str = "ticket"
    image_credit: str | None = None
    meta: dict[str, Any] = {}
    # People going (meetups, sports, events, concerts, festivals): everyone
    # with a booking, newest first; `going` previews up to three profiles.
    going_count: int = 0
    going: list[dict[str, Any]] = []

    @classmethod
    def from_entity(cls, listing: BookListing, detail: dict | None = None,
                    going: tuple[int, list[dict]] | None = None) -> ListingResponse:
        detail = detail or {}
        # Imported provider listings (District/Accessly) have no vertical.
        vertical = detail.get("vertical") or ("movies" if "Movies" in listing.tags else "events")
        kind = detail.get("booking_kind") or ("external" if listing.source_url else "ticket")
        return cls(
            going_count=going[0] if going else 0,
            going=going[1] if going else [],
            vertical=vertical,
            kind=kind,
            image_credit=detail.get("image_credit"),
            meta=detail.get("meta") or {},
            id=listing.id,
            title=listing.title,
            category=listing.category,
            venue=listing.venue,
            location_note=listing.location_note,
            description=listing.description,
            price_min_minor_units=listing.price_min_minor_units,
            price_max_minor_units=listing.price_max_minor_units,
            currency=listing.currency,
            duration_label=listing.duration_label,
            rating=listing.rating,
            starts_at=listing.starts_at,
            is_free=listing.is_free,
            tags=listing.tags,
            image_url=listing.image_url,
            source_url=listing.source_url,
            source_name=listing.source_name,
        )


class BookingResponse(BaseModel):
    id: str
    listing_id: str
    title: str
    venue: str
    date: dt.date
    time: dt.time | None
    participants: int
    estimated_total_min_minor_units: int
    estimated_total_max_minor_units: int
    currency: str
    status: BookingStatus
    created_at: dt.datetime
    details: dict[str, str] = {}
    vertical: str | None = None
    image_url: str | None = None

    @classmethod
    def from_entity(cls, booking: Booking, detail: dict | None = None) -> BookingResponse:
        detail = detail or {}
        return cls(
            details=booking.details or {},
            vertical=detail.get("vertical"),
            image_url=detail.get("image_url"),
            id=booking.id,
            listing_id=booking.listing_id,
            title=booking.title,
            venue=booking.venue,
            date=booking.date,
            time=booking.time,
            participants=booking.participants,
            estimated_total_min_minor_units=booking.estimated_total_min_minor_units,
            estimated_total_max_minor_units=booking.estimated_total_max_minor_units,
            currency=booking.currency,
            status=booking.status,
            created_at=booking.created_at,
        )


class CreateBookingRequest(BaseModel):
    listing_id: str
    date: dt.date
    time: dt.time | None = None
    participants: int = Field(default=1, ge=1, le=20)
    details: dict[str, str] = Field(default_factory=dict, max_length=12)


async def _details(c: Container, ids: list[str]) -> dict[str, dict]:
    """platform_content rows (vertical, booking kind, meta, credit) by listing id."""
    if not ids:
        return {}
    rows = await c.graph.store.get_many([key("platform_content", "book", i) for i in ids])
    return {row.get("domain_ref"): row for row in rows if row}


# Kinds priced per person/seat (the total scales with participants).
PER_HEAD = {"ticket", "trip", "rsvp"}

# Verticals that show who's going (the rest show who liked them).
GOING = {"meetups", "sports", "events", "concerts", "festive"}


async def _going(c: Container, ids: list[str]) -> dict[str, tuple[int, list[dict]]]:
    """Booked/attending people per listing, from the graph's activity rows."""
    if not ids:
        return {}
    wanted = {key("phlio_object", "book", i): i for i in ids}
    by_listing: dict[str, list[dict]] = {}
    for row in await c.graph.store.rows("activity", {"verb": "booked"}):
        listing = wanted.get(str(row.get("out")))
        if listing:
            by_listing.setdefault(listing, []).append(row)
    preview_ids = set()
    for rows in by_listing.values():
        rows.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        preview_ids.update(str(r["in"]).removeprefix("user:") for r in rows[:3])
    people = {u.id: c.graph.profile(u) for u in await c.identity_repository.get_many(list(preview_ids))}
    return {
        listing: (len(rows), [people[p] for r in rows[:3]
                              if (p := str(r["in"]).removeprefix("user:")) in people])
        for listing, rows in by_listing.items()
    }


@router.get("/listings", response_model=Page[ListingResponse])
async def browse_listings(
    category: BookCategory | None = Query(default=None),
    max_price_minor_units: int | None = Query(default=None, ge=0),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    book_service: BookService = Depends(get_book_service),
    c: Container = Depends(get_container),
) -> Page[ListingResponse]:
    revision = await c.graph.store.revision()
    cache_key = f'book:catalog:{revision}:{category}:{max_price_minor_units}:{cursor}:{limit}'
    cached = await c.cache.get(cache_key)
    if cached is not None:
        return Page[ListingResponse].model_validate(cached)
    listings, next_cursor = await book_service.browse(
        category=category,
        max_price_minor_units=max_price_minor_units,
        cursor=cursor,
        limit=clamp_limit(limit),
    )
    details = await _details(c, [l.id for l in listings])
    going = await _going(c, [l.id for l in listings
                             if (details.get(l.id) or {}).get("vertical") in GOING])
    page = Page(
        items=[ListingResponse.from_entity(l, details.get(l.id), going.get(l.id)) for l in listings],
        meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None),
    )
    await c.cache.put(cache_key, page.model_dump(mode='json'), ttl=120)
    return page


@router.get("/listings/{listing_id}", response_model=ListingResponse)
async def get_listing(
    listing_id: str,
    book_service: BookService = Depends(get_book_service),
    c: Container = Depends(get_container),
) -> ListingResponse:
    listing = await book_service.get_listing_or_raise(listing_id)
    return ListingResponse.from_entity(listing, (await _details(c, [listing_id])).get(listing_id),
                                       (await _going(c, [listing_id])).get(listing_id))


@router.post(
    "/bookings",
    response_model=BookingResponse,
    status_code=201,
)
async def create_booking(
    payload: CreateBookingRequest,
    book_service: BookService = Depends(get_book_service),
    activity_service: ActivityService = Depends(get_activity_service),
    current_user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
) -> BookingResponse:
    if any(len(k) > 40 or len(v) > 200 for k, v in payload.details.items()):
        raise HTTPException(422, "Booking details are too long.")
    detail = (await _details(c, [payload.listing_id])).get(payload.listing_id) or {}
    booking = await book_service.create_booking(
        user_id=current_user.id,
        listing_id=payload.listing_id,
        date=payload.date,
        time=payload.time,
        participants=payload.participants,
        details=payload.details,
        unit_multiplier=payload.participants if detail.get("booking_kind") in PER_HEAD else 1,
    )
    # You now count as going (and appear in the avatar stack).
    try:
        await c.graph.action(current_user.id, key("phlio_object", "book", payload.listing_id),
                             "booked", trusted=True)
    except Exception:  # the booking itself already succeeded
        pass
    # Cross-domain side effect kept at the API edge: a confirmed booking
    # shows up in the Activity feed without the Book service knowing
    # Activity exists.
    await activity_service.record(
        user_id=current_user.id,
        kind=ActivityKind.BOOK,
        title="Booking confirmed 🎟️",
        body=f"{booking.title} · {booking.venue}, {booking.date.isoformat()}"
        + (f" at {booking.time.strftime('%H:%M')}" if booking.time else ""),
        icon="🎟️",
        ref_id=booking.id,
    )
    return BookingResponse.from_entity(booking, detail)


@router.get("/bookings", response_model=Page[BookingResponse])
async def my_bookings(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    book_service: BookService = Depends(get_book_service),
    current_user: User = Depends(get_current_user),
    c: Container = Depends(get_container),
) -> Page[BookingResponse]:
    bookings, next_cursor = await book_service.my_bookings(
        user_id=current_user.id, cursor=cursor, limit=clamp_limit(limit)
    )
    details = await _details(c, list({b.listing_id for b in bookings}))
    return Page(
        items=[BookingResponse.from_entity(b, details.get(b.listing_id)) for b in bookings],
        meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None),
    )
