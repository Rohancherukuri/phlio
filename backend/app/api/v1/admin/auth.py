"""Admin accounts: signup, login and the team (separate from app users).

    GET    /admin/auth/status          whether an owner exists / a code is needed
    POST   /admin/auth/signup          {email, name, password, code?}
    POST   /admin/auth/login           {email, password}
    POST   /admin/auth/oauth/{google|apple}  {token, code?, name?} — sign in, or
                                       sign up with an invite/signup code
    GET    /admin/auth/me
    GET    /admin/team                 admins and open invites (admin+)
    POST   /admin/team/invites         {email?, role} → a one-time invite code (admin+)
    DELETE /admin/team/invites/{code}
    PATCH  /admin/team/{id}            {role?, disabled?} (owner)

Who can sign up: the very first signup becomes the owner (it must give
ADMIN_SIGNUP_CODE when that is set, and in production it always must).
Everyone after that needs an invite code from an owner or admin.

Admin tokens are separate from app tokens: same signing key, but type
"admin" and audience "phlio-admin", so an app access token can never open
the admin API and an admin token can never act as an app user.
"""

from __future__ import annotations

import datetime as dt
import hmac
import secrets
import uuid
from typing import Literal

import jwt as pyjwt
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, EmailStr, Field

from app.api.deps import get_container
from app.domains.graph.service import key
from app.domains.graph.store import now
from app.infrastructure.security.password import hash_password, verify_password

router = APIRouter(prefix="/admin", tags=["admin"])

USER, INVITE, AUDIT = "admin_user", "admin_invite", "admin_audit"
Role = Literal["owner", "admin", "analyst", "viewer"]
RANK = {"viewer": 0, "analyst": 1, "admin": 2, "owner": 3}
AUDIENCE = "phlio-admin"


class SignupIn(BaseModel):
    email: EmailStr
    name: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=10, max_length=128)
    code: str | None = Field(default=None, max_length=128)


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class InviteIn(BaseModel):
    email: EmailStr | None = None
    role: Literal["admin", "analyst", "viewer"] = "viewer"


class MemberPatch(BaseModel):
    role: Role | None = None
    disabled: bool | None = None


def _public(a: dict) -> dict:
    return {k: a.get(k) for k in ("id", "email", "name", "role", "created_at", "last_login", "disabled")} | {
        "id": a["admin_id"]
    }


def issue_admin_token(admin: dict, settings) -> dict:
    hours = max(1, settings.admin_token_hours)
    issued = dt.datetime.now(dt.UTC)
    token = pyjwt.encode(
        {"sub": admin["admin_id"], "type": "admin", "aud": AUDIENCE, "role": admin["role"],
         "iat": issued, "exp": issued + dt.timedelta(hours=hours), "jti": uuid.uuid4().hex},
        settings.jwt_secret, algorithm=settings.jwt_algorithm,
    )
    return {"access_token": token, "token_type": "bearer", "expires_in": hours * 3600}


def decode_admin_token(token: str, settings) -> str:
    try:
        payload = pyjwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm], audience=AUDIENCE)
    except pyjwt.PyJWTError:
        raise HTTPException(401, "Your admin session has expired. Sign in again.") from None
    if payload.get("type") != "admin" or not payload.get("sub"):
        raise HTTPException(401, "Not an admin token.")
    return payload["sub"]


async def admin_by_id(c, admin_id: str) -> dict | None:
    rows = await c.graph.store.rows(USER, {"admin_id": admin_id})
    return rows[0] if rows else None


async def admin_from_token(c, token: str) -> dict:
    admin = await admin_by_id(c, decode_admin_token(token, c.settings))
    if not admin or admin.get("disabled"):
        raise HTTPException(401, "This admin account is not active.")
    return admin


def require(role: Role = "viewer"):
    async def dependency(c=Depends(get_container), authorization: str | None = Header(default=None)) -> dict:
        if not authorization or not authorization.lower().startswith("bearer "):
            raise HTTPException(401, "Sign in to the admin panel.")
        admin = await admin_from_token(c, authorization.split(" ", 1)[1].strip())
        if RANK.get(admin.get("role"), -1) < RANK[role]:
            raise HTTPException(403, f"This needs the {role} role.")
        return admin

    return dependency


