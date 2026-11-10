"""Sign in with Google / Apple, and two-factor authentication (TOTP).

Google / Apple
--------------
The app gets an ID token from Google (google_sign_in) or Apple
(sign_in_with_apple) and posts it here. The token's signature is checked
against the provider's published keys (JWKS), and its audience must be one of
our client ids (``GOOGLE_CLIENT_IDS`` / ``APPLE_CLIENT_IDS``, comma separated).
The provider account is linked to a Phlio account in ``oauth_identity``:
an existing link signs that account in; otherwise a verified email that
matches an account links to it; otherwise a new account is created
(``is_new_user`` tells the app to show the sign-up details step).

Two-factor authentication
-------------------------
Authenticator-app codes (RFC 6238 TOTP, 6 digits, 30 s, ±1 step) plus ten
one-time backup codes. The secret is stored encrypted (Fernet, keyed from
JWT_SECRET) in ``two_factor:<user_id>``; backup codes are stored hashed.
When it's on, password and Google/Apple sign-ins return
``{"two_factor_required": true, "challenge": …}`` instead of tokens, and the
app finishes with ``POST /auth/2fa/verify``.
"""
from __future__ import annotations

import base64
import datetime as dt
import hashlib
import hmac
import re
import secrets
import struct
import time
from urllib.parse import quote, urlencode

import jwt as pyjwt
from cryptography.fernet import Fernet, InvalidToken
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key
from app.domains.identity.entities import User
from app.infrastructure.core_engine.native import native
from app.infrastructure.security import guard
from app.infrastructure.security.guard import client_ip
from app.infrastructure.security.jwt import issue_token_pair

router = APIRouter(prefix="/auth", tags=["auth"])

ISSUER = "Phlio"
STEP = 30
DIGITS = 6
CHALLENGE_MINUTES = 5


# -- TOTP ------------------------------------------------------------------------------

