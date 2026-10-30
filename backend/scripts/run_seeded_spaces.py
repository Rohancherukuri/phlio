"""Keep a handful of community Spaces live on the local LiveKit server.

Each seeded Space is a real LiveKit room: its host and speakers are demo
community accounts connected as participants, each publishing their own
voice track (Kokoro-TTS conversations in media/spaces_seed/<key>/, looped
in sync), plus a few listener accounts that come and go. So the Spaces bar,
join sheet, speaking rings, reactions and "request to speak" all behave
exactly as they do for a real Space:

  * hosts approve speak requests after a few seconds, so you can join the
    conversation (your mic goes live like any speaker's);
  * listeners send the odd reaction;
  * Spaces marked `record` are recorded by the same recorder the API uses,
    and every few minutes a Space wraps up and another one starts, so
    "Recorded" fills up over time. Three recordings are pre-seeded from the
    conversation mixes on first run.

Run: uv run python -m scripts.run_seeded_spaces [--listeners 5] [--live 6]
(Start-GraphDemo.ps1 starts it in the background when LiveKit is set up.)
Only demo accounts (is_test_user) ever take part.
"""
import argparse
import asyncio
import contextlib
import datetime as dt
import hashlib
import json
import logging
import os
import random
import shutil
import signal
import subprocess
import time
import uuid
from pathlib import Path

import numpy as np
from livekit import api, rtc

from app.core.container import build_container, media_root_path
from app.domains.spaces import (DATA_TOPIC, ROLE_HOST, ROLE_LISTENER, ROLE_SPEAKER, request_key,
                                rtc_url, send, set_role, token, utcnow)
from app.domains.spaces import recorder
from scripts.run_graph_demo import settings

log = logging.getLogger('phlio.spaces.seed')
SR = 24000
FRAME = SR // 50  # 20 ms
CHUNK = SR // 10  # pushed 100 ms at a time
QUEUE_MS = 1000  # buffered audio per seeded speaker
PREFIX = 'social-seed-'
REACTIONS = ['❤️', '😂', '👏', '🔥', '💯', '🙌', '😮', '👍']
ROOT = Path(__file__).resolve().parent.parent


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', str(path), '-f', 's16le', '-ac', '1',
                          '-ar', str(SR), '-'], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.int16)


