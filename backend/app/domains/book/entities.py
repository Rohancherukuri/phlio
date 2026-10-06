"""Framework-agnostic domain entities for Phlio Book.

Per Phlio_Final_Product_Blueprint.md section 9: **Book = acquire access to
an experience/service/transport/venue/time slot** (Shop = acquire products).
Every Book subdomain (movies, sports, services, meet, travel) shares one
booking abstraction, so `BookListing` + `Booking` intentionally stay generic
rather than modelling a movie ticket differently from a badminton court.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from enum import StrEnum


class BookCategory(StrEnum):
    ENTERTAINMENT = "entertainment"
    SPORTS_AND_ACTIVITIES = "sports_and_activities"
    MOBILITY = "mobility"
    SERVICES = "services"
    MEET = "meet"
    TRAVEL = "travel"


class BookingStatus(StrEnum):
    CONFIRMED = "confirmed"
    CANCELLED = "cancelled"
    COMPLETED = "completed"


@dataclass(slots=True)
class BookListing:
    """A bookable experience/venue/time slot shown in discovery."""

    id: str
    title: str
    category: BookCategory
    venue: str
    location_note: str = ""
    description: str = ""
    # Estimated price range for the whole experience, in minor units
    # (paise). A range, never a hard quote — blueprint section 10's rule
    # that displayed ETAs/prices are estimates applies here too.
    price_min_minor_units: int = 0
    price_max_minor_units: int = 0
    currency: str = "INR"
    duration_label: str = ""
    rating: float | None = None
    starts_at: dt.datetime | None = None
    is_free: bool = False
    tags: list[str] = field(default_factory=list)


@dataclass(slots=True)
class Booking:
    """A user's reservation against a `BookListing`."""

    id: str
    user_id: str
    listing_id: str
    # Snapshot of the listing at booking time — the listing can change or
    # be delisted later; the booking is the user's record of what they
    # agreed to (mirrors the blueprint's shared booking abstraction).
    title: str
    venue: str
    date: dt.date
    time: dt.time | None = None
    participants: int = 1
    estimated_total_min_minor_units: int = 0
    estimated_total_max_minor_units: int = 0
    currency: str = "INR"
    status: BookingStatus = BookingStatus.CONFIRMED
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))
