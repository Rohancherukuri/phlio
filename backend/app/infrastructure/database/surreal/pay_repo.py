"""Durable Phlio Pay ledger (simulated money) on SurrealDB.

Replaces the in-memory store in "surreal" mode, so wallets, transactions and
split requests survive restarts and live in the cloud database with
everything else. Tables: ``pay_wallet`` (id = user id), ``pay_transaction``,
``pay_split``. Amounts stay in minor units (paise); times are ISO strings so
newest-first ordering is a plain string sort.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import asdict

from app.domains.pay.entities import (
    SplitParticipant, SplitRequest, Transaction, TransactionStatus, TransactionType, Wallet,
)
from app.infrastructure.database.memory.social_repo import _paginate
from app.infrastructure.database.surreal.client import record


def _when(value) -> dt.datetime:
    if isinstance(value, dt.datetime):
        return value if value.tzinfo else value.replace(tzinfo=dt.UTC)
    parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=dt.UTC)


def _raw_id(row) -> str:
    return str(row["id"]).split(":", 1)[1]


class SurrealPayRepository:
    def __init__(self, db):
        self._db = db

    async def _upsert(self, key: str, data: dict) -> None:
        await self._db.query("UPSERT $id CONTENT $data", {"id": record(key), "data": data})

    # -- seeding helpers (same names as the in-memory repository) ----------------
    async def seed_wallet(self, wallet: Wallet) -> None:
        await self.save_wallet(wallet)

    async def seed_transaction(self, transaction: Transaction) -> None:
        await self.add_transaction(transaction)

    # -- PayRepository -------------------------------------------------------------
    async def get_wallet(self, user_id: str) -> Wallet | None:
        row = await self._db.select("pay_wallet:" + user_id)
        if isinstance(row, list):
            row = row[0] if row else None
        if not row:
            return None
        return Wallet(user_id=row["user_id"], balance_minor_units=int(row["balance_minor_units"]),
                      currency=row.get("currency", "INR"), upi_handle=row.get("upi_handle", ""))

    async def save_wallet(self, wallet: Wallet) -> None:
        await self._upsert("pay_wallet:" + wallet.user_id, asdict(wallet))

    async def add_transaction(self, transaction: Transaction) -> Transaction:
        data = asdict(transaction)
        data.pop("id")
        data.update(type=str(transaction.type), status=str(transaction.status),
                    created_at=transaction.created_at.isoformat())
        await self._upsert("pay_transaction:" + transaction.id, data)
        return transaction

    async def list_transactions(self, *, user_id: str, cursor: str | None, limit: int):
        rows = await self._db.rows(
            "SELECT * FROM pay_transaction WHERE user_id = $u ORDER BY created_at DESC", {"u": user_id})
        items = [
            Transaction(id=_raw_id(r), user_id=r["user_id"], type=TransactionType(r["type"]),
                        counterparty=r["counterparty"], amount_minor_units=int(r["amount_minor_units"]),
                        note=r.get("note", ""), currency=r.get("currency", "INR"),
                        status=TransactionStatus(r.get("status", "success")), created_at=_when(r["created_at"]))
            for r in rows
        ]
        return _paginate(items, cursor=cursor, limit=limit)

    async def add_split(self, split: SplitRequest) -> SplitRequest:
        data = asdict(split)
        data.pop("id")
        data["created_at"] = split.created_at.isoformat()
        await self._upsert("pay_split:" + split.id, data)
        return split

    async def list_splits(self, *, user_id: str, cursor: str | None, limit: int):
        rows = await self._db.rows(
            "SELECT * FROM pay_split WHERE requester_id = $u ORDER BY created_at DESC", {"u": user_id})
        items = [
            SplitRequest(id=_raw_id(r), requester_id=r["requester_id"], note=r.get("note", ""),
                         total_minor_units=int(r["total_minor_units"]), currency=r.get("currency", "INR"),
                         participants=[SplitParticipant(**p) for p in r.get("participants") or []],
                         created_at=_when(r["created_at"]))
            for r in rows
        ]
        return _paginate(items, cursor=cursor, limit=limit)
