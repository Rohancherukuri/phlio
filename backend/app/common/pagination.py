"""Small helpers for cursor-based pagination shared by every list endpoint.

The "cursor" is intentionally opaque to clients — internally it is just the
id of the last item seen, base64-free for readability in this v1. Domains
are free to encode richer cursors later (e.g. compound sort keys) without
breaking the public contract, since clients must treat the cursor as an
opaque token they pass back verbatim.
"""

from __future__ import annotations

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 100


def clamp_limit(limit: int | None) -> int:
    if limit is None:
        return DEFAULT_PAGE_SIZE
    return max(1, min(limit, MAX_PAGE_SIZE))
