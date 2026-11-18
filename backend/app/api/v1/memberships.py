"""
Creator memberships: members-only videos and a Join button.

A creator turns on a monthly membership (price ₹10–₹5,000 and a short list
of perks) and can mark any video or clip **Members only**. Viewers who
aren't members see the video with a lock and a Join button; the playback
URL is withheld by the server until they join.

Joining pays one month through Razorpay in **test mode** (the existing
sandbox keys used by Phlio Pay's gateway): the server creates the order,
the app opens Razorpay Checkout, the server verifies the signature and
checks the payment is captured, then grants 30 days. Renewing adds 30 days
to the current end date. There is no auto-renewal and no real money moves.

Endpoints under ``/api/v1/memberships``:

``GET    /plan``                     my plan (creator)
``PUT    /plan``                     set up / change / pause my plan
``GET    /creators/{username}``      a creator's plan + my membership
``POST   /creators/{username}/join`` start checkout → Razorpay order
``POST   /orders/{id}/verify``       finish checkout (payment id + signature)
``GET    /mine``                     memberships I hold
``PUT    /videos/{video_id}``        mark my video members-only (or not)
"""

from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app.api.deps import get_container, get_current_user
from app.api.v1 import pay_gateway
from app.domains.graph.service import key

router = APIRouter(prefix="/memberships", tags=["memberships"])
PERIOD = dt.timedelta(days=30)


def _now() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


class PlanIn(BaseModel):
    enabled: bool = True
    price_minor_units: int = Field(ge=1000, le=500000)  # ₹10 – ₹5,000 a month
    title: str = Field(default="Member", min_length=1, max_length=40)
    perks: list[str] = Field(default_factory=list, max_length=6)

    @field_validator("perks")
    @classmethod
    def _perks(cls, perks):
        clean = [" ".join(p.split())[:80] for p in perks if p.strip()]
        return clean


class JoinIn(BaseModel):
    request_id: uuid.UUID  # idempotency: one order per tap


class VerifyIn(BaseModel):
    payment_id: str = Field(pattern=r"^pay_[A-Za-z0-9]+$")
    signature: str = Field(pattern=r"^[a-fA-F0-9]{64}$")


class VideoIn(BaseModel):
    members_only: bool


def _plan_out(plan: dict | None) -> dict | None:
    if not plan or not plan.get("enabled"):
        return None
    return dict(price_minor_units=plan["price_minor_units"], currency="INR", title=plan.get("title", "Member"),
                perks=plan.get("perks", []), period_days=PERIOD.days)


async def membership_of(c, member_id: str, creator_id: str) -> dict | None:
    """The active membership, or None."""
    if member_id == creator_id:
        return {"until": None, "creator": True}
    row = await c.graph.store.get(key("membership", member_id, creator_id))
    if not row:
        return None
    try:
        if dt.datetime.fromisoformat(row["until"]) <= _now():
            return None
    except (KeyError, ValueError):
        return None
    return row


async def gate_videos(c, viewer_id: str, items: list[dict]) -> list[dict]:
    """Adds members_only / locked / membership to video responses and
    withholds the playback URL of locked ones."""
    creators = {}
    for item in items:
        item.setdefault("members_only", False)
        item["locked"] = False
        if not item.get("members_only"):
            continue
        creator_id = item.get("creator_id")
        if creator_id not in creators:
            plan = await c.graph.store.get(key("membership_plan", creator_id))
            creators[creator_id] = (_plan_out(plan), await membership_of(c, viewer_id, creator_id))
        plan, member = creators[creator_id]
        item["membership"] = plan
        if member is None:
            item["locked"] = True
            item["url"] = ""  # no playback without membership
    return items


@router.get("/plan")
async def my_plan(user=Depends(get_current_user), c=Depends(get_container)):
    plan = await c.graph.store.get(key("membership_plan", user.id))
    members = [m for m in await c.graph.store.rows("membership", {"creator": user.id})
               if dt.datetime.fromisoformat(m["until"]) > _now()]
    return dict(plan=_plan_out(plan) if plan else None, enabled=bool(plan and plan.get("enabled")),
                raw={k: v for k, v in (plan or {}).items() if k not in ("id", "creator")},
                active_members=len(members), payments_configured=pay_gateway.configured(c))


@router.put("/plan")
async def set_plan(body: PlanIn, user=Depends(get_current_user), c=Depends(get_container)):
    await c.graph.store.put(key("membership_plan", user.id), dict(creator=user.id, **body.model_dump(),
                                                                   updated_at=_now().isoformat()))
    return await my_plan(user, c)


async def _creator(c, username: str):
    creator = await c.identity_repository.get_by_username(username.lower())
    if creator is None:
        raise HTTPException(404, "Creator not found.")
    return creator


@router.get("/creators/{username}")
async def creator_plan(username: str, user=Depends(get_current_user), c=Depends(get_container)):
    creator = await _creator(c, username)
    plan = _plan_out(await c.graph.store.get(key("membership_plan", creator.id)))
    mine = await membership_of(c, user.id, creator.id)
    return dict(creator=creator.username, creator_name=creator.full_name, avatar_url=creator.avatar_url,
                plan=plan, member=mine is not None, until=(mine or {}).get("until"),
                is_creator=creator.id == user.id, test_mode=True,
                payments_configured=pay_gateway.configured(c))


