"""Durable Book listings and reservations."""

import datetime as dt
import uuid
from dataclasses import asdict

from app.domains.book.entities import BookCategory, Booking, BookingStatus, BookListing
from app.infrastructure.database.memory.social_repo import _paginate
from app.infrastructure.database.surreal.client import record


class SurrealBookRepository:
    def __init__(self, db):
        self._db = db

    @staticmethod
    def listing(row):
        row = dict(row)
        row["id"] = row["id"].split(":", 1)[1]
        row["category"] = BookCategory(row["category"])
        return BookListing(**row)

    async def seed_listing(self, listing):
        data = asdict(listing)
        data.pop("id")
        await self._db.query(
            "UPSERT $id CONTENT $data", {"id": record("book_listing:" + listing.id), "data": data}
        )

    async def get_listing(self, listing_id):
        row = await self._db.select("book_listing:" + listing_id)
        if isinstance(row, list):
            row = row[0] if row else None
        return self.listing(row) if row else None

    async def list_listings(self, *, category, max_price_minor_units, cursor, limit):
        rows = await self._db.rows("SELECT * FROM book_listing ORDER BY id")
        items = [
            self.listing(r)
            for r in rows
            if (category is None or r["category"] == category.value)
            and (max_price_minor_units is None or r["price_min_minor_units"] <= max_price_minor_units)
        ]
        return _paginate(items, cursor=cursor, limit=limit)

    async def create_booking(self, booking):
        if not booking.id:
            booking.id = "bkg_" + uuid.uuid4().hex
        data = asdict(booking)
        data.pop("id")
        data["date"] = booking.date.isoformat()
        data["time"] = booking.time.isoformat() if booking.time else None
        await self._db.create("booking:" + booking.id, data)
        return booking

    async def list_bookings(self, *, user_id, cursor, limit):
        rows = await self._db.rows(
            "SELECT * FROM booking WHERE user_id=$user ORDER BY created_at DESC", {"user": user_id}
        )
        items = []
        for row in rows:
            row["id"] = row["id"].split(":", 1)[1]
            row["date"] = dt.date.fromisoformat(row["date"])
            row["time"] = dt.time.fromisoformat(row["time"]) if row.get("time") else None
            row["status"] = BookingStatus(row["status"])
            items.append(Booking(**row))
        return _paginate(items, cursor=cursor, limit=limit)

    async def listing_has_booking_on(self, *, listing_id, user_id, date):
        rows = await self._db.rows(
            "SELECT id FROM booking WHERE user_id=$user AND listing_id=$listing "
            'AND date=$date AND status="confirmed" LIMIT 1',
            {"user": user_id, "listing": listing_id, "date": date.isoformat()},
        )
        return bool(rows)
