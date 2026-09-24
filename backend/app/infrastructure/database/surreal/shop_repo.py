"""SurrealDB implementation of `ShopRepository`.

Table shape (see `data/surrealdb/schema/shop.surql`), using the `product`/
`seller` naming from Phlio_Final_Product_Blueprint.md section 25 ("Data
Architecture"):

    DEFINE TABLE seller SCHEMAFULL;
    DEFINE FIELD user_id         ON seller TYPE record<user>;
    DEFINE FIELD display_name    ON seller TYPE string;
    DEFINE FIELD handle          ON seller TYPE string;
    DEFINE FIELD specialty       ON seller TYPE string;
    DEFINE FIELD bio             ON seller TYPE string;
    DEFINE FIELD followers_count ON seller TYPE int DEFAULT 0;

    DEFINE TABLE product SCHEMAFULL;
    DEFINE FIELD seller_id          ON product TYPE record<seller>;
    DEFINE FIELD title              ON product TYPE string;
    DEFINE FIELD description        ON product TYPE string;
    DEFINE FIELD category           ON product TYPE string;
    DEFINE FIELD condition          ON product TYPE string;
    DEFINE FIELD price_minor_units  ON product TYPE int;
    DEFINE FIELD currency           ON product TYPE string;
    DEFINE FIELD image_urls         ON product TYPE array<string>;
    DEFINE FIELD favorite_count     ON product TYPE int DEFAULT 0;
    DEFINE FIELD created_at         ON product TYPE datetime DEFAULT time::now();

    -- user -> saved -> product, per blueprint section 25's graph examples.
    DEFINE TABLE saved TYPE RELATION FROM user TO product;
"""

from __future__ import annotations

from surrealdb import Surreal

from app.domains.shop.entities import Product, ProductCondition, Seller, ShopCategory

_PRODUCTS = "product"
_SELLERS = "seller"


def _strip_prefix(record_id: str) -> str:
    return record_id.split(":", 1)[1] if ":" in record_id else record_id


def _row_to_product(row: dict) -> Product:
    return Product(
        id=_strip_prefix(row["id"]),
        seller_id=_strip_prefix(row["seller_id"]),
        title=row["title"],
        description=row.get("description", ""),
        category=ShopCategory(row["category"]),
        condition=ProductCondition(row.get("condition", "new")),
        price_minor_units=row["price_minor_units"],
        currency=row.get("currency", "INR"),
        image_urls=row.get("image_urls", []),
        favorite_count=row.get("favorite_count", 0),
        created_at=row["created_at"],
    )


def _row_to_seller(row: dict) -> Seller:
    return Seller(
        id=_strip_prefix(row["id"]),
        user_id=_strip_prefix(row["user_id"]),
        display_name=row["display_name"],
        handle=row["handle"],
        specialty=row.get("specialty", ""),
        bio=row.get("bio", ""),
        followers_count=row.get("followers_count", 0),
    )


class SurrealShopRepository:
    def __init__(self, db: Surreal) -> None:
        self._db = db

    async def get_product(self, product_id: str) -> Product | None:
        row = await self._db.select(f"{_PRODUCTS}:{product_id}")
        return _row_to_product(row[0] if isinstance(row, list) else row) if row else None

    async def list_products(
        self,
        *,
        category: ShopCategory | None,
        max_price_minor_units: int | None,
        cursor: str | None,
        limit: int,
    ) -> tuple[list[Product], str | None]:
        query = f"SELECT * FROM {_PRODUCTS} "
        params: dict = {"limit": limit + 1}
        clauses = []
        if category is not None:
            clauses.append("category = $category")
            params["category"] = category.value
        if max_price_minor_units is not None:
            clauses.append("price_minor_units <= $max_price")
            params["max_price"] = max_price_minor_units
        if cursor:
            clauses.append("created_at < $cursor")
            params["cursor"] = cursor
        if clauses:
            query += "WHERE " + " AND ".join(clauses) + " "
        query += "ORDER BY created_at DESC LIMIT $limit"

        result = await self._db.query(query, params)
        records = result[0]["result"] if result and result[0].get("result") else []
        has_more = len(records) > limit
        page = records[:limit]
        next_cursor = page[-1]["created_at"].isoformat() if has_more and page else None
        return [_row_to_product(r) for r in page], next_cursor

    async def get_seller(self, seller_id: str) -> Seller | None:
        row = await self._db.select(f"{_SELLERS}:{seller_id}")
        return _row_to_seller(row[0] if isinstance(row, list) else row) if row else None

    async def list_featured_sellers(self, limit: int) -> list[Seller]:
        result = await self._db.query(
            f"SELECT * FROM {_SELLERS} ORDER BY followers_count DESC LIMIT $limit",
            {"limit": limit},
        )
        records = result[0]["result"] if result and result[0].get("result") else []
        return [_row_to_seller(r) for r in records]

    async def is_favorited_by(self, product_id: str, user_id: str) -> bool:
        result = await self._db.query(
            "SELECT VALUE count() FROM saved WHERE in = $user AND out = $product",
            {"user": f"user:{user_id}", "product": f"{_PRODUCTS}:{product_id}"},
        )
        records = result[0]["result"] if result and result[0].get("result") else []
        return bool(records and records[0])

    async def set_favorited(self, product_id: str, user_id: str, favorited: bool) -> Product:
        if favorited:
            await self._db.query(
                "RELATE $user->saved->$product",
                {"user": f"user:{user_id}", "product": f"{_PRODUCTS}:{product_id}"},
            )
            await self._db.query(f"UPDATE {_PRODUCTS}:{product_id} SET favorite_count += 1")
        else:
            await self._db.query(
                "DELETE saved WHERE in = $user AND out = $product",
                {"user": f"user:{user_id}", "product": f"{_PRODUCTS}:{product_id}"},
            )
            await self._db.query(
                f"UPDATE {_PRODUCTS}:{product_id} SET favorite_count = math::max([favorite_count - 1, 0])"
            )
        product = await self.get_product(product_id)
        assert product is not None
        return product