class SeededSpace:
    def __init__(self, c, lk, spec, folder, people, listeners_n, rnd):
        self.c, self.lk, self.spec, self.folder = c, lk, spec, folder
        self.people, self.listeners_n, self.rnd = people, listeners_n, rnd
        self.room = PREFIX + spec['key'] + '-' + uuid.uuid4().hex[:6]
        self.rooms: dict[str, rtc.Room] = {}
        self.tasks: list[asyncio.Task] = []
        self.host_id = spec['cast']['H'][0]

    async def open(self):
        host = self.people[self.host_id]
        self.meta = dict(host_id=self.host_id, name=host.full_name, title=self.spec['title'],
                         audio_only=True, topics=self.spec['topics'], record=self.spec['record'],
                         started_at=utcnow(), seeded=True)
        await self.lk.room.create_room(api.CreateRoomRequest(
            name=self.room, empty_timeout=30, metadata=json.dumps(self.meta)))
        await self.c.graph.store.put('live_session:' + self.room, dict(
            room=self.room, **self.meta, status='live', ended_at=None, recording_url=None))
        # Speakers, all starting from the same clock so the conversation lines up.
        tracks = {role: decode(self.folder / f'{role}.ogg') for role in self.spec['cast']}
        length = max(len(t) for t in tracks.values())
        t0 = time.monotonic() + 1.5
        offset = self.rnd.randrange(0, length // FRAME) * FRAME  # join mid-conversation
        for role, (ident, _) in self.spec['cast'].items():
            pcm = np.zeros(length, np.int16)
            pcm[:len(tracks[role])] = tracks[role]
            await self._speaker(ident, ROLE_HOST if role == 'H' else ROLE_SPEAKER, pcm, t0, offset)
        if self.spec['record']:
            await recorder.start(self.c.settings, self.c.graph.store, media_root_path(self.c.settings),
                                 self.room, self.meta, self._profile)
        pool = [p for p in self.people if p not in {i for i, _ in self.spec['cast'].values()}]
        for ident in self.rnd.sample(pool, min(len(pool), self.listeners_n)):
            await self._listener(ident)
        self.tasks += [asyncio.create_task(self._requests()), asyncio.create_task(self._life(pool))]
        log.info('Live: %s (%s)', self.spec['title'], self.room)

    async def _profile(self, ident):
        p = self.people.get(ident) or await self.c.identity_repository.get_by_id(ident)
        return p and dict(id=p.id, username=p.username, display_name=p.full_name, avatar_url=p.avatar_url)

    async def _connect(self, ident, role, publish):
        person = self.people[ident]
        room = rtc.Room()
        jwt = token(self.c.settings, identity=ident, name=person.full_name, room=self.room,
                    publish=publish, role=role, ttl_minutes=24 * 60)
        await room.connect(rtc_url(self.c.settings), jwt, rtc.RoomOptions(auto_subscribe=False))
        self.rooms[ident] = room
        return room

    async def _speaker(self, ident, role, pcm, t0, offset):
        room = await self._connect(ident, role, True)
        # A deep queue paced by the native audio clock: event-loop hiccups
        # (Windows' ~16 ms timer, a dozen bots, the recorder) no longer
        # starve the track, which is what made seeded voices stutter.
        source = rtc.AudioSource(SR, 1, queue_size_ms=QUEUE_MS)
        track = rtc.LocalAudioTrack.create_audio_track('microphone', source)
        await room.local_participant.publish_track(
            track, rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE, dtx=True))

        async def pump():
            # Every speaker starts on the same clock; after that
            # capture_frame() blocks while the queue is full, so the native
            # 48 kHz playout clock paces the stream (no asyncio.sleep jitter)
            # and speakers stay in step with each other.
            delay = t0 - time.monotonic()
            if delay > 0:
                await asyncio.sleep(delay)
            n = len(pcm)
            pos = offset % n
            while True:
                chunk = pcm[pos:pos + CHUNK]
                if len(chunk) < CHUNK:
                    chunk = np.concatenate([chunk, pcm[:CHUNK - len(chunk)]])
                await source.capture_frame(rtc.AudioFrame(chunk.tobytes(), SR, 1, CHUNK))
                pos = (pos + CHUNK) % n
        self.tasks.append(asyncio.create_task(pump()))

    async def _listener(self, ident):
        with contextlib.suppress(Exception):
            await self._connect(ident, ROLE_LISTENER, False)

    async def _requests(self):
        """The host approves requests to speak after a short beat."""
        while True:
            await asyncio.sleep(2)
            with contextlib.suppress(Exception):
                for row in await self.c.graph.store.rows('space_request', {'room': self.room,
                                                                          'status': 'pending'}):
                    age = (dt.datetime.now(dt.UTC) - dt.datetime.fromisoformat(row['created_at'])).total_seconds()
                    if age < 3:
                        continue
                    await set_role(self.lk, self.room, row['user_id'], ROLE_SPEAKER)
                    await self.c.graph.store.put(row['id'], dict(row, status='approved', decided_at=utcnow()))
                    await send(self.lk, self.room, dict(type='approved', user_id=row['user_id']),
                               to=[row['user_id']])
                    await self._react(self.host_id, '👋')

    async def _react(self, ident, emoji):
        room = self.rooms.get(ident)
        if room:
            with contextlib.suppress(Exception):
                await room.local_participant.publish_data(
                    json.dumps(dict(type='reaction', emoji=emoji)), topic=DATA_TOPIC)

    async def _life(self, pool):
        """Listeners drift in and out; someone reacts now and then."""
        while True:
            await asyncio.sleep(self.rnd.uniform(5, 14))
            listeners = [i for i in self.rooms if i not in {x for x, _ in self.spec['cast'].values()}]
            roll = self.rnd.random()
            if roll < 0.55 and self.rooms:
                await self._react(self.rnd.choice(list(self.rooms)), self.rnd.choice(REACTIONS))
            elif roll < 0.8 and len(listeners) < self.listeners_n + 3:
                free = [p for p in pool if p not in self.rooms]
                if free:
                    await self._listener(self.rnd.choice(free))
            elif listeners and len(listeners) > max(1, self.listeners_n - 3):
                ident = self.rnd.choice(listeners)
                room = self.rooms.pop(ident)
                with contextlib.suppress(Exception):
                    await room.disconnect()

    async def close(self):
        for task in self.tasks:
            task.cancel()
        await recorder.stop(self.room)
        for room in list(self.rooms.values()):
            with contextlib.suppress(Exception):
                await room.disconnect()
        self.rooms.clear()
        with contextlib.suppress(Exception):
            await self.lk.room.delete_room(api.DeleteRoomRequest(room=self.room))
        saved = await self.c.graph.store.get('live_session:' + self.room)
        if saved:
            await self.c.graph.store.put(saved['id'], dict(saved, status='ended', ended_at=utcnow()))
        log.info('Ended: %s', self.spec['title'])


