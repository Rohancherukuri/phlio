"""In-memory implementation of `PayRepository` — the simulated ledger."""

from __future__ import annotations

import asyncio

from app.domains.pay.entities import SplitRequest, Transaction, Wallet
from app.infrastructure.database.memory.social_repo import _paginate


class InMemoryPayRepository:
    def __init__(self) -> None:
        self._wallets: dict[str, Wallet] = {}
        self._transactions_by_user: dict[str, list[Transaction]] = {}
        self._splits_by_user: dict[str, list[SplitRequest]] = {}
        self._lock = asyncio.Lock()

    # -- seeding helper (used by app/core/seed.py, not part of Protocol) ----
    async def seed_wallet(self, wallet: Wallet) -> None:
        self._wallets[wallet.user_id] = wallet

    async def seed_transaction(self, transaction: Transaction) -> None:
        self._transactions_by_user.setdefault(transaction.user_id, []).append(transaction)
        self._transactions_by_user[transaction.user_id].sort(
            key=lambda t: t.created_at, reverse=True
        )

    async def get_wallet(self, user_id: str) -> Wallet | None:
        return self._wallets.get(user_id)

    async def save_wallet(self, wallet: Wallet) -> None:
        async with self._lock:
            self._wallets[wallet.user_id] = wallet

    async def add_transaction(self, transaction: Transaction) -> Transaction:
        async with self._lock:
            self._transactions_by_user.setdefault(transaction.user_id, []).insert(0, transaction)
            return transaction

    async def list_transactions(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[Transaction], str | None]:
        return _paginate(
            self._transactions_by_user.get(user_id, []), cursor=cursor, limit=limit
        )

    async def add_split(self, split: SplitRequest) -> SplitRequest:
        async with self._lock:
            self._splits_by_user.setdefault(split.requester_id, []).insert(0, split)
            return split

    async def list_splits(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[SplitRequest], str | None]:
        return _paginate(self._splits_by_user.get(user_id, []), cursor=cursor, limit=limit)
