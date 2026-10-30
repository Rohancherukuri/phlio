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
        self.db.execute("CREATE TABLE IF NOT EXISTS inbox_preferences (owner TEXT, peer TEXT, folder TEXT, read_at TEXT, PRIMARY KEY(owner, peer))")
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
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS public_chat (id TEXT PRIMARY KEY, creator TEXT, sender TEXT, "
            "username TEXT, text TEXT, attachments TEXT, created_at TEXT)"
        )
        self.db.execute("CREATE INDEX IF NOT EXISTS public_chat_creator ON public_chat(creator, created_at)")
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS message_overlays (message_id TEXT PRIMARY KEY, overlays TEXT)"
        )
        # Instagram-style message actions: reply threads, per-user "Delete for
        # you", and pinned messages per conversation.
        self.db.execute("CREATE TABLE IF NOT EXISTS message_meta (message_id TEXT PRIMARY KEY, reply_to TEXT)")
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS message_hidden (message_id TEXT, user_id TEXT, PRIMARY KEY(message_id, user_id))"
        )
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS message_pins (message_id TEXT PRIMARY KEY, pinned_by TEXT, pinned_at TEXT)"
        )
        self.db.commit()
        self.calls: dict[str, dict] = {}

    def inbox_state(self, owner: str, peer: str) -> dict:
        row = self.db.execute('SELECT folder, read_at FROM inbox_preferences WHERE owner=? AND peer=?', (owner, peer)).fetchone()
        return dict(row) if row else dict(folder=None, read_at='')

    def update_inbox(self, owner: str, peer: str, folder=None, read=False):
        state = self.inbox_state(owner, peer)
        self.db.execute('INSERT OR REPLACE INTO inbox_preferences VALUES (?,?,?,?)',
            (owner, peer, folder or state['folder'], dt.datetime.now(dt.UTC).isoformat() if read else state['read_at']))
        self.db.commit()

    def inbox_counts(self, owner: str, peer: str, read_at: str):
        unread = self.db.execute('SELECT COUNT(*) FROM messages WHERE sender=? AND recipient=? AND created_at>?', (peer, owner, read_at or '')).fetchone()[0]
        replied = self.db.execute('SELECT 1 FROM messages WHERE sender=? AND recipient=? LIMIT 1',(owner,peer)).fetchone() is not None
        return unread, replied

    def public_history(self, creator: str):
        rows = self.db.execute(
            "SELECT * FROM public_chat WHERE creator=? ORDER BY created_at DESC LIMIT 100", (creator,)
        ).fetchall()
        return [
            dict(
                id=r["id"],
                sender_id=r["sender"],
                username=r["username"],
                text=r["text"],
                attachments=json.loads(r["attachments"]),
                created_at=r["created_at"],
            )
            for r in reversed(rows)
        ]

    def public_send(self, creator: str, user: str, username: str, text: str, attachments: list):
        mid = uuid.uuid4().hex
        self.db.execute(
            "INSERT INTO public_chat VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                mid,
                creator,
                user,
                username,
                text.strip(),
                json.dumps(attachments),
                dt.datetime.now(dt.UTC).isoformat(),
            ),
        )
        self.db.commit()
        return {"id": mid}

    def overlays(self, message_id: str, user: str, peer: str, overlays: list):
        row = self.db.execute(
            "SELECT * FROM messages WHERE id=? AND sender=? AND recipient=?", (message_id, user, peer)
        ).fetchone()
        if not row:
            raise HTTPException(404, "Sent message not found.")
        self.db.execute(
            "INSERT OR REPLACE INTO message_overlays VALUES (?, ?)", (message_id, json.dumps(overlays))
        )
        self.db.commit()
        return overlays

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
            count = self.db.execute(
                "SELECT COUNT(*) FROM reactions WHERE message_id=?", (message_id,)
            ).fetchone()[0]
            if count >= 60:
                raise HTTPException(422, "Too many reactions on this message.")
            self.db.execute("INSERT INTO reactions VALUES (?, ?, ?, ?)", (message_id, user, kind, value))
        self.db.commit()
        return self._reactions_for([message_id])[message_id]

    def _participant_message(self, message_id: str, user: str, peer: str | None = None):
        row = self.db.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone()
        if not row or user not in (row["sender"], row["recipient"]):
            raise HTTPException(404, "Message not found.")
        if peer and peer not in (row["sender"], row["recipient"]):
            raise HTTPException(404, "Message not found.")
        return row

    def hide(self, message_id: str, user: str, peer: str) -> None:
        """Delete for you: only this user stops seeing the message."""
        self._participant_message(message_id, user, peer)
        self.db.execute("INSERT OR IGNORE INTO message_hidden VALUES (?, ?)", (message_id, user))
        self.db.commit()

    def unsend(self, message_id: str, user: str, peer: str) -> None:
        """Unsend: the sender removes the message for both people."""
        row = self._participant_message(message_id, user, peer)
        if row["sender"] != user:
            raise HTTPException(403, "You can only unsend your own messages.")
        for table, column in [("messages", "id"), ("reactions", "message_id"), ("message_overlays", "message_id"),
                              ("message_meta", "message_id"), ("message_hidden", "message_id"),
                              ("message_pins", "message_id")]:
            self.db.execute(f"DELETE FROM {table} WHERE {column}=?", (message_id,))
        self.db.commit()

    def pin(self, message_id: str, user: str, peer: str, pinned: bool) -> bool:
        self._participant_message(message_id, user, peer)
        if pinned:
            self.db.execute("INSERT OR REPLACE INTO message_pins VALUES (?, ?, ?)",
                            (message_id, user, dt.datetime.now(dt.UTC).isoformat()))
        else:
            self.db.execute("DELETE FROM message_pins WHERE message_id=?", (message_id,))
        self.db.commit()
        return pinned

    def forward(self, message_id: str, user: str, recipient: str, file_prefix: str) -> dict:
        """Copy a message's text and attachments into another conversation.
        Uploaded files get a new record so the new recipient can open them."""
        row = self._participant_message(message_id, user)
        attachments = []
        for raw in json.loads(row["attachments"] or "[]"):
            item = dict(raw, id=uuid.uuid4().hex)
            url = item.get("url") or ""
            if url.startswith(file_prefix):
                source = self.file(url.removeprefix(file_prefix), user)
                file_id = uuid.uuid4().hex
                self.store_file(file_id, user, recipient, source["path"], source["name"], source["mime"])
                item["url"] = file_prefix + file_id
            attachments.append(item)
        return self.send(user, recipient, row["text"], attachments)

    def _reply_preview(self, message_id: str | None):
        if not message_id:
            return None
        row = self.db.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone()
        if not row:
            return dict(id=message_id, deleted=True)
        attachments = json.loads(row["attachments"] or "[]")
        return dict(id=row["id"], sender_id=row["sender"], text=row["text"][:280],
                    kind=(attachments[0].get("kind") if attachments else None))

    def send(self, sender: str, recipient: str, text: str, attachments: list[dict],
             reply_to: str | None = None) -> dict:
        if reply_to:
            original = self.db.execute("SELECT sender, recipient FROM messages WHERE id=?", (reply_to,)).fetchone()
            if not original or {original["sender"], original["recipient"]} != {sender, recipient}:
                reply_to = None
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
        if reply_to:
            self.db.execute("INSERT OR REPLACE INTO message_meta VALUES (?, ?)", (message["id"], reply_to))
        self.db.commit()
        message["reply_to"] = self._reply_preview(reply_to)
        message["pinned"] = False
        return message

    def history(self, user: str, peer: str, before: str | None = None) -> list[dict]:
        rows = self.db.execute(
            "SELECT * FROM messages WHERE ((sender=? AND recipient=?) OR (sender=? AND recipient=?)) "
            "AND (? IS NULL OR created_at < ?) "
            "AND id NOT IN (SELECT message_id FROM message_hidden WHERE user_id=?) "
            "ORDER BY created_at DESC LIMIT 100",
            (user, peer, peer, user, before, before, user),
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
            overlay = self.db.execute(
                "SELECT overlays FROM message_overlays WHERE message_id=?", (m["id"],)
            ).fetchone()
            m["overlays"] = json.loads(overlay["overlays"]) if overlay else []
            meta = self.db.execute("SELECT reply_to FROM message_meta WHERE message_id=?", (m["id"],)).fetchone()
            m["reply_to"] = self._reply_preview(meta["reply_to"]) if meta else None
            pin = self.db.execute("SELECT pinned_at FROM message_pins WHERE message_id=?", (m["id"],)).fetchone()
            m["pinned"] = bool(pin)
            m["pinned_at"] = pin["pinned_at"] if pin else None
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
