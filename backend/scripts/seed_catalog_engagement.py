"""Idempotent test-account likes and photographic demo catalog curators."""
import asyncio
import hashlib
import random
from app.config import Settings
from app.core.container import build_container
from app.domains.graph.service import key
from app.infrastructure.database.surreal.client import record
from scripts.import_shop_catalog import SOURCES

async def main():
    c = await build_container(Settings())
    try:
        for index, source in enumerate(SOURCES):
            await c.graph.store.db.query('UPDATE $id SET user_id = $owner', {
                'id':record('seller:import_'+source[0]), 'owner':record(f'user:demo_{21+index:03}')})
        count = 0
        for platform in ('shop','book'):
            for row in await c.graph.store.rows('platform_content', {'platform':platform}):
                if not row.get('imported'): continue
                oid = key('phlio_object',platform,row['domain_ref'])
                rng = random.Random(hashlib.sha256(oid.encode()).hexdigest())
                for number in rng.sample(range(21,100),rng.randint(5,12)):
                    actor = f'demo_{number:03}'
                    if not await c.graph.store.get(key('activity',actor,oid,'liked')):
                        for attempt in range(5):
                            try:
                                await c.graph.action(actor,oid,'liked')
                                break
                            except RuntimeError as exc:
                                if 'conflict' not in str(exc) or attempt == 4: raise
                                await asyncio.sleep(.2 * (attempt+1))
                count += 1
        print(f'Updated photo curators and demo likes for {count} catalog items.')
    finally:
        await c.cache.close()
        if c.graph.store.db: await c.graph.store.db.close()

if __name__ == '__main__': asyncio.run(main())
