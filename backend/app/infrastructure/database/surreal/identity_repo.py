"""SurrealDB implementation of `IdentityRepository`.

Table shape (see `data/surrealdb/schema/identity.surql`):

    DEFINE TABLE user SCHEMAFULL;
    DEFINE FIELD username        ON user TYPE string ASSERT $value != NONE;
    DEFINE FIELD email           ON user TYPE string ASSERT $value != NONE;
    DEFINE FIELD full_name       ON user TYPE string;
    DEFINE FIELD hashed_password ON user TYPE string;
    DEFINE FIELD avatar_url      ON user TYPE option<string>;
    DEFINE FIELD bio             ON user TYPE string;
    DEFINE FIELD interests       ON user TYPE array<string>;
    DEFINE FIELD is_verified     ON user TYPE bool DEFAULT false;
    DEFINE FIELD created_at      ON user TYPE datetime DEFAULT time::now();
    DEFINE INDEX user_username_unique ON user FIELDS username UNIQUE;
    DEFINE INDEX user_email_unique    ON user FIELDS email UNIQUE;
"""

from __future__ import annotations

import datetime as dt

from surrealdb import Surreal

from app.domains.identity.entities import User

_TABLE = "user"


def _row_to_user(row: dict) -> User:
    record_id: str = row["id"]  # SurrealDB record id, e.g. "user:usr_abc123"
    user_id = record_id.split(":", 1)[1] if ":" in record_id else record_id
    return User(
        id=user_id,
        username=row["username"],
        full_name=row["full_name"],
        email=row["email"],
        hashed_password=row["hashed_password"],
        avatar_url=row.get("avatar_url"),
        bio=row.get("bio", ""),
        interests=row.get("interests", []),
        created_at=row.get("created_at") or dt.datetime.now(dt.UTC),
        is_verified=row.get("is_verified", False),
        is_creator=row.get("is_creator", False),
        is_test_user=row.get("is_test_user", False),
        phone_number=row.get("phone_number"),
        date_of_birth=dt.date.fromisoformat(row["date_of_birth"]) if row.get("date_of_birth") else None,
    )


def _user_to_row(user: User) -> dict:
    return {
        "username": user.username,
        "full_name": user.full_name,
        "email": user.email,
        "hashed_password": user.hashed_password,
        "avatar_url": user.avatar_url,
        "bio": user.bio,
        "interests": user.interests,
        "is_verified": user.is_verified,
        "created_at": user.created_at,
        "is_creator": user.is_creator,
        "is_test_user": user.is_test_user,
        "phone_number": user.phone_number,
        "date_of_birth": user.date_of_birth.isoformat() if user.date_of_birth else None,
    }


class SurrealIdentityRepository:
    def __init__(self, db: Surreal) -> None:
        self._db = db

    async def create_user(self, user: User) -> User:
        record_id = f"{_TABLE}:{user.id}"
        result = await self._db.create(record_id, _user_to_row(user))
        row = result[0] if isinstance(result, list) else result
        return _row_to_user(row)

    async def get_by_id(self, user_id: str) -> User | None:
        row = await self._db.select(f"{_TABLE}:{user_id}")
        if not row:
            return None
        return _row_to_user(row[0] if isinstance(row, list) else row)

    async def get_by_username(self, username: str) -> User | None:
        rows = await self._db.query(
            f"SELECT * FROM {_TABLE} WHERE username = $username LIMIT 1",
            {"username": username},
        )
        records = rows[0]["result"] if rows and rows[0].get("result") else []
        return _row_to_user(records[0]) if records else None

    async def get_by_email(self, email: str) -> User | None:
        rows = await self._db.query(
            f"SELECT * FROM {_TABLE} WHERE email = $email LIMIT 1",
            {"email": email},
        )
        records = rows[0]["result"] if rows and rows[0].get("result") else []
        return _row_to_user(records[0]) if records else None

    async def get_by_phone(self, phone_number: str) -> User | None:
        rows = await self._db.query(
            f"SELECT * FROM {_TABLE} WHERE phone_number = $phone LIMIT 1", {"phone": phone_number}
        )
        records = rows[0]["result"] if rows and rows[0].get("result") else []
        return _row_to_user(records[0]) if records else None

    async def update_user(self, user: User) -> User:
        record_id = f"{_TABLE}:{user.id}"
        result = await self._db.merge(record_id, _user_to_row(user))
        row = result[0] if isinstance(result, list) else result
        return _row_to_user(row)

    async def search_users(self, query: str, limit: int = 30) -> list[User]:
        rows = await self._db.query(
            "SELECT * FROM user WHERE string::contains(string::lowercase(username), $q) "
            "OR string::contains(string::lowercase(full_name), $q) LIMIT $limit",
            {"q": query.lower().lstrip("@"), "limit": limit},
        )
        records = rows[0]["result"] if rows and rows[0].get("result") else []
        return [_row_to_user(row) for row in records]