@router.post("/creators/{username}/join")
async def join(username: str, body: JoinIn, user=Depends(get_current_user), c=Depends(get_container)):
    creator = await _creator(c, username)
    if creator.id == user.id:
        raise HTTPException(400, "You can't join your own membership.")
    plan = _plan_out(await c.graph.store.get(key("membership_plan", creator.id)))
    if not plan:
        raise HTTPException(404, "This creator doesn't offer a membership right now.")
    if not pay_gateway.configured(c):
        raise HTTPException(503, "Payments aren't set up yet (Razorpay test keys missing on the server).")
    await c.cache.rate_limit(user.id, "membership-join", 10)
    order_id = hashlib.sha256(f"{user.id}:{creator.id}:{body.request_id}".encode()).hexdigest()[:32]
    existing = await c.graph.store.get(key("membership_order", order_id))
    if existing:
        if existing["amount"] != plan["price_minor_units"]:
            raise HTTPException(409, "The price changed. Start again.")
        return _order_out(c, existing)
    order = dict(order_id=order_id, member=user.id, creator=creator.id, amount=plan["price_minor_units"],
                 currency="INR", status="processing", created_at=_now().isoformat())
    await c.graph.store.put(key("membership_order", order_id), order)
    # Never retry this POST automatically: a timeout may still have created the order.
    result = await pay_gateway.provider(c, "POST", "orders", {
        "amount": plan["price_minor_units"], "currency": "INR", "receipt": "mem_" + order_id[:30],
        "notes": {"kind": "membership", "creator": creator.username}})
    order["razorpay_order_id"] = result["id"]
    await c.graph.store.put(key("membership_order", order_id), order)
    return _order_out(c, order)


def _order_out(c, order: dict) -> dict:
    return dict(id=order["order_id"], razorpay_order_id=order.get("razorpay_order_id"), amount=order["amount"],
                currency=order["currency"], status=order["status"], key_id=c.settings.razorpay_key_id, test_mode=True)


@router.post("/orders/{order_id}/verify")
async def verify(order_id: str, body: VerifyIn, user=Depends(get_current_user), c=Depends(get_container)):
    order = await c.graph.store.get(key("membership_order", order_id)) if len(order_id) == 32 else None
    if not order or order["member"] != user.id or not order.get("razorpay_order_id"):
        raise HTTPException(404, "Checkout not found.")
    if order["status"] == "success":
        return await _granted(c, order)
    expected = hmac.new(c.settings.razorpay_key_secret.encode(),
                        f"{order['razorpay_order_id']}|{body.payment_id}".encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, body.signature):
        raise HTTPException(422, "Payment verification failed.")
    # Confirm with Razorpay that the payment really was captured for this amount.
    payments = await pay_gateway.provider(c, "GET", f"orders/{order['razorpay_order_id']}/payments")
    captured = next((p for p in payments.get("items", []) if p.get("id") == body.payment_id
                     and p.get("status") == "captured" and p.get("amount") == order["amount"]
                     and p.get("currency") == "INR"), None)
    if not captured:
        raise HTTPException(409, "The payment hasn't completed yet. Check again in a moment.")
    order.update(status="success", payment_id=body.payment_id, paid_at=_now().isoformat())
    await c.graph.store.put(key("membership_order", order_id), order)
    current = await c.graph.store.get(key("membership", user.id, order["creator"]))
    start = _now()
    if current:
        try:
            start = max(start, dt.datetime.fromisoformat(current["until"]))
        except (KeyError, ValueError):
            pass
    await c.graph.store.put(key("membership", user.id, order["creator"]), dict(
        member=user.id, creator=order["creator"], until=(start + PERIOD).isoformat(),
        since=(current or {}).get("since") or _now().isoformat(), last_order=order_id))
    return await _granted(c, order)


async def _granted(c, order: dict) -> dict:
    row = await c.graph.store.get(key("membership", order["member"], order["creator"]))
    return dict(status="success", member=True, until=(row or {}).get("until"))


@router.get("/mine")
async def mine(user=Depends(get_current_user), c=Depends(get_container)):
    out = []
    for m in await c.graph.store.rows("membership", {"member": user.id}):
        if dt.datetime.fromisoformat(m["until"]) <= _now():
            continue
        creator = await c.identity_repository.get_by_id(m["creator"])
        if creator:
            out.append(dict(creator=creator.username, creator_name=creator.full_name,
                            avatar_url=creator.avatar_url, until=m["until"]))
    return {"items": out}


@router.put("/videos/{video_id}")
async def set_video(video_id: str, body: VideoIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = c.social_video_service.db.execute("SELECT creator FROM videos WHERE id=?", (video_id,)).fetchone()
    if not row:
        raise HTTPException(404, "Video not found.")
    if row[0] != user.id:
        raise HTTPException(403, "Only the creator can change this.")
    if body.members_only and not _plan_out(await c.graph.store.get(key("membership_plan", user.id))):
        raise HTTPException(409, "Set up your membership first.")
    detail_key = key("platform_content", "social", video_id)
    existing = await c.graph.store.get(detail_key) or {}
    await c.graph.store.put(detail_key, {**{k: v for k, v in existing.items() if k != "id"},
                                         "members_only": body.members_only})
    return {"members_only": body.members_only}
