"""Moment reactions, viewers and comments; Experience collaborators,
places and video edits; story effects in filter specs."""

from __future__ import annotations

import io
import json
import shutil
import subprocess
from pathlib import Path

import pytest
from httpx import AsyncClient
from PIL import Image

from app.api.v1.media_edits import ffmpeg_command, parse_media_edits

pytestmark = pytest.mark.asyncio


def png() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (48, 48), (40, 160, 220)).save(buf, "PNG")
    return buf.getvalue()


async def login(client: AsyncClient, name: str) -> dict:
    r = await client.post("/api/v1/auth/login", json={"identifier": name, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}


async def befriend(client: AsyncClient, a: dict, b: dict, b_name: str, a_name: str) -> None:
    assert (await client.post("/api/v1/messaging/friends", headers=a, json={"peer": b_name})).status_code == 201
    r = await client.post(f"/api/v1/messaging/friends/{a_name}/accept", headers=b)
    assert r.status_code == 204, r.text


async def moment(client: AsyncClient, headers: dict, **data) -> dict:
    r = await client.post("/api/v1/social/moments", headers=headers,
                          files={"file": ("m.png", png(), "image/png")}, data=data)
    assert r.status_code == 201, r.text
    return r.json()


async def test_reactions_show_in_viewers(client: AsyncClient, auth_headers: dict) -> None:
    m = await moment(client, auth_headers)
    neha = await login(client, "neha")
    base = f"/api/v1/social/moments/{m['id']}"
    assert (await client.put(base + "/seen", headers=neha)).status_code == 204
    assert (await client.put(base + "/reaction", headers=neha, json={"emoji": "😍"})).status_code == 200
    # Own moment: no reacting.
    assert (await client.put(base + "/reaction", headers=auth_headers, json={"emoji": "😍"})).status_code == 422

    v = (await client.get(base + "/viewers", headers=auth_headers)).json()
    assert v["count"] == 1 and v["reactions"] == 1
    assert v["people"][0]["username"] == "neha" and v["people"][0]["reaction"] == "😍"
    assert (await client.get(base + "/viewers", headers=neha)).status_code == 403

    mine = (await client.get("/api/v1/social/moments/user/arjun", headers=auth_headers)).json()["items"]
    item = next(i for i in mine if i["id"] == m["id"])
    assert item["view_count"] == 1 and item["reaction_count"] == 1 and item["comment_count"] == 0
    theirs = (await client.get("/api/v1/social/moments/user/arjun", headers=neha)).json()["items"]
    assert next(i for i in theirs if i["id"] == m["id"])["my_reaction"] == "😍"

    assert (await client.delete(base + "/reaction", headers=neha)).status_code == 204
    v = (await client.get(base + "/viewers", headers=auth_headers)).json()
    assert v["people"][0]["reaction"] is None


async def test_comments_thread_permissions(client: AsyncClient, auth_headers: dict) -> None:
    m = await moment(client, auth_headers)
    neha = await login(client, "neha")
    kiara = await login(client, "artbykiara")
    base = f"/api/v1/social/moments/{m['id']}/comments"

    q = await client.post(base, headers=neha, json={"text": "Which part was your fave?"})
    assert q.status_code == 201, q.text
    q = q.json()
    a = (await client.post(base, headers=auth_headers, json={"text": "When we made the dough :)", "reply_to": q["id"]})).json()
    assert a["reply_to"] == q["id"] and a["reply_to_user"] == "neha" and a["by_author"]
    # Replying to a reply stays in the same thread.
    b = (await client.post(base, headers=kiara, json={"text": "Same!", "reply_to": a["id"]})).json()
    assert b["reply_to"] == q["id"]
    late = (await client.post(base, headers=kiara, json={"text": "Lovely"})).json()

    # Comments land in DMs: the author got Neha's and Kiara's; Neha got the replies to her.
    arjun_dms = (await client.get("/api/v1/messaging/peers/neha/messages", headers=auth_headers)).json()
    texts = [m["text"] for m in (arjun_dms["items"] if isinstance(arjun_dms, dict) else arjun_dms)]
    assert any(t.startswith("💬 Commented on your moment: Which part was your fave?") for t in texts)
    assert any(t.startswith("↩️ Replied to your comment on my moment: When we made the dough") for t in texts)
    kiara_dms = (await client.get("/api/v1/messaging/peers/artbykiara/messages", headers=auth_headers)).json()
    ktexts = [m["text"] for m in (kiara_dms["items"] if isinstance(kiara_dms, dict) else kiara_dms)]
    assert any("Commented on your moment: Lovely" in t for t in ktexts)

    listed = (await client.get(base, headers=kiara)).json()
    assert listed["count"] == 4 and [i["id"] for i in listed["items"]] == [q["id"], a["id"], b["id"], late["id"]]
    assert listed["items"][0]["can_delete"] is False

    # Edit own; can't edit others'.
    e = await client.put(f"{base}/{a['id']}", headers=auth_headers, json={"text": "Making the dough!"})
    assert e.status_code == 200 and e.json()["edited_at"]
    assert (await client.put(f"{base}/{a['id']}", headers=neha, json={"text": "x"})).status_code == 403
    # Others can't delete; the author can delete anything (and its replies go too).
    assert (await client.delete(f"{base}/{late['id']}", headers=neha)).status_code == 403
    assert (await client.delete(f"{base}/{q['id']}", headers=auth_headers)).status_code == 204
    left = (await client.get(base, headers=auth_headers)).json()
    assert [i["id"] for i in left["items"]] == [late["id"]]

    mine = (await client.get("/api/v1/social/moments/user/arjun", headers=auth_headers)).json()["items"]
    assert next(i for i in mine if i["id"] == m["id"])["comment_count"] == 1

    v = (await client.get(f"/api/v1/social/moments/{m['id']}/viewers", headers=auth_headers)).json()
    assert v["comments"] == 1

    # Deleting the moment removes its comments.
    assert (await client.delete(f"/api/v1/social/moments/{m['id']}", headers=auth_headers)).status_code == 204
    assert (await client.get(base, headers=auth_headers)).status_code == 404


async def test_comments_off(client: AsyncClient, auth_headers: dict) -> None:
    m = await moment(client, auth_headers, allow_comments="false")
    neha = await login(client, "neha")
    base = f"/api/v1/social/moments/{m['id']}/comments"
    assert (await client.post(base, headers=neha, json={"text": "hi"})).status_code == 403
    listed = (await client.get(base, headers=neha)).json()
    assert listed["allow_comments"] is False and listed["count"] == 0
    assert (await client.post(base, headers=neha, json={"text": "   "})).status_code in (403, 422)


async def test_story_fx_in_filter_spec(client: AsyncClient, auth_headers: dict) -> None:
    spec = {"look": "normal", "fx": "vhs", "fx_amount": 0.7, "adjust": {"warmth": 0.3, "contrast": -0.2}}
    m = await moment(client, auth_headers, filter_spec=json.dumps(spec))
    assert m["filter_spec"]["fx"] == "vhs" and m["filter_spec"]["adjust"] == {"warmth": 0.3, "contrast": -0.2}
    bad = await client.post("/api/v1/social/moments", headers=auth_headers, files={"file": ("m.png", png(), "image/png")},
                            data={"filter_spec": json.dumps({"fx": "vhs", "adjust": {"glow": 0.4}})})
    assert bad.status_code == 422
    bad = await client.post("/api/v1/social/moments", headers=auth_headers, files={"file": ("m.png", png(), "image/png")},
                            data={"filter_spec": json.dumps({"adjust": {"warmth": 3}})})
    assert bad.status_code == 422


async def test_experience_collaborators_and_place(client: AsyncClient, auth_headers: dict) -> None:
    neha = await login(client, "neha")
    kiara = await login(client, "artbykiara")
    place = {"name": "La Cabra Bakery", "address": "E 4th St", "lat": 40.7265, "lng": -73.9897, "source": "photo"}

    async def post(headers, **data):
        return await client.post("/api/v1/social/memories", headers=headers,
                                 files={"file": ("e.png", png(), "image/png")},
                                 data={"kind": "experience", "audience": "friends", **data})

    # Not friends yet.
    r = await post(auth_headers, group="exp_trip", collaborators=json.dumps(["neha"]))
    assert r.status_code == 422
    await befriend(client, auth_headers, neha, "neha", "arjun")
    await befriend(client, auth_headers, kiara, "artbykiara", "arjun")

    r = await post(auth_headers, group="exp_trip", collaborators=json.dumps(["neha"]),
                   caption="Europe with @artbykiara and @nobody_here", location=json.dumps(place))
    assert r.status_code == 201, r.text
    first = r.json()
    assert set(first["collaborators"]) == {(await client.get("/api/v1/auth/me", headers=neha)).json()["id"],
                                           (await client.get("/api/v1/auth/me", headers=kiara)).json()["id"]}
    assert first["location"]["name"] == "La Cabra Bakery" and first["location"]["source"] == "photo"

    # A collaborator adds to the same dump.
    added = await post(neha, group="exp_trip")
    assert added.status_code == 201, added.text
    assert added.json()["group_owner"] == first["author"]

    listed = (await client.get("/api/v1/social/memories", headers=kiara)).json()
    dump = [m for m in listed if m.get("group") == "exp_trip"]
    assert len(dump) == 2
    owners = next(m for m in dump if m["author"]["username"] == "arjun")
    assert {p["username"] for p in owners["collaborators"]} == {"neha", "artbykiara"}
    joined = next(m for m in dump if m["author"]["username"] == "neha")
    assert {p["username"] for p in joined["collaborators"]} == {"arjun", "artbykiara"}

    # Owner removes Kiara; she can no longer add.
    r = await client.put("/api/v1/social/memories/groups/exp_trip/collaborators", headers=auth_headers,
                         json={"collaborators": ["neha"]})
    assert r.status_code == 200 and [p["username"] for p in r.json()["collaborators"]] == ["neha"]
    assert (await post(kiara, group="exp_trip")).status_code == 403
    assert (await client.put("/api/v1/social/memories/groups/exp_trip/collaborators", headers=neha,
                             json={"collaborators": []})).status_code == 403

    assert (await post(auth_headers, location=json.dumps({"name": "x", "lat": 95, "lng": 0}))).status_code == 422
    # Snaps can't have collaborators.
    r = await client.post("/api/v1/social/memories", headers=auth_headers, files={"file": ("e.png", png(), "image/png")},
                          data={"kind": "snap", "collaborators": json.dumps(["neha"])})
    assert r.status_code == 422


async def test_media_edits_validation_and_command(tmp_path: Path) -> None:
    assert parse_media_edits("") is None
    assert parse_media_edits(json.dumps({"speed": 1})) is None  # a no-op
    edits = parse_media_edits(json.dumps({"trim_start": 1, "trim_end": 4, "speed": 2, "rotate": 90, "flip": True,
                                          "crop": [0.1, 0, 0.8, 1]}))
    cmd = " ".join(ffmpeg_command(Path("a.mp4"), Path("b.mp4"), edits))
    assert "-ss 1.000" in cmd and "-to 4.000" in cmd and "transpose=1" in cmd and "hflip" in cmd
    assert "setpts=PTS/2.0000" in cmd and "atempo=2" in cmd and "crop=iw*0.8000" in cmd
    boomerang = " ".join(ffmpeg_command(Path("a.mp4"), Path("b.mp4"), {"motion": "boomerang"}))
    assert "reverse" in boomerang and "-an" in boomerang
    slow = ffmpeg_command(Path("a.mp4"), Path("b.mp4"), {"motion": "slow_motion", "speed": 0.5})
    assert "atempo=0.5" in " ".join(slow)  # 0.25x needs two stages
    for bad in ({"trim_start": 3, "trim_end": 3.1}, {"crop": [0.5, 0, 0.8, 1]}, {"speed": 9}, {"motion": "teleport"}):
        with pytest.raises(Exception):
            parse_media_edits(json.dumps(bad))


@pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="needs ffmpeg")
async def test_video_edits_render(client: AsyncClient, auth_headers: dict, tmp_path: Path) -> None:
    clip = tmp_path / "clip.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=160x120:rate=15:duration=3",
                    "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-shortest", "-pix_fmt", "yuv420p",
                    str(clip)], check=True)
    r = await client.post("/api/v1/social/moments", headers=auth_headers,
                          files={"file": ("clip.mp4", clip.read_bytes(), "video/mp4")},
                          data={"edits": json.dumps({"trim_start": 0.5, "trim_end": 2.5, "rotate": 90, "speed": 2})})
    assert r.status_code == 201, r.text
    url = r.json()["media_url"]
    assert url.endswith("-edit.mp4")
    root = Path(client._transport.app.state.container.settings.media_root)  # type: ignore[attr-defined]
    path = root / url.removeprefix("/media/")
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                            "stream=width,height:format=duration", "-of", "json", str(path)],
                           capture_output=True, check=True)
    info = json.loads(probe.stdout)
    assert info["streams"][0]["width"] == 120 and info["streams"][0]["height"] == 160  # rotated
    assert float(info["format"]["duration"]) < 1.4  # 2 s trimmed, played at 2x
    boom = await client.post("/api/v1/social/memories", headers=auth_headers,
                             files={"file": ("clip.mp4", clip.read_bytes(), "video/mp4")},
                             data={"kind": "experience", "edits": json.dumps({"motion": "boomerang"})})
    assert boom.status_code == 201, boom.text



