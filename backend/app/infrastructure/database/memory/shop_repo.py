"""In-memory implementation of `ShopRepository`."""

from __future__ import annotations

import asyncio

from app.domains.shop.entities import Product, Seller, ShopCategory
from app.infrastructure.database.memory.social_repo import _paginate


class InMemoryShopRepository:
    def __init__(self) -> None:
        self._products: dict[str, Product] = {}
        self._products_newest_first: list[Product] = []
        self._sellers: dict[str, Seller] = {}
        self._favorites: set[tuple[str, str]] = set()
        self._lock = asyncio.Lock()

    # -- seeding helpers (used by app/core/seed.py; intentionally not part
    # -- of the ShopRepository Protocol -- these exist only on the in-memory
    # -- implementation, mirroring how a real seed script would use
    # -- SurrealDB's own `INSERT` directly rather than the repository.) ------
    async def seed_seller(self, seller: Seller) -> None:
        self._sellers[seller.id] = seller

    async def seed_product(self, product: Product) -> None:
        self._products[product.id] = product
        self._products_newest_first.append(product)
        self._products_newest_first.sort(key=lambda p: p.created_at, reverse=True)

    async def get_product(self, product_id: str) -> Product | None:
        return self._products.get(product_id)

    async def list_products(
        self,
        *,
        category: ShopCategory | None,
        max_price_minor_units: int | None,
        cursor: str | None,
        limit: int,
    ) -> tuple[list[Product], str | None]:
        items = self._products_newest_first
        if category is not None:
            items = [p for p in items if p.category == category]
        if max_price_minor_units is not None:
            items = [p for p in items if p.price_minor_units <= max_price_minor_units]
        return _paginate(items, cursor=cursor, limit=limit)

    async def get_seller(self, seller_id: str) -> Seller | None:
        return self._sellers.get(seller_id)

    async def list_featured_sellers(self, limit: int) -> list[Seller]:
        ranked = sorted(self._sellers.values(), key=lambda s: s.followers_count, reverse=True)
        return ranked[:limit]

    async def is_favorited_by(self, product_id: str, user_id: str) -> bool:
        return (product_id, user_id) in self._favorites

    async def set_favorited(self, product_id: str, user_id: str, favorited: bool) -> Product:
        async with self._lock:
            product = self._products[product_id]
            key = (product_id, user_id)
            if favorited and key not in self._favorites:
                self._favorites.add(key)
                product.favorite_count += 1
            elif not favorited and key in self._favorites:
                self._favorites.discard(key)
                product.favorite_count = max(0, product.favorite_count - 1)
            return product
