"""Phlio Stickers — the shared Foxy sticker catalog.

A deliberately tiny "domain": stickers are platform primitives (blueprint
section 16), not user data. The catalog is the server-side source of truth
for which stickers exist and how they're labelled; the asset bytes ship
inside the Flutter app (`assets/stickers/`) so they render offline. Keep
this list in sync with `frontend/ui/lib/design_system/widgets/phlio_fox.dart`
(`PhlioStickers.catalog`).
"""

FOXY_STICKER_CATALOG: list[dict] = [
    {"id": "idle", "label": "Foxy", "pack": "foxy_classics"},
    {"id": "happy", "label": "Happy", "pack": "foxy_classics"},
    {"id": "hello", "label": "Hello!", "pack": "foxy_classics"},
    {"id": "wave", "label": "Wave", "pack": "foxy_classics"},
    {"id": "excited", "label": "Excited", "pack": "foxy_classics"},
    {"id": "thinking", "label": "Thinking", "pack": "foxy_classics"},
    {"id": "listening", "label": "Listening", "pack": "foxy_classics"},
    {"id": "surprised", "label": "Surprised", "pack": "foxy_classics"},
    {"id": "sad", "label": "Sad", "pack": "foxy_classics"},
    {"id": "determined", "label": "Determined", "pack": "foxy_classics"},
    {"id": "coffee", "label": "Coffee break", "pack": "foxy_classics"},
    {"id": "sleepy", "label": "Sleepy", "pack": "foxy_classics"},
]

STICKER_IDS: frozenset[str] = frozenset(s["id"] for s in FOXY_STICKER_CATALOG)
