"""
NewsAPI.org headlines for Phlio News (https://newsapi.org/docs/endpoints/top-headlines).

Runs alongside the publisher RSS feeds in ``news.py``: for each NewsAPI
category we store the headline, a short description, the publisher's name,
image and a link to the original article — never the article body — in
``platform_content`` with ``platform='news'``, like the RSS items.

The key (``NEWS_API_KEY``) is sent as the ``X-Api-Key`` header from the
server only. NewsAPI's free Developer plan allows 100 requests a day and is
meant for development; we fetch the 7 categories at most every
``NEWS_API_INTERVAL_MINUTES`` (default 180 → 56 requests a day). Use a paid
plan for a public production launch.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import logging
from urllib.parse import urlparse

import httpx

log = logging.getLogger(__name__)
URL = "https://newsapi.org/v2/top-headlines"
# NewsAPI category -> Phlio News tab
CATEGORIES = {
    "general": "Top International",
    "business": "Business",
    "entertainment": "Entertainment",
    "science": "Science",
    "health": "Science",
    "sports": "Sports",
    "technology": "Technology",
}


def parse(payload: dict, category: str) -> list[dict]:
    out = []
    for a in payload.get("articles") or []:
        title, url = (a.get("title") or "").strip(), (a.get("url") or "").strip()
        if not title or title == "[Removed]" or urlparse(url).scheme != "https":
            continue
        publisher = ((a.get("source") or {}).get("name") or urlparse(url).netloc).strip()
        # Headlines usually end with " - Publisher"; the publisher is shown separately.
        if publisher and title.endswith(" - " + publisher):
            title = title[: -len(publisher) - 3].strip()
        try:
            published = dt.datetime.fromisoformat((a.get("publishedAt") or "").replace("Z", "+00:00")).astimezone(dt.UTC)
        except ValueError:
            continue
        image = a.get("urlToImage") or None
        if image and urlparse(image).scheme != "https":
            image = None
        out.append(dict(
            ref="napi_" + hashlib.sha256(url.encode()).hexdigest()[:24], title=title[:500], source_url=url,
            publisher=publisher[:120] or "NewsAPI", published_at=published.isoformat(), category=category,
            image_url=image, location=None, summary=(a.get("description") or "").strip()[:280],
        ))
    return out


async def fetch(client: httpx.AsyncClient, api_key: str, country: str = "us") -> list[dict]:
    articles: list[dict] = []
    for news_category, phlio_category in CATEGORIES.items():
        try:
            r = await client.get(URL, params={"country": country, "category": news_category, "pageSize": 20},
                                 headers={"X-Api-Key": api_key})
            if r.status_code in (401, 426, 429):
                log.warning("NewsAPI refused (%s): %s", r.status_code, (r.json() or {}).get("code"))
                break  # bad key / plan / daily limit — stop for this round
            r.raise_for_status()
            articles += parse(r.json(), phlio_category)
        except (httpx.HTTPError, ValueError):
            log.exception("NewsAPI category unavailable: %s", news_category)
    return articles
