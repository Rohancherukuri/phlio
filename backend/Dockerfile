# syntax=docker/dockerfile:1
#
# Multi-stage build:
#   1. Compile phlio_core: the `phlio_native` Python extension (in-process,
#      what the API actually calls) and the `phlio-core` CLI (fallback).
#   2. Install the Python backend with uv, copying both artefacts in.
#
# Build from the repository root so both `backend/` and `phlio_core/` are
# in the build context:
#   docker build -f backend/Dockerfile -t phlio-backend .

# ---- Stage 1: build the Rust core engine ---------------------------------
# 1.82+: Cargo.lock is lockfile v4 (cargo >= 1.78). python3 is only needed by
# PyO3's build script to read the interpreter config; the extension targets the
# stable ABI (abi3, CPython >= 3.9), so Debian's 3.11 building for the 3.12
# runtime below is fine.
FROM rust:1.82-slim-bookworm AS core-engine-builder
RUN apt-get update && apt-get install -y --no-install-recommends python3 && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY phlio_core/ ./phlio_core/
RUN cd phlio_core \
    && cargo test --locked --workspace --exclude phlio-native \
    && cargo build --locked --release --bin phlio-core \
    && cargo build --locked --profile release-native -p phlio-native --features extension-module \
    && mkdir -p /out/native \
    && cp target/release/phlio-core /out/phlio-core \
    && cp target/release-native/libphlio_native.so /out/native/phlio_native.abi3.so \
    && strip /out/phlio-core /out/native/phlio_native.abi3.so

# ---- Stage 2: Python backend ------------------------------------------------
FROM python:3.12-slim-bookworm AS backend

# uv is a single static binary — copying it from its official distroless
# image is the fastest, smallest way to install it (no pip bootstrap needed).
COPY --from=ghcr.io/astral-sh/uv:0.8.0 /uv /uvx /usr/local/bin/

# Exports trimmed, muted and rotated DM videos.
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN useradd --system --uid 10001 --no-create-home --home-dir /app phlio

# Install dependencies first (better Docker layer caching: this layer only
# invalidates when pyproject.toml/uv.lock change, not on every code edit).
# `--extra surreal` is included so the image supports DATABASE_BACKEND=surreal
# at runtime too, decided by an environment variable rather than a rebuild.
COPY backend/pyproject.toml backend/uv.lock backend/README.md ./
# Byte-compile dependencies at build time: imports at boot then skip parsing
# (cuts cold start on Render's small instances noticeably).
ENV UV_COMPILE_BYTECODE=1
RUN uv sync --frozen --no-install-project --no-dev --extra surreal

COPY backend/app ./app
COPY backend/migrations ./migrations
RUN python -m compileall -q -j 0 app
# Bundled libraries served under /media (Stream music, Studio sound effects,
# seeded Spaces audio). Runtime uploads are git-ignored, so a clean checkout
# (what Render builds from) only carries these.
COPY --chown=phlio:phlio backend/media ./media

# Bring in the compiled Rust binary from stage 1, at the path
# `app/config.py`'s default `core_engine_binary_path` resolves relative to
# (`../phlio_core/target/release/phlio-core` from `backend/`).
COPY --from=core-engine-builder /out/phlio-core /phlio_core/target/release/phlio-core
# The in-process extension: importable as `phlio_native` via PYTHONPATH.
COPY --from=core-engine-builder /out/native/ /opt/phlio_native/

ENV CORE_ENGINE_BINARY_PATH=/phlio_core/target/release/phlio-core
ENV PYTHONPATH=/opt/phlio_native
# Bytecode is precompiled above, so nothing needs writing at runtime; logs unbuffered.
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
ENV DATABASE_BACKEND=memory
ENV APP_ENV=production
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD python -c "import os, urllib.request; urllib.request.urlopen(f'http://localhost:{os.environ.get(\"PORT\", \"8000\")}/health')" || exit 1

# Run as an unprivileged user: a compromised process can't modify the app
# code, the Python environment or the system. It owns only /app itself (so it
# can create runtime folders such as data/) and the media library.
RUN mkdir -p /app/data && chown phlio:phlio /app /app/data
USER phlio

# Hosts like Render inject $PORT; locally it stays 8000.
# --no-server-header: don't advertise the server software and version.
# --timeout-keep-alive 30: reuse connections across a mobile session's requests.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*' --no-server-header --timeout-keep-alive 30"]
