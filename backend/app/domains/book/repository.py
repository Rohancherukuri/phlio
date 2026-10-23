"""Repository contract for Phlio Book."""

from __future__ import annotations

import datetime as dt
from typing import Protocol

from app.domains.book.entities import BookListing, BookCategory, Booking


class BookRepository(Protocol):
    async def list_listings(
        self,
        *,
        category: BookCategory | None,
        max_price_minor_units: int | None,
        cursor: str | None,
        limit: int,
    ) -> tuple[list[BookListing], str | None]: ...

    async def get_listing(self, listing_id: str) -> BookListing | None: ...

    async def create_booking(self, booking: Booking) -> Booking: ...

    async def list_bookings(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[Booking], str | None]: ...

    async def listing_has_booking_on(
        self, *, listing_id: str, user_id: str, date: dt.date
    ) -> bool: ...
