"""Pay domain service: wallet, simulated transfers, and bill splits.

Rules enforced here (and nowhere else):
- amounts must be positive;
- sends cannot overdraw the wallet;
- splits divide equally, with the rounding remainder on the requester;
- every successful transfer emits a `Transaction` record.

A `PaymentGateway`-style abstraction will replace the direct balance math
when a regulated partner is integrated; the service's public API is designed
to survive that swap unchanged.
"""

from __future__ import annotations

import logging

from app.common.exceptions import ValidationAppError
from app.domains.pay.entities import (
    SplitParticipant,
    SplitRequest,
    Transaction,
    TransactionStatus,
    TransactionType,
    Wallet,
)
from app.domains.pay.repository import PayRepository

logger = logging.getLogger("phlio.pay")


class PayService:
    def __init__(self, repository: PayRepository, id_factory) -> None:
        self._repository = repository
        self._id_factory = id_factory

    async def get_wallet(self, user_id: str) -> Wallet:
        wallet = await self._repository.get_wallet(user_id)
        if wallet is None:
            # Wallets are created lazily — everyone can receive a payment
            # request even before they've "set up" Pay.
            wallet = Wallet(user_id=user_id, upi_handle=f"{user_id}@phlio")
            await self._repository.save_wallet(wallet)
        return wallet

    async def list_transactions(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[Transaction], str | None]:
        return await self._repository.list_transactions(user_id=user_id, cursor=cursor, limit=limit)

    async def send_money(
        self, *, user_id: str, counterparty: str, amount_minor_units: int, note: str = ""
    ) -> Transaction:
        if amount_minor_units <= 0:
            raise ValidationAppError("Amount must be greater than zero.")
        if not counterparty.strip():
            raise ValidationAppError("Recipient is required.")

        wallet = await self.get_wallet(user_id)
        if wallet.balance_minor_units < amount_minor_units:
            raise ValidationAppError("Insufficient balance.")

        wallet.balance_minor_units -= amount_minor_units
        await self._repository.save_wallet(wallet)

        transaction = Transaction(
            id=await self._id_factory("txn"),
            user_id=user_id,
            type=TransactionType.SEND,
            counterparty=counterparty.strip(),
            amount_minor_units=amount_minor_units,
            note=note,
            currency=wallet.currency,
            status=TransactionStatus.SUCCESS,
        )
        created = await self._repository.add_transaction(transaction)
        logger.info(
            "pay.sent txn_id=%s user_id=%s amount=%d to=%s",
            created.id, user_id, amount_minor_units, counterparty,
        )
        return created

    async def receive_money(
        self, *, user_id: str, counterparty: str, amount_minor_units: int, note: str = ""
    ) -> Transaction:
        if amount_minor_units <= 0:
            raise ValidationAppError("Amount must be greater than zero.")

        wallet = await self.get_wallet(user_id)
        wallet.balance_minor_units += amount_minor_units
        await self._repository.save_wallet(wallet)

        transaction = Transaction(
            id=await self._id_factory("txn"),
            user_id=user_id,
            type=TransactionType.RECEIVE,
            counterparty=counterparty.strip(),
            amount_minor_units=amount_minor_units,
            note=note,
            currency=wallet.currency,
        )
        created = await self._repository.add_transaction(transaction)
        logger.info(
            "pay.received txn_id=%s user_id=%s amount=%d from=%s",
            created.id, user_id, amount_minor_units, counterparty,
        )
        return created

    async def create_split(
        self,
        *,
        user_id: str,
        total_minor_units: int,
        participant_names: list[str],
        note: str = "",
    ) -> SplitRequest:
        if total_minor_units <= 0:
            raise ValidationAppError("Total must be greater than zero.")
        names = [n.strip() for n in participant_names if n.strip()]
        if not names:
            raise ValidationAppError("At least one participant is required.")

        wallet = await self.get_wallet(user_id)
        share_count = len(names) + 1  # participants + the requester
        per_head = total_minor_units // share_count
        remainder = total_minor_units - per_head * share_count

        participants = [SplitParticipant(name=n, amount_minor_units=per_head) for n in names]
        created = SplitRequest(
            id=await self._id_factory("split"),
            requester_id=user_id,
            note=note,
            total_minor_units=total_minor_units,
            currency=wallet.currency,
            participants=participants,
        )
        # Requester absorbs the rounding remainder (a few paise at most).
        created.participants.append(
            SplitParticipant(name="You", amount_minor_units=per_head + remainder, has_paid=True)
        )
        return await self._repository.add_split(created)

    async def list_splits(
        self, *, user_id: str, cursor: str | None, limit: int
    ) -> tuple[list[SplitRequest], str | None]:
        return await self._repository.list_splits(user_id=user_id, cursor=cursor, limit=limit)
