# syntax=docker/dockerfile:1
#
# Multi-stage build:
#   1. Compile the phlio_core Rust CLI (release profile).
#   2. Install the Python backend with uv, copying the compiled binary in.
#
# Build from the repository root so both `backend/` and `phlio_core/` are
# in the build context:
#   docker build -f backend/Dockerfile -t phlio-backend .

# ---- Stage 1: build the Rust core engine ---------------------------------
FROM rust:1.75-slim-bookworm AS core-engine-builder
WORKDIR /build
COPY phlio_core/ ./phlio_core/
RUN cd phlio_core && cargo build --release --bin phlio-core

# ---- Stage 2: Python backend ------------------------------------------------
FROM python:3.12-slim-bookworm AS backend

# uv is a single static binary — copying it from its official distroless
# image is the fastest, smallest way to install it (no pip bootstrap needed).
COPY --from=ghcr.io/astral-sh/uv:0.5.11 /uv /uvx /usr/local/bin/

# Exports trimmed, muted and rotated DM videos.
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies first (better Docker layer caching: this layer only
# invalidates when pyproject.toml/uv.lock change, not on every code edit).
# `--extra surreal` is included so the image supports DATABASE_BACKEND=surreal
# at runtime too, decided by an environment variable rather than a rebuild.
COPY backend/pyproject.toml backend/uv.lock backend/README.md ./
RUN uv sync --frozen --no-install-project --no-dev --extra surreal

COPY backend/app ./app
COPY backend/migrations ./migrations

# Bring in the compiled Rust binary from stage 1, at the path
# `app/config.py`'s default `core_engine_binary_path` resolves relative to
# (`../phlio_core/target/release/phlio-core` from `backend/`).
COPY --from=core-engine-builder /build/phlio_core/target/release/phlio-core /phlio_core/target/release/phlio-core

ENV CORE_ENGINE_BINARY_PATH=/phlio_core/target/release/phlio-core
ENV DATABASE_BACKEND=memory
ENV APP_ENV=production
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
