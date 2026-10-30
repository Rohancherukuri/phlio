"""Refresh Stream's free catalogs in the isolated graph demo database."""
import asyncio
from app.core.container import build_container
from app.domains.stream.catalog import refresh, details
from scripts.run_graph_demo import settings


async def main():
    c = await build_container(settings)
    try:
        await refresh(c)
        rows = await c.graph.store.rows('platform_content', {'platform': 'stream'})
        providers = {}
        for row in rows:
            if row.get('provider'):
                providers[row['provider']] = providers.get(row['provider'], 0) + 1
        print('Stream catalog:', providers)
        for provider in ('tvmaze', 'kitsu', 'jikan'):
            first = next((r for r in rows if r.get('provider') == provider), None)
            if first:
                item = await details(c, first['domain_ref'])
                print(provider, 'detail:', item['title'], 'episodes:', item.get('episode_count'),
                      'viewing links:', len(item.get('watch_links', [])),
                      'cached fallback:', item.get('details_unavailable', False))
    finally:
        await c.cache.close()
        if c.graph.store.db:
            await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == '__main__':
    asyncio.run(main())
