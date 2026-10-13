"""Phlio Shop endpoints: browsing/filtering the marketplace and favoriting.

Mounted at `/shop` (not `/art`) per Phlio_Final_Product_Blueprint.md
section 10 — Art & Handmade is a `category` query parameter value, not a
separate route namespace.
"""

from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.deps import get_current_user, get_shop_service, get_container
from app.core.container import Container
from app.domains.graph.service import key
from app.common.pagination import clamp_limit
from app.common.schemas import Page, PageMeta
from app.domains.identity.entities import User
from app.domains.shop.entities import Product, ProductCondition, Seller, ShopCategory
from app.domains.shop.service import ShopService

router = APIRouter(prefix="/shop", tags=["shop"])


class CartQuantity(BaseModel):
    quantity: int = Field(ge=0, le=99)


@router.get('/cart')
async def get_cart(user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    rows = await c.graph.store.rows('shop_cart', {'user_id': user.id})
    items, totals = [], {}
    for row in rows:
        product = await c.shop_repository.get_product(row['product_id'])
        if product is None:
            continue
        subtotal = product.price_minor_units * row['quantity']
        totals[product.currency] = totals.get(product.currency, 0) + subtotal
        items.append({'product': ProductResponse.from_entity(product, favorited_by_me=False),
                      'quantity': row['quantity'], 'subtotal_minor_units': subtotal})
    return {'items': items, 'totals': totals, 'count': sum(i['quantity'] for i in items)}


@router.put('/cart/{product_id}')
async def set_cart_quantity(product_id: str, body: CartQuantity,
                            user: User = Depends(get_current_user), c: Container = Depends(get_container)):
    await c.shop_service.get_product_or_raise(product_id)
    rid = key('shop_cart', user.id, product_id)
    if body.quantity == 0:
        await c.graph.store.delete(rid)
    else:
        await c.graph.store.put(rid, {'user_id': user.id, 'product_id': product_id, 'quantity': body.quantity})
    return await get_cart(user, c)


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
    c: Container = Depends(get_container),
) -> Page[ProductResponse]:
    revision = await c.graph.store.revision()
    version = await c.cache.get('shop:version')
    cache_key = f'shop:catalog:{revision}:{version}:{current_user.id}:{category}:{max_price_minor_units}:{cursor}:{limit}'
    cached = await c.cache.get(cache_key)
    if cached is not None:
        return Page[ProductResponse].model_validate(cached)
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
    page = Page(items=items, meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None))
    await c.cache.put(cache_key, page.model_dump(mode='json'), ttl=60)
    return page


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
    c: Container = Depends(get_container),
) -> ProductResponse:
    product = await shop_service.toggle_favorite(product_id, current_user.id)
    favorited = await shop_service.is_favorited_by(product_id, current_user.id)
    await c.cache.put('shop:version', uuid.uuid4().hex, ttl=86400)
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
