from app.domains.social.video_service import SocialVideoService


async def test_follow_creator(client, auth_headers):
    path = "/api/v1/social/creators/neha/follow"
    assert (await client.put(path)).status_code == 401
    assert (await client.put(path, headers=auth_headers)).status_code == 204
    assert (await client.put(path, headers=auth_headers)).status_code == 204
    assert (await client.get("/api/v1/social/following", headers=auth_headers)).json() == ["neha"]
    assert (await client.put("/api/v1/social/creators/arjun/follow", headers=auth_headers)).status_code == 422
    assert (
        await client.put("/api/v1/social/creators/missing/follow", headers=auth_headers)
    ).status_code == 404
    assert (await client.delete(path, headers=auth_headers)).status_code == 204
    assert (await client.get("/api/v1/social/following", headers=auth_headers)).json() == []


async def test_video_catalog_and_upload(client, auth_headers, monkeypatch):
    monkeypatch.setattr("app.api.v1.social_videos.probe_duration", lambda _: 60.0)
    path = "/api/v1/social/videos"
    assert (await client.get(path)).status_code == 401
    assert (
        await client.post(
            path, headers=auth_headers, data={"title": "Demo"}, files={"file": ("demo.txt", b"not video")}
        )
    ).status_code == 422
    assert (
        await client.post(
            path, headers=auth_headers, data={"title": "Demo"}, files={"file": ("demo.mp4", b"")}
        )
    ).status_code == 422
    result = await client.post(
        path, headers=auth_headers, data={"title": "My demo"}, files={"file": ("demo.mp4", b"test-media")}
    )
    assert result.status_code == 201, result.text
    videos = (await client.get(path, headers=auth_headers)).json()
    assert len(videos) == 1
    assert videos[0]["title"] == "My demo"
    assert videos[0]["creator"] == "arjun"
    assert videos[0]["url"].startswith("/media/social/")
    shared = await client.get(f"/api/v1/content/social/{videos[0]['id']}", headers=auth_headers)
    assert shared.status_code == 200
    assert shared.json()["media_url"] == videos[0]["url"]
    media = await client.get(videos[0]["url"])
    assert media.status_code == 200
    assert media.content == b"test-media"
    partial = await client.get(videos[0]["url"], headers={"Range": "bytes=0-3"})
    assert partial.status_code == 206
    assert partial.content == b"test"


def test_subscriptions_persist_and_are_scoped(tmp_path):
    path = str(tmp_path / "social.db")
    service = SocialVideoService(path)
    service.follow("alice", "creator", True)
    service.db.close()
    reopened = SocialVideoService(path)
    assert reopened.following("alice") == ["creator"]
    assert reopened.following("bob") == []
    reopened.db.close()


async def test_video_clip_duration_boundaries(client, auth_headers, monkeypatch):
    for kind, seconds, status in [
        ("video", 59, 422),
        ("video", 60, 201),
        ("video", 300, 201),
        ("video", 301, 422),
        ("clip", 14, 422),
        ("clip", 15, 201),
        ("clip", 120, 201),
        ("clip", 121, 422),
    ]:
        monkeypatch.setattr("app.api.v1.social_videos.probe_duration", lambda _, value=seconds: value)
        response = await client.post(
            "/api/v1/social/videos",
            headers=auth_headers,
            data={"title": "Duration test", "kind": kind},
            files={"file": ("test.mp4", b"probe mocked")},
        )
        assert response.status_code == status, response.text
        if status == 201:
            assert response.json()["kind"] == kind
            assert response.json()["duration_seconds"] == seconds

async def test_empty_video_cursor_is_first_page(client, auth_headers, monkeypatch):
    monkeypatch.setattr('app.api.v1.social_videos.probe_duration', lambda _: 60.0)
    response = await client.post('/api/v1/social/videos', headers=auth_headers,
        data={'title':'Cursor regression'}, files={'file':('cursor.mp4',b'test-media')})
    assert response.status_code == 201
    plain = await client.get('/api/v1/social/videos', headers=auth_headers)
    empty = await client.get('/api/v1/social/videos?before=', headers=auth_headers)
    assert len(plain.json()) == 1
    assert empty.json() == plain.json()
