"""
In-memory repository implementations.

These back `DATABASE_BACKEND=memory` (the default). Every implementation
here satisfies the exact same `Protocol` as its SurrealDB counterpart in
`../surreal/`, so switching backends is a one-line config change (see
`app/core/container.py`) and never touches domain or API code.

Concurrency: FastAPI's default dev server is single-process with an asyncio
event loop, so a plain `dict` behind an `asyncio.Lock` is sufficient here —
these are deliberately NOT meant to survive a restart or scale beyond one
process. That is exactly what `surreal/` is for.
"""
