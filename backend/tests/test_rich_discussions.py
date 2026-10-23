import pytest
from fastapi import HTTPException
from app.api.v1.social_comments import create, comments, like_comment, report_comment
from app.core.container import build_container
from app.core.seed import seed_memory_backend

@pytest.mark.asyncio
@pytest.mark.parametrize('platform,kind', [('shop','product'),('stream','track'),('book','activity'),('social','clip')])
async def test_thread_reactions_and_cross_content_rejection(settings, platform, kind):
    c = await build_container(settings)
    await seed_memory_backend(c)
    me = (await c.identity_repository.search_users('', 1))[0]
    await c.graph.register_object(me.id, platform+'.'+kind, 'thread', 'Thread')
    await c.graph.register_object(me.id, platform+'.'+kind, 'other', 'Other')
    root = await create('thread', 'Hello', None, None, None, platform, me, c)
    reply = await create('thread', 'Reply', None, None, root['id'], platform, me, c)
    await like_comment('thread', reply['id'], True, platform, me, c)
    await like_comment('thread', reply['id'], True, platform, me, c)
    rows = (await comments('thread', platform, me, c))['items']
    saved = next(r for r in rows if r['id'] == reply['id'])
    assert saved['parent_id'] == root['id']
    assert saved['likes_count'] == 1 and saved['liked_by_me']
    with pytest.raises(HTTPException) as error:
        await create('other', 'Wrong thread', None, None, root['id'], platform, me, c)
    assert error.value.status_code == 404
    await report_comment('thread', reply['id'], platform, me, c)
    reports = await c.graph.store.rows('content_report', {'comment_id': reply['id']})
    assert len(reports) == 1 and reports[0]['status'] == 'pending'
    with pytest.raises(HTTPException):
        await report_comment('other', reply['id'], platform, me, c)
    await like_comment('thread', reply['id'], False, platform, me, c)
    assert not next(r for r in (await comments('thread', platform, me, c))['items'] if r['id']==reply['id'])['liked_by_me']
    await c.cache.close()
    c.social_video_service.db.close()
    c.messaging_service.db.close()
