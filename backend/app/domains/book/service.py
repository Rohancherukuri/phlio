"""Book domain service: discovery, booking, and my-bookings.

Deliberately the only place that knows the booking rules (no duplicate
bookings for the same listing/day, free listings are first-class, price
ranges stay ranges). HTTP layers and the Agent tool layer call this service
— they never touch the repository directly.
"""

from __future__ import annotations

import datetime as dt
import logging

from app.common.exceptions import ConflictError, NotFoundError, ValidationAppError
from app.domains.book.entities import BookCategory, BookListing, Booking, BookingStatus
from app.domains.book.repository import BookRepository

logger = logging.getLogger("phlio.book")

MAX_PARTICIPANTS = 20


class BookService:
    def __init__(self, repository: BookRepository) -> None:
        self._repository = repository

    async def browse(
        self,
        *,
        category: BookCategory | None,
        max_price_minor_units: int | None,
        cursor: str | None,
        limit: int,
    ) -> tuple[list[BookListing], str | None]:
        return await self._repository.list_listings(
            category=category,
            max_price_minor_units=max_price_minor_units,
            cursor=cursor,
            limit=limit,
        )

    async def get_listing_or_raise(self, listing_id: str) -> BookListing:
        listing = await self._repository.get_listing(listing_id)
        if listing is None:
            raise NotFoundError("Listing not found.")
        return listing

    async def create_booking(
        self,
        *,
        user_id: str,
        listing_id: str,
        date: dt.date,
        time: dt.time | None,
        participants: int,
    ) -> Booking:
        if participants < 1 or participants > MAX_PARTICIPANTS:
            raise ValidationAppError(f"Participants must be between 1 and {MAX_PARTICIPANTS}.")
        if date < dt.date.today():
            raise ValidationAppError("Booking date cannot be in the past.")

        listing = await self.get_listing_or_raise(listing_id)
        if await self._repository.listing_has_booking_on(
            listing_id=listing_id, user_id=user_id, date=date
        ):
            raise ConflictError("You already have a booking for this listing on that date.")

        booking = Booking(
            id="",  # assigned by the repository/core engine
            user_id=user_id,
            listing_id=listing.id,
            title=listing.title,
            venue=listing.venue,
            date=date,
            time=time,
            participants=participants,
            estimated_total_min_minor_units=listing.price_min_minor_units,
            estimated_total_max_minor_units=listing.price_max_minor_units,
            currency=listing.currency,
            status=BookingStatus.CONFIRMED,
        )
        created = await self._repository.create_booking(booking)
        logger.info(
            "book.created booking_id=%s listing_id=%s user_id=%s date=%s participants=%d",
            created.id, listing_id, user_id, date.isoformat(), participants,
        )
        return created

    async def my_bookings(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[Booking], str | None]:
        return await self._repository.list_bookings(user_id=user_id, cursor=cursor, limit=limit)
