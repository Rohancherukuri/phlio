"""Space recording without LiveKit Egress.

A hidden `rec-…` participant joins the Space, subscribes to every audio
track and mixes them against the wall clock (so silences keep their real
length) into a 24 kHz mono WAV. When the Space ends the WAV is encoded to
AAC with ffmpeg (kept as WAV if ffmpeg is missing) and a `space_recording`
row is written: media url, duration, waveform peaks and a speaker timeline
(who was talking when) for the playback screen.

One recorder per room per process; `start` / `stop` are idempotent.
"""
import asyncio
import contextlib
import hashlib
import logging
import shutil
import subprocess
import time
import wave
from pathlib import Path

import numpy as np
from livekit import rtc

from app.domains.spaces import is_system, rtc_url, token, utcnow

log = logging.getLogger('phlio.spaces.recorder')
SR = 24000
_active: dict[str, 'SpaceRecorder'] = {}


class SpaceRecorder:
    def __init__(self, settings, store, media_root: Path, room: str, meta: dict, profile):
        self.settings, self.store, self.room_name, self.meta = settings, store, room, meta
        self.profile = profile  # async identity -> dict | None
        self.folder = media_root / 'space_recordings'
        self.folder.mkdir(parents=True, exist_ok=True)
        self.slug = hashlib.sha1(room.encode()).hexdigest()[:16]
        self.wav_path = self.folder / f'{self.slug}.wav'
        self.room = rtc.Room()
        self.buffers: dict[str, np.ndarray] = {}
        self.readers: dict[str, asyncio.Task] = {}
        self.t0 = 0.0
        self.written = 0
        self.rms: list[float] = []  # one value per 100 ms, for the waveform
        self.speaking: dict[str, float] = {}
        self.timeline: list[list] = []
        self.voices: set[str] = set()
        self.writer: asyncio.Task | None = None
        self.done = asyncio.Event()
        self.finishing = False

    # -- lifecycle ------------------------------------------------------------
    async def start(self):
        jwt = token(self.settings, identity='rec-' + self.slug, name='Recorder', room=self.room_name,
                    publish=False, data=False, hidden=True, recorder=True, ttl_minutes=30)

        @self.room.on('track_subscribed')
        def _sub(track, publication, participant):
            if track.kind == rtc.TrackKind.KIND_AUDIO and not is_system(participant.identity):
                key = participant.identity + ':' + publication.sid
                self.buffers[key] = np.zeros(0, np.float32)
                self.readers[key] = asyncio.create_task(self._read(key, track))

        @self.room.on('track_unsubscribed')
        def _unsub(track, publication, participant):
            key = participant.identity + ':' + publication.sid
            task = self.readers.pop(key, None)
            if task:
                task.cancel()

        @self.room.on('active_speakers_changed')
        def _speakers(speakers):
            now = self._clock()
            current = {p.identity for p in speakers if not is_system(p.identity)}
            for ident in list(self.speaking):
                if ident not in current:
                    start = self.speaking.pop(ident)
                    if now - start > 0.25:
                        self.timeline.append([round(start, 2), round(now, 2), ident])
            for ident in current:
                self.speaking.setdefault(ident, now)
                self.voices.add(ident)

        @self.room.on('disconnected')
        def _gone(*_):
            if not self.finishing:
                asyncio.create_task(self.stop())

        await self.room.connect(rtc_url(self.settings), jwt,
                                rtc.RoomOptions(auto_subscribe=True))
        self.t0 = time.monotonic()
        self.wav = wave.open(str(self.wav_path), 'wb')
        self.wav.setnchannels(1)
        self.wav.setsampwidth(2)
        self.wav.setframerate(SR)
        self.writer = asyncio.create_task(self._write())
        log.info('Recording %s', self.room_name)

    def _clock(self) -> float:
        return time.monotonic() - self.t0 if self.t0 else 0.0

    async def _read(self, key, track):
        stream = rtc.AudioStream(track, sample_rate=SR, num_channels=1)
        try:
            async for event in stream:
                pcm = np.frombuffer(event.frame.data, dtype=np.int16).astype(np.float32) / 32768
                buf = self.buffers.get(key)
                if buf is None:
                    break
                buf = np.concatenate([buf, pcm])
                if len(buf) > SR:  # more than 1 s behind: drop the oldest audio
                    buf = buf[-SR // 2:]
                self.buffers[key] = buf
        except asyncio.CancelledError:
            pass
        finally:
            self.buffers.pop(key, None)
            with contextlib.suppress(Exception):
                await stream.aclose()

    async def _write(self):
        """Every 100 ms, emit exactly the samples the wall clock says are
        due (lagging 300 ms so network jitter has arrived)."""
        try:
            while True:
                await asyncio.sleep(0.1)
                self._flush(max(0.0, self._clock() - 0.3))
        except asyncio.CancelledError:
            self._flush(self._clock())

    def _flush(self, until: float):
        due = int(until * SR) - self.written
        if due <= 0:
            return
        mix = np.zeros(due, np.float32)
        for key, buf in list(self.buffers.items()):
            take = buf[:due]
            mix[:len(take)] += take
            self.buffers[key] = buf[len(take):]
        mix = np.clip(mix, -1, 1)
        self.wav.writeframes((mix * 32767).astype(np.int16).tobytes())
        self.written += due
        block = SR // 10
        for i in range(0, len(mix), block):
            seg = mix[i:i + block]
            self.rms.append(float(np.sqrt(np.mean(seg ** 2))) if len(seg) else 0.0)

    async def stop(self):
        if self.finishing:
            await self.done.wait()
            return
        self.finishing = True
        _active.pop(self.room_name, None)
        try:
            if self.writer:
                self.writer.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await self.writer
            for task in list(self.readers.values()):
                task.cancel()
            now = self._clock()
            for ident, start in self.speaking.items():
                self.timeline.append([round(start, 2), round(now, 2), ident])
            with contextlib.suppress(Exception):
                await self.room.disconnect()
            if hasattr(self, 'wav'):
                self.wav.close()
                await self._save()
        except Exception:
            log.exception('Could not finish recording %s', self.room_name)
        finally:
            self.done.set()

    async def _save(self):
        duration = self.written / SR
        if duration < 3:
            self.wav_path.unlink(missing_ok=True)
            return
        media = self.wav_path
        if shutil.which('ffmpeg'):
            m4a = self.wav_path.with_suffix('.m4a')
            proc = await asyncio.create_subprocess_exec(
                'ffmpeg', '-y', '-loglevel', 'error', '-i', str(self.wav_path), '-c:a', 'aac',
                '-b:a', '64k', str(m4a), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if await proc.wait() == 0:
                self.wav_path.unlink(missing_ok=True)
                media = m4a
        speakers = []
        for ident in sorted(self.voices | {self.meta.get('host_id', '')} - {''},
                            key=lambda i: (i != self.meta.get('host_id'), i)):
            person = await self.profile(ident)
            if person:
                speakers.append(person)
        await save_recording(self.store, self.room_name, self.meta, media_url='/media/space_recordings/' + media.name,
                             duration=duration, peaks=bucket(self.rms), timeline=sorted(self.timeline),
                             speakers=speakers)
        log.info('Saved recording of %s (%.0fs)', self.room_name, duration)


def bucket(values: list[float], n: int = 96) -> list[float]:
    if not values:
        return []
    chunks = np.array_split(np.array(values, np.float32), min(n, len(values)))
    peaks = np.array([float(c.max()) if len(c) else 0.0 for c in chunks])
    top = float(np.percentile(peaks, 98)) or 1.0
    return [round(float(min(1.0, v / top)), 3) for v in peaks]


async def save_recording(store, room, meta, *, media_url, duration, peaks, timeline, speakers,
                         ended_at=None, started_at=None):
    row = dict(room=room, title=meta.get('title') or 'Space', topics=meta.get('topics') or [],
               host_id=meta.get('host_id'), host_name=meta.get('name'),
               started_at=started_at or meta.get('started_at') or utcnow(), ended_at=ended_at or utcnow(),
               duration=round(duration, 2), media_url=media_url, peaks=peaks, timeline=timeline,
               speakers=speakers, plays=0, seeded=bool(meta.get('seeded')), status='ready')
    saved = await store.put('space_recording:' + hashlib.sha1(room.encode()).hexdigest()[:20], row)
    session = await store.get('live_session:' + room)
    if session:
        await store.put(session['id'], dict(session, recording_url=media_url))
    return saved


async def start(settings, store, media_root, room, meta, profile):
    if room in _active:
        return _active[room]
    rec = SpaceRecorder(settings, store, media_root, room, meta, profile)
    _active[room] = rec
    try:
        await rec.start()
    except Exception:
        _active.pop(room, None)
        log.exception('Could not start recording %s', room)
        return None
    return rec


def is_recording(room: str) -> bool:
    return room in _active


async def stop(room: str):
    rec = _active.get(room)
    if rec:
        await rec.stop()
