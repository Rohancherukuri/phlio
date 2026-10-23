from types import SimpleNamespace
import pytest
from fastapi import HTTPException
from app.api.v1 import playlists as api
from app.core.container import build_container
from app.core.seed import seed_memory_backend

async def test_private_platform_bookmark_collections(settings):
    c = await build_container(settings)
    await seed_memory_backend(c)
    people = await c.graph.identity.search_users('',30)
    owner, other = (SimpleNamespace(id=p.id) for p in people[:2])
    news = await c.graph.register_object(owner.id,'news.article','playlist-news','News')
    stream = await c.graph.register_object(owner.id,'stream.movie','playlist-film','Film')
    playlist = await api.create(api.Create(name=' Reading ',platform='news'),owner,c)
    pid = playlist['id']
    assert playlist['name'] == 'Reading'
    assert (await api.playlists('news',other,c))['items'] == []
    for operation in (lambda:api.items(pid,other,c),lambda:api.rename(pid,api.Name(name='Stolen'),other,c),lambda:api.delete(pid,other,c)):
        with pytest.raises(HTTPException) as error: await operation()
        assert error.value.status_code == 404
    with pytest.raises(HTTPException) as error:
        await api.add(pid,api.Item(object_id=news['id']),owner,c)
    assert error.value.status_code == 422
    await c.graph.action(owner.id,news['id'],'saved')
    await c.graph.action(owner.id,stream['id'],'saved')
    with pytest.raises(HTTPException): await api.add(pid,api.Item(object_id=stream['id']),owner,c)
    for _ in range(2): await api.add(pid,api.Item(object_id=news['id']),owner,c)
    assert len((await api.items(pid,owner,c))['items']) == 1
    await api.rename(pid,api.Name(name='Weekend'),owner,c)
    assert (await api.playlists('news',owner,c))['items'][0]['name'] == 'Weekend'
    await api.remove(pid,news['id'],owner,c)
    assert (await api.items(pid,owner,c))['items'] == []
    await api.add(pid,api.Item(object_id=news['id']),owner,c)
    await api.delete(pid,owner,c)
    from app.domains.graph.service import key
    assert await c.graph.store.get(key('activity',owner.id,news['id'],'saved'))
    assert await c.graph.store.rows('playlist_item',{'playlist_id':pid}) == []
    await c.cache.close()
    c.messaging_service.db.close()
    c.social_video_service.db.close()

async def test_playlist_api_validation(client,auth_headers):
    for body in ({'name':'  ','platform':'news'},{'name':'test','platform':'invalid'}):
        assert (await client.post('/api/v1/playlists',json=body,headers=auth_headers)).status_code == 422
    response = await client.post('/api/v1/playlists',json={'name':'Watch later','platform':'stream'},headers=auth_headers)
    assert response.status_code == 201
    assert (await client.get('/api/v1/playlists',params={'platform':'stream'},headers=auth_headers)).json()['items'][0]['id'] == response.json()['id']

async def test_stream_playlist_rejects_other_media_mode(settings):
    from app.domains.graph.service import key
    c = await build_container(settings)
    await seed_memory_backend(c)
    user = SimpleNamespace(id=(await c.graph.identity.search_users('', 1))[0].id)
    track = await c.graph.register_object(user.id, 'stream.track', 'song-one', 'Song')
    movie = await c.graph.register_object(user.id, 'stream.movie', 'film-one', 'Film')
    await c.graph.store.put(key('platform_content','stream','song-one'), dict(kind='song',category='Music'))
    for obj in (track,movie): await c.graph.action(user.id,obj['id'],'saved')
    audio = await api.create(api.Create(name='Music',platform='stream',media_mode='audio'),user,c)
    video = await api.create(api.Create(name='Films',platform='stream',media_mode='video'),user,c)
    await api.add(audio['id'],api.Item(object_id=track['id']),user,c)
    await api.add(video['id'],api.Item(object_id=movie['id']),user,c)
    for playlist,obj in ((audio,movie),(video,track)):
        with pytest.raises(HTTPException) as error:
            await api.add(playlist['id'],api.Item(object_id=obj['id']),user,c)
        assert error.value.status_code == 422
    await c.cache.close()
    c.messaging_service.db.close()
    c.social_video_service.db.close()

@pytest.mark.parametrize('platform,kind', [('shop','product'),('book','activity'),('news','article'),('stream','movie')])
async def test_default_save_and_move(settings, platform, kind):
    c = await build_container(settings)
    await seed_memory_backend(c)
    people = await c.graph.identity.search_users('', 2)
    user, other = people
    obj = await c.graph.register_object(user.id, platform+'.'+kind, 'save-example', 'Example')
    body = api.SaveBookmark(platform=platform, ref='save-example')
    first = await api.save_bookmark(body, user, c)
    again = await api.save_bookmark(body, user, c)
    assert first['id'] == again['id'] and first['name'] == 'Saved'
    assert len(await c.graph.store.rows('playlist_item', {'playlist_id':first['id']})) == 1
    target = await api.create(api.Create(name='Favorites', platform=platform), user, c)
    await api.save_bookmark(api.SaveBookmark(platform=platform, ref='save-example', playlist_id=target['id']), user, c)
    assert not await c.graph.store.rows('playlist_item', {'playlist_id':first['id']})
    assert len(await c.graph.store.rows('playlist_item', {'playlist_id':target['id']})) == 1
    with pytest.raises(HTTPException):
        await api.save_bookmark(api.SaveBookmark(platform=platform, ref='save-example', playlist_id=target['id']), other, c)
    await c.cache.close()
    c.messaging_service.db.close()
    c.social_video_service.db.close()
