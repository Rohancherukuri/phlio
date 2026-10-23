"""Idempotent, explicitly fictional discussion for the licensed demo footage."""
import asyncio
import datetime as dt
from app.core.container import build_container
from app.domains.graph.service import key
from scripts.run_graph_demo import settings

OBSERVATIONS = [
    'The blend of live-action actors and digital effects is fun to study.',
    'The lighting makes the real and computer-generated parts feel connected.',
    'I paused this to look more closely at the background details.',
    'The color grading gives this sci-fi scene a distinctive atmosphere.',
    'Interesting how much story the framing communicates without a caption.',
    'I would love to see a breakdown of the compositing in this scene.',
    'The contrast between the characters and their surroundings stands out.',
    'This is a good example to discuss in a filmmaking room.',
    'The scene has a lot of visual detail to take in on a second watch.',
    'The way the camera frames the action caught my attention.',
    'Watching this with sound adds a different layer to the atmosphere.',
    'The production design really sells the science-fiction setting.',
    'I like comparing the practical set with the digital elements.',
    'The visual effects support the scene instead of needing an explanation.',
    'This makes me want to explore how open movies are made.',
    'A behind-the-scenes comparison would be great alongside this excerpt.',
    'There is a lot here to learn about matching light and perspective.',
    'The mood comes through even in a short excerpt of the film.',
    'I noticed more of the environment when I watched it again.',
    'Saving this as a reference for a discussion about visual storytelling.',
]


async def seed(c):
    count = 0
    for index in range(20):
        for kind in ('video', 'clip'):
            ref = f'demo_{kind}_{index:02}'
            obj = await c.graph.store.get(key('phlio_object', 'social', ref))
            if not obj:
                continue
            messages = [
                OBSERVATIONS[index],
                ('The portrait crop makes this moment feel more immediate. I want to see the wider scene too.'
                 if kind == 'clip' else 'The wider frame helps me follow the action and notice the set design.'),
                ('This 30-second excerpt makes me curious about the rest of Tears of Steel.'
                 if kind == 'clip' else 'Nice to have a 90-second scene to watch rather than only a quick cut.'),
                'Thanks for including the Blender Foundation credit and the open-film source.',
            ]
            for n, text in enumerate(messages):
                cid = key('content_comment', 'licensed-demo-v1', ref, str(n))
                if await c.graph.store.get(cid):
                    continue
                author = f'demo_{20 + (index * 3 + n + (20 if kind == "clip" else 0)) % 80:03}'
                if not await c.identity_repository.get_by_id(author):
                    continue
                await c.graph.store.put(cid, dict(object_id=obj['id'], author_id=author,
                    text=text, mentions=[], image_url=None, sticker_id=None, demo=True,
                    created_at=(dt.datetime.now(dt.UTC) - dt.timedelta(minutes=index * 5 + n + 2)).isoformat()))
                count += 1
    return count


async def main():
    c = await build_container(settings)
    try:
        print(f'Added {await seed(c)} demo comments across Videos and Clips.')
    finally:
        await c.cache.close()
        await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == '__main__':
    asyncio.run(main())
