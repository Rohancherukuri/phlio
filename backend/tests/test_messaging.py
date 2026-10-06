from __future__ import annotations

from app.domains.messaging.service import MessagingService


async def login(client, username):
    response = await client.post(
        "/api/v1/auth/login", json={"identifier": username, "password": "password123"}
    )
    return {"Authorization": f"Bearer {response.json()['tokens']['access_token']}"}


async def test_dm_delivered_to_recipient_and_hidden_from_others(client, auth_headers):
    recipient = await login(client, "neha")
    outsider = await login(client, "artbykiara")
    sent = await client.post(
        "/api/v1/messaging/peers/neha/messages", headers=auth_headers, json={"text": "Hello Neha"}
    )
    assert sent.status_code == 201, sent.text
    received = await client.get("/api/v1/messaging/peers/arjun/messages", headers=recipient)
    assert received.json()[0]["text"] == "Hello Neha"
    private = await client.get("/api/v1/messaging/peers/arjun/messages", headers=outsider)
    assert private.json() == []
    conversations = await client.get("/api/v1/messaging/conversations", headers=recipient)
    assert conversations.json()[0]["peer"]["username"] == "arjun"
    assert (await client.get("/api/v1/messaging/conversations")).status_code == 401


async def test_dm_validation_and_identity_resolution(client, auth_headers):
    assert (await client.get("/api/v1/messaging/peers/usr_neha", headers=auth_headers)).json()[
        "username"
    ] == "neha"
    assert (await client.get("/api/v1/messaging/peers/missing", headers=auth_headers)).status_code == 404
    response = await client.post(
        "/api/v1/messaging/peers/neha/messages", headers=auth_headers, json={"text": " "}
    )
    assert response.status_code == 422


async def test_private_upload_requires_conversation_access(client, auth_headers):
    recipient = await login(client, "neha")
    outsider = await login(client, "artbykiara")
    upload = await client.post(
        "/api/v1/messaging/peers/neha/files",
        headers=auth_headers,
        files=[("files", ("notes.txt", b"Secret notes", "text/plain"))],
    )
    assert upload.status_code == 201, upload.text
    attachment = upload.json()[0]
    url = attachment["url"]
    assert (await client.get(url, headers=recipient)).content == b"Secret notes"
    assert (await client.get(url, headers=outsider)).status_code == 404
    assert (await client.get(url)).status_code == 401
    sent = await client.post(
        "/api/v1/messaging/peers/neha/messages", headers=auth_headers, json={"attachments": [attachment]}
    )
    assert sent.status_code == 201
    stolen = await client.post(
        "/api/v1/messaging/peers/artbykiara/messages", headers=recipient, json={"attachments": [attachment]}
    )
    assert stolen.status_code == 403


async def test_call_accept_signal_and_hangup(client, auth_headers):
    recipient = await login(client, "neha")
    outsider = await login(client, "artbykiara")
    created = await client.post(
        "/api/v1/messaging/calls", headers=auth_headers, json={"peer": "neha", "video": True}
    )
    assert created.status_code == 201, created.text
    call_id = created.json()["id"]
    base = f"/api/v1/messaging/calls/{call_id}"
    incoming = await client.get("/api/v1/messaging/calls/incoming", headers=recipient)
    assert incoming.json()[0]["caller"]["username"] == "arjun"
    assert (await client.get(base, headers=outsider)).status_code == 404
    assert (await client.post(base + "/actions/accept", headers=auth_headers)).status_code == 409
    assert (await client.post(base + "/actions/accept", headers=recipient)).json()["status"] == "accepted"
    offer = {"kind": "offer", "payload": {"type": "offer", "sdp": "v=0"}}
    assert (await client.post(base + "/signals", headers=outsider, json=offer)).status_code == 404
    assert (await client.post(base + "/signals", headers=recipient, json=offer)).status_code == 403
    assert (await client.post(base + "/signals", headers=auth_headers, json=offer)).status_code == 204
    signals = (await client.get(base, headers=recipient)).json()["signals"]
    assert signals[0]["kind"] == "offer"
    assert (await client.get(base, headers=recipient, params={"after": signals[0]["seq"]})).json()[
        "signals"
    ] == []
    assert (await client.get(base, headers=auth_headers)).json()["signals"] == []
    assert (await client.post(base + "/actions/end", headers=recipient)).json()["status"] == "ended"
    assert (await client.get(base, headers=auth_headers)).json()["status"] == "ended"


async def test_call_busy_decline_and_malformed_signals(client, auth_headers):
    recipient = await login(client, "neha")
    first = await client.post("/api/v1/messaging/calls", headers=auth_headers, json={"peer": "neha"})
    base = f"/api/v1/messaging/calls/{first.json()['id']}"
    busy = await client.post("/api/v1/messaging/calls", headers=auth_headers, json={"peer": "artbykiara"})
    assert busy.status_code == 409
    malformed = await client.post(
        base + "/signals", headers=auth_headers, json={"kind": "offer", "payload": {}}
    )
    assert malformed.status_code == 422
    assert (await client.post(base + "/actions/decline", headers=recipient)).json()["status"] == "declined"
    assert (await client.get("/api/v1/messaging/calls/incoming", headers=recipient)).json() == []
    assert (
        await client.post("/api/v1/messaging/calls", headers=auth_headers, json={"peer": "arjun"})
    ).status_code == 422


