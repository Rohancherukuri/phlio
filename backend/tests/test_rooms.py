"""Tests for room discovery, membership, and messaging."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_discover_lists_seeded_rooms(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get("/api/v1/rooms/discover", headers=auth_headers)
    assert response.status_code == 200
    names = {r["name"] for r in response.json()["items"]}
    assert "Tech & AI" in names


async def test_discover_filters_by_category(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.get(
        "/api/v1/rooms/discover", headers=auth_headers, params={"category": "art_and_creators"}
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert all(r["category"] == "art_and_creators" for r in items)
    assert len(items) >= 1


async def test_create_room_and_join(client: AsyncClient, auth_headers: dict) -> None:
    create = await client.post(
        "/api/v1/rooms",
        headers=auth_headers,
        json={
            "name": "Weekend Hikers",
            "description": "Trail meetups every Saturday.",
            "category": "travel_and_explore",
            "icon": "🥾",
        },
    )
    assert create.status_code == 201, create.text
    room = create.json()
    assert room["member_count"] == 1  # creator auto-joins

    mine = await client.get("/api/v1/rooms/mine", headers=auth_headers)
    assert any(r["id"] == room["id"] for r in mine.json())


async def test_send_and_list_messages(client: AsyncClient, auth_headers: dict) -> None:
    rooms = await client.get("/api/v1/rooms/discover", headers=auth_headers)
    room_id = rooms.json()["items"][0]["id"]

    sent = await client.post(
        f"/api/v1/rooms/{room_id}/messages", headers=auth_headers, json={"text": "Hello room!"}
    )
    assert sent.status_code == 201, sent.text

    messages = await client.get(f"/api/v1/rooms/{room_id}/messages", headers=auth_headers)
    texts = [m["text"] for m in messages.json()["items"]]
    assert "Hello room!" in texts


async def test_empty_message_is_rejected(client: AsyncClient, auth_headers: dict) -> None:
    rooms = await client.get("/api/v1/rooms/discover", headers=auth_headers)
    room_id = rooms.json()["items"][0]["id"]

    response = await client.post(
        f"/api/v1/rooms/{room_id}/messages", headers=auth_headers, json={"text": "   "}
    )
    assert response.status_code == 422


async def test_message_in_unknown_room_is_404(client: AsyncClient, auth_headers: dict) -> None:
    response = await client.post(
        "/api/v1/rooms/rm_does_not_exist/messages", headers=auth_headers, json={"text": "hi"}
    )
    assert response.status_code == 404


async def test_upload_files_and_send_with_attachments(
    client: AsyncClient, auth_headers: dict, tmp_path
) -> None:
    rooms = await client.get("/api/v1/rooms/discover", headers=auth_headers)
    room_id = rooms.json()["items"][0]["id"]

    # Multi-file upload: a PDF and an image, streamed to the media root.
    pdf = tmp_path / "project-brief.pdf"
    pdf.write_bytes(b"%PDF-1.4 minimal test payload")
    png = tmp_path / "diagram.png"
    png.write_bytes(b"\x89PNG\r\n\x1a\nnot-a-real-png-body")

    upload = await client.post(
        f"/api/v1/rooms/{room_id}/files",
        headers=auth_headers,
        files=[
            ("files", ("project-brief.pdf", pdf.open("rb"), "application/pdf")),
            ("files", ("diagram.png", png.open("rb"), "image/png")),
        ],
    )
    assert upload.status_code == 201, upload.text
    attachments = upload.json()
    assert [a["kind"] for a in attachments] == ["document", "image"]
    assert all(a["url"].startswith("/media/rooms/") for a in attachments)
    assert attachments[0]["size"] == pdf.stat().st_size

    # Uploaded media is actually served back.
    media = await client.get(attachments[0]["url"])
    assert media.status_code == 200
    assert media.content.startswith(b"%PDF")

    # Attach the metadata to a message.
    sent = await client.post(
        f"/api/v1/rooms/{room_id}/messages",
        headers=auth_headers,
        json={
            "text": "Docs for review",
            "attachments": [
                {"kind": a["kind"], "name": a["name"], "size": a["size"],
                 "mime": a["mime"], "url": a["url"]}
                for a in attachments
            ],
        },
    )
    assert sent.status_code == 201, sent.text
    body = sent.json()
    assert len(body["attachments"]) == 2

    # Pack stickers need no bytes at all.
    sticker = await client.post(
        f"/api/v1/rooms/{room_id}/messages",
        headers=auth_headers,
        json={"text": "", "attachments": [{"kind": "sticker", "name": "Foxy wizard",
                                           "value": "costume_wizard"}]},
    )
    assert sticker.status_code == 201, sticker.text


async def test_message_without_text_or_attachments_is_rejected(
    client: AsyncClient, auth_headers: dict
) -> None:
    rooms = await client.get("/api/v1/rooms/discover", headers=auth_headers)
    room_id = rooms.json()["items"][0]["id"]
    response = await client.post(
        f"/api/v1/rooms/{room_id}/messages", headers=auth_headers, json={"text": ""}
    )
    assert response.status_code == 422


async def test_toggle_reaction_round_trip(client: AsyncClient, auth_headers: dict) -> None:
    rooms = await client.get("/api/v1/rooms/discover", headers=auth_headers)
    room_id = rooms.json()["items"][0]["id"]
    sent = await client.post(
        f"/api/v1/rooms/{room_id}/messages", headers=auth_headers, json={"text": "react to me"}
    )
    message_id = sent.json()["id"]

    def values(message: dict) -> set[tuple[str, str]]:
        return {(r["kind"], r["value"]) for r in message["reactions"]}

    # Add an emoji reaction, a sticker, and a GIF.
    for kind, value in (("emoji", "🔥"), ("sticker", "costume_wizard"), ("gif", "anim_celebration")):
        response = await client.post(
            f"/api/v1/rooms/{room_id}/messages/{message_id}/reactions",
            headers=auth_headers,
            json={"kind": kind, "value": value},
        )
        assert response.status_code == 200, response.text
        assert (kind, value) in values(response.json())

    # Toggling the same reaction by the same user removes it.
    off = await client.post(
        f"/api/v1/rooms/{room_id}/messages/{message_id}/reactions",
        headers=auth_headers,
        json={"kind": "sticker", "value": "costume_wizard"},
    )
    assert ("sticker", "costume_wizard") not in values(off.json())
    assert ("emoji", "🔥") in values(off.json())  # others survive

    # Seeded document message carries its reactions out of the box.
    listing = await client.get(f"/api/v1/rooms/rm_tech_ai/messages", headers=auth_headers)
    seeded = next(m for m in listing.json()["items"] if m["id"] == "msg_seed_4")
    assert len(seeded["attachments"]) == 2
    assert {r["value"] for r in seeded["reactions"]} >= {"🔥", "costume_wizard"}
