"""No-key discovery sources. Metadata never implies permission to stream.

Provider data is persisted in the graph, including attribution. Only the explicitly
licensed open-film allowlist has media URLs. Failed refreshes retain older data.
"""
import asyncio
import html
import logging
import re
import time
from urllib.parse import urlparse

import httpx

from app.domains.graph.service import key

log = logging.getLogger(__name__)
_lock = asyncio.Lock()
_details_lock = asyncio.Lock()
_refresh_tasks = {}
TTL = 86400


def clean(value):
    return html.unescape(re.sub(r"<[^>]*>", "", str(value or ""))).strip()


def link(value):
    value = str(value or "")
    return value if urlparse(value).scheme in {"https", "http"} else None


def tv(show):
    return dict(
        domain_ref=f"tvmaze-{show['id']}", title=show['name'], kind="series",
        category="TV Series", provider="tvmaze", provider_id=show['id'],
        publisher="TVmaze", source_url=show.get('url'),
        attribution="TVmaze · CC BY-SA 4.0 · normalized for Phlio",
        license_url="https://creativecommons.org/licenses/by-sa/4.0/",
        description=clean(show.get('summary')), image_url=(show.get('image') or {}).get('original'),
        genres=show.get('genres') or [], language=show.get('language'),
        released=show.get('premiered'), status=show.get('status'),
        runtime=show.get('averageRuntime') or show.get('runtime'),
        rating=(show.get('rating') or {}).get('average'),
        watch_links=[dict(name="Official show website", url=link(show['officialSite']))]
        if link(show.get('officialSite')) else [], media_url=None,
    )


def anime(show):
    return dict(
        domain_ref=f"jikan-{show['mal_id']}", title=show.get('title_english') or show['title'],
        kind="series", category="Anime", provider="jikan", provider_id=show['mal_id'],
        publisher="MyAnimeList via Jikan", source_url=show.get('url'),
        attribution="Anime information from MyAnimeList via the open-source Jikan API",
        description=clean(show.get('synopsis')),
        image_url=((show.get('images') or {}).get('jpg') or {}).get('large_image_url'),
        genres=[g['name'] for g in show.get('genres', [])],
        studio=', '.join(s['name'] for s in show.get('studios', [])),
        released=(show.get('aired') or {}).get('from'), status=show.get('status'),
        duration=show.get('duration'), episode_count=show.get('episodes'),
        rating=show.get('score'), age_rating=show.get('rating'),
        trailer_url=link((show.get('trailer') or {}).get('url')),
        watch_links=[dict(name=s['name'], url=link(s.get('url')))
                     for s in show.get('streaming', []) if link(s.get('url'))],
        media_url=None,
    )


def kitsu(payload):
    show = payload['data']
    a = show['attributes']
    included = payload.get('included', [])
    return dict(domain_ref=f"kitsu-{show['id']}", title=a['canonicalTitle'], kind='series',
        category='Anime', provider='kitsu', provider_id=int(show['id']), publisher='Kitsu',
        source_url=f"https://kitsu.app/anime/{a['slug']}", attribution='Anime information from Kitsu',
        description=clean(a.get('synopsis')), image_url=(a.get('posterImage') or {}).get('large'),
        genres=[x['attributes']['name'] for x in included if x['type'] == 'genres'],
        released=a.get('startDate'), status=a.get('status'), runtime=a.get('episodeLength'),
        episode_count=a.get('episodeCount'), age_rating=a.get('ageRatingGuide') or a.get('ageRating'),
        rating=round(float(a['averageRating']) / 10, 2) if a.get('averageRating') else None,
        trailer_url=f"https://www.youtube.com/watch?v={a['youtubeVideoId']}" if a.get('youtubeVideoId') else None,
        watch_links=[dict(name=urlparse(x['attributes']['url']).netloc,
                         url=link(x['attributes']['url'])) for x in included
                     if x['type'] == 'streamingLinks' and link(x['attributes'].get('url'))],
        media_url=None)


def films():
    # Unmodified films, including original end credits; never substitute trailers.
    rows = [
        ('big-buck-bunny', 'Big Buck Bunny', '2008', 'Sacha Goedegebure', 10,
         'A gentle rabbit confronts three woodland bullies in this animated comedy.',
         'https://peach.blender.org/', 'BigBuckBunny', ['Animation', 'Comedy']),
        ('tears-of-steel', 'Tears of Steel', '2012', 'Ian Hubert', 12,
         'In a future Amsterdam, a team attempts to resolve a conflict between humans and robots.',
         'https://mango.blender.org/', 'TearsOfSteel', ['Science fiction', 'Short film']),
    ]
    return [dict(domain_ref='open-film-' + ref, title=title, kind='movie', category='Movies',
                 provider='blender', publisher='Blender Foundation', source_url=source,
                 attribution=f'{title} © Blender Foundation · CC BY 3.0 · Original film, credits preserved',
                 license_url='https://creativecommons.org/licenses/by/3.0/',
                 description=description, released=year, director=director, runtime=runtime,
                 genres=genres, language='English', status='Released',
                 image_url='/media/live_recordings/big-buck-bunny.jpg' if ref == 'big-buck-bunny' else '/media/licensed_social/tears-video-00-cover-v2.jpg',
                 media_url='/media/live_recordings/big-buck-bunny.mp4' if ref == 'big-buck-bunny' else 'https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov',
                 watch_links=[]) for ref,title,year,director,runtime,description,source,filename,genres in rows]


