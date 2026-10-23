"""Idempotent import of attributed CC BY music from Incompetech."""
import asyncio,json,subprocess
from urllib.parse import quote
import httpx
from app.config import Settings
from app.core.container import build_container,media_root_path
from app.domains.graph.service import key
SOURCE='https://www.incompetech.com/music/royalty-free/music.html'
LICENSE='https://creativecommons.org/licenses/by/4.0/'
async def main():
 c=await build_container(Settings(database_backend='surreal',surreal_database='phlio_graph_dev',redis_enabled=True,redis_namespace='phlio_graph_dev'))
 root=media_root_path(c.settings)/'stream_music'
 root.mkdir(parents=True,exist_ok=True)
 imported=[]
 try:
  async with httpx.AsyncClient(timeout=90,follow_redirects=True) as client:
   response=await client.get(SOURCE.replace('music.html','pieces.json'));response.raise_for_status()
   for i,t in enumerate(response.json()[:8]):
    ref='music_'+t['isrc'].lower();path=root/(ref+'.mp3');cover=root/(ref+'.png')
    if not path.exists():
     r=await client.get('https://www.incompetech.com/music/royalty-free/mp3-royaltyfree/'+quote(t['filename']));r.raise_for_status()
     if len(r.content)<10000: raise ValueError('Invalid audio download')
     temp=path.with_suffix('.part');temp.write_bytes(r.content);temp.replace(path)
    if not cover.exists():
     color=['9d80ff','45d7ac','ff9966','64b5f6','f48fb1','ffe082','80cbc4','b39ddb'][i]
     subprocess.run(['ffmpeg','-y','-i',str(path),'-filter_complex',f'aformat=channel_layouts=mono,showwavespic=s=600x600:colors=0x{color}','-frames:v','1',str(cover)],check=True,capture_output=True,timeout=45)
    obj=await c.graph.register_object('platform','stream.track',ref,t['title'])
    credit=f"{t['title']} by Kevin MacLeod (incompetech.com). CC BY 4.0: {LICENSE}. Audio unchanged; waveform artwork generated from the recording."
    await c.graph.store.put(key('platform_content','stream',ref),dict(platform='stream',domain_ref=ref,object_id=obj['id'],kind='song',category='Music',publisher='Kevin MacLeod',description=credit,source_url=SOURCE,license_url=LICENSE,media_url=f'/media/stream_music/{ref}.mp3',image_url=f'/media/stream_music/{ref}.png',imported=True,demo=False))
    imported.append(t['title'])
  print(json.dumps({'imported':len(imported),'titles':imported}))
 finally: await c.cache.close()
if __name__=='__main__': asyncio.run(main())

