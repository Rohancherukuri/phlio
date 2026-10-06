"""In-memory implementation of `BookRepository` (and the backing store for
the Activity feed's real-time items — Activity stays ephemeral in this build
stage, exactly like Agent conversation history)."""

from __future__ import annotations

import asyncio
import datetime as dt

from app.domains.book.entities import BookCategory, BookListing, Booking
from app.infrastructure.database.memory.social_repo import _paginate


class InMemoryBookRepository:
    def __init__(self) -> None:
        self._listings: dict[str, BookListing] = {}
        self._listings_ordered: list[BookListing] = []
        self._bookings: dict[str, Booking] = {}
        self._bookings_by_user: dict[str, list[Booking]] = {}
        self._lock = asyncio.Lock()

    # -- seeding helper (used by app/core/seed.py, not part of Protocol) ----
    async def seed_listing(self, listing: BookListing) -> None:
        self._listings[listing.id] = listing
        self._listings_ordered.append(listing)

    async def list_listings(
        self,
        *,
        category: BookCategory | None,
        max_price_minor_units: int | None,
        cursor: str | None,
        limit: int,
    ) -> tuple[list[BookListing], str | None]:
        items = self._listings_ordered
        if category is not None:
            items = [l for l in items if l.category == category]
        if max_price_minor_units is not None:
            items = [l for l in items if l.price_min_minor_units <= max_price_minor_units]
        return _paginate(items, cursor=cursor, limit=limit)

    async def get_listing(self, listing_id: str) -> BookListing | None:
        return self._listings.get(listing_id)

    async def create_booking(self, booking: Booking) -> Booking:
        async with self._lock:
            self._bookings[booking.id] = booking
            self._bookings_by_user.setdefault(booking.user_id, []).insert(0, booking)
            return booking

    async def list_bookings(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[Booking], str | None]:
        return _paginate(self._bookings_by_user.get(user_id, []), cursor=cursor, limit=limit)

    async def listing_has_booking_on(
        self, *, listing_id: str, user_id: str, date: dt.date
    ) -> bool:
        return any(
            b.listing_id == listing_id
            and b.date == date
            and b.status.value == "confirmed"
            for b in self._bookings_by_user.get(user_id, [])
        )
