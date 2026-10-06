"""Phlio Book endpoints: listing discovery, booking creation, my bookings.

Mounted at `/book`. Public discovery (like Rooms), authenticated booking —
creating a booking mutates state, so it requires a token per the platform's
blanket rule that mutations go through `get_current_user`.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.deps import get_activity_service, get_book_service, get_current_user
from app.common.pagination import clamp_limit
from app.common.schemas import Page, PageMeta
from app.domains.activity.entities import ActivityKind
from app.domains.activity.service import ActivityService
from app.domains.book.entities import BookCategory, BookListing, Booking, BookingStatus
from app.domains.book.service import BookService
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

    @classmethod
    def from_entity(cls, listing: BookListing) -> ListingResponse:
        return cls(
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

    @classmethod
    def from_entity(cls, booking: Booking) -> BookingResponse:
        return cls(
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


@router.get("/listings", response_model=Page[ListingResponse])
async def browse_listings(
    category: BookCategory | None = Query(default=None),
    max_price_minor_units: int | None = Query(default=None, ge=0),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    book_service: BookService = Depends(get_book_service),
) -> Page[ListingResponse]:
    listings, next_cursor = await book_service.browse(
        category=category,
        max_price_minor_units=max_price_minor_units,
        cursor=cursor,
        limit=clamp_limit(limit),
    )
    return Page(
        items=[ListingResponse.from_entity(l) for l in listings],
        meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None),
    )


@router.get("/listings/{listing_id}", response_model=ListingResponse)
async def get_listing(
    listing_id: str, book_service: BookService = Depends(get_book_service)
) -> ListingResponse:
    listing = await book_service.get_listing_or_raise(listing_id)
    return ListingResponse.from_entity(listing)


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
) -> BookingResponse:
    booking = await book_service.create_booking(
        user_id=current_user.id,
        listing_id=payload.listing_id,
        date=payload.date,
        time=payload.time,
        participants=payload.participants,
    )
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
    return BookingResponse.from_entity(booking)


@router.get("/bookings", response_model=Page[BookingResponse])
async def my_bookings(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    book_service: BookService = Depends(get_book_service),
    current_user: User = Depends(get_current_user),
) -> Page[BookingResponse]:
    bookings, next_cursor = await book_service.my_bookings(
        user_id=current_user.id, cursor=cursor, limit=clamp_limit(limit)
    )
    return Page(
        items=[BookingResponse.from_entity(b) for b in bookings],
        meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None),
    )
