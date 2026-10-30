from types import SimpleNamespace
import asyncio
from unittest.mock import AsyncMock

import httpx
import pytest

from app.domains.stream import catalog


def test_provider_metadata_never_becomes_playable():
    row = catalog.tv({'id': 1, 'name': 'Example', 'summary': '<p>Hello &amp; welcome</p>',
                      'officialSite': 'javascript:alert(1)'})
    assert row['description'] == 'Hello & welcome'
    assert row['media_url'] is None
    assert not row['watch_links']
    row = catalog.anime({'mal_id': 1, 'title': 'Example',
                         'streaming': [{'name': 'Provider', 'url': 'https://example.org'}]})
    assert row['media_url'] is None
    assert row['watch_links'][0]['url'] == 'https://example.org'


def test_kitsu_normalizes_score_and_links():
    row = catalog.kitsu({'data': {'id': '2', 'attributes': {'canonicalTitle': 'Anime',
        'slug': 'anime', 'averageRating': '84.4'}}, 'included': [
            {'type': 'genres', 'attributes': {'name': 'Adventure'}},
            {'type': 'streamingLinks', 'attributes': {'url': 'https://www.crunchyroll.com/example'}}]})
    assert row['rating'] == 8.44
    assert row['genres'] == ['Adventure']
    assert row['media_url'] is None
    assert len(row['watch_links']) == 1


@pytest.mark.asyncio
async def test_detail_outage_keeps_saved_data_and_backs_off(monkeypatch):
    row = dict(provider='tvmaze', provider_id=1, title='Saved title', description='Saved synopsis')
    store = SimpleNamespace(get=AsyncMock(return_value=row), put=AsyncMock())
    c = SimpleNamespace(graph=SimpleNamespace(store=store))
    fetch = AsyncMock(side_effect=httpx.ConnectError('offline'))
    monkeypatch.setattr(catalog, 'fetch', fetch)
    result = await catalog.details(c, 'tvmaze-1')
    assert result['description'] == 'Saved synopsis'
    assert result['details_unavailable'] is True
    await catalog.details(c, 'tvmaze-1')
    assert fetch.await_count == 1


@pytest.mark.asyncio
async def test_show_details_cached_with_cast_and_episode_data(monkeypatch):
    row = dict(provider='tvmaze', provider_id=1)
    store = SimpleNamespace(get=AsyncMock(return_value=row), put=AsyncMock())
    c = SimpleNamespace(graph=SimpleNamespace(store=store))
    fetch = AsyncMock(return_value={'id': 1, 'name': 'Show', '_embedded': {
        'cast': [{'person': {'name': 'Actor'}, 'character': {'name': 'Character'}}],
        'episodes': [{'name': 'Pilot', 'season': 1, 'number': 1, 'summary': '<p>Story</p>'}]}})
    monkeypatch.setattr(catalog, 'fetch', fetch)
    result = await catalog.details(c, 'tvmaze-1')
    assert result['episode_count'] == 1
    assert result['episodes'][0]['description'] == 'Story'
    assert result['cast'][0]['name'] == 'Actor'
    await catalog.details(c, 'tvmaze-1')
    assert fetch.await_count == 1


@pytest.mark.asyncio
async def test_cached_catalog_does_not_wait_for_provider_refresh(monkeypatch):
    release = asyncio.Event()
    started = asyncio.Event()
    async def slow_refresh(c):
        started.set()
        await release.wait()
    monkeypatch.setattr(catalog, 'refresh', slow_refresh)
    c = SimpleNamespace(graph=SimpleNamespace(store=SimpleNamespace(
        get=AsyncMock(return_value={'next_refresh': 0}))))
    await asyncio.wait_for(catalog.ensure_catalog(c), timeout=.2)
    await started.wait()
    task = catalog._refresh_tasks[id(c)]
    await catalog.ensure_catalog(c)
    assert catalog._refresh_tasks[id(c)] is task
    release.set()
    await task
    assert id(c) not in catalog._refresh_tasks
