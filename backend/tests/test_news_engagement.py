import pytest
from app.domains.graph.news import parse_feed


def test_feed_parser_requires_safe_link_and_publication_date():
    raw = b'<rss><channel><item><title>Real headline</title><link>https://example.com/story</link><pubDate>Fri, 09 Oct 2026 10:00:00 GMT</pubDate></item><item><title>Unsafe</title><link>javascript:alert(1)</link><pubDate>Fri, 09 Oct 2026 10:00:00 GMT</pubDate></item></channel></rss>'
    items = parse_feed(raw, 'Science', 'Publisher')
    assert len(items) == 1
    assert items[0]['publisher'] == 'Publisher'
    assert items[0]['published_at'].startswith('2026-10-09')
    assert items == parse_feed(raw, 'Science', 'Publisher')


@pytest.mark.asyncio
async def test_bookmarks_reposts_and_idempotent_views(client, auth_headers):
    post = await client.post('/api/v1/social/posts', headers=auth_headers, json={'text':'Persistence test'})
    path = '/api/v1/content/social/' + post.json()['id']
    for verb, metric in [('saved','bookmarks'), ('reposted','reposts'), ('viewed','views')]:
        r = await client.put(path + '/actions/' + verb, headers=auth_headers)
        assert r.status_code == 200, r.text
        assert r.json()[metric + '_count'] == 1
        r = await client.put(path + '/actions/' + verb, headers=auth_headers)
        assert r.json()[metric + '_count'] == (1 if verb == 'viewed' else 0)
    await client.put(path + '/actions/saved', headers=auth_headers)
    library = await client.get('/api/v1/library/saved', headers=auth_headers)
    assert library.json()['items'][0]['ref'] == post.json()['id']
