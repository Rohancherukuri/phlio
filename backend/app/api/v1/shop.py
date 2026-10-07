"""Phlio Shop endpoints: browsing/filtering the marketplace and favoriting.

Mounted at `/shop` (not `/art`) per Phlio_Final_Product_Blueprint.md
section 10 — Art & Handmade is a `category` query parameter value, not a
separate route namespace.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.api.deps import get_current_user, get_shop_service
from app.common.pagination import clamp_limit
from app.common.schemas import Page, PageMeta
from app.domains.identity.entities import User
from app.domains.shop.entities import Product, ProductCondition, Seller, ShopCategory
from app.domains.shop.service import ShopService

router = APIRouter(prefix="/shop", tags=["shop"])


class ProductResponse(BaseModel):
    id: str
    seller_id: str
    title: str
    description: str
    category: ShopCategory
    condition: ProductCondition
    price_minor_units: int
    currency: str
    image_urls: list[str]
    favorite_count: int
    created_at: dt.datetime
    favorited_by_me: bool

    @classmethod
    def from_entity(cls, product: Product, *, favorited_by_me: bool) -> ProductResponse:
        return cls(
            id=product.id,
            seller_id=product.seller_id,
            title=product.title,
            description=product.description,
            category=product.category,
            condition=product.condition,
            price_minor_units=product.price_minor_units,
            currency=product.currency,
            image_urls=product.image_urls,
            favorite_count=product.favorite_count,
            created_at=product.created_at,
            favorited_by_me=favorited_by_me,
        )


class SellerResponse(BaseModel):
    id: str
    user_id: str
    display_name: str
    handle: str
    specialty: str
    bio: str
    followers_count: int

    @classmethod
    def from_entity(cls, seller: Seller) -> SellerResponse:
        return cls(
            id=seller.id,
            user_id=seller.user_id,
            display_name=seller.display_name,
            handle=seller.handle,
            specialty=seller.specialty,
            bio=seller.bio,
            followers_count=seller.followers_count,
        )


@router.get("/products", response_model=Page[ProductResponse])
async def browse_products(
    category: ShopCategory | None = Query(default=None),
    max_price_minor_units: int | None = Query(default=None, ge=0),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    shop_service: ShopService = Depends(get_shop_service),
    current_user: User = Depends(get_current_user),
) -> Page[ProductResponse]:
    products, next_cursor = await shop_service.browse(
        category=category,
        max_price_minor_units=max_price_minor_units,
        cursor=cursor,
        limit=clamp_limit(limit),
    )
    items = [
        ProductResponse.from_entity(
            p, favorited_by_me=await shop_service.is_favorited_by(p.id, current_user.id)
        )
        for p in products
    ]
    return Page(items=items, meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None))


@router.get("/products/{product_id}", response_model=ProductResponse)
async def get_product(
    product_id: str,
    shop_service: ShopService = Depends(get_shop_service),
    current_user: User = Depends(get_current_user),
) -> ProductResponse:
    product = await shop_service.get_product_or_raise(product_id)
    favorited = await shop_service.is_favorited_by(product_id, current_user.id)
    return ProductResponse.from_entity(product, favorited_by_me=favorited)


@router.post("/products/{product_id}/favorite", response_model=ProductResponse)
async def toggle_favorite(
    product_id: str,
    shop_service: ShopService = Depends(get_shop_service),
    current_user: User = Depends(get_current_user),
) -> ProductResponse:
    product = await shop_service.toggle_favorite(product_id, current_user.id)
    favorited = await shop_service.is_favorited_by(product_id, current_user.id)
    return ProductResponse.from_entity(product, favorited_by_me=favorited)


@router.get("/sellers/featured", response_model=list[SellerResponse])
async def featured_sellers(
    limit: int = Query(default=6, ge=1, le=20),
    shop_service: ShopService = Depends(get_shop_service),
) -> list[SellerResponse]:
    sellers = await shop_service.featured_sellers(limit)
    return [SellerResponse.from_entity(s) for s in sellers]


@router.get("/sellers/{seller_id}", response_model=SellerResponse)
async def get_seller(seller_id: str, shop_service: ShopService = Depends(get_shop_service)) -> SellerResponse:
    seller = await shop_service.get_seller_or_raise(seller_id)
    return SellerResponse.from_entity(seller)
