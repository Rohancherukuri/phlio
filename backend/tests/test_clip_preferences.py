from types import SimpleNamespace
import pytest
from fastapi import HTTPException
from app.api.v1.social_videos import clip_preference, clip_preferences, report_clip, ClipFeedback
from app.core.container import build_container
from app.core.seed import seed_memory_backend

@pytest.mark.asyncio
async def test_preferences_are_private_and_replaceable(settings):
    c = await build_container(settings)
    await seed_memory_backend(c)
    owner, other = (await c.identity_repository.search_users('', 2))
    await c.graph.register_object(owner.id, 'social.clip', 'sample', 'Mountain hiking')
    await clip_preference('sample', ClipFeedback(preference='interested'), owner, c)
    await clip_preference('sample', ClipFeedback(preference='not_interested'), owner, c)
    rows = await clip_preferences(owner, c)
    assert len(rows) == 1
    assert rows[0]['preference'] == 'not_interested'
    assert rows[0]['creator'] == owner.username
    assert await clip_preferences(other, c) == []
    await report_clip('sample', owner, c)
    assert len(await c.graph.store.rows('content_report')) == 1
    with pytest.raises(HTTPException):
        await clip_preference('missing', ClipFeedback(preference='interested'), owner, c)
    await c.cache.close()
    c.social_video_service.db.close()
    c.messaging_service.db.close()
