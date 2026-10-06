"""Repository contract for Phlio Pay."""

from __future__ import annotations

from typing import Protocol

from app.domains.pay.entities import SplitRequest, Transaction, Wallet


class PayRepository(Protocol):
    async def get_wallet(self, user_id: str) -> Wallet | None: ...

    async def save_wallet(self, wallet: Wallet) -> None: ...

    async def add_transaction(self, transaction: Transaction) -> Transaction: ...

    async def list_transactions(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[Transaction], str | None]: ...

    async def add_split(self, split: SplitRequest) -> SplitRequest: ...

    async def list_splits(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[SplitRequest], str | None]: ...
