import pytest
from app.api.v1.graph import ContactMatchIn, match_contacts, find_friends, contact_phone
from app.core.container import build_container
from app.core.seed import seed_memory_backend

@pytest.mark.asyncio
async def test_contact_matching_and_blocks(settings):
    c = await build_container(settings)
    await seed_memory_backend(c)
    me, peer = await c.identity_repository.search_users('', 2)
    peer.phone_number = '+919876543210'
    await c.identity_repository.update_user(peer)
    body = ContactMatchIn(phones=['98765 43210', '+919876543210', 'bad'], region='IN')
    matches = await match_contacts(body, me, c)
    assert len(matches) == 1
    assert matches[0]['id'] == peer.id
    assert 'phone_number' not in matches[0]
    assert await match_contacts(body, peer, c) == []
    await c.graph.relationship(me.id, peer.id, 'request')
    incoming = (await c.graph.connections(peer.id))['friends']
    assert incoming[0]['incoming'] is True
    await c.graph.relationship(peer.id, me.id, 'accept')
    assert await c.graph.friends(me.id, peer.id)
    await c.graph.relationship(peer.id, me.id, 'block')
    assert await match_contacts(body, me, c) == []
    assert await find_friends(peer.username, me, c) == []
    await c.cache.close()
    c.social_video_service.db.close()
    c.messaging_service.db.close()

def test_phone_normalization():
    assert contact_phone('98765 43210', 'IN') == '+919876543210'
    assert contact_phone('not a number', 'IN') is None
