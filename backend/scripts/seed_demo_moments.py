"""Refresh test creators' moments for 24 hours using their existing clips."""
import asyncio,datetime as dt,json
from app.config import Settings
from app.core.container import build_container
from app.domains.graph.service import key
async def main():
 c=await build_container(Settings(debug=True,database_backend='surreal',surreal_database='phlio_graph_dev',redis_enabled=True,redis_namespace='phlio_graph_dev',social_video_database='data/phlio_graph_dev_videos.sqlite3'))
 count=0
 for i in range(20):
  owner=f'demo_{i:03}'
  row=c.social_video_service.db.execute("SELECT * FROM videos WHERE creator=? AND kind='clip' LIMIT 1",(owner,)).fetchone()
  if not row:continue
  obj=await c.graph.store.get(key('phlio_object','social',row['id']))
  if not obj or obj['state']!='active':continue
  await c.graph.store.put('shared_story:demo_moment_'+str(i),dict(author=owner,object_id=obj['id'],created_at=dt.datetime.now(dt.UTC).isoformat(),expires_at=(dt.datetime.now(dt.UTC)+dt.timedelta(hours=24)).isoformat()))
  count+=1
 print(json.dumps({'moments':count,'expires':'24 hours'}))
 await c.cache.close();c.social_video_service.db.close();c.messaging_service.db.close()
if __name__=='__main__':asyncio.run(main())

