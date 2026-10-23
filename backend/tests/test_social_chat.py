import json
import shutil
import subprocess

import pytest
from fastapi import HTTPException

from app.domains.messaging.media_policy import IMAGE_LIMIT, MEDIA_LIMIT, validate_size
from app.domains.messaging.service import MessagingService


async def login(client, username):
    response = await client.post(
        "/api/v1/auth/login", json={"identifier": username, "password": "password123"}
    )
    return {"Authorization": f"Bearer {response.json()['tokens']['access_token']}"}


PNG = b"\x89PNG\r\n\x1a\nimage"
BASE = "/api/v1/messaging/peers/neha"


async def test_public_chat_is_separate_and_text_pack_only(client, auth_headers):
    path = "/api/v1/social/creators/neha/chat"
    assert (await client.get(path)).status_code == 401
    await client.post(BASE + "/messages", headers=auth_headers, json={"text": "Private secret"})
    assert (await client.get(path, headers=auth_headers)).json() == []
    for kind in ["image", "video", "audio", "document"]:
        r = await client.post(
            path, headers=auth_headers, json={"attachments": [{"kind": kind, "name": "file"}]}
        )
        assert r.status_code == 422
    assert (
        await client.post(
            path,
            headers=auth_headers,
            json={"attachments": [{"kind": "sticker", "name": "unknown", "value": "unknown"}]},
        )
    ).status_code == 422
    sent = await client.post(
        path,
        headers=auth_headers,
        json={"text": "Public hello", "attachments": [{"kind": "gif", "name": "Wave", "value": "anim_wave"}]},
    )
    assert sent.status_code == 201, sent.text
    outsider = await login(client, "artbykiara")
    messages = (await client.get(path, headers=outsider)).json()
    assert [m["text"] for m in messages] == ["Public hello"]
    assert messages[0]["username"] == "arjun"
    assert len((await client.get(BASE + "/messages", headers=auth_headers)).json()) == 1


async def test_dm_media_rules_and_cleanup(client, auth_headers, settings):
    for name, data in [("notes.pdf", b"%PDF"), ("fake.jpg", b"%PDF-not-an-image"), ("empty.png", b"")]:
        response = await client.post(BASE + "/files", headers=auth_headers, files=[("files", (name, data))])
        assert response.status_code == 422, response.text
    response = await client.post(
        BASE + "/files",
        headers=auth_headers,
        files=[("files", ("ok.png", PNG)), ("files", ("large.png", PNG + b"x" * IMAGE_LIMIT))],
    )
    assert response.status_code == 413
    from pathlib import Path

    assert list(Path(settings.messaging_media_root).iterdir()) == []
    forged = await client.post(
        BASE + "/messages",
        headers=auth_headers,
        json={"attachments": [{"kind": "document", "name": "file", "url": "https://example.org/secret.pdf"}]},
    )
    assert forged.status_code == 422


@pytest.mark.parametrize(
    "kind,limit", [("image", IMAGE_LIMIT), ("video", MEDIA_LIMIT), ("audio", MEDIA_LIMIT)]
)
def test_dm_limit_boundaries(kind, limit):
    validate_size(kind, limit)
    with pytest.raises(HTTPException) as e:
        validate_size(kind, limit + 1)
    assert e.value.status_code == 413


async def test_sent_sticker_overlays_shared_but_sender_owned(client, auth_headers):
    recipient = await login(client, "neha")
    outsider = await login(client, "artbykiara")
    sent = (await client.post(BASE + "/messages", headers=auth_headers, json={"text": "Decorate me"})).json()
    path = BASE + "/messages/" + sent["id"] + "/overlays"
    body = {"overlays": [{"value": "costume_wizard", "x": 0.25, "y": 0.75, "scale": 1.5}]}
    assert (await client.put(path, headers=auth_headers, json=body)).status_code == 200
    history = (await client.get("/api/v1/messaging/peers/arjun/messages", headers=recipient)).json()
    assert history[0]["overlays"] == body["overlays"]
    assert (await client.put(path, headers=outsider, json=body)).status_code == 404
    assert (
        await client.put(
            "/api/v1/messaging/peers/arjun/messages/" + sent["id"] + "/overlays", headers=recipient, json=body
        )
    ).status_code == 404
    body["overlays"][0]["x"] = 2
    assert (await client.put(path, headers=auth_headers, json=body)).status_code == 422
    assert (await client.put(path, headers=auth_headers, json={"overlays": []})).status_code == 200


async def test_video_trim_mute_rotate_export(client, auth_headers, tmp_path):
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        pytest.skip("Video editing integration requires ffmpeg and ffprobe")
    source = tmp_path / "source.mp4"
    subprocess.run(
        [
            ffmpeg,
            "-v",
            "error",
            "-f",
            "lavfi",
            "-i",
            "color=c=red:s=64x48:r=10:d=3",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:duration=3",
            "-c:v",
            "libx264",
            "-c:a",
            "aac",
            "-y",
            str(source),
        ],
        check=True,
    )
    result = await client.post(
        BASE + "/files",
        headers=auth_headers,
        data={"edits": json.dumps([{"start": 1, "end": 2, "mute": True, "turns": 1}])},
        files=[("files", ("clip.mp4", source.read_bytes()))],
    )
    assert result.status_code == 201, result.text
    output = tmp_path / "edited.mp4"
    output.write_bytes((await client.get(result.json()[0]["url"], headers=auth_headers)).content)
    details = json.loads(
        subprocess.check_output(
            [ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(output)]
        )
    )
    assert float(details["format"]["duration"]) == pytest.approx(1, abs=0.2)
    assert len(details["streams"]) == 1
    assert (details["streams"][0]["width"], details["streams"][0]["height"]) == (48, 64)


def test_chat_and_overlays_survive_restart(tmp_path):
    path = str(tmp_path / "messages.db")
    s = MessagingService(path)
    s.public_send("alice", "bob", "bob", "Hello everyone", [])
    message = s.send("alice", "bob", "Private", [])
    s.overlays(message["id"], "alice", "bob", [{"value": "costume_wizard", "x": 0.5, "y": 0.5, "scale": 1}])
    s.db.close()
    reopened = MessagingService(path)
    assert reopened.public_history("alice")[0]["text"] == "Hello everyone"
    assert len(reopened.history("bob", "alice")[0]["overlays"]) == 1
    reopened.db.close()
