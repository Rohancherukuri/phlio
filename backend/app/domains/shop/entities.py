"""Framework-agnostic domain entities for Phlio Shop.

`ShopCategory` lists the full category set from
Phlio_Final_Product_Blueprint.md section 10 so the API contract doesn't
need a breaking change when a second category is seeded; only
`ART_AND_HANDMADE` has real data in this build stage (see
`app/core/seed.py`).
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from enum import StrEnum


class ShopCategory(StrEnum):
    FASHION = "fashion"
    FOOD_AND_GROCERY = "food_and_grocery"
    PHARMA_AND_WELLNESS = "pharma_and_wellness"
    ELECTRONICS = "electronics"
    HOME_AND_LIVING = "home_and_living"
    ART_AND_HANDMADE = "art_and_handmade"
    SPORTS_AND_FITNESS = "sports_and_fitness"
    BOOKS_AND_EDUCATION = "books_and_education"
    BEAUTY_AND_PERSONAL_CARE = "beauty_and_personal_care"
    TOYS_AND_GAMES = "toys_and_games"
    AUTOMOTIVE = "automotive"
    PET_SUPPLIES = "pet_supplies"
    DIGITAL_PRODUCTS = "digital_products"


class ProductCondition(StrEnum):
    """Per blueprint section 10, "Used / new / handmade"."""

    NEW = "new"
    LIKE_NEW = "like_new"
    GOOD = "good"
    USED = "used"
    REFURBISHED = "refurbished"
    HANDMADE = "handmade"
    CUSTOM_MADE = "custom_made"


@dataclass(slots=True)
class Seller:
    """A storefront on Phlio Shop — an artist, brand, retailer, local shop,
    or individual seller (blueprint section 10, "Marketplace roles")."""

    id: str
    user_id: str
    display_name: str
    handle: str
    specialty: str
    bio: str
    followers_count: int = 0


@dataclass(slots=True)
class Product:
    id: str
    seller_id: str
    title: str
    description: str
    category: ShopCategory
    condition: ProductCondition
    price_minor_units: int
    currency: str
    image_urls: list[str] = field(default_factory=list)
    favorite_count: int = 0
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))
