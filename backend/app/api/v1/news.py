from fastapi import APIRouter, Depends, Query
from app.api.deps import get_container, get_current_user
from app.domains.graph.news import CATEGORIES

router = APIRouter(prefix='/news', tags=['news'])

@router.get('/feed')
async def feed(category: str = 'Top International', q: str = Query('', max_length=200),
               user=Depends(get_current_user), c=Depends(get_container)):
    cache_key = 'news:articles:' + str(await c.graph.store.revision())
    rows = await c.cache.get(cache_key)
    if rows is None:
        rows = [r for r in await c.graph.store.rows('platform_content', {'platform':'news'}) if r.get('source_url') and not r.get('demo')]
        rows.sort(key=lambda r: r.get('published_at', ''), reverse=True)
        await c.cache.put(cache_key, rows)
    # Publisher imports are public platform-owned objects. Read current state in
    # one query instead of hundreds of per-article authorization round trips.
    objects = await c.graph.store.rows('phlio_object', {
        'platform': 'news', 'owner': 'platform', 'audience': 'public', 'state': 'active',
    })
    allowed = {obj['id'] for obj in objects}
    authorized = [] if await c.graph.blocked(user.id, 'platform') else [
        row for row in rows if row['object_id'] in allowed
    ]
    topics = [dict(name=name, count=sum(r.get('category') == name for r in authorized)) for name in CATEGORIES[3:]]
    if category == 'Blindspot':
        viewed = {a['out'] for a in await c.graph.store.rows('activity', {'in':'user:' + user.id, 'verb':'viewed'})}
        items = [r for r in authorized if r['object_id'] not in viewed]
        items.sort(key=lambda r: sum(x['category'] == r['category'] for x in authorized))
    elif category == 'For You':
        actions = await c.graph.store.rows('activity', {'in':'user:' + user.id})
        selected = {a['out'] for a in actions if a['verb'] in {'liked','saved'}}
        preferred = {r['category'] for r in authorized if r['object_id'] in selected}
        items = sorted(authorized, key=lambda r: r['category'] in preferred, reverse=True)
    else:
        target = 'International' if category == 'Top International' else category
        items = [r for r in authorized if r.get('category') == target]
    if q:
        items = [r for r in authorized if q.casefold() in ' '.join(str(r.get(f,'')) for f in ['title','publisher','category','source_url']).casefold()]
    return dict(items=items[:100], headlines=items[:6], categories=CATEGORIES, topics=topics,
                notice='Stories you have not opened, prioritizing less represented topics. This is not a political-bias rating.' if category == 'Blindspot' else None)