async def test_comment_mentions_share_and_report(client: AsyncClient, auth_headers: dict) -> None:
    m = await moment(client, auth_headers)
    neha = await login(client, "neha")
    base = f"/api/v1/social/moments/{m['id']}/comments"
    c = (await client.post(base, headers=neha, json={"text": "Look @arjun and @nobody_xyz."})).json()
    assert [p["username"] for p in c["mentions"]] == ["arjun"]
    r = await client.post(f"{base}/{c['id']}/share", headers=auth_headers,
                          json={"destination": "dm", "target": "artbykiara", "message": "lol"})
    assert r.status_code == 201, r.text
    dms = (await client.get("/api/v1/messaging/peers/artbykiara/messages", headers=auth_headers)).json()
    texts = [x["text"] for x in (dms["items"] if isinstance(dms, dict) else dms)]
    assert any(t.startswith("💬 Shared a comment by @neha on @arjun's moment") for t in texts) and "lol" in texts
    assert (await client.post(f"{base}/{c['id']}/report", headers=auth_headers, json={"reason": "Spam"})).status_code == 204


async def test_content_comment_share(client: AsyncClient, auth_headers: dict) -> None:
    feed = (await client.get("/api/v1/social/feed", headers=auth_headers)).json()
    post = (feed["items"] if isinstance(feed, dict) else feed)[0]
    pid = post["id"]
    c = await client.post(f"/api/v1/social/content/{pid}/comments", headers=auth_headers,
                          data={"text": "hey @neha."})
    assert c.status_code == 201, c.text
    comment = c.json()
    assert [p["username"] for p in comment["mentions"]] == ["neha"]
    r = await client.post(f"/api/v1/content/social/{pid}/share", headers=auth_headers,
                          json={"destination": "dm", "target": "neha", "comment_id": comment["id"]})
    assert r.status_code == 201, r.text
    dms = (await client.get("/api/v1/messaging/peers/neha/messages", headers=auth_headers)).json()
    texts = [x["text"] for x in (dms["items"] if isinstance(dms, dict) else dms)]
    assert any(t.startswith("💬 Shared a comment by @arjun") and "“hey @neha.”" in t for t in texts)
    bad = await client.post(f"/api/v1/content/social/{pid}/share", headers=auth_headers,
                            json={"destination": "dm", "target": "neha", "comment_id": "content_comment:nope"})
    assert bad.status_code == 404
    listed = (await client.get(f"/api/v1/social/content/{pid}/comments", headers=auth_headers)).json()["items"]
    assert "liked_by_author" in listed[0]



async def test_moment_mentions_and_applied_look(client: AsyncClient, auth_headers: dict) -> None:
    spec = {"look": "normal", "applied_look": "clarendon", "fx": "vhs"}
    m = await moment(client, auth_headers, caption="with @artbykiara", mentions=json.dumps(["neha", "@neha", "arjun"]),
                     filter_spec=json.dumps(spec))
    assert sorted(p["username"] for p in m["mentions"]) == ["artbykiara", "neha"]
    assert m["filter_spec"]["applied_look"] == "clarendon"
    bad = await client.post("/api/v1/social/moments", headers=auth_headers, files={"file": ("m.png", png(), "image/png")},
                            data={"mentions": json.dumps({"a": 1})})
    assert bad.status_code == 422
