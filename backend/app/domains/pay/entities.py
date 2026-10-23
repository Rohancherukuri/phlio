"""Framework-agnostic domain entities for Phlio Pay.

Per Phlio_Final_Product_Blueprint.md section 4: Pay is financial
infrastructure users access from anywhere in Phlio. **This build stage is a
simulated ledger** — balances and transfers live in the in-memory store so
the product surfaces (wallet, send money, split bills) are real end to end.
Real UPI/rail integration requires regulated partners and must go through
the "Agent proposes -> policy engine -> user confirms -> deterministic
execution" pipeline; nothing here ever moves real money.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from enum import StrEnum


class TransactionType(StrEnum):
    SEND = "send"
    RECEIVE = "receive"


class TransactionStatus(StrEnum):
    SUCCESS = "success"
    PENDING = "pending"


@dataclass(slots=True)
class Wallet:
    """A user's Phlio Pay balance. Minor units (paise) throughout."""

    user_id: str
    balance_minor_units: int = 0
    currency: str = "INR"
    upi_handle: str = ""


@dataclass(slots=True)
class Transaction:
    id: str
    user_id: str
    type: TransactionType
    counterparty: str  # display name or handle of the other side
    amount_minor_units: int
    note: str = ""
    currency: str = "INR"
    status: TransactionStatus = TransactionStatus.SUCCESS
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))


@dataclass(slots=True)
class SplitParticipant:
    name: str
    amount_minor_units: int
    has_paid: bool = False


@dataclass(slots=True)
class SplitRequest:
    """A "split the bill" request — e.g. the Agent plan's estimated total
    divided across friends. Equal shares by default; the requester absorbs
    any rounding remainder."""

    id: str
    requester_id: str
    note: str
    total_minor_units: int
    currency: str = "INR"
    participants: list[SplitParticipant] = field(default_factory=list)
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))
