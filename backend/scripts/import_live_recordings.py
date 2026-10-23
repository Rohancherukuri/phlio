"""Import licensed films as recordings, never as fake live broadcasts."""
import asyncio
import re
import subprocess
from pathlib import Path
import httpx
from app.config import Settings
from app.core.container import build_container, media_root_path

async def main():
    c=await build_container(Settings(debug=True))
    folder=media_root_path(c.settings)/'live_recordings'; folder.mkdir(parents=True,exist_ok=True)
    # Official project source and distribution mirror; retain full end credits.
    source='https://peach.blender.org/about/'
    url='https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4.zip'
    path=folder/'big-buck-bunny.mp4'
    if not path.exists():
        temp=path.with_suffix('.download')
        async with httpx.AsyncClient(timeout=120,follow_redirects=True) as client:
            async with client.stream('GET',url) as response:
                response.raise_for_status()
                with temp.open('wb') as out:
                    async for chunk in response.aiter_bytes(): out.write(chunk)
        import zipfile, shutil
        with zipfile.ZipFile(temp) as archive:
            entry=next(n for n in archive.namelist() if n.lower().endswith('.mp4'))
            with archive.open(entry) as source_file, path.open('wb') as destination:
                shutil.copyfileobj(source_file,destination)
        temp.unlink()
    entries=[('big-buck-bunny','Big Buck Bunny',path,source,'Blender Foundation / www.bigbuckbunny.org · CC BY 3.0',45)]
    # Reuse existing locally imported licensed footage rather than downloading twice.
    from scripts.import_licensed_social import CREDIT, SOURCE
    for number in [0,6,12]:
        existing=media_root_path(c.settings)/f'licensed_social/tears-video-{number:02}.mp4'
        if existing.exists(): entries.append((f'tears-scene-{number}','Tears of Steel · Scene '+str(number+1),existing,SOURCE,CREDIT,3))
    for key,title,video,source,credit,offset in entries:
        thumb=folder/(key+'.jpg')
        if not thumb.exists(): subprocess.run(['ffmpeg','-y','-ss',str(offset),'-i',str(video),'-frames:v','1','-vf','scale=640:-1',str(thumb)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        await c.graph.store.put('live_recording:'+key,dict(title=title,name='Blender Foundation',category='Creative films',media_url='/media/'+video.relative_to(media_root_path(c.settings)).as_posix(),thumbnail_url='/media/live_recordings/'+thumb.name,source_url=source,attribution=credit,status='recorded'))
    await c.cache.close()
    print('Imported',len(entries),'licensed recordings with local media and thumbnails.')
if __name__=='__main__': asyncio.run(main())