def new_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def totp(secret: str, step: int) -> str:
    key_bytes = base64.b32decode(secret + "=" * (-len(secret) % 8), casefold=True)
    digest = hmac.new(key_bytes, struct.pack(">Q", step), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(value % 10 ** DIGITS).zfill(DIGITS)


def matching_step(secret: str, code: str, now: float | None = None) -> int | None:
    """The time step `code` belongs to (now, or one step either side).

    Runs in Rust (``phlio_crypto::totp_matching_step``: constant-time, checks
    every window) when ``phlio_native`` is loaded; this Python body is the
    behaviour-identical fallback."""
    code = re.sub(r"\s", "", code or "")
    if not re.fullmatch(r"\d{6}", code):
        return None
    if native is not None:
        try:
            return native.totp_matching_step(secret, code, now if now is not None else time.time())
        except ValueError:
            return None
    current = int((now if now is not None else time.time()) // STEP)
    for step in (current, current - 1, current + 1):
        if hmac.compare_digest(totp(secret, step), code):
            return step
    return None


def _fernet(c) -> Fernet:
    digest = hashlib.sha256(("phlio-2fa:" + c.settings.jwt_secret).encode()).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def _hash_code(code: str) -> str:
    return hashlib.sha256(code.replace("-", "").lower().encode()).hexdigest()


def _backup_codes() -> list[str]:
    alphabet = "abcdefghjkmnpqrstuvwxyz23456789"
    return ["".join(secrets.choice(alphabet) for _ in range(4)) + "-" +
            "".join(secrets.choice(alphabet) for _ in range(4)) for _ in range(10)]


async def two_factor_row(c, user_id: str) -> dict | None:
    return await c.graph.store.get(key("two_factor", user_id))


async def two_factor_enabled(c, user_id: str) -> bool:
    row = await two_factor_row(c, user_id)
    return bool(row and row.get("enabled"))


async def check_code(c, user_id: str, code: str) -> bool:
    """An authenticator code (not reused) or an unused backup code."""
    row = await two_factor_row(c, user_id)
    if not row or not row.get("secret"):
        return False
    try:
        secret = _fernet(c).decrypt(row["secret"].encode()).decode()
    except InvalidToken:
        return False
    step = matching_step(secret, code)
    if step is not None:
        if step <= int(row.get("last_step") or 0):
            return False  # each code works once
        await c.graph.store.put(row["id"], dict(row, last_step=step))
        return True
    hashed = _hash_code(code.strip())
    backups = list(row.get("backup_codes") or [])
    if row.get("enabled") and hashed in backups:
        backups.remove(hashed)
        await c.graph.store.put(row["id"], dict(row, backup_codes=backups))
        return True
    return False


# -- Sessions -----------------------------------------------------------------------------

def _challenge(c, user_id: str) -> str:
    now = dt.datetime.now(dt.UTC)
    return pyjwt.encode({"sub": user_id, "type": "2fa", "iat": now,
                         "exp": now + dt.timedelta(minutes=CHALLENGE_MINUTES)},
                        c.settings.jwt_secret, algorithm=c.settings.jwt_algorithm)


async def session_or_challenge(c, user: User, **extra) -> dict:
    """Tokens for `user`, or a 2FA challenge when two-factor is on."""
    from app.api.v1.auth import AuthResponse, TokenResponse, UserResponse

    if await two_factor_enabled(c, user.id):
        return dict(two_factor_required=True, challenge=_challenge(c, user.id),
                    methods=["totp", "backup_code"], **extra)
    tokens = issue_token_pair(user.id, c.settings)
    body = AuthResponse(user=UserResponse.from_entity(user),
                        tokens=TokenResponse.from_token_pair(tokens)).model_dump(mode="json")
    return dict(body, **extra)


class VerifyIn(BaseModel):
    challenge: str
    code: str = Field(min_length=6, max_length=12)


@router.post("/2fa/verify")
async def verify_login(body: VerifyIn, request: Request, c=Depends(get_container)):
    """Second step of sign-in: the challenge plus a code."""
    try:
        payload = pyjwt.decode(body.challenge, c.settings.jwt_secret, algorithms=[c.settings.jwt_algorithm])
    except pyjwt.PyJWTError:
        raise HTTPException(400, "This sign-in expired. Start again.")
    if payload.get("type") != "2fa" or not payload.get("sub"):
        raise HTTPException(400, "This sign-in expired. Start again.")
    user_id = payload["sub"]
    await c.cache.rate_limit(user_id, "2fa-verify", 8)
    ip = client_ip(request)
    guard.two_factor_guard.check(user_id, ip)
    if not await check_code(c, user_id, body.code):
        guard.two_factor_guard.failed(user_id, ip)
        raise HTTPException(422, "That code didn't work. Check your authenticator app and try again.")
    guard.two_factor_guard.succeeded(user_id)
    user = await c.identity_service.get_user_or_raise(user_id)
    from app.api.v1.auth import AuthResponse, TokenResponse, UserResponse

    tokens = issue_token_pair(user.id, c.settings)
    return AuthResponse(user=UserResponse.from_entity(user), tokens=TokenResponse.from_token_pair(tokens))


# -- 2FA settings -------------------------------------------------------------------------

@router.get("/2fa")
async def two_factor_status(user=Depends(get_current_user), c=Depends(get_container)):
    row = await two_factor_row(c, user.id)
    enabled = bool(row and row.get("enabled"))
    return dict(enabled=enabled,
                backup_codes_left=len((row or {}).get("backup_codes") or []) if enabled else 0,
                enabled_at=(row or {}).get("enabled_at") if enabled else None)


@router.post("/2fa/setup")
async def two_factor_setup(user=Depends(get_current_user), c=Depends(get_container)):
    """A new secret for the authenticator app (not on until confirmed)."""
    row = await two_factor_row(c, user.id)
    if row and row.get("enabled"):
        raise HTTPException(409, "Two-factor authentication is already on.")
    secret = new_secret()
    await c.graph.store.put(key("two_factor", user.id), dict(
        owner=user.id, enabled=False, secret=_fernet(c).encrypt(secret.encode()).decode(),
        last_step=0, backup_codes=[], created_at=dt.datetime.now(dt.UTC).isoformat()))
    label = quote(f"{ISSUER}:{user.username}")
    uri = f"otpauth://totp/{label}?" + urlencode(
        dict(secret=secret, issuer=ISSUER, algorithm="SHA1", digits=DIGITS, period=STEP))
    return dict(secret=" ".join(secret[i:i + 4] for i in range(0, len(secret), 4)), otpauth_uri=uri)


class CodeIn(BaseModel):
    code: str = Field(min_length=6, max_length=12)


@router.post("/2fa/enable")
async def two_factor_enable(body: CodeIn, user=Depends(get_current_user), c=Depends(get_container)):
    await c.cache.rate_limit(user.id, "2fa-enable", 10)
    row = await two_factor_row(c, user.id)
    if not row or not row.get("secret"):
        raise HTTPException(409, "Start the set-up first.")
    if row.get("enabled"):
        raise HTTPException(409, "Two-factor authentication is already on.")
    if not await check_code(c, user.id, body.code):
        raise HTTPException(422, "That code didn't match. Use the 6-digit code your app shows now.")
    codes = _backup_codes()
    row = await two_factor_row(c, user.id)
    await c.graph.store.put(row["id"], dict(row, enabled=True, backup_codes=[_hash_code(x) for x in codes],
                                            enabled_at=dt.datetime.now(dt.UTC).isoformat()))
    return dict(enabled=True, backup_codes=codes)


@router.post("/2fa/backup-codes")
async def two_factor_new_backup_codes(body: CodeIn, user=Depends(get_current_user), c=Depends(get_container)):
    await c.cache.rate_limit(user.id, "2fa-manage", 10)
    if not await two_factor_enabled(c, user.id):
        raise HTTPException(409, "Two-factor authentication is off.")
    if not await check_code(c, user.id, body.code):
        raise HTTPException(422, "That code didn't work.")
    codes = _backup_codes()
    row = await two_factor_row(c, user.id)
    await c.graph.store.put(row["id"], dict(row, backup_codes=[_hash_code(x) for x in codes]))
    return dict(backup_codes=codes)


@router.post("/2fa/disable")
async def two_factor_disable(body: CodeIn, user=Depends(get_current_user), c=Depends(get_container)):
    await c.cache.rate_limit(user.id, "2fa-manage", 10)
    if not await two_factor_enabled(c, user.id):
        return dict(enabled=False)
    if not await check_code(c, user.id, body.code):
        raise HTTPException(422, "That code didn't work.")
    await c.graph.store.delete(key("two_factor", user.id))
    return dict(enabled=False)


# -- Google / Apple -------------------------------------------------------------------------

_jwks: dict[str, pyjwt.PyJWKClient] = {}

PROVIDERS = {
    "google": dict(jwks="https://www.googleapis.com/oauth2/v3/certs",
                   issuers=("accounts.google.com", "https://accounts.google.com"),
                   setting="google_client_ids", name="Google"),
    "apple": dict(jwks="https://appleid.apple.com/auth/keys",
                  issuers=("https://appleid.apple.com",),
                  setting="apple_client_ids", name="Apple"),
}


def _client_ids(c, provider: str) -> list[str]:
    """GOOGLE_CLIENT_IDS / APPLE_CLIENT_IDS, plus the single-id names
    (GOOGLE_SERVER_CLIENT_ID, GOOGLE_IOS_CLIENT_ID, APPLE_IOS_BUNDLE_ID,
    APPLE_SERVICE_ID) if those are what's set."""
    s = c.settings
    raw = [getattr(s, PROVIDERS[provider]["setting"], "") or ""]
    if provider == "google":
        raw += [getattr(s, "google_server_client_id", ""), getattr(s, "google_ios_client_id", "")]
    else:
        raw += [getattr(s, "apple_ios_bundle_id", ""), getattr(s, "apple_service_id", "")]
    ids = [x.strip() for part in raw for x in (part or "").split(",") if x.strip()]
    return list(dict.fromkeys(ids))


def verify_id_token(provider: str, token: str, audiences: list[str]) -> dict:
    """Checks a Google / Apple ID token's signature, issuer, audience and
    expiry against the provider's published keys. Returns its claims."""
    info = PROVIDERS[provider]
    client = _jwks.setdefault(provider, pyjwt.PyJWKClient(info["jwks"], cache_keys=True, lifespan=3600))
    signing_key = client.get_signing_key_from_jwt(token)
    claims = pyjwt.decode(token, signing_key.key, algorithms=["RS256", "ES256"], audience=audiences,
                          options={"require": ["exp", "iat", "sub", "aud", "iss"]}, leeway=60)
    if claims.get("iss") not in info["issuers"]:
        raise pyjwt.InvalidIssuerError("Unexpected issuer")
    return claims


async def _unique_username(c, email: str | None, name: str | None) -> str:
    base = (email or "").split("@")[0] or (name or "phlio")
    base = re.sub(r"[^a-z0-9._]", "", base.lower())[:20].strip("._") or "phlio"
    if len(base) < 3:
        base = (base + "user")[:20]
    candidate = base
    for _ in range(20):
        if await c.identity_repository.get_by_username(candidate) is None:
            return candidate
        candidate = f"{base}{secrets.randbelow(9000) + 1000}"
    return f"phlio{secrets.token_hex(4)}"


async def sign_in_with(c, provider: str, claims: dict, full_name: str | None = None) -> dict:
    sub = str(claims["sub"])
    email = (claims.get("email") or "").strip().lower() or None
    verified = str(claims.get("email_verified", "false")).lower() == "true"
    link_id = key("oauth_identity", provider, sub)
    link = await c.graph.store.get(link_id)
    user = None
    is_new = False
    if link:
        user = await c.identity_repository.get_by_id(link["user_id"])
    if user is None and email and verified:
        user = await c.identity_repository.get_by_email(email)
    if user is None:
        if not email:
            raise HTTPException(422, f"{PROVIDERS[provider]['name']} didn't share an email address.")
        name = (full_name or claims.get("name") or email.split("@")[0]).strip()[:120] or "Phlio user"
        username = await _unique_username(c, email, name)
        # A random password nobody knows: the account signs in with the provider
        # (a password can be set later through "forgot password").
        user, _ = await c.identity_service.register(
            full_name=name, username=username, email=email,
            password=secrets.token_urlsafe(24))
        is_new = True
    await c.graph.store.put(link_id, dict(provider=provider, sub=sub, user_id=user.id, email=email,
                                          linked_at=(link or {}).get("linked_at")
                                          or dt.datetime.now(dt.UTC).isoformat()))
    return await session_or_challenge(c, user, is_new_user=is_new, provider=provider)


class GoogleIn(BaseModel):
    id_token: str = Field(min_length=20, max_length=8192)


class AppleIn(BaseModel):
    identity_token: str = Field(min_length=20, max_length=8192)
    full_name: str | None = Field(default=None, max_length=120)


async def _verified(c, provider: str, token: str) -> dict:
    audiences = _client_ids(c, provider)
    if not audiences:
        raise HTTPException(503, f"Sign in with {PROVIDERS[provider]['name']} isn't set up on this server yet.")
    try:
        return await run_in_threadpool(verify_id_token, provider, token, audiences)
    except (pyjwt.PyJWTError, pyjwt.PyJWKClientError) as exc:
        raise HTTPException(422, f"{PROVIDERS[provider]['name']} sign-in couldn't be verified. Try again.") from exc


@router.post("/oauth/google")
async def google_sign_in(body: GoogleIn, request: Request, c=Depends(get_container)):
    await c.cache.rate_limit(request.client.host if request.client else "anon", "oauth", 30)
    claims = await _verified(c, "google", body.id_token)
    return await sign_in_with(c, "google", claims)


@router.post("/oauth/apple")
async def apple_sign_in(body: AppleIn, request: Request, c=Depends(get_container)):
    await c.cache.rate_limit(request.client.host if request.client else "anon", "oauth", 30)
    claims = await _verified(c, "apple", body.identity_token)
    return await sign_in_with(c, "apple", claims, body.full_name)


@router.post("/oauth/apple/callback")
async def apple_android_callback(request: Request):
    """Android: Apple posts the sign-in result here (the web flow's redirect
    URI); send it back into the app (sign_in_with_apple's callback activity)."""
    form = await request.form()
    package = getattr(request.app.state.settings, "android_package_name", "") or "com.example.phlio"
    query = urlencode({k: str(v) for k, v in form.items()})
    return RedirectResponse(f"intent://callback?{query}#Intent;package={package};scheme=signinwithapple;end",
                            status_code=307)
