"""Public movie/event discovery, with source links instead of invented tickets."""
import asyncio
import datetime as dt
import hashlib
import json
import re
from decimal import Decimal

import httpx
from app.config import Settings
from app.core.container import build_container
from app.domains.book.entities import BookCategory, BookListing
from app.domains.graph.service import key

MOVIES = 'https://www.district.in/movies/hyderabad-movie-tickets'
EVENTS = 'https://www.accessly.co.in/explore/hyderabad/things-to-do'

def structured(text):
    for attrs, body in re.findall(r'<script([^>]*)>(.*?)</script>', text, re.S):
        if 'ld+json' in attrs:
            try:
                data = json.loads(body)
                yield from data if isinstance(data, list) else [data]
            except ValueError:
                continue

def tag(title):
    value = title.lower()
    for result, words in [
        ('Navratri', ('navratri', 'dandiya', 'garba')),
        ('Comedy', ('comedy', 'standup', 'stand-up', 'comic')),
        ('Sports', ('karting', 'golf', 'gaming', 'smaaash', 'game room', 'vr arena')),
        ('Workshops', ('workshop', 'clay', 'pottery', 'paint', 'vinyl', 'craft')),
        ('Music', ('music', 'concert', 'live band', 'worship', 'singer', 'dj ', 'musical')),
        ('Plays', ('theatre', 'theater', 'play ', 'drama')),
    ]:
        if any(word in value for word in words): return result
    return 'Experiences'

async def main():
    c = await build_container(Settings())
    listings = []
    async with httpx.AsyncClient(timeout=30, follow_redirects=True) as http:
        response = await http.get(MOVIES); response.raise_for_status()
        seen = set()
        for schema in structured(response.text):
            if schema.get('@type') != 'ItemList': continue
            for row in schema.get('itemListElement', []):
                movie = row.get('item', {})
                url = movie.get('url')
                if not url or url in seen or not movie.get('image'): continue
                seen.add(url)
                listings.append(BookListing(id='import_movie_'+hashlib.sha256(url.encode()).hexdigest()[:16],
                    title=movie['name'],category=BookCategory.ENTERTAINMENT,
                    venue='Hyderabad cinemas',location_note='Hyderabad',
                    description='Movie listed by District for Hyderabad. Choose a cinema and confirm showtimes and ticket prices with the provider.',
                    tags=['Movies'], image_url=movie['image'],source_url=url,source_name='District'))
        response = await http.get(EVENTS); response.raise_for_status()
        urls = []
        for schema in structured(response.text):
            if schema.get('@type') == 'ItemList':
                urls += [row['url'] for row in schema.get('itemListElement',[]) if row.get('url')]
        semaphore = asyncio.Semaphore(4)
        async def event(url):
            async with semaphore:
                response = await http.get(url); response.raise_for_status()
                for data in structured(response.text):
                    if data.get('@type') != 'Event': continue
                    image = data.get('image')
                    if isinstance(image,list): image = image[0] if image else None
                    if not image: continue
                    start = dt.datetime.fromisoformat(data['startDate'].replace('Z','+00:00'))
                    end = dt.datetime.fromisoformat(data.get('endDate',data['startDate']).replace('Z','+00:00'))
                    if end < dt.datetime.now(dt.UTC): continue
                    place = data.get('location', {})
                    offer = data.get('offers', {})
                    if isinstance(offer,list): offer = offer[0] if offer else {}
                    price = int(Decimal(str(offer.get('price', 0))) * 100)
                    section = tag(data['name'])
                    return BookListing(id='import_event_'+hashlib.sha256(url.encode()).hexdigest()[:16],
                        title=data['name'], category=BookCategory.SPORTS_AND_ACTIVITIES if section=='Sports' else BookCategory.ENTERTAINMENT,
                        venue=place.get('name','See provider'),location_note='Hyderabad',
                        description=f'{section} at {place.get("name", "the listed venue")}. Check dates, ticket options and availability with Accessly.',
                        price_min_minor_units=price,price_max_minor_units=price,currency=offer.get('priceCurrency','INR'),
                        starts_at=start,is_free='price' in offer and price==0,tags=[section],
                        image_url=image,source_url=url,source_name='Accessly')
        results = await asyncio.gather(*(event(url) for url in dict.fromkeys(urls)), return_exceptions=True)
        for result in results:
            if isinstance(result, BookListing): listings.append(result)
            elif isinstance(result, Exception): print('Skipped unavailable event:', type(result).__name__, flush=True)
    for listing in listings:
        await c.book_repository.seed_listing(listing)
        await c.graph.register_object('demo_000','book.activity',listing.id,listing.title)
        await c.graph.store.put(key('platform_content','book',listing.id),dict(
            platform='book',domain_ref=listing.id,kind='experience',image_url=listing.image_url,
            object_id=key('phlio_object','book',listing.id),description=listing.description,source_url=listing.source_url,source_name=listing.source_name,imported=True))
    await c.cache.close()
    print({'listings':len(listings),'movies':sum('Movies' in l.tags for l in listings),
           'sections': sorted({t for l in listings for t in l.tags})})

if __name__ == '__main__': asyncio.run(main())
