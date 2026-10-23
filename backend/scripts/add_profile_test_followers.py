"""Add a bounded, repeatable set of fictional photo-profile followers in development."""
import argparse
import asyncio
import secrets
import httpx
from app.config import Settings
from app.core.container import build_container, media_root_path
from app.domains.identity.entities import User
from app.infrastructure.security.password import hash_password
from app.domains.graph.service import key

FIRST=['Aarav','Maya','Kabir','Anika','Rohan','Zoya','Vihaan','Isha','Arjun','Tara','Aditya','Naina','Dev','Sana','Karan','Riya','Neil','Meera','Rishi','Aisha','Armaan','Kiara','Reyansh','Diya','Ishaan','Avni','Dhruv','Sara','Yash','Leela']
LAST=['Shah','Kapoor','Rao','Patel','Mehta','Iyer','Singh','Nair','Verma','Desai']

async def main(username):
    settings=Settings()
    if settings.is_production: raise RuntimeError('Test followers are development-only.')
    c=await build_container(settings)
    try:
        target=await c.identity_repository.get_by_username(username)
        if not target: raise RuntimeError('Target account not found.')
        root=media_root_path(settings)/'test_followers';root.mkdir(parents=True,exist_ok=True)
        password_hash=hash_password(secrets.token_urlsafe(40))
        async with httpx.AsyncClient(timeout=30,follow_redirects=True) as http:
            for i in range(30):
                uid=f'test_follower_{i+1:03}'
                file=root/f'{uid}.jpg'
                if not file.exists():
                    response=await http.get(f'https://randomuser.me/api/portraits/{"men" if i%2==0 else "women"}/{60+i//2}.jpg')
                    response.raise_for_status()
                    if not response.content.startswith(b'\xff\xd8'):raise ValueError('Expected JPEG portrait')
                    file.write_bytes(response.content)
                existing=await c.identity_repository.get_by_id(uid)
                if existing and not existing.is_test_user:raise RuntimeError('Refusing to modify a real account.')
                if not existing:
                    await c.identity_repository.create_user(User(id=uid,username=f'{FIRST[i].lower()}.{LAST[i%10].lower()}',
                        full_name=f'{FIRST[i]} {LAST[i%10]}',email=f'{uid}@example.test',hashed_password=password_hash,
                        avatar_url=f'/media/test_followers/{file.name}',bio='Fictional test profile. Photo sourced from RandomUser.me.',
                        interests=['photography','travel'],is_test_user=True))
                if existing and existing.username.endswith('.test'):
                    desired = existing.username.removesuffix('.test')
                    collision = await c.identity_repository.get_by_username(desired)
                    if collision and collision.id != existing.id:
                        desired += f'{i+1:02}'
                    existing.username = desired
                    await c.identity_repository.update_user(existing)
                if not await c.graph.store.get(key('follows',uid,target.id)):
                    await c.graph.relationship(uid,target.id,'follow')
                # Seed only fictional accounts, once per conversation. Keep existing chats intact.
                if i < 15 and not c.messaging_service.db.execute(
                    'SELECT 1 FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?) LIMIT 1',
                    (uid,target.id,target.id,uid)).fetchone():
                    topics = ['photography walk', 'weekend travel plans', 'new video', 'music recommendations', 'coffee meetup']
                    c.messaging_service.send(uid, target.id,
                        f'Hi {target.full_name}! This is a test conversation about {topics[i%5]}. What do you think?', [])
                    c.messaging_service.update_inbox(target.id, uid, folder='primary')
        followers=await c.graph.store.rows('follows',{'out':'user:'+target.id})
        print(f'Added/verified 30 photo test followers for @{username}. Actual follower count: {len(followers)}.')
    finally:
        await c.cache.close()
        if c.graph.store.db:await c.graph.store.db.close()

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--username',required=True)
    asyncio.run(main(parser.parse_args().username))
