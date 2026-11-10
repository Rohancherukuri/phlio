# Performance and security hardening (Nov 2026)

What was changed to make Phlio boot and load faster and to harden it, where
the code lives, and how to build, verify and tune it.

## 1. Rust core engine, in-process (`phlio_core/crates/native`)

**Before:** every call into Rust (`generate_id` for each post, comment,
message, room and sign-up; HMAC signing; risk scoring) spawned the
`phlio-core` CLI: fork + exec + JSON over pipes, about **1.5 ms per call**.

**Now:** the same crates are compiled into a Python extension module,
`phlio_native` (PyO3, stable ABI `abi3-py39`), and called directly:
about **0.5 µs per call**, roughly 3000x faster, with no process churn under
load.

| Crate | What it does |
|---|---|
| `crates/crypto` | IDs, HMAC-SHA256 sign/verify (constant-time), **TOTP (RFC 6238)**, `constant_time_eq`, `sha256_hex` |
| `crates/risk_features` | Rule-based risk scoring (unchanged) |
| `crates/guard` *(new)* | `Throttle`: brute-force lockouts, bounded memory, thread-safe |
| `crates/native` *(new)* | PyO3 bindings for all of the above |
| `cli` | The JSON CLI, kept as a fallback |

The backend picks the fastest engine it finds
(`backend/app/infrastructure/core_engine/native.py`, `client.py`):

1. `phlio_native` importable (Docker image), or built in `phlio_core/target/release-native/`.
2. The `phlio-core` CLI (now with a 5 s timeout so a wedged binary can't hang a request).
3. Pure-Python mirrors, which give the same results and are logged at startup.

`PHLIO_NATIVE=0` forces the fallback.
`tests/test_core_engine.py` checks that Rust and Python agree on:

- every risk-rule combination;
- the RFC 6238 TOTP vectors;
- throttle behaviour.

**Robustness choices:**

- No `unsafe` code.
- Errors raise `ValueError` instead of crashing.
- The extension is built with `panic = "unwind"` (profile `release-native`), so a panic becomes a Python exception rather than aborting the API.
- Hashing and signing release the GIL.

### Build

| Where | Command |
|---|---|
| Docker / Render | Automatic: `backend/Dockerfile` stage 1 runs the Rust tests, then builds the CLI and the extension. |
| macOS / Linux (in `phlio_core/`) | `PYO3_PYTHON=../backend/.venv/bin/python cargo build --profile release-native -p phlio-native --features extension-module` |
| Windows (PowerShell, in `phlio_core\`) | `$env:PYO3_PYTHON="..\backend\.venv\Scripts\python.exe"; cargo build --profile release-native -p phlio-native --features extension-module` |
| Wheel | `maturin build --release -m phlio_core/crates/native/Cargo.toml` |

Plain `cargo build` / `cargo test` skip the extension (`default-members`), so
they still work without Python.

When the backend starts with the extension, the log says
`phlio_native 0.1.0 loaded (in-process Rust core engine)`.

## 2. Backend speed

- **gzip** for responses of 1 KiB or more: JSON shrinks by 70–90 % (`/openapi.json`: 234 KB → 24 KB).
  - Compression level 5 keeps CPU low.
  - Already-compressed media types, `/media` and `Range` requests are excluded, so video seeking is unaffected.
- **Docker cold start:**
  - Dependencies and app code are byte-compiled at build time (`UV_COMPILE_BYTECODE=1` and `compileall`).
  - uvicorn uses keep-alive 30 s.
- **CORS preflight cache:** `max_age=600`, so browsers send one preflight per 10 minutes instead of one per request.

## 3. App speed (Flutter)

| Change | File | Effect |
|---|---|---|
| Session tokens cached in memory | `core/storage/token_storage.dart` | Secure storage used to be read on **every** API request (a Keystore round trip). It is now read once at boot; writes go through the cache. |
| Boot work runs in parallel, audio init capped at 1.5 s | `main.dart` | The first frame no longer waits on the media service and the token read one after the other. |
| Response cache | `core/network/response_cache.dart` | See below. |
| Connection reuse | `core/network/api_client.dart` | Keep-alive 25 s and 6 connections per host, so most requests skip the TLS handshake. |
| Image cache | `main.dart` | Increased to 200 MB, so scrolling back doesn't re-decode images. |

**The response cache** works in three ways:

- **Merges duplicate requests:** identical GETs in flight at the same time become one request.
- **Instant first paint:** on the first load of a feed or list in an app session, the copy from the last session is shown if the server hasn't answered within 1.5 s. A sleeping free-tier server then shows content instead of a spinner. The fresh result replaces the copy for next time. Later loads, including pull-to-refresh, always go to the network.
- **Offline fallback:** feeds and lists show the last copy (up to 3 days old) when the connection fails or the server returns 502/503/504.

**Cache safety:**

- What can be cached:
  - JSON GETs only.
  - Never `/pay/*` or `/auth/*`, and never anything the server marks `no-store`.
- Who can see it: the cache key includes a hash of the account token, and the whole cache is wiped on sign-out.
- After any POST/PUT/PATCH/DELETE, old copies are no longer shown in that session.
- Files live in the app's private cache directory and are bounded: 300 files, 1 MB each, 3 days.

## 4. Security hardening

| Area | What | Where |
|---|---|---|
| Brute force | Five wrong passwords lock that account for 1 min, doubling each time up to 1 h. Thirty failures from one IP lock that IP. The lock is checked **before** the password hash is computed, and returns `429` with `Retry-After`. A successful login clears the account's counter. The same limits apply to 2FA codes (5 per account, 20 per IP), on top of the existing 8/min rate limit. | `app/infrastructure/security/guard.py`, `phlio_core/crates/guard` |
| TOTP | Constant-time Rust implementation that always checks all three time windows, so timing doesn't reveal which one matched. | `crates/crypto` |
| Headers | `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `Permissions-Policy`, COOP, `CSP default-src 'none'` on API and media, HSTS in production, `Cache-Control: no-store` on `/auth/*`. | `app/middleware/security.py` |
| Body limits | JSON and form bodies over 4 MiB get `413`, checked from `Content-Length` and while streaming. Login fields are length-capped. Uploads are unaffected. | `app/middleware/security.py`, `auth.py` |
| Config | Production refuses to start with the default or a short `JWT_SECRET` (Render generates one). `DEBUG` is forced off in production. | `app/config.py` |
| API docs | `/docs`, `/redoc` and `/openapi.json` are off in production. Set `API_DOCS_ENABLED=true` to expose them. | `app/main.py` |
| CORS | With `CORS_ALLOW_ORIGINS=*`, credentialed CORS is switched off: the app uses bearer tokens, never cookies. | `app/main.py` |
| Container | Runs as an unprivileged user (uid 10001). The server header is hidden (`--no-server-header`). | `backend/Dockerfile` |

**Known limits:**

- Lockout counters are per process. Several instances each allow their own quota; a Redis-backed guard can replace them behind the same interface.
- Uploads keep their own per-endpoint caps.

### Tuning

- **Lockout limits:** `login_guard` and `two_factor_guard` at the bottom of `guard.py`.
- **JSON size limit:** `MAX_JSON_BODY_BYTES`.
- **What paints instantly:** `_instantPaths` in `response_cache.dart`.
