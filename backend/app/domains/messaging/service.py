"""Private conversations stored in SQLite; short-lived two-person call signaling."""

from __future__ import annotations

import datetime as dt
import json
import sqlite3
import time
import uuid
from pathlib import Path

from fastapi import HTTPException


class MessagingService:
    def __init__(self, database: str) -> None:
        if database != ":memory:":
            Path(database).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(database)
        self.db.row_factory = sqlite3.Row
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, sender TEXT, "
            "recipient TEXT, text TEXT, attachments TEXT, created_at TEXT)"
        )
        self.db.execute("CREATE INDEX IF NOT EXISTS dm_participants ON messages(sender, recipient)")
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS files (id TEXT PRIMARY KEY, owner TEXT, peer TEXT, "
            "path TEXT, name TEXT, mime TEXT)"
        )
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS friendships (sender TEXT, recipient TEXT, status TEXT, "
            "PRIMARY KEY(sender, recipient))"
        )
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS reactions (message_id TEXT, user_id TEXT, kind TEXT, value TEXT, "
            "PRIMARY KEY(message_id, user_id, kind, value))"
        )
        self.db.commit()
        self.calls: dict[str, dict] = {}

    def friends(self, user: str) -> list[dict]:
        return [
            dict(row)
            for row in self.db.execute(
                "SELECT * FROM friendships WHERE sender=? OR recipient=?", (user, user)
            ).fetchall()
        ]

    def request_friend(self, user: str, peer: str) -> None:
        if user == peer:
            raise HTTPException(422, "Choose another person.")
        existing = self.db.execute(
            "SELECT * FROM friendships WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)",
            (user, peer, peer, user),
        ).fetchone()
        if existing:
            raise HTTPException(409, "You are already friends or a request is pending.")
        self.db.execute("INSERT INTO friendships VALUES (?, ?, 'pending')", (user, peer))
        self.db.commit()

    def friend_action(self, user: str, peer: str, action: str) -> None:
        if action == "accept":
            cursor = self.db.execute(
                "UPDATE friendships SET status='accepted' "
                "WHERE sender=? AND recipient=? AND status='pending'",
                (peer, user),
            )
        else:
            cursor = self.db.execute(
                "DELETE FROM friendships WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)",
                (user, peer, peer, user),
            )
        self.db.commit()
        if not cursor.rowcount:
            raise HTTPException(404, "Friend request not found.")

    def searchable_messages(self, user: str):
        # Stream only this user's messages; never expose another conversation.
        for row in self.db.execute(
            "SELECT * FROM messages WHERE sender=? OR recipient=? ORDER BY created_at DESC", (user, user)
        ):
            yield dict(
                id=row["id"],
                text=row["text"],
                attachments=json.loads(row["attachments"]),
                created_at=row["created_at"],
                peer_id=row["recipient"] if row["sender"] == user else row["sender"],
            )

    def store_file(self, file_id: str, owner: str, peer: str, path: str, name: str, mime: str) -> None:
        self.db.execute(
            "INSERT INTO files VALUES (?, ?, ?, ?, ?, ?)", (file_id, owner, peer, path, name, mime)
        )
        self.db.commit()

    def file(self, file_id: str, user: str):
        row = self.db.execute("SELECT * FROM files WHERE id=?", (file_id,)).fetchone()
        if not row or user not in (row["owner"], row["peer"]):
            raise HTTPException(404, "File not found.")
        return row

    def _reactions_for(self, message_ids: list[str]) -> dict[str, list[dict]]:
        grouped: dict[str, list[dict]] = {mid: [] for mid in message_ids}
        if not message_ids:
            return grouped
        placeholders = ",".join("?" * len(message_ids))
        for row in self.db.execute(
            f"SELECT message_id, user_id, kind, value FROM reactions WHERE message_id IN ({placeholders}) "
            "ORDER BY rowid",
            message_ids,
        ):
            grouped[row["message_id"]].append(
                dict(user_id=row["user_id"], kind=row["kind"], value=row["value"])
            )
        return grouped

    def react(self, message_id: str, user: str, kind: str, value: str) -> list[dict]:
        row = self.db.execute("SELECT sender, recipient FROM messages WHERE id=?", (message_id,)).fetchone()
        if not row or user not in (row["sender"], row["recipient"]):
            raise HTTPException(404, "Message not found.")
        existing = self.db.execute(
            "SELECT 1 FROM reactions WHERE message_id=? AND user_id=? AND kind=? AND value=?",
            (message_id, user, kind, value),
        ).fetchone()
        if existing:
            self.db.execute(
                "DELETE FROM reactions WHERE message_id=? AND user_id=? AND kind=? AND value=?",
                (message_id, user, kind, value),
            )
        else:
            count = self.db.execute("SELECT COUNT(*) FROM reactions WHERE message_id=?", (message_id,)).fetchone()[0]
            if count >= 60:
                raise HTTPException(422, "Too many reactions on this message.")
            self.db.execute(
                "INSERT INTO reactions VALUES (?, ?, ?, ?)", (message_id, user, kind, value)
            )
        self.db.commit()
        return self._reactions_for([message_id])[message_id]

    def send(self, sender: str, recipient: str, text: str, attachments: list[dict]) -> dict:
        message = {
            "id": uuid.uuid4().hex,
            "sender_id": sender,
            "recipient_id": recipient,
            "text": text.strip(),
            "attachments": attachments,
            "reactions": [],
            "created_at": dt.datetime.now(dt.UTC).isoformat(),
        }
        self.db.execute(
            "INSERT INTO messages VALUES (?, ?, ?, ?, ?, ?)",
            (
                message["id"],
                sender,
                recipient,
                message["text"],
                json.dumps(attachments),
                message["created_at"],
            ),
        )
        self.db.commit()
        return message

    def history(self, user: str, peer: str, before: str | None = None) -> list[dict]:
        rows = self.db.execute(
            "SELECT * FROM messages WHERE ((sender=? AND recipient=?) OR (sender=? AND recipient=?)) "
            "AND (? IS NULL OR created_at < ?) ORDER BY created_at DESC LIMIT 100",
            (user, peer, peer, user, before, before),
        ).fetchall()
        messages = [
            dict(
                id=r["id"],
                sender_id=r["sender"],
                recipient_id=r["recipient"],
                text=r["text"],
                attachments=json.loads(r["attachments"]),
                created_at=r["created_at"],
            )
            for r in reversed(rows)
        ]
        reactions = self._reactions_for([m["id"] for m in messages])
        for m in messages:
            m["reactions"] = reactions[m["id"]]
        return messages

    def peers(self, user: str) -> list[str]:
        rows = self.db.execute(
            "SELECT CASE WHEN sender=? THEN recipient ELSE sender END AS peer, MAX(created_at) AS latest "
            "FROM messages WHERE sender=? OR recipient=? GROUP BY peer ORDER BY latest DESC",
            (user, user, user),
        ).fetchall()
        return [r["peer"] for r in rows]

    def _expire(self) -> None:
        now = time.monotonic()
        for call in self.calls.values():
            if call["status"] == "ringing" and now - call["started"] > 60:
                call["status"] = "missed"
            elif call["status"] == "accepted" and any(now - t > 45 for t in call["seen"].values()):
                call["status"] = "ended"
        self.calls = {key: c for key, c in self.calls.items() if now - c["started"] < 86400}

    def call(self, call_id: str, user: str) -> dict:
        self._expire()
        call = self.calls.get(call_id)
        if not call or user not in (call["caller_id"], call["recipient_id"]):
            raise HTTPException(404, "Call not found.")
        call["seen"][user] = time.monotonic()
        return call

    def create_call(self, caller: str, recipient: str, video: bool) -> dict:
        if caller == recipient:
            raise HTTPException(422, "Choose another person to call.")
        self._expire()
        for call in self.calls.values():
            if call["status"] in ("ringing", "accepted") and (
                caller in (call["caller_id"], call["recipient_id"])
                or recipient in (call["caller_id"], call["recipient_id"])
            ):
                raise HTTPException(409, "A participant is already in a call.")
        call = dict(
            id=uuid.uuid4().hex,
            caller_id=caller,
            recipient_id=recipient,
            video=video,
            status="ringing",
            started=time.monotonic(),
            seen={caller: time.monotonic(), recipient: time.monotonic()},
            signals=[],
        )
        self.calls[call["id"]] = call
        return call

    def incoming(self, user: str) -> list[dict]:
        self._expire()
        return [c for c in self.calls.values() if c["recipient_id"] == user and c["status"] == "ringing"]

    def transition(self, call_id: str, user: str, action: str) -> dict:
        call = self.call(call_id, user)
        if action in ("accept", "decline"):
            if user != call["recipient_id"] or call["status"] != "ringing":
                raise HTTPException(409, "This call can no longer be answered.")
            call["status"] = "accepted" if action == "accept" else "declined"
            call["seen"] = dict.fromkeys(call["seen"], time.monotonic())
        elif action == "end":
            call["status"] = "ended"
        return call

    def signal(self, call_id: str, user: str, kind: str, payload: dict) -> None:
        call = self.call(call_id, user)
        if call["status"] != "accepted":
            raise HTTPException(409, "The call is not active.")
        if kind == "offer" and user != call["caller_id"]:
            raise HTTPException(403, "Only the caller can send an offer.")
        if kind == "answer" and user != call["recipient_id"]:
            raise HTTPException(403, "Only the recipient can send an answer.")
        if len(call["signals"]) >= 512:
            raise HTTPException(429, "Too many call signals.")
        if kind in ("offer", "answer") and any(s["kind"] == kind for s in call["signals"]):
            raise HTTPException(409, "Description already sent.")
        call["signals"].append(dict(seq=len(call["signals"]) + 1, sender=user, kind=kind, payload=payload))

    @staticmethod
    def public_call(call: dict) -> dict:
        return {k: call[k] for k in ("id", "caller_id", "recipient_id", "video", "status")}
