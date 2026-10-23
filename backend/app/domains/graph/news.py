"""Publisher RSS ingestion: attributed headlines and links, never full articles."""
import asyncio
import datetime as dt
import hashlib
import logging
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from urllib.parse import urlparse
import httpx
from app.domains.graph.service import key

CATEGORIES = ['Top International', 'For You', 'Blindspot', 'Local News', 'Sports', 'Business', 'Entertainment', 'Science', 'International', 'Technology', 'Politics', 'AI']
FEEDS = [(category, 'The Guardian', f'https://www.theguardian.com/{section}/rss') for category, section in [
 ('International','world'), ('Sports','sport'), ('Business','business'), ('Entertainment','culture'),
 ('Science','science'), ('Technology','technology'), ('Politics','politics'), ('AI','technology/artificialintelligenceai')]] + [
 ('Local News','The Hindu','https://www.thehindu.com/news/cities/Hyderabad/feeder/default.rss')]
log = logging.getLogger(__name__)

def parse_feed(raw, category, publisher):
    root = ET.fromstring(raw)
    result = []
    for item in root.findall('./channel/item')[:25]:
        title, url = item.findtext('title', '').strip(), item.findtext('link', '').strip()
        if not title or urlparse(url).scheme != 'https':
            continue
        try:
            published = parsedate_to_datetime(item.findtext('pubDate', '')).astimezone(dt.UTC).isoformat()
        except (ValueError, TypeError):
            continue
        images = item.findall('{http://search.yahoo.com/mrss/}content') + item.findall('{http://search.yahoo.com/mrss/}thumbnail')
        image = next((e.get('url') for e in images if e.get('url', '').startswith('https://')), None)
        result.append(dict(ref='rss_' + hashlib.sha256(url.encode()).hexdigest()[:24], title=title[:500],
            source_url=url, publisher=publisher, published_at=published, category=category,
            image_url=image, location='Hyderabad' if category == 'Local News' else None))
    return result

async def refresh(c):
    imported = 0
    async with httpx.AsyncClient(timeout=20, follow_redirects=True, headers={'User-Agent':'PhlioNewsReader/1.0'}) as client:
        for category, publisher, url in FEEDS:
            try:
                response = await client.get(url)
                response.raise_for_status()
                if len(response.content) > 4_000_000:
                    raise ValueError('Feed too large')
                articles = parse_feed(response.content, category, publisher)
                for article in articles:
                    ref = article['ref']
                    oid = key('phlio_object', 'news', ref)
                    if not await c.graph.store.get(oid):
                        await c.graph.register_object('platform', 'news.article', ref, article['title'])
                    await c.graph.store.put(key('platform_content', 'news', ref), dict(
                        **article, platform='news', domain_ref=ref, object_id=oid,
                        kind='article', demo=False, description='', fetched_at=dt.datetime.now(dt.UTC).isoformat()))
                    imported += 1
            except (httpx.HTTPError, ET.ParseError, ValueError):
                log.exception('News feed unavailable: %s', publisher)
    return imported

async def run(c):
    while True:
        try:
            await refresh(c)
        except Exception:
            log.exception('News refresh failed; keeping last successful articles')
        await asyncio.sleep(1800)