async def fetch(url):
    # URLs are constructed solely from fixed provider hosts and integer IDs.
    async with httpx.AsyncClient(timeout=httpx.Timeout(8, connect=4), follow_redirects=True) as client:
        response = await client.get(url, headers={'User-Agent': 'Phlio/1.0 catalog'})
        response.raise_for_status()
        return response.json()


async def save(c, row):
    ref = row['domain_ref']
    obj = await c.graph.register_object('platform', 'stream.' + row['kind'], ref, row['title'])
    await c.graph.store.put(key('platform_content', 'stream', ref),
                           dict(row, platform='stream', object_id=obj['id'], demo=False))


async def ensure_catalog(c):
    marker = await c.graph.store.get(key('stream_catalog_state', 'providers-v1'))
    if not marker:
        await refresh(c)
    elif marker.get('next_refresh', 0) <= time.time() and id(c) not in _refresh_tasks:
        # Existing shelves stay responsive while a provider is offline.
        async def update():
            try:
                await refresh(c)
            except Exception:
                log.exception('Stream background refresh failed; retained saved catalog')
            finally:
                _refresh_tasks.pop(id(c), None)
        _refresh_tasks[id(c)] = asyncio.create_task(update())


async def refresh(c):
    """Persist a small, balanced starter catalog; retry failed providers in 5 minutes."""
    async with _lock:
        marker_id = key('stream_catalog_state', 'providers-v1')
        marker = await c.graph.store.get(marker_id) or {}
        if marker.get('next_refresh', 0) > time.time():
            return
        if not marker.get('films_loaded'):
            from app.core.container import media_root_path
            root = media_root_path(c.settings)
            for row in films():
                if row['domain_ref'] == 'open-film-tears-of-steel' and (root / 'stream_films/tears-of-steel.mp4').exists():
                    row['media_url'] = '/media/stream_films/tears-of-steel.mp4'
                for field in ('media_url', 'image_url'):
                    value = row.get(field) or ''
                    if value.startswith('/media/') and not (root / value.removeprefix('/media/')).exists():
                        row[field] = None
                await save(c, row)
        results = await asyncio.gather(
            fetch('https://api.tvmaze.com/shows?page=0'),
            fetch('https://api.jikan.moe/v4/top/anime?limit=12&sfw=true'),
            return_exceptions=True,
        )
        # Kitsu provides an independent, no-key fallback when Jikan is unavailable.
        if isinstance(results[1], Exception):
            try:
                fallback = await fetch('https://kitsu.io/api/edge/anime?page[limit]=12&sort=popularityRank')
                for item in fallback['data']:
                    if not item['attributes'].get('nsfw'):
                        row = kitsu({'data': item})
                        old = await c.graph.store.get(key('platform_content', 'stream', row['domain_ref']))
                        if not old or old.get('details_at', 0) + TTL <= time.time():
                            await save(c, row)
            except (httpx.HTTPError, ValueError, KeyError, TypeError):
                log.warning('Kitsu fallback temporarily unavailable')
        failed = False
        for provider, result, normalize in zip(['tvmaze', 'jikan'], results, [tv, anime]):
            if isinstance(result, Exception):
                failed = True
                log.warning('Stream catalog %s unavailable: %s', provider, type(result).__name__)
                continue
            try:
                rows = result[:12] if provider == 'tvmaze' else result['data'][:12]
                for item in rows:
                    row = normalize(item)
                    # Keep previously fetched rich detail fields during daily catalog updates.
                    old = await c.graph.store.get(key('platform_content', 'stream', row['domain_ref']))
                    if old and old.get('details_at', 0) + TTL > time.time():
                        continue
                    await save(c, row)
            except (ValueError, KeyError, TypeError):
                failed = True
                log.exception('Invalid %s catalog response', provider)
        await c.graph.store.put(marker_id, dict(films_loaded=True,
            next_refresh=time.time() + (300 if failed else TTL)))


async def details(c, ref):
    async with _details_lock:
        record_id = key('platform_content', 'stream', ref)
        row = await c.graph.store.get(record_id) or {}
        provider = row.get('provider')
        if provider not in {'tvmaze', 'jikan', 'kitsu'} or row.get('details_at', 0) + TTL > time.time():
            return row
        if row.get('retry_after', 0) > time.time():
            return row
        pid = int(row['provider_id'])
        try:
            if provider == 'tvmaze':
                data = await fetch(f'https://api.tvmaze.com/shows/{pid}?embed[]=cast&embed[]=episodes')
                extra = tv(data)
                embedded = data.get('_embedded') or {}
                extra['cast'] = [dict(name=x['person']['name'], role=x['character']['name'])
                                 for x in embedded.get('cast', [])]
                extra['episodes'] = [dict(title=x['name'], season=x.get('season'), number=x.get('number'),
                    released=x.get('airdate'), description=clean(x.get('summary')))
                    for x in embedded.get('episodes', [])]
                extra['episode_count'] = len(extra['episodes'])
            elif provider == 'jikan':
                extra = anime((await fetch(f'https://api.jikan.moe/v4/anime/{pid}/full'))['data'])
            else:
                extra = kitsu(await fetch(f'https://kitsu.io/api/edge/anime/{pid}?include=genres,streamingLinks'))
            row.update(extra, details_at=time.time(), details_unavailable=False)
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            # Return the saved synopsis rather than replacing the screen with an error.
            row.update(retry_after=time.time() + 60, details_unavailable=True)
        await c.graph.store.put(record_id, row)
        return row
