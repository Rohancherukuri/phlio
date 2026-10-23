import pytest
from types import SimpleNamespace
from fastapi import HTTPException
from app.api.v1.social import edit_content,delete_content,EditContentRequest
from app.core.container import build_container
from app.core.seed import seed_memory_backend
from app.domains.graph.service import key

@pytest.mark.parametrize('kind',['post','video','clip'])
async def test_owner_edit_delete(settings,kind):
 c=await build_container(settings);await seed_memory_backend(c)
 users=await c.identity_repository.search_users('',2)
 owner,other=[SimpleNamespace(id=u.id) for u in users]
 if kind=='post':
  post=await c.social_service.create_post(author_id=owner.id,text='Original',media=[],tags=[]);rid=post.id
 else:
  rid='owned-'+kind
  c.social_video_service.db.execute('INSERT INTO videos(id,creator,title,url,created_at,kind) VALUES(?,?,?,?,?,?)',(rid,owner.id,'Original','/media/test.mp4','2026-01-01',kind));c.social_video_service.db.commit()
  await c.graph.register_object(owner.id,'social.'+kind,rid,'Original')
 for operation in (lambda:edit_content(rid,EditContentRequest(text='Changed'),other,c),lambda:delete_content(rid,other,c)):
  with pytest.raises(HTTPException) as e: await operation()
  assert e.value.status_code==403
 await edit_content(rid,EditContentRequest(text='Changed'),owner,c)
 assert (await c.graph.store.get(key('phlio_object','social',rid)))['title']=='Changed'
 if kind=='post': assert (await c.social_repository.get_post(rid)).text=='Changed'
 else: assert c.social_video_service.db.execute('SELECT title FROM videos WHERE id=?',(rid,)).fetchone()[0]=='Changed'
 await delete_content(rid,owner,c)
 assert (await c.graph.store.get(key('phlio_object','social',rid)))['state']=='deleted'
 with pytest.raises(HTTPException) as e: await edit_content(rid,EditContentRequest(text='Again'),owner,c)
 assert e.value.status_code==404
 await c.cache.close();c.social_video_service.db.close();c.messaging_service.db.close()

async def test_batched_feed_preserves_visibility_and_likes(settings):
 c=await build_container(settings);await seed_memory_backend(c)
 viewer,author=(await c.identity_repository.search_users('',2))
 post=await c.social_service.create_post(author_id=author.id,text='Visible',media=[],tags=[])
 await c.social_repository.set_liked(post.id,viewer.id,True)
 posts,likes=await c.social_service.feed_metadata([post],viewer.id)
 assert posts == [post] and likes == {post.id}
 await c.graph.relationship(author.id,viewer.id,'block')
 assert (await c.social_service.feed_metadata([post],viewer.id)) == ([],set())
 await c.graph.relationship(author.id,viewer.id,'unblock')
 await delete_content(post.id,author,c)
 assert (await c.social_service.feed_metadata([post],viewer.id)) == ([],set())
 await c.cache.close();c.social_video_service.db.close();c.messaging_service.db.close()
