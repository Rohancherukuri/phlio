"""Phlio Pay endpoints: wallet overview, simulated transfers, bill splits.

Every endpoint requires auth. This is a *simulated* ledger (see
`domains/pay/entities.py`) — the request/response contract is designed so a
regulated provider can be dropped in behind `PayService` without changing
these schemas.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.deps import get_activity_service, get_current_user, get_pay_service
from app.common.pagination import clamp_limit
from app.common.schemas import Page, PageMeta
from app.domains.activity.entities import ActivityKind
from app.domains.activity.service import ActivityService
from app.domains.identity.entities import User
from app.domains.pay.entities import (
    SplitRequest,
    Transaction,
    TransactionStatus,
    TransactionType,
)
from app.domains.pay.service import PayService

router = APIRouter(prefix="/pay", tags=["pay"])


class TransactionResponse(BaseModel):
    id: str
    type: TransactionType
    counterparty: str
    amount_minor_units: int
    note: str
    currency: str
    status: TransactionStatus
    created_at: dt.datetime

    @classmethod
    def from_entity(cls, txn: Transaction) -> TransactionResponse:
        return cls(
            id=txn.id,
            type=txn.type,
            counterparty=txn.counterparty,
            amount_minor_units=txn.amount_minor_units,
            note=txn.note,
            currency=txn.currency,
            status=txn.status,
            created_at=txn.created_at,
        )


class SplitParticipantResponse(BaseModel):
    name: str
    amount_minor_units: int
    has_paid: bool


class SplitResponse(BaseModel):
    id: str
    note: str
    total_minor_units: int
    currency: str
    participants: list[SplitParticipantResponse]
    created_at: dt.datetime

    @classmethod
    def from_entity(cls, split: SplitRequest) -> SplitResponse:
        return cls(
            id=split.id,
            note=split.note,
            total_minor_units=split.total_minor_units,
            currency=split.currency,
            participants=[
                SplitParticipantResponse(
                    name=p.name, amount_minor_units=p.amount_minor_units, has_paid=p.has_paid
                )
                for p in split.participants
            ],
            created_at=split.created_at,
        )


class WalletOverviewResponse(BaseModel):
    balance_minor_units: int
    currency: str
    upi_handle: str
    recent_transactions: list[TransactionResponse]


class SendMoneyRequest(BaseModel):
    counterparty: str = Field(min_length=1, max_length=80)
    amount_minor_units: int = Field(gt=0)
    note: str = Field(default="", max_length=140)


class CreateSplitRequest(BaseModel):
    total_minor_units: int = Field(gt=0)
    participant_names: list[str] = Field(min_length=1, max_length=20)
    note: str = Field(default="", max_length=140)


@router.get("/overview", response_model=WalletOverviewResponse)
async def pay_overview(
    pay_service: PayService = Depends(get_pay_service),
    current_user: User = Depends(get_current_user),
) -> WalletOverviewResponse:
    wallet = await pay_service.get_wallet(current_user.id)
    transactions, _ = await pay_service.list_transactions(
        user_id=current_user.id, cursor=None, limit=8
    )
    return WalletOverviewResponse(
        balance_minor_units=wallet.balance_minor_units,
        currency=wallet.currency,
        upi_handle=wallet.upi_handle,
        recent_transactions=[TransactionResponse.from_entity(t) for t in transactions],
    )


@router.get("/transactions", response_model=Page[TransactionResponse])
async def list_transactions(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    pay_service: PayService = Depends(get_pay_service),
    current_user: User = Depends(get_current_user),
) -> Page[TransactionResponse]:
    transactions, next_cursor = await pay_service.list_transactions(
        user_id=current_user.id, cursor=cursor, limit=clamp_limit(limit)
    )
    return Page(
        items=[TransactionResponse.from_entity(t) for t in transactions],
        meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None),
    )


@router.post("/transactions", response_model=TransactionResponse, status_code=201)
async def send_money(
    payload: SendMoneyRequest,
    pay_service: PayService = Depends(get_pay_service),
    activity_service: ActivityService = Depends(get_activity_service),
    current_user: User = Depends(get_current_user),
) -> TransactionResponse:
    txn = await pay_service.send_money(
        user_id=current_user.id,
        counterparty=payload.counterparty,
        amount_minor_units=payload.amount_minor_units,
        note=payload.note,
    )
    await activity_service.record(
        user_id=current_user.id,
        kind=ActivityKind.PAY,
        title=f"Sent ₹{payload.amount_minor_units / 100:,.0f} to {txn.counterparty}",
        body=txn.note or "Phlio Pay transfer",
        icon="💸",
        ref_id=txn.id,
    )
    return TransactionResponse.from_entity(txn)


@router.post("/splits", response_model=SplitResponse, status_code=201)
async def create_split(
    payload: CreateSplitRequest,
    pay_service: PayService = Depends(get_pay_service),
    activity_service: ActivityService = Depends(get_activity_service),
    current_user: User = Depends(get_current_user),
) -> SplitResponse:
    split = await pay_service.create_split(
        user_id=current_user.id,
        total_minor_units=payload.total_minor_units,
        participant_names=payload.participant_names,
        note=payload.note,
    )
    await activity_service.record(
        user_id=current_user.id,
        kind=ActivityKind.PAY,
        title="Split request created 🧾",
        body=f"{split.note or 'Bill'} · ₹{split.total_minor_units / 100:,.0f} across "
        f"{len(split.participants)} people",
        icon="🧾",
        ref_id=split.id,
    )
    return SplitResponse.from_entity(split)


@router.get("/splits", response_model=Page[SplitResponse])
async def list_splits(
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    pay_service: PayService = Depends(get_pay_service),
    current_user: User = Depends(get_current_user),
) -> Page[SplitResponse]:
    splits, next_cursor = await pay_service.list_splits(
        user_id=current_user.id, cursor=cursor, limit=clamp_limit(limit)
    )
    return Page(
        items=[SplitResponse.from_entity(s) for s in splits],
        meta=PageMeta(next_cursor=next_cursor, has_more=next_cursor is not None),
    )
