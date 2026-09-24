# Phlio Backend

FastAPI service implementing the Phlio backend as a **domain-oriented modular
monolith** (see `docs/architecture/phlio_architecture.md`, section 9-10).

Implemented in this pass: `identity` (auth), `social`, `rooms`, `art`, and
`agent`, plus a `home` aggregation layer. Payments, booking, shop, deliver
and meet are intentionally deferred — see the root `README.md` for the
staged build plan.

## Quick start

```bash
cd backend
uv sync                 # installs dependencies into .venv using uv
uv run uvicorn app.main:app --reload --port 8000
```

Open http://localhost:8000/docs for the interactive API docs.

## Configuration

Copy `.env.example` to `.env` and adjust as needed. By default the service
runs with `DATABASE_BACKEND=memory`, which uses seeded in-process
repositories — no external database required to explore the API.

## Tests

```bash
uv run pytest
```
