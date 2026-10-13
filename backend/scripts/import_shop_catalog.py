"""Import a bounded catalog from public retailer feeds; never place orders.

Descriptions are original short factual labels, not copied retailer marketing.
Source URL and retrieval date remain visible in each listing. Prices are USD
snapshots for comparison, not an assertion of Phlio stock or a seller partnership.
"""
import asyncio
import datetime as dt
from decimal import Decimal

import httpx
from app.config import Settings
from app.core.container import build_container
from app.domains.graph.service import key
from app.infrastructure.database.surreal.client import record

SOURCES = [
    ('allbirds', 'Allbirds', 'https://www.allbirds.com', 'fashion'),
    ('colourpop', 'ColourPop', 'https://colourpop.com', 'beauty_and_personal_care'),
    ('deathwish', 'Death Wish Coffee', 'https://www.deathwishcoffee.com', 'food_and_grocery'),
    ('westpaw', 'West Paw', 'https://www.westpaw.com', 'pet_supplies'),
    ('keychron', 'Keychron', 'https://www.keychron.com', 'electronics'),
    ('gaia', 'Gaia Herbs', 'https://www.gaiaherbs.com', 'pharma_and_wellness'),
    ('manduka', 'Manduka', 'https://www.manduka.com', 'sports_and_fitness'),
    ('dover', 'Dover Publications', 'https://store.doverpublications.com', 'books_and_education'),
    ('drool', 'DROOL', 'https://drool-art.com', 'art_and_handmade'),
    ('melissa', 'Melissa & Doug', 'https://www.melissaanddoug.com', 'toys_and_games'),
    ('chemicalguys', 'Chemical Guys', 'https://www.chemicalguys.com', 'automotive'),
    ('cymatics', 'Cymatics', 'https://cymatics.fm', 'digital_products'),
]

def normalize(source, product):
    code, brand, origin, category = source
    title = product['title']
    kind = product.get('product_type', '')
    if any(word in title.lower() for word in ('test product', 'gift card', 'sign', 'display', 'replacement', 'hidden', 'employee', 'wholesale')):
        return None
    variant = next((v for v in product.get('variants', []) if v.get('available') and Decimal(v['price']) > 0), None)
    if not variant or not product.get('images'):
        return None
    if code == 'deathwish' and any(word in kind.lower() for word in ('drinkware', 'mug')):
        category = 'home_and_living'
    return dict(id=f'import_{code}_{product["id"]}', title=title, category=category,
        price_minor_units=int(Decimal(variant['price']) * 100), currency='GBP' if code == 'drool' else 'USD',
        image_urls=[im['src'] for im in product['images'][:3]],
        source_url=origin+'/products/'+product['handle'], source_name=brand,
        description=f'{brand} · {kind or category.replace("_", " ")}.\n'
                    f'Listed option: {variant["title"]}.\n'
                    f'Imported price snapshot ({dt.date.today().isoformat()}); confirm options, availability and final price at the retailer.\n'
                    f'{origin}/products/{product["handle"]}')

async def main():
    c = await build_container(Settings())
    if c.graph.store.db is None:
        raise RuntimeError('A persistent SurrealDB configuration is required.')
    count = 0
    categories = {}
    async with httpx.AsyncClient(timeout=30, follow_redirects=True) as http:
        for source in SOURCES:
            code, brand, origin, category = source
            response = await http.get(origin+'/products.json?limit=50')
            response.raise_for_status()
            selected = [p for raw in response.json()['products'] if (p := normalize(source, raw))][:8]
            seller = 'import_'+code
            await c.graph.store.db.query('UPSERT $id CONTENT $data', {
                'id': record('seller:'+seller), 'data': dict(user_id=record('user:demo_000'),
                display_name=brand+' catalog', handle=code, specialty=category,
                bio='Imported public catalog. No seller partnership implied.', followers_count=0)})
            for item in selected:
                rid = item.pop('id')
                source_url, source_name = item.pop('source_url'), item.pop('source_name')
                existing = await c.shop_repository.get_product(rid)
                item.update(seller_id=record('seller:'+seller), condition='new',
                    favorite_count=existing.favorite_count if existing else 0,
                    created_at=existing.created_at if existing else dt.datetime.now(dt.UTC))
                await c.graph.store.db.query('UPSERT $id CONTENT $data', {'id':record('product:'+rid), 'data':item})
                await c.graph.register_object('demo_000', 'shop.product', rid, item['title'])
                await c.graph.store.put(key('platform_content','shop',rid), dict(platform='shop',domain_ref=rid,
                    kind='product',description=item['description'],image_url=item['image_urls'][0],
                    object_id=key('phlio_object','shop',rid),source_url=source_url,source_name=source_name,imported=True))
                count += 1
                categories[item['category']] = categories.get(item['category'],0)+1
            print(brand, len(selected), flush=True)
    await c.cache.close()
    print({'imported':count,'categories':categories})

if __name__ == '__main__':
    asyncio.run(main())