def test_messages_survive_database_reopen(tmp_path):
    path = str(tmp_path / "messages.sqlite3")
    first = MessagingService(path)
    first.send("alice", "bob", "Persistent hello", [])
    first.db.close()
    second = MessagingService(path)
    assert second.history("bob", "alice")[0]["text"] == "Persistent hello"
    second.db.close()


def test_unanswered_and_abandoned_calls_expire(monkeypatch):
    now = [0.0]
    monkeypatch.setattr("app.domains.messaging.service.time.monotonic", lambda: now[0])
    service = MessagingService(":memory:")
    ringing = service.create_call("alice", "bob", False)
    now[0] = 61
    assert service.call(ringing["id"], "alice")["status"] == "missed"
    active = service.create_call("alice", "bob", False)
    service.transition(active["id"], "bob", "accept")
    now[0] = 107
    assert service.call(active["id"], "alice")["status"] == "ended"
    service.db.close()


async def test_friend_requests_require_recipient_consent(client, auth_headers):
    recipient = await login(client, "neha")
    outsider = await login(client, "artbykiara")
    base = "/api/v1/messaging/friends"
    assert (await client.post(base, headers=auth_headers, json={"peer": "neha"})).status_code == 201
    assert (await client.post(base, headers=auth_headers, json={"peer": "neha"})).status_code == 409
    assert (await client.post(base, headers=auth_headers, json={"peer": "arjun"})).status_code == 422
    pending = (await client.get(base, headers=recipient)).json()
    assert pending[0]["incoming"] is True and pending[0]["status"] == "pending"
    assert (await client.get(base, headers=outsider)).json() == []
    assert (await client.post(base + "/neha/accept", headers=auth_headers)).status_code == 404
    assert (await client.post(base + "/arjun/accept", headers=outsider)).status_code == 404
    assert (await client.post(base + "/arjun/accept", headers=recipient)).status_code == 204
    assert (await client.get(base, headers=auth_headers)).json()[0]["status"] == "accepted"
    assert (await client.post(base + "/arjun/remove", headers=recipient)).status_code == 204
    assert (await client.get(base, headers=auth_headers)).json() == []


async def test_search_filters_and_private_conversation_boundary(client, auth_headers):
    outsider = await login(client, "artbykiara")
    for filename in ["searchunique.txt", "searchunique.png", "searchunique.mp4", "searchunique.m4a"]:
        upload = await client.post(
            "/api/v1/messaging/peers/neha/files",
            headers=auth_headers,
            files=[("files", (filename, b"sample", "application/octet-stream"))],
        )
        assert upload.status_code == 201
        sent = await client.post(
            "/api/v1/messaging/peers/neha/messages", headers=auth_headers, json={"attachments": upload.json()}
        )
        assert sent.status_code == 201
    await client.post(
        "/api/v1/messaging/peers/neha/messages",
        headers=auth_headers,
        json={"text": "searchunique https://example.com/plan"},
    )
    for kind, count in [
        ("recent", 5),
        ("files", 1),
        ("images", 1),
        ("videos", 1),
        ("audio", 1),
        ("media", 3),
        ("links", 1),
    ]:
        params = {"q": "searchunique", "kind": kind}
        result = await client.get("/api/v1/messaging/search", headers=auth_headers, params=params)
        assert result.status_code == 200, result.text
        assert len(result.json()) == count
        assert (await client.get("/api/v1/messaging/search", headers=outsider, params=params)).json() == []
    assert (await client.get("/api/v1/messaging/search")).status_code == 401
    people = (
        await client.get(
            "/api/v1/messaging/search", headers=auth_headers, params={"kind": "people", "q": "neh"}
        )
    ).json()
    assert people[0]["peer"]["username"] == "neha"
    assert "email" not in people[0]["peer"] and "hashed_password" not in people[0]["peer"]


async def test_room_search_only_includes_joined_rooms_and_pins(client, auth_headers):
    outsider = await login(client, "artbykiara")
    room = (
        await client.post(
            "/api/v1/rooms",
            headers=auth_headers,
            json={
                "name": "Search test room",
                "description": "searchpin meeting at six",
                "category": "tech_and_ai",
                "icon": "T",
                "is_private": True,
            },
        )
    ).json()
    assert "id" in room, room
    await client.post(
        f"/api/v1/rooms/{room['id']}/messages",
        headers=auth_headers,
        json={"text": "searchroom confidential conversation"},
    )
    result = await client.get("/api/v1/messaging/search", headers=auth_headers, params={"q": "searchroom"})
    assert result.json()[0]["room_id"] == room["id"]
    assert (
        await client.get("/api/v1/messaging/search", headers=outsider, params={"q": "searchroom"})
    ).json() == []
    pins = (
        await client.get(
            "/api/v1/messaging/search", headers=auth_headers, params={"q": "searchpin", "kind": "pins"}
        )
    ).json()
    assert pins[0]["text"] == "searchpin meeting at six"
    assert (
        await client.get(
            "/api/v1/messaging/search", headers=outsider, params={"q": "searchpin", "kind": "pins"}
        )
    ).json() == []
