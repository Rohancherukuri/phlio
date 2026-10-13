import io
import pytest
from PIL import Image

pytestmark = pytest.mark.asyncio

async def test_rich_comments_on_posts_and_videos(client,auth_headers,monkeypatch):
    monkeypatch.setattr('app.api.v1.social_videos.probe_duration',lambda _:60.0)
    monkeypatch.setattr('app.api.v1.social_videos.make_thumbnail', lambda *args: None)
    p=await client.post('/api/v1/social/posts',headers=auth_headers,json={'text':'Rich comments'})
    v=await client.post('/api/v1/social/videos',headers=auth_headers,data={'title':'Rich video'},files={'file':('test.mp4',b'video')})
    for rid in [p.json()['id'],v.json()['id']]:
        path=f'/api/v1/social/content/{rid}/comments'
        picture=io.BytesIO();Image.new('RGB',(8,8),'red').save(picture,format='PNG')
        r=await client.post(path,headers=auth_headers,data={'text':'Hi @neha','sticker_id':'happy'},files={'image':('photo.png',picture.getvalue(),'image/png')})
        assert r.status_code==201,r.text
        assert r.json()['mentions'][0]['username']=='neha'
        assert r.json()['image_url'].endswith('.png')
        got=await client.get(path,headers=auth_headers)
        assert got.json()['items'][0]['author']['username']=='arjun'
        assert got.json()['items'][0]['text']=='Hi @neha'
        assert (await client.get(path)).status_code==401
        bad=await client.post(path,headers=auth_headers,files={'image':('fake.png',b'<script>bad</script>','image/png')})
        assert bad.status_code==422
        assert (await client.post(path,headers=auth_headers,data={'sticker_id':'unknown'})).status_code==422
        assert (await client.post(path,headers=auth_headers,data={'text':'  '})).status_code==422

async def test_existing_comments_preserved(client,auth_headers):
    post=await client.post('/api/v1/social/posts',headers=auth_headers,json={'text':'Old and new'})
    rid=post.json()['id']
    await client.post(f'/api/v1/social/posts/{rid}/comments',headers=auth_headers,json={'text':'Original comment'})
    r=await client.get(f'/api/v1/social/content/{rid}/comments',headers=auth_headers)
    assert r.json()['items'][0]['text']=='Original comment'
