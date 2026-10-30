import io
import wave
from pathlib import Path
from app.domains.messaging import audio_enhancement
from tests.test_messaging import login

async def test_improve_voice_sender_only_restorable_and_private(client, auth_headers, monkeypatch):
    data = io.BytesIO()
    with wave.open(data, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(48000)
        wav.writeframes(bytes(9600))
    upload = await client.post('/api/v1/messaging/peers/neha/files', headers=auth_headers,
        files=[('files', ('voice.wav', data.getvalue(), 'audio/wav'))])
    assert upload.status_code == 201, upload.text
    sent = await client.post('/api/v1/messaging/peers/neha/messages', headers=auth_headers,
        json={'attachments': upload.json()})
    assert sent.status_code == 201, sent.text
    message = sent.json()
    original = message['attachments'][0]
    url = f"/api/v1/messaging/peers/neha/messages/{message['id']}/improve-audio"
    body = {'attachment_id': original['id']}
    calls = []
    def enhance(source, output):
        calls.append(source)
        output.write_bytes(b'clean audio')
    monkeypatch.setattr(audio_enhancement, 'enhance_audio', enhance)
    recipient = await login(client, 'neha')
    outsider = await login(client, 'artbykiara')
    assert (await client.post(url, headers=outsider, json=body)).status_code == 404
    assert (await client.post(url, headers=recipient, json=body)).status_code == 403
    result = await client.post(url, headers=auth_headers, json=body)
    assert result.status_code == 200, result.text
    history = await client.get('/api/v1/messaging/peers/neha/messages', headers=auth_headers)
    clean = history.json()[0]['attachments'][0]
    assert clean['enhanced_by'] == 'DeepFilterNet3'
    assert clean['original_audio'] == original
    assert (await client.get(clean['url'], headers=recipient)).content == b'clean audio'
    assert (await client.get(clean['url'], headers=outsider)).status_code == 404
    assert (await client.get(original['url'], headers=auth_headers)).content == data.getvalue()
    body['attachment_id'] = clean['id']
    assert (await client.post(url, headers=auth_headers, json=body)).status_code == 200
    assert len(calls) == 1
    body['restore'] = True
    assert (await client.post(url, headers=auth_headers, json=body)).status_code == 200
    history = await client.get('/api/v1/messaging/peers/neha/messages', headers=auth_headers)
    assert history.json()[0]['attachments'][0] == original

    from fastapi import HTTPException
    def broken(source, output):
        raise HTTPException(503, 'Enhancer unavailable')
    monkeypatch.setattr(audio_enhancement, 'enhance_audio', broken)
    body = {'attachment_id': original['id']}
    assert (await client.post(url, headers=auth_headers, json=body)).status_code == 503
    history = await client.get('/api/v1/messaging/peers/neha/messages', headers=auth_headers)
    assert history.json()[0]['attachments'][0] == original
