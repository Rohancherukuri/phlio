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


async def test_video_catalog_and_upload(client, auth_headers):
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
