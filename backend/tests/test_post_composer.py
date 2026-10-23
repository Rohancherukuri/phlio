import io
import wave
import pytest
from PIL import Image

@pytest.mark.asyncio
async def test_composer_upload_and_publish(client, auth_headers):
    image = io.BytesIO()
    Image.new('RGB', (10, 10)).save(image, format='PNG')
    response = await client.post('/api/v1/social/composer/upload',headers=auth_headers,files={'file':('photo.png',image.getvalue(),'image/png')})
    assert response.status_code == 200, response.text
    attachment = response.json()
    audio = io.BytesIO()
    with wave.open(audio,'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(8000)
        output.writeframes(b'\0\0'*800)
    response = await client.post('/api/v1/social/composer/upload',headers=auth_headers,files={'file':('song.wav',audio.getvalue(),'audio/wav')})
    assert response.status_code == 200, response.text
    song = response.json()
    response = await client.post('/api/v1/social/posts',headers=auth_headers,json={'text':'Music and photo','media':[attachment],'music_id':song['id']})
    assert response.status_code == 201, response.text
    saved = await client.get('/api/v1/music/content/post/'+response.json()['id'],headers=auth_headers)
    assert saved.status_code == 200, saved.text
    assert saved.json()['source'] == 'local'
    assert saved.json()['id'] == song['id']

@pytest.mark.asyncio
async def test_composer_rejects_invalid_upload(client,auth_headers):
    response = await client.post('/api/v1/social/composer/upload',headers=auth_headers,files={'file':('fake.png',b'invalid','image/png')})
    assert response.status_code == 422
    response = await client.post('/api/v1/social/composer/upload',files={'file':('fake.png',b'invalid','image/png')})
    assert response.status_code == 401
