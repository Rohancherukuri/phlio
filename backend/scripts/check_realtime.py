"""Local SFU media smoke test: uv run --with livekit python -m scripts.check_realtime.

Publishes generated silent audio and colored frames between two test clients;
does not access a camera/microphone or contact another person.
"""
import asyncio
import uuid
from livekit import rtc, api
from app.config import Settings


async def main():
    settings = Settings()
    name = 'verification-' + uuid.uuid4().hex
    sender, receiver = rtc.Room(), rtc.Room()
    audio = video = None
    counts = {'audio': 0, 'video': 0}
    readers = []
    async def read(track):
        kind = 'audio' if track.kind == rtc.TrackKind.KIND_AUDIO else 'video'
        stream = rtc.AudioStream(track) if kind == 'audio' else rtc.VideoStream(track)
        try:
            async for _ in stream:
                counts[kind] += 1
        finally:
            await stream.aclose()
    @receiver.on('track_subscribed')
    def subscribed(track, publication, participant):
        readers.append(asyncio.create_task(read(track)))
    def token(identity):
        return api.AccessToken(settings.livekit_api_key, settings.livekit_api_secret).with_identity(identity).with_grants(
            api.VideoGrants(room_join=True, room=name)).to_jwt()
    try:
        await receiver.connect(settings.livekit_url, token('test-receiver'))
        await sender.connect(settings.livekit_url, token('test-sender'))
        audio = rtc.AudioSource(48000, 1)
        video = rtc.VideoSource(320, 180)
        await sender.local_participant.publish_track(rtc.LocalAudioTrack.create_audio_track('test-audio', audio))
        await sender.local_participant.publish_track(rtc.LocalVideoTrack.create_video_track('test-video', video))
        for index in range(300):
            await audio.capture_frame(rtc.AudioFrame(bytes(960), 48000, 1, 480))
            if index % 3 == 0:
                frame = rtc.VideoFrame(320, 180, rtc.VideoBufferType.RGBA,
                                       bytes([index % 255, 90, 170, 255]) * (320 * 180))
                video.capture_frame(frame)
            await asyncio.sleep(.01)
        await asyncio.sleep(1)
        assert counts['audio'] > 50 and counts['video'] > 20, counts
        print('SFU media received:', counts)
    finally:
        await sender.disconnect()
        await receiver.disconnect()
        for task in readers:
            task.cancel()
        await asyncio.gather(*readers, return_exceptions=True)
        if audio:
            await audio.aclose()
        if video:
            await video.aclose()
        async with api.LiveKitAPI(settings.livekit_api_url, settings.livekit_api_key, settings.livekit_api_secret) as client:
            await client.room.delete_room(api.DeleteRoomRequest(room=name))


if __name__ == '__main__':
    asyncio.run(main())
