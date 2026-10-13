"""Prepare a real data-saver stream for each licensed demo video."""
import asyncio
import subprocess
from app.core.container import build_container, media_root_path
from app.domains.graph.service import key
from scripts.run_graph_demo import settings


async def main():
    c = await build_container(settings)
    root = media_root_path(settings) / 'licensed_social'
    limit = asyncio.Semaphore(2)
    async def prepare(index):
        async with limit:
            original = root / f'tears-video-{index:02}.mp4'
            target = root / f'tears-video-{index:02}-360p.mp4'
            if not original.exists():
                return
            if not target.exists():
                temporary = target.with_name(target.stem + '.part.mp4')
                await asyncio.to_thread(subprocess.run, ['ffmpeg', '-nostdin', '-v', 'error', '-y',
                    '-i', str(original), '-vf', 'scale=-2:360', '-c:v', 'libx264', '-preset', 'veryfast',
                    '-crf', '28', '-c:a', 'aac', '-b:a', '64k', '-movflags', '+faststart', str(temporary)],
                    check=True, timeout=300)
                temporary.replace(target)
            rid = key('platform_content', 'social', f'demo_video_{index:02}')
            row = await c.graph.store.get(rid)
            if row:
                row['sources'] = [dict(label='480p (original)', url='/media/licensed_social/' + original.name),
                                  dict(label='360p (data saver)', url='/media/licensed_social/' + target.name)]
                await c.graph.store.put(rid, row)
            print(f'Prepared video {index + 1}/20', flush=True)
    try:
        await asyncio.gather(*(prepare(i) for i in range(20)))
    finally:
        await c.cache.close()
        await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == '__main__':
    asyncio.run(main())
