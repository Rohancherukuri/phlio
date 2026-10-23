import pytest
from app.api.v1.content import engagement
from app.core.container import build_container
from app.core.seed import seed_memory_backend

@pytest.mark.asyncio
@pytest.mark.parametrize('platform,kind', [('news','article'),('stream','track'),('stream','movie'),('book','activity'),('shop','product'),('rooms','room'),('pay','merchant'),('social','post')])
async def test_follower_avatar_preview_is_directional_and_private(settings, platform, kind):
    c = await build_container(settings)
    await seed_memory_backend(c)
    me, follower, stranger = (await c.identity_repository.search_users('', 3))
    obj = await c.graph.register_object(me.id, platform + '.' + kind, 'sample', 'Sample')
    for person in [me, follower, stranger]:
        await c.graph.set_policy(person.id, dict(platform=platform,object_type='*',verb='liked',audience='public',identity_mode='identified',foxy_access='none',selected_users=[]))
        await c.graph.action(person.id, obj['id'], 'liked')
    await c.graph.relationship(follower.id, me.id, 'follow')
    data = await engagement(platform, 'sample', me, c)
    assert data['count'] == 3
    assert [p['id'] for p in data['follower_avatars']] == [me.id, follower.id]
    assert data['follower_like_count'] == 1
    await c.graph.set_policy(follower.id, dict(platform=platform,object_type='*',verb='liked',audience='nobody',identity_mode='hidden',foxy_access='none',selected_users=[]))
    data = await engagement(platform, 'sample', me, c)
    assert [p['id'] for p in data['follower_avatars']] == [me.id]
    await c.cache.close()
    c.social_video_service.db.close()
    c.messaging_service.db.close()
