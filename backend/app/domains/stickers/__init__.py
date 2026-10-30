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

import json
import re
from pathlib import Path

# Animated Foxy stickers are `foxy:<outfit>:<mood>` and play from the app's
# bundled Rive file (frontend/ui/assets/rive/foxy.riv). Keep these lists in
# sync with `FoxyOutfit` / `FoxyMood` in
# frontend/ui/lib/design_system/widgets/foxy_rive.dart.
FOXY_OUTFITS = ("classic", "explorer", "hoodie", "space", "samurai", "wizard", "chef",
                "student", "business", "rainy", "winter", "traveler")
FOXY_MOODS = ("wave", "think", "celebrate", "explore", "sleep", "hello", "curious",
              "noPeeking", "focused", "cozy", "love")
ANIMATED_STICKER = re.compile(r"foxy:(%s):(%s)" % ("|".join(FOXY_OUTFITS), "|".join(FOXY_MOODS)))
GIPHY_REFERENCE = re.compile(r"giphy:(gif|sticker):[A-Za-z0-9]{1,80}")

# The curated animated set shown first in the app's sticker sheet.
FOXY_ANIMATED_CATALOG: list[dict] = [
    {"id": f"foxy:{outfit}:{mood}", "label": label, "pack": "foxy_animated"}
    for outfit, mood, label in [
        ("classic", "wave", "Hi!"), ("classic", "celebrate", "Yay"), ("classic", "love", "Love it"),
        ("classic", "think", "Hmm"), ("classic", "sleep", "Night night"),
        ("classic", "noPeeking", "Not looking"), ("classic", "curious", "Oh?"), ("classic", "cozy", "Cozy"),
        ("wizard", "think", "Magic"), ("wizard", "celebrate", "Ta-da"), ("chef", "hello", "Dinner?"),
        ("chef", "love", "Chef's kiss"), ("traveler", "explore", "Trip time"),
        ("explorer", "wave", "Adventure"), ("space", "curious", "Out of this world"),
        ("samurai", "focused", "On guard"), ("samurai", "celebrate", "Victory"),
        ("business", "focused", "In a meeting"), ("business", "celebrate", "Deal!"),
        ("student", "think", "Studying"), ("hoodie", "cozy", "Chill"),
        ("hoodie", "sleep", "Five more minutes"), ("rainy", "hello", "Rainy day"),
        ("winter", "cozy", "Brr"), ("winter", "love", "Warm hugs"),
    ]
]

# Foxy Moves: the rigged animated sticker pack (animated WebP in the app,
# APNG for Discord — see brand/foxy-moves/).
FOXY_MOVES_CATALOG: list[dict] = [
    {"id": f"move_{key}", "label": label, "pack": "foxy_moves"}
    for key, label in [
        ("hi", "Hi!"), ("thumbs_up", "Thumbs up"), ("clap", "Clap"), ("giggle", "Giggle"), ("love", "Love"),
        ("sad", "Sad"), ("angry", "Grr"), ("confused", "Huh?"), ("sorry", "Sorry"), ("good_job", "Good job"),
        ("cheers", "Cheers"), ("wink", "Wink"), ("yay", "Yay!"), ("wag", "Tail wag"), ("coffee", "Coffee"),
        ("sleep", "Sleepy"), ("wizard", "Magic"), ("chef", "Pancakes"), ("samurai", "Slash"),
        ("space", "Floating"), ("rainy", "Rainy day"), ("winter", "Brr"), ("hoodie", "Vibing"),
        ("student", "Studying"),
    ]
]

# The Foxy chat pack (emoji badges, costume/text stickers, GIF loops):
# value id -> "emoji" | "sticker" | "gif".
CHAT_PACK: dict[str, str] = json.loads((Path(__file__).parent / "chat_pack.json").read_text())

STICKER_IDS: frozenset[str] = frozenset(s["id"] for s in FOXY_STICKER_CATALOG)


def is_known_sticker(value: str | None) -> bool:
    """Any sticker id a comment, post or moment may carry."""
    if not value:
        return False
    return (
        value in STICKER_IDS
        or CHAT_PACK.get(value) in ("emoji", "sticker", "gif")
        or ANIMATED_STICKER.fullmatch(value) is not None
        or GIPHY_REFERENCE.fullmatch(value) is not None
    )
