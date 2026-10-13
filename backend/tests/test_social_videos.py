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
    monkeypatch.setattr('app.api.v1.social_videos.make_thumbnail', lambda *args: None)
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
        monkeypatch.setattr('app.api.v1.social_videos.make_thumbnail', lambda *args: None)
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
    monkeypatch.setattr('app.api.v1.social_videos.make_thumbnail', lambda *args: None)
    response = await client.post('/api/v1/social/videos', headers=auth_headers,
        data={'title':'Cursor regression'}, files={'file':('cursor.mp4',b'test-media')})
    assert response.status_code == 201
    plain = await client.get('/api/v1/social/videos', headers=auth_headers)
    empty = await client.get('/api/v1/social/videos?before=', headers=auth_headers)
    assert len(plain.json()) == 1
    assert empty.json() == plain.json()


async def test_bulk_catalog_preserves_block_filter_and_cache_revocation(settings):
    from app.api.v1.social_videos import videos
    from app.core.container import build_container
    from app.core.seed import seed_memory_backend

    c = await build_container(settings)
    await seed_memory_backend(c)
    viewer, creator = (await c.identity_repository.search_users('', 30))[:2]
    try:
        c.social_video_service.publish('bulk-test', creator.id, 'Catalog test', '/media/test.mp4')
        await c.graph.register_object(creator.id, 'social.video', 'bulk-test', 'Catalog test')
        assert [row['id'] for row in await videos(None, viewer, c)] == ['bulk-test']
        await c.graph.relationship(creator.id, viewer.id, 'block')
        assert await videos(None, viewer, c) == []
        await c.graph.relationship(creator.id, viewer.id, 'unblock')
        assert len(await videos(None, viewer, c)) == 1
        await c.graph.relationship(viewer.id, creator.id, 'block')
        assert await videos(None, viewer, c) == []
    finally:
        await c.cache.close()
        c.messaging_service.db.close()
        c.social_video_service.db.close()
