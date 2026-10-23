import io
import pytest
from PIL import Image

@pytest.mark.asyncio
async def test_memory_capture_archive_delete(client, auth_headers):
    image = io.BytesIO()
    Image.new('RGB', (20, 20), 'orange').save(image, format='JPEG')
    response = await client.post('/api/v1/social/memories', headers=auth_headers,
        files={'file': ('snap.jpg', image.getvalue(), 'image/jpeg')}, data={'caption': 'My snap'})
    assert response.status_code == 201, response.text
    memory = response.json()
    rows = (await client.get('/api/v1/social/memories', headers=auth_headers)).json()
    assert rows[0]['caption'] == 'My snap'
    assert rows[0]['image_url'].startswith('/social/memories/')
    assert (await client.get('/api/v1/social/memories')).status_code == 401
    assert (await client.delete('/api/v1/social/memories/' + memory['id'], headers=auth_headers)).status_code == 204
    assert (await client.get('/api/v1/social/memories', headers=auth_headers)).json() == []
    bad = await client.post('/api/v1/social/memories', headers=auth_headers,
        files={'file': ('snap.jpg', b'invalid', 'image/jpeg')})
    assert bad.status_code == 422

@pytest.mark.asyncio
async def test_memories_friend_visibility_and_expiry(settings):
    import datetime as dt
    from app.core.container import build_container
    from app.core.seed import seed_memory_backend
    from app.api.v1.social import memories, delete_memory, memory_seen, memory_react, MemoryReaction
    from fastapi import HTTPException
    c = await build_container(settings)
    await seed_memory_backend(c)
    owner, peer = await c.identity_repository.search_users('', 2)
    await c.graph.store.put('social_memory:snap', dict(author=owner.id, image_url='/media/snap.jpg', caption='', created_at=dt.datetime.now(dt.UTC).isoformat()))
    assert await memories(peer, c) == []
    await c.graph.relationship(owner.id, peer.id, 'request')
    await c.graph.relationship(peer.id, owner.id, 'accept')
    assert (await memories(peer, c))[0]['unread'] is True
    await memory_seen('social_memory:snap', peer, c)
    assert (await memories(peer, c))[0]['unread'] is False
    await memory_react('social_memory:snap', MemoryReaction(emoji='heart'), peer, c)
    assert len((await memories(owner, c))[0]['reactions']) == 1
    with pytest.raises(HTTPException):
        await delete_memory('social_memory:snap', peer, c)
    row = await c.graph.store.get('social_memory:snap')
    row['created_at'] = (dt.datetime.now(dt.UTC) - dt.timedelta(days=2)).isoformat()
    await c.graph.store.put(row['id'], row)
    assert await memories(peer, c) == []
    assert len(await memories(owner, c)) == 1
    await c.cache.close()
    c.social_video_service.db.close()
    c.messaging_service.db.close()


@pytest.mark.asyncio
async def test_close_friends_publication_requires_followers_and_protects_photo(client, auth_headers):
    c = client._transport.app.state.container
    arjun = await c.identity_repository.get_by_username('arjun')
    peer = next(p for p in await c.identity_repository.search_users('', 10) if p.id != arjun.id)
    image = io.BytesIO()
    Image.new('RGB', (20,20)).save(image, format='JPEG')
    import json
    payload = {'audience':'close_friends', 'recipients':json.dumps([peer.id]), 'kind':'moment'}
    async def publish():
        return await client.post('/api/v1/social/memories', headers=auth_headers, data=payload,
            files={'file': ('snap.jpg', image.getvalue(), 'image/jpeg')})
    assert (await publish()).status_code == 422
    await c.graph.relationship(peer.id, arjun.id, 'follow')
    created = await publish()
    assert created.status_code == 201, created.text
    from app.api.v1.social import memories
    assert any(m['id'] == created.json()['id'] for m in await memories(peer, c))
    photo = created.json()['image_url']
    assert (await client.get('/api/v1' + photo)).status_code == 401
    assert (await client.get('/api/v1' + photo, headers=auth_headers)).status_code == 200
    await c.graph.relationship(peer.id, arjun.id, 'unfollow')
    assert not any(m['id'] == created.json()['id'] for m in await memories(peer, c))
