"""Phlio Spaces — live audio rooms on LiveKit.

Roles live in each participant's LiveKit metadata (`{"role": ...}`):
host, cohost, speaker or listener. Speakers are listeners whose publish
permission the host switched on; the server is the only one that changes
permissions (see `promote` / `demote`).
"""
import datetime as dt
import hashlib
import json

from livekit import api

ROLE_HOST, ROLE_COHOST, ROLE_SPEAKER, ROLE_LISTENER = 'host', 'cohost', 'speaker', 'listener'
DATA_TOPIC = 'space'


def utcnow() -> str:
    return dt.datetime.now(dt.UTC).isoformat()


def rtc_url(settings) -> str:
    """WebSocket URL for server-side participants (recorder, seeded hosts).
    Prefer the local API address — it is reachable from this machine even
    when LIVEKIT_URL is the LAN address handed to phones."""
    base = settings.livekit_api_url or settings.livekit_url
    return base.replace('https://', 'wss://').replace('http://', 'ws://')


def token(settings, *, identity: str, name: str, room: str, publish: bool, data: bool = True,
          hidden: bool = False, recorder: bool = False, role: str = ROLE_LISTENER,
          audio_only: bool = True, ttl_minutes: int = 10) -> str:
    grants = api.VideoGrants(
        room_join=True, room=room, can_subscribe=True, can_publish=publish,
        can_publish_data=data, can_publish_sources=['microphone'] if audio_only else None,
        hidden=hidden or None, recorder=recorder or None)
    return (api.AccessToken(settings.livekit_api_key, settings.livekit_api_secret)
            .with_identity(identity).with_name(name)
            .with_metadata(json.dumps({'role': role}))
            .with_ttl(dt.timedelta(minutes=ttl_minutes))
            .with_grants(grants)
            .to_jwt())


def role_of(participant, host_id: str) -> str:
    if participant.identity == host_id:
        return ROLE_HOST
    try:
        role = json.loads(participant.metadata or '{}').get('role')
    except ValueError:
        role = None
    if role in (ROLE_COHOST, ROLE_SPEAKER) and participant.permission.can_publish:
        return role
    return ROLE_SPEAKER if participant.permission.can_publish else ROLE_LISTENER


def is_system(identity: str) -> bool:
    """Recorder and anonymous listeners are never shown as people."""
    return identity.startswith(('rec-', 'anon-'))


def request_key(room: str, user_id: str) -> str:
    return 'space_request:' + hashlib.sha1(f'{room}|{user_id}'.encode()).hexdigest()


async def set_role(lk, room: str, identity: str, role: str):
    """Switch a participant between listener and speaker/co-host."""
    speaking = role in (ROLE_SPEAKER, ROLE_COHOST, ROLE_HOST)
    await lk.room.update_participant(api.UpdateParticipantRequest(
        room=room, identity=identity, metadata=json.dumps({'role': role}),
        permission=api.ParticipantPermission(
            can_subscribe=True, can_publish=speaking, can_publish_data=True,
            can_publish_sources=[api.TrackSource.MICROPHONE] if speaking else [])))


async def send(lk, room: str, payload: dict, to: list[str] | None = None):
    await lk.room.send_data(api.SendDataRequest(
        room=room, data=json.dumps(payload).encode(), kind=api.DataPacket.Kind.RELIABLE,
        destination_identities=to or [], topic=DATA_TOPIC))