async def audit(c, admin: dict | None, action: str, **detail) -> None:
    await c.graph.store.put(key(AUDIT, uuid.uuid4().hex), {
        "admin_id": admin["admin_id"] if admin else None, "email": admin.get("email") if admin else None,
        "action": action, "detail": detail, "created_at": now(),
    })


async def _has_admins(c) -> bool:
    return bool(await c.graph.store.rows(USER))


@router.get("/auth/status")
async def status(c=Depends(get_container)):
    has = await _has_admins(c)
    settings = c.settings
    return {
        "has_admins": has,
        "signup": "invite" if has else "bootstrap",
        "code_required": (not has) and bool(settings.admin_signup_code or settings.is_production),
        # Public web client ids for Google Identity Services / Sign in with Apple JS.
        "google_client_id": _first(settings.google_server_client_id or settings.google_client_ids),
        "apple_service_id": _first(settings.apple_service_id),
    }


def _first(value: str | None) -> str | None:
    ids = [x.strip() for x in (value or "").split(",") if x.strip()]
    return ids[0] if ids else None


def _same(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode(), b.encode())


async def _create_admin(c, *, email: str, name: str, code: str | None, password: str | None = None,
                        links: dict | None = None) -> dict:
    """Creates an admin: the first one is the owner (with the signup code when
    one is required), everyone after that needs an invite."""
    if await c.graph.store.get(key(USER, email)):
        raise HTTPException(409, "An admin with this email already exists.")
    settings = c.settings
    invite = None
    if not await _has_admins(c):
        expected = settings.admin_signup_code
        if settings.is_production and not expected:
            raise HTTPException(403, "Set ADMIN_SIGNUP_CODE on the server to create the first admin.")
        if expected and not (code and _same(code, expected)):
            raise HTTPException(403, "The signup code is not right.")
        role = "owner"
    else:
        invite = await c.graph.store.get(key(INVITE, code or "-"))
        if not invite or invite.get("used_by") or dt.datetime.fromisoformat(invite["expires_at"]) < dt.datetime.now(dt.UTC):
            raise HTTPException(403, "Ask an admin for an invite code.")
        if invite.get("email") and invite["email"] != email:
            raise HTTPException(403, "This invite is for a different email.")
        role = invite["role"]
    admin = {
        "admin_id": "adm_" + uuid.uuid4().hex[:16], "email": email, "name": (name or email.split("@")[0]).strip()[:80],
        "role": role, "password_hash": hash_password(password) if password else None,
        "created_at": now(), "last_login": now(), "disabled": False, **(links or {}),
    }
    await c.graph.store.put(key(USER, email), admin)
    if invite:
        await c.graph.store.put(key(INVITE, code), dict(invite, used_by=admin["admin_id"], used_at=now()))
    await audit(c, admin, "signup", role=role, method=next(iter(links or {}), "password_").split("_")[0])
    return admin


@router.post("/auth/signup", status_code=201)
async def signup(body: SignupIn, request: Request, c=Depends(get_container)):
    ip = request.client.host if request.client else "?"
    await c.cache.rate_limit(ip, "admin_signup", 10)
    admin = await _create_admin(c, email=body.email.lower(), name=body.name, code=body.code, password=body.password)
    return {"admin": _public(admin), "tokens": issue_admin_token(admin, c.settings)}


@router.post("/auth/login")
async def login(body: LoginIn, request: Request, c=Depends(get_container)):
    email = body.email.lower()
    ip = request.client.host if request.client else "?"
    await c.cache.rate_limit(f"{ip}:{email}", "admin_login", 8)
    admin = await c.graph.store.get(key(USER, email))
    # Same answer (and a hash check either way) for unknown emails and
    # wrong passwords, so the form can't be used to find admin emails.
    valid = verify_password(body.password, (admin or {}).get("password_hash") or _DUMMY)
    if not admin or not valid or admin.get("disabled"):
        raise HTTPException(401, "Email or password is incorrect.")
    admin["last_login"] = now()
    await c.graph.store.put(key(USER, email), admin)
    await audit(c, admin, "login")
    return {"admin": _public(admin), "tokens": issue_admin_token(admin, c.settings)}


_DUMMY = hash_password(secrets.token_urlsafe(16))


class OAuthIn(BaseModel):
    token: str = Field(min_length=20, max_length=8192)
    code: str | None = Field(default=None, max_length=128)
    name: str | None = Field(default=None, max_length=80)


