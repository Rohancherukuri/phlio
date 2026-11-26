"""Phlio Pay profile: your QR codes, bank accounts, cards and pay settings.

    GET   /pay/profile                     everything on the Pay profile page
    PATCH /pay/profile/settings            {autopay?, fingerprint?, international?, shake_to_scan?}
    PUT   /pay/profile/primary             {account_id}: the account money arrives in

Phlio Pay runs on a simulated ledger (see pay.py), so the linked bank
accounts and cards here are **test accounts**: generated per user from a
hash of their id, always masked (only the last four digits exist), and
flagged ``test_mode``. No real account or card numbers are stored or
accepted. UPI ids are on Phlio's own ``@phlio`` handle, and each QR code
encodes a standard ``upi://pay`` link for that id.
"""

from __future__ import annotations

import hashlib
import secrets
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.api.deps import get_container, get_current_user, get_pay_service
from app.domains.graph.service import key
from app.domains.graph.store import now

router = APIRouter(prefix="/pay/profile", tags=["pay"])

TABLE = "pay_profile"
# name, short name, colour
BANKS = [
    ("HDFC Bank", "HDFC", "#72A7FF"),
    ("State Bank of India", "SBI", "#68D7CD"),
    ("ICICI Bank", "ICICI", "#FFB58F"),
    ("Union Bank of India", "Union Bank", "#F5636B"),
    ("Axis Bank", "Axis", "#E795D7"),
    ("Kotak Mahindra Bank", "Kotak", "#F6B93B"),
]
NETWORKS = ["RuPay", "Visa", "Mastercard"]
DEFAULT_SETTINGS = dict(autopay=False, fingerprint=False, international=False, shake_to_scan=True)


class SettingsIn(BaseModel):
    autopay: bool | None = None
    fingerprint: bool | None = None
    international: bool | None = None
    shake_to_scan: bool | None = None


class PrimaryIn(BaseModel):
    account_id: str


def _digits(seed: str, n: int = 4) -> str:
    return str(int(hashlib.sha256(seed.encode()).hexdigest(), 16))[-n:]


def _accounts(user) -> list[dict]:
    """Two or three test bank accounts, the same every time for a user."""
    h = int(hashlib.sha256(("pay-accounts" + user.id).encode()).hexdigest(), 16)
    count = 2 + h % 2
    picked, i = [], h
    while len(picked) < count:
        bank = BANKS[i % len(BANKS)]
        if bank not in picked:
            picked.append(bank)
        i //= 7
        i += 3
    handle = user.username.lower().replace("_", ".")
    out = []
    for n, (name, short, colour) in enumerate(picked):
        slug = short.lower().replace(" ", "")
        out.append(dict(
            id=f"acc_{slug}", bank=name, short=short, colour=colour,
            type="Savings" if n != 2 else "Current", last4=_digits(user.id + slug),
            upi_id=f"{handle}@phlio" if n == 0 else f"{handle}.{slug}@phlio",
        ))
    return out


def _cards(user, accounts: list[dict]) -> list[dict]:
    first, other = accounts[0], accounts[-1]
    return [
        dict(id="card_debit", kind="debit", bank=first["short"], network="RuPay", last4=_digits(user.id + "debit"),
             colour=first["colour"], upi_linked=True),
        dict(id="card_credit", kind="credit", bank=other["short"],
             network=NETWORKS[1 + int(_digits(user.id, 1)) % 2], last4=_digits(user.id + "credit"),
             colour=other["colour"], upi_linked=False),
    ]


def _qr(upi_id: str, name: str) -> str:
    return "upi://pay?" + urlencode({"pa": upi_id, "pn": name, "cu": "INR"})


def _mask_phone(phone: str | None) -> str | None:
    if not phone:
        return None
    digits = [ch for ch in phone if ch.isdigit()]
    return (phone[:3] + " ••••• " + "".join(digits[-4:])) if len(digits) >= 6 else phone


async def _row(c, user_id: str) -> dict:
    return await c.graph.store.get(key(TABLE, user_id)) or {}


@router.get("")
async def profile(user=Depends(get_current_user), pay=Depends(get_pay_service), c=Depends(get_container)):
    row = await _row(c, user.id)
    accounts = _accounts(user)
    primary = row.get("primary") if any(a["id"] == row.get("primary") for a in accounts) else accounts[0]["id"]
    name = user.full_name or user.username
    for a in accounts:
        a["primary"] = a["id"] == primary
        a["qr"] = _qr(a["upi_id"], name)
    accounts.sort(key=lambda a: not a["primary"])
    wallet = await pay.get_wallet(user.id)
    if not row.get("refer_code"):
        row = dict(row, refer_code=f"PHLIO{secrets.token_hex(3).upper()}", created_at=now())
        await c.graph.store.put(key(TABLE, user.id), row)
    return dict(
        name=name, username=user.username, avatar_url=user.avatar_url, phone=_mask_phone(user.phone_number),
        wallet_upi=wallet.upi_handle, receiving=True, test_mode=True,
        accounts=accounts, cards=_cards(user, accounts),
        settings={**DEFAULT_SETTINGS, **(row.get("settings") or {})},
        refer=dict(code=row["refer_code"], reward="₹100 for you and a friend after their first payment"),
    )


@router.patch("/settings")
async def update_settings(body: SettingsIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _row(c, user.id)
    settings = {**DEFAULT_SETTINGS, **(row.get("settings") or {}),
                **{k: v for k, v in body.model_dump().items() if v is not None}}
    await c.graph.store.put(key(TABLE, user.id), dict(row, settings=settings, updated_at=now()))
    return settings


@router.put("/primary")
async def set_primary(body: PrimaryIn, user=Depends(get_current_user), c=Depends(get_container)):
    if body.account_id not in {a["id"] for a in _accounts(user)}:
        raise HTTPException(404, "No such account.")
    row = await _row(c, user.id)
    await c.graph.store.put(key(TABLE, user.id), dict(row, primary=body.account_id, updated_at=now()))
    return dict(primary=body.account_id)