async def seed_recordings(c, specs, seed_dir, people):
    """First run: three finished Spaces you can play straight away."""
    out = media_root_path(c.settings) / 'space_recordings'
    out.mkdir(parents=True, exist_ok=True)
    now = dt.datetime.now(dt.UTC)
    for n, spec in enumerate(s for s in specs if s['record']):
        room = 'social-seedrec-' + spec['key']
        if await c.graph.store.get('space_recording:' + hashlib.sha1(room.encode()).hexdigest()[:20]):
            continue
        folder = seed_dir / spec['key']
        info = json.loads((folder / 'timeline.json').read_text())
        target = out / f'seed-{spec["key"]}.m4a'
        shutil.copyfile(folder / 'mix.m4a', target)
        role_to_id = {role: ident for role, (ident, _) in spec['cast'].items()}
        speakers = []
        for role in ['H'] + [r for r in spec['cast'] if r != 'H']:
            p = people.get(role_to_id[role])
            if p:
                speakers.append(dict(id=p.id, username=p.username, display_name=p.full_name,
                                     avatar_url=p.avatar_url))
        started = now - dt.timedelta(days=n + 1, hours=random.Random(spec['key']).randint(1, 9))
        host = people[spec['cast']['H'][0]]
        meta = dict(host_id=host.id, name=host.full_name, title=spec['title'], topics=spec['topics'],
                    seeded=True)
        await recorder.save_recording(
            c.graph.store, room, meta, media_url='/media/space_recordings/' + target.name,
            duration=info['duration'], peaks=info['peaks'],
            timeline=[[a, b, role_to_id[r]] for a, b, r in info['timeline']], speakers=speakers,
            started_at=started.isoformat(),
            ended_at=(started + dt.timedelta(seconds=info['duration'])).isoformat())
        log.info('Seeded recording: %s', spec['title'])


async def main(args):
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
    c = await build_container(settings)
    s = c.settings
    if not all((s.livekit_url, s.livekit_api_key, s.livekit_api_secret)):
        raise SystemExit('LiveKit is not configured (run scripts/Start-Realtime.ps1 -Install).')
    seed_dir = media_root_path(s) / 'spaces_seed'
    specs = json.loads((seed_dir / 'spaces.json').read_text(encoding='utf-8'))
    people = {}
    for i in range(100):
        p = await c.identity_repository.get_by_id(f'demo_{i:03}')
        if p and p.is_test_user:
            people[p.id] = p
    specs = [sp for sp in specs if all(ident in people for ident, _ in sp['cast'].values())]
    if not specs:
        raise SystemExit('Seed the community accounts first (Start-GraphDemo.ps1 -Seed).')
    pid = ROOT / 'data' / 'seeded-spaces.pid'
    pid.write_text(str(os.getpid()))
    lk = api.LiveKitAPI(s.livekit_api_url or s.livekit_url, s.livekit_api_key, s.livekit_api_secret)
    rnd = random.Random()
    live: dict[str, SeededSpace] = {}
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        with contextlib.suppress(NotImplementedError, ValueError):
            asyncio.get_running_loop().add_signal_handler(sig, stop.set)
    try:
        # Clear rooms left by a previous run.
        for room in (await lk.room.list_rooms(api.ListRoomsRequest())).rooms:
            if room.name.startswith(PREFIX):
                await lk.room.delete_room(api.DeleteRoomRequest(room=room.name))
        for row in await c.graph.store.rows('live_session', {'status': 'live'}):
            if row['room'].startswith(PREFIX):
                await c.graph.store.put(row['id'], dict(row, status='ended', ended_at=utcnow()))
        await seed_recordings(c, specs, seed_dir, people)
        ends: dict[str, float] = {}
        rest: dict[str, float] = {}
        while not stop.is_set():
            now = time.monotonic()
            for key, space in list(live.items()):
                if now > ends[key]:
                    await space.close()
                    del live[key]
                    rest[key] = now + rnd.uniform(60, 180)
            for spec in specs:
                key = spec['key']
                if key in live or len(live) >= args.live or now < rest.get(key, 0):
                    continue
                space = SeededSpace(c, lk, spec, seed_dir / key, people, args.listeners, rnd)
                try:
                    await space.open()
                except Exception:
                    log.exception('Could not start %s', key)
                    await space.close()
                    rest[key] = now + 60
                    continue
                live[key] = space
                ends[key] = now + rnd.uniform(args.min_minutes, args.max_minutes) * 60
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(stop.wait(), 5)
    finally:
        for space in list(live.values()):
            with contextlib.suppress(Exception):
                await space.close()
        await lk.aclose()
        pid.unlink(missing_ok=True)
        await c.cache.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--listeners', type=int, default=5, help='listener accounts per Space')
    parser.add_argument('--live', type=int, default=6, help='Spaces live at once')
    parser.add_argument('--min-minutes', type=float, default=20)
    parser.add_argument('--max-minutes', type=float, default=45)
    with contextlib.suppress(KeyboardInterrupt):
        asyncio.run(main(parser.parse_args()))