@router.post("/auth/oauth/{provider}")
async def oauth(provider: Literal["google", "apple"], body: OAuthIn, request: Request, c=Depends(get_container)):
    """Sign in with Google or Apple. The ID token is verified against the
    provider's keys (same checks as the app's sign-in). An existing admin is
    matched by the provider account, then by verified email; a new one needs
    the same signup code / invite as a password signup."""
    from app.api.v1.auth_security import _verified

    ip = request.client.host if request.client else "?"
    await c.cache.rate_limit(ip, "admin_oauth", 20)
    claims = await _verified(c, provider, body.token)
    sub = str(claims["sub"])
    email = (claims.get("email") or "").strip().lower()
    verified = str(claims.get("email_verified", "false")).lower() == "true"
    field = f"{provider}_sub"
    matches = await c.graph.store.rows(USER, {field: sub})
    admin = matches[0] if matches else None
    if admin is None and email and verified:
        admin = await c.graph.store.get(key(USER, email))
    if admin is None:
        if not (email and verified):
            raise HTTPException(422, "Your account didn't share a verified email address.")
        if not body.code and await _has_admins(c):
            raise HTTPException(403, f"No admin account for {email}. Ask an admin for an invite.")
        admin = await _create_admin(c, email=email, name=body.name or claims.get("name") or "", code=body.code,
                                    links={field: sub})
        return {"admin": _public(admin), "tokens": issue_admin_token(admin, c.settings), "is_new": True}
    if admin.get("disabled"):
        raise HTTPException(401, "This admin account is turned off.")
    admin[field] = sub
    admin["last_login"] = now()
    await c.graph.store.put(key(USER, admin["email"]), admin)
    await audit(c, admin, "login", provider=provider)
    return {"admin": _public(admin), "tokens": issue_admin_token(admin, c.settings), "is_new": False}


@router.get("/auth/me")
async def me(admin=Depends(require())):
    return _public(admin)


@router.get("/team")
async def team(admin=Depends(require("admin")), c=Depends(get_container)):
    members = sorted(await c.graph.store.rows(USER), key=lambda a: a["created_at"])
    invites = [
        {k: i.get(k) for k in ("code", "email", "role", "created_at", "expires_at", "created_by")}
        for i in await c.graph.store.rows(INVITE)
        if not i.get("used_by") and dt.datetime.fromisoformat(i["expires_at"]) >= dt.datetime.now(dt.UTC)
    ]
    log = sorted(await c.graph.store.rows(AUDIT), key=lambda a: a["created_at"], reverse=True)[:30]
    return {"members": [_public(m) for m in members], "invites": invites,
            "audit": [{k: a.get(k) for k in ("email", "action", "detail", "created_at")} for a in log]}


@router.post("/team/invites", status_code=201)
async def invite(body: InviteIn, admin=Depends(require("admin")), c=Depends(get_container)):
    code = secrets.token_urlsafe(18)
    row = {"code": code, "email": body.email.lower() if body.email else None, "role": body.role,
           "created_by": admin["email"], "created_at": now(),
           "expires_at": (dt.datetime.now(dt.UTC) + dt.timedelta(days=7)).isoformat()}
    await c.graph.store.put(key(INVITE, code), row)
    await audit(c, admin, "invite", role=body.role, email=row["email"])
    return row


@router.delete("/team/invites/{code}", status_code=204)
async def revoke(code: str, admin=Depends(require("admin")), c=Depends(get_container)):
    await c.graph.store.delete(key(INVITE, code))
    await audit(c, admin, "revoke_invite")


@router.patch("/team/{admin_id}")
async def update_member(admin_id: str, body: MemberPatch, admin=Depends(require("owner")), c=Depends(get_container)):
    member = await admin_by_id(c, admin_id)
    if not member:
        raise HTTPException(404, "No such admin.")
    if member["admin_id"] == admin["admin_id"]:
        raise HTTPException(400, "You can't change your own role or access.")
    if body.role is not None:
        member["role"] = body.role
    if body.disabled is not None:
        member["disabled"] = body.disabled
    await c.graph.store.put(key(USER, member["email"]), member)
    await audit(c, admin, "update_member", member=member["email"], role=member["role"], disabled=member["disabled"])
    return _public(member)
