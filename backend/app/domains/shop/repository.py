"""Repository contract for the shop domain."""

from __future__ import annotations

from typing import Protocol

from app.domains.shop.entities import Product, Seller, ShopCategory


class ShopRepository(Protocol):
    async def get_product(self, product_id: str) -> Product | None: ...

    async def list_products(
        self,
        *,
        category: ShopCategory | None,
        max_price_minor_units: int | None,
        cursor: str | None,
        limit: int,
    ) -> tuple[list[Product], str | None]: ...

    async def get_seller(self, seller_id: str) -> Seller | None: ...

    async def list_featured_sellers(self, limit: int) -> list[Seller]: ...

    async def is_favorited_by(self, product_id: str, user_id: str) -> bool: ...

    async def set_favorited(self, product_id: str, user_id: str, favorited: bool) -> Product: ...
