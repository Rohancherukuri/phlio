"""Maintenance and seed scripts (`uv run python -m scripts.<name>`).

When a script can't reach SurrealDB, print what to do instead of a long
traceback.
"""

import sys

_hook = sys.excepthook


def _friendly(exc_type, exc, tb):
    try:
        from app.infrastructure.database.surreal.client import SurrealUnavailable
    except Exception:  # noqa: BLE001
        SurrealUnavailable = ()  # type: ignore[assignment]
    if SurrealUnavailable and issubclass(exc_type, SurrealUnavailable):
        print(f"\n{exc}\n", file=sys.stderr)
        return
    _hook(exc_type, exc, tb)


sys.excepthook = _friendly
