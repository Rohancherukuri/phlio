"""Shop domain service: browsing, filtering, and favoriting."""

from __future__ import annotations

import logging

from app.common.exceptions import NotFoundError
from app.domains.shop.entities import Product, Seller, ShopCategory
from app.domains.shop.repository import ShopRepository

logger = logging.getLogger("phlio.shop")


class ShopService:
    def __init__(self, repository: ShopRepository) -> None:
        self._repository = repository

    async def browse(
        self,
        *,
        category: ShopCategory | None,
        max_price_minor_units: int | None,
        cursor: str | None,
        limit: int,
    ) -> tuple[list[Product], str | None]:
        logger.debug(
            "shop.browse category=%s max_price=%s cursor=%s limit=%d",
            category, max_price_minor_units, cursor, limit,
        )
        return await self._repository.list_products(
            category=category,
            max_price_minor_units=max_price_minor_units,
            cursor=cursor,
            limit=limit,
        )

    async def get_product_or_raise(self, product_id: str) -> Product:
        product = await self._repository.get_product(product_id)
        if product is None:
            raise NotFoundError("Product not found.")
        return product

    async def get_seller_or_raise(self, seller_id: str) -> Seller:
        seller = await self._repository.get_seller(seller_id)
        if seller is None:
            raise NotFoundError("Seller not found.")
        return seller

    async def featured_sellers(self, limit: int = 6) -> list[Seller]:
        return await self._repository.list_featured_sellers(limit)

    async def is_favorited_by(self, product_id: str, user_id: str) -> bool:
        return await self._repository.is_favorited_by(product_id, user_id)

    async def toggle_favorite(self, product_id: str, user_id: str) -> Product:
        await self.get_product_or_raise(product_id)
        currently = await self._repository.is_favorited_by(product_id, user_id)
        product = await self._repository.set_favorited(product_id, user_id, not currently)
        logger.info(
            "shop.favorite_toggled product_id=%s user_id=%s favorited=%s",
            product_id, user_id, not currently,
        )
        return product
