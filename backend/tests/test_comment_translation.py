import pytest
from fastapi import HTTPException
from app.api.v1 import social_comments as api
from app.core.container import build_container
from app.core.seed import seed_memory_backend

async def test_translation_cache_is_access_checked(settings, monkeypatch):
    c=await build_container(settings)
    await seed_memory_backend(c)
    user, other=await c.identity_repository.search_users('',2)
    await c.graph.register_object(user.id,'shop.product','translate-test','Product')
    row=await api.create('translate-test','Bonjour',None,None,None,'shop',user,c)
    calls=[]
    cached={}
    async def get(k): return cached.get(k)
    async def put(k,v,ttl=60): cached[k]=v
    monkeypatch.setattr(c.cache,'get',get)
    monkeypatch.setattr(c.cache,'put',put)
    class Response:
        status_code=200
        def json(self): return {'text':'Hello','target_language':'en','model':'MADLAD-400-3B'}
    class Client:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def post(self, url, json): calls.append(json); return Response()
    monkeypatch.setattr('httpx.AsyncClient',Client)
    for _ in range(2):
        result=await api.translate_comment('translate-test',row['id'],'shop',other,c)
        assert result['text']=='Hello'
    assert len(calls)==1
    await c.graph.relationship(user.id,other.id,'block')
    with pytest.raises(HTTPException): await api.translate_comment('translate-test',row['id'],'shop',other,c)
    assert len(calls)==1
    await c.cache.close();c.social_video_service.db.close();c.messaging_service.db.close()
