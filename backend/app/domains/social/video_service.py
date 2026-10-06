"""Durable video metadata and creator subscriptions."""

import datetime as dt
import sqlite3
from pathlib import Path


class SocialVideoService:
    def __init__(self, database: str):
        if database != ":memory:":
            Path(database).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(database)
        self.db.row_factory = sqlite3.Row
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS follows (viewer TEXT, creator TEXT, PRIMARY KEY(viewer, creator))"
        )
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS videos "
            "(id TEXT PRIMARY KEY, creator TEXT, title TEXT, url TEXT, created_at TEXT)"
        )
        self.db.commit()

    def following(self, user: str) -> list[str]:
        return [r["creator"] for r in self.db.execute("SELECT creator FROM follows WHERE viewer=?", (user,))]

    def follow(self, user: str, creator: str, enabled: bool):
        if enabled:
            self.db.execute("INSERT OR IGNORE INTO follows VALUES (?, ?)", (user, creator))
        else:
            self.db.execute("DELETE FROM follows WHERE viewer=? AND creator=?", (user, creator))
        self.db.commit()

    def publish(self, video_id: str, creator: str, title: str, url: str):
        self.db.execute(
            "INSERT INTO videos VALUES (?, ?, ?, ?, ?)",
            (video_id, creator, title, url, dt.datetime.now(dt.UTC).isoformat()),
        )
        self.db.commit()

    def videos(self, before: str | None = None):
        return [
            dict(row)
            for row in self.db.execute(
                "SELECT * FROM videos WHERE (? IS NULL OR created_at < ?) ORDER BY created_at DESC LIMIT 50",
                (before, before),
            )
        ]
