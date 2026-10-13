"""Repair shared catalog references and replace generated stream demo media."""
import asyncio
from app.config import Settings
from app.core.container import build_container, media_root_path
from app.domains.graph.service import key
from scripts.import_licensed_social import CREDIT, SOURCE

async def main():
    c = await build_container(Settings())
    for platform in ('shop','book'):
        for row in await c.graph.store.rows('platform_content', {'platform':platform}):
            if row.get('imported') and not row.get('object_id'):
                row['object_id'] = key('phlio_object',platform,row['domain_ref'])
                await c.graph.store.put(row['id'],row)
    count = 0
    for row in await c.graph.store.rows('platform_content', {'platform':'stream'}):
        if not row.get('demo') or not row['domain_ref'].startswith('demo_stream_'): continue
        number = int(row['domain_ref'].rsplit('_',1)[1]) % 20
        media = f'/media/licensed_social/tears-video-{number:02}.mp4'
        thumb = f'/media/licensed_social/tears-video-{number:02}-cover-v2.jpg'
        if not (media_root_path(c.settings)/media.removeprefix('/media/')).is_file(): continue
        row.update(media_url=media,image_url=thumb,source_url=SOURCE,kind='recording',
                   description='Recorded film excerpt. '+CREDIT,attribution=CREDIT)
        await c.graph.store.put(row['id'],row)
        obj = await c.graph.store.get(row['object_id'])
        if obj:
            obj['title'] = f'Tears of Steel · Recorded scene {number+1}'
            await c.graph.store.put(obj['id'],obj)
        count += 1
    await c.cache.close()
    print(f'Repaired catalog references; {count} recordings use licensed footage.')

if __name__ == '__main__': asyncio.run(main())
