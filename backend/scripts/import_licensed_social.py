"""Replace test patterns with attributed CC BY 3.0 live-action film excerpts."""
import asyncio
import json
import subprocess
from pathlib import Path
import httpx
from scripts.run_graph_demo import settings
from app.core.container import build_container, media_root_path
from app.domains.graph.service import key
from app.infrastructure.video_thumbnail import make_thumbnail

SOURCE = 'https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov'
CREDIT = 'Tears of Steel — (CC) Blender Foundation | mango.blender.org · CC BY 3.0 · trimmed excerpts; clips reframed vertically'

async def main():
    c = await build_container(settings)
    root = media_root_path(settings) / 'licensed_social'
    root.mkdir(parents=True, exist_ok=True)
    original = root / 'tears-of-steel-source.mov'
    try:
        if not original.exists():
            partial = original.with_suffix('.part')
            print('Downloading original live-action open film from Blender Foundation...', flush=True)
            async with httpx.AsyncClient(timeout=120, follow_redirects=True) as client:
                async with client.stream('GET', SOURCE) as response:
                    response.raise_for_status()
                    with partial.open('wb') as out:
                        async for chunk in response.aiter_bytes(1024*1024): out.write(chunk)
            for attempt in range(8):
                try:
                    partial.replace(original)
                    break
                except PermissionError:
                    if attempt == 7: raise
                    await asyncio.sleep(1)
        fingerprints = []
        manifest = []
        for i in range(20):
            for kind, seconds in [('video', 90), ('clip', 30)]:
                ref = f'demo_{kind}_{i:02}'
                name = f'tears-{kind}-{i:02}'
                target, cover = root / (name+'.mp4'), root / (name+'-cover-v2.jpg')
                print(f'Preparing {kind} {i+1}/20', flush=True)
                if not target.exists():
                    vf = 'scale=854:-2' if kind == 'video' else 'scale=-2:640,crop=360:640'
                    subprocess.run(['ffmpeg','-nostdin','-v','error','-y','-ss',str(30+i*27),'-i',str(original),'-t',str(seconds),'-vf',vf,'-c:v','libx264','-preset','veryfast','-crf','25','-c:a','aac','-b:a','96k','-movflags','+faststart',str(target)],check=True,timeout=180)
                position = make_thumbnail(target, cover, seconds, fingerprints, offset=7 if kind == 'clip' else 2)
                manifest.append(dict(id=ref, file=cover.name, source=target.name, seconds=position))
                url, thumb = '/media/licensed_social/'+target.name, '/media/licensed_social/'+cover.name
                title = f'Tears of Steel · {"Scene" if kind == "video" else "Moment"} {i+1:02}'
                c.social_video_service.db.execute('UPDATE videos SET title=?,url=?,thumbnail_url=?,duration_seconds=? WHERE id=?',(title,url,thumb,seconds,ref))
                c.social_video_service.db.commit()
                oid = key('phlio_object','social',ref)
                obj = await c.graph.store.get(oid)
                if obj:
                    obj['title'] = title
                    await c.graph.store.put(oid,obj)
                    await c.graph.store.put(key('platform_content','social',ref),dict(platform='social',domain_ref=ref,object_id=oid,kind=kind,description=CREDIT,image_url=thumb,media_url=url,demo=True,attribution=CREDIT,source_url=SOURCE,license_url='https://creativecommons.org/licenses/by/3.0/'))
            # Replace demo post patterns too, keeping existing posts/likes/comments.
            for j in (1, 2):
                pid = f'demo_post_{i:02}_{j}'
                cover = root / f'post-{i:02}-{j}-cover-v2.jpg'
                source = root / f'tears-video-{i:02}.mp4'
                position = make_thumbnail(source, cover, 90, fingerprints, offset=18 if j == 1 else 40)
                thumb = '/media/licensed_social/' + cover.name
                caption = f'Tears of Steel · film study {i+1:02}: {"a still from the scene" if j == 1 else "watch the scene"}. {CREDIT}'
                post = await c.social_repository.get_post(pid)
                if post:
                    await c.social_repository._db.merge('post:' + pid, dict(text=caption, tags=['openfilm', 'cinema', 'tearsofsteel'],
                        media=[dict(kind='image' if j == 1 else 'video', url=thumb if j == 1 else '/media/licensed_social/' + source.name, thumbnail_url=thumb)]))
                    obj = await c.graph.store.get(key('phlio_object', 'social', pid))
                    if obj:
                        obj['title'] = caption[:160]
                        await c.graph.store.put(obj['id'], obj)
                manifest.append(dict(id=pid, file=cover.name, source=source.name, seconds=position))
        (root/'thumbnails.json').write_text(json.dumps(manifest, indent=2))
        (root/'LICENSE.json').write_text(json.dumps(dict(source=SOURCE,credit=CREDIT,license='https://mango.blender.org/sharing/'),indent=2))
        print('Replaced 20 videos and 20 clips with licensed real footage.',flush=True)
    finally:
        await c.cache.close()
        await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()

if __name__ == '__main__': asyncio.run(main())
