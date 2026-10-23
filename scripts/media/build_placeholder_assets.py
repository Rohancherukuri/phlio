"""Build the Phlio placeholder asset pack.

Branded, generated placeholders for platform content that has no real
imagery yet (video thumbnails, creator avatars, shop products, book
listings). Each placeholder is a dusk-gradient composition in the brand
palette with a category glyph, so the app looks designed rather than
grey-boxed while real content is pending.

Outputs (into frontend/ui/assets):
  images/placeholders/social/thumb_<name>.png   960x540 video thumbnails
  images/placeholders/social/avatar_<name>.png  240x240 square avatars
  images/placeholders/shop/product_<name>.png   800x800 product shots
  images/placeholders/book/listing_<name>.png   960x540 listing images

Run: python scripts/media/build_placeholder_assets.py
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

ROOT = "I:/Rohan/projects/phlio"
ASSETS = f"{ROOT}/frontend/ui/assets"
FONT_PATH = f"{ASSETS}/fonts/quicksand-v37-latin-700.ttf"
FONT_PATH_MEDIUM = f"{ASSETS}/fonts/quicksand-v37-latin-500.ttf"

# Dusk gradient pairs (top, bottom) per content category — all sit inside
# the brand's navy/orange/violet world.
PALETTES = {
    "gaming":   ((59, 42, 90), (108, 74, 182)),
    "music":    ((90, 42, 72), (181, 72, 125)),
    "art":      ((90, 58, 30), (199, 123, 63)),
    "tech":     ((30, 58, 90), (63, 124, 182)),
    "chat":     ((30, 74, 68), (63, 167, 152)),
    "travel":   ((34, 48, 74), (90, 123, 176)),
    "fitness":  ((74, 36, 24), (176, 90, 42)),
    "food":     ((74, 58, 20), (176, 143, 46)),
    "movie":    ((44, 32, 84), (120, 82, 190)),
    "dinner":   ((84, 44, 36), (196, 108, 84)),
    "cafe":     ((64, 48, 30), (168, 126, 78)),
    "badminton":((26, 66, 60), (58, 160, 140)),
    "walk":     ((40, 60, 46), (110, 150, 108)),
    "lamp":     ((70, 50, 24), (190, 140, 66)),
    "painting": ((60, 40, 70), (150, 100, 170)),
    "lantern":  ((64, 46, 20), (180, 130, 60)),
    "ceramics": ((54, 62, 66), (120, 140, 146)),
    "jewelry":  ((66, 36, 50), (170, 90, 120)),
    "print":    ((36, 52, 78), (96, 132, 176)),
}

GLYPHS = {
    "gaming": "PLAY", "music": "AUDIO", "art": "ART", "tech": "CODE",
    "chat": "CHAT", "travel": "GO", "fitness": "MOVE", "food": "TASTE",
    "movie": "CINEMA", "dinner": "TABLE", "cafe": "BREW",
    "badminton": "COURT", "walk": "TRAIL", "lamp": "GLOW",
    "painting": "CANVAS", "lantern": "LIGHT", "ceramics": "CLAY",
    "jewelry": "GEM", "print": "PRINT",
}


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def gradient(size, top, bottom):
    w, h = size
    im = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        im.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return im.resize((w, h))


def bokeh(im, seed, count=7):
    """Soft translucent circles — the 'dusk city lights' brand texture."""
    import random
    rng = random.Random(seed)
    w, h = im.size
    overlay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for _ in range(count):
        r = rng.randint(min(w, h) // 8, min(w, h) // 3)
        x = rng.randint(-r // 2, w - r // 2)
        y = rng.randint(-r // 2, h - r // 2)
        alpha = rng.randint(14, 34)
        d.ellipse((x, y, x + r, y + r), fill=(255, 255, 255, alpha))
    overlay = overlay.filter(ImageFilter.GaussianBlur(min(w, h) // 24))
    im.paste(Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB"), (0, 0))
    return im


def glow(im, center_rel=(0.72, 0.22), radius_rel=0.5, strength=70):
    w, h = im.size
    overlay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    r = int(min(w, h) * radius_rel)
    cx, cy = int(w * center_rel[0]), int(h * center_rel[1])
    for i in range(strength):
        a = int(2 * (1 - i / strength))
        d.ellipse((cx - r + i * 2, cy - r + i * 2, cx + r - i * 2, cy + r - i * 2),
                  fill=(255, 190, 130, a))
    im.paste(Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB"), (0, 0))
    return im


def label_block(im, glyph, caption=None):
    w, h = im.size
    d = ImageDraw.Draw(im, "RGBA")
    # Large translucent glyph word, centered.
    font = ImageFont.truetype(FONT_PATH, int(h * 0.22))
    bbox = d.textbbox((0, 0), glyph, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((w - tw) / 2 - bbox[0], (h - th) / 2 - bbox[1] - h * 0.03), glyph,
           font=font, fill=(255, 255, 255, 60))
    # Caption bottom-left.
    if caption:
        cfont = ImageFont.truetype(FONT_PATH_MEDIUM, int(h * 0.055))
        d.text((int(w * 0.05), int(h * 0.86)), caption, font=cfont, fill=(255, 255, 255, 210))
    # Watermark bottom-right.
    wfont = ImageFont.truetype(FONT_PATH_MEDIUM, int(h * 0.04))
    wm = "PHLIO"
    wbbox = d.textbbox((0, 0), wm, font=wfont)
    d.text((w - (wbbox[2] - wbbox[0]) - int(w * 0.05), int(h * 0.9)), wm,
           font=wfont, fill=(255, 255, 255, 110))
    return im


def make_thumb(path, category, caption, size=(960, 540)):
    top, bottom = PALETTES[category]
    im = gradient(size, top, bottom)
    im = glow(im)
    im = bokeh(im, caption)
    im = label_block(im, GLYPHS[category], caption)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "PNG")
    print("wrote", os.path.relpath(path, ROOT))


def make_avatar(path, initial, category, size=(240, 240)):
    top, bottom = PALETTES[category]
    im = gradient(size, bottom, top)
    d = ImageDraw.Draw(im, "RGBA")
    font = ImageFont.truetype(FONT_PATH, int(size[1] * 0.42))
    bbox = d.textbbox((0, 0), initial, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((size[0] - tw) / 2 - bbox[0], (size[1] - th) / 2 - bbox[1]), initial,
           font=font, fill=(255, 255, 255, 230))
    # Inner ring for a designed feel.
    d.ellipse((6, 6, size[0] - 6, size[1] - 6), outline=(255, 255, 255, 70), width=3)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "PNG")
    print("wrote", os.path.relpath(path, ROOT))


def make_product(path, category, caption, size=(800, 800)):
    top, bottom = PALETTES[category]
    im = gradient(size, top, bottom)
    im = glow(im, center_rel=(0.5, 0.3), radius_rel=0.55, strength=80)
    im = bokeh(im, caption, count=5)
    d = ImageDraw.Draw(im, "RGBA")
    # A simple "pedestal" arc so products read as object shots.
    d.ellipse((size[0]*0.15, size[1]*0.72, size[0]*0.85, size[1]*1.05),
              fill=(0, 0, 0, 46))
    font = ImageFont.truetype(FONT_PATH, int(size[1] * 0.16))
    glyph = GLYPHS[category]
    bbox = d.textbbox((0, 0), glyph, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((size[0] - tw) / 2 - bbox[0], size[1] * 0.38 - th / 2 - bbox[1]), glyph,
           font=font, fill=(255, 255, 255, 66))
    cfont = ImageFont.truetype(FONT_PATH_MEDIUM, int(size[1] * 0.045))
    d.text((int(size[0] * 0.06), int(size[1] * 0.88)), caption, font=cfont,
           fill=(255, 255, 255, 200))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "PNG")
    print("wrote", os.path.relpath(path, ROOT))


SOCIAL = "images/placeholders/social"
SHOP = "images/placeholders/shop"
BOOK = "images/placeholders/book"

# -- Social clips: portrait 9:16 art for the Reels/Shorts-style tab ----------
for name, cat, caption in [
    ("clip_gaming", "gaming", "1v4 clutch · retroray"),
    ("clip_art", "art", "30s sketch challenge"),
    ("clip_music", "music", "beat switch moment"),
    ("clip_tech", "tech", "hot reload in action"),
    ("clip_fitness", "fitness", "form check"),
]:
    make_thumb(f"{ASSETS}/{SOCIAL}/{name}.png", cat, caption, size=(720, 1280))

# -- Social video thumbnails (creators x categories) --------------------------
make_thumb(f"{ASSETS}/{SOCIAL}/thumb_gaming_1.png", "gaming", "Ranked grind till dawn")
make_thumb(f"{ASSETS}/{SOCIAL}/thumb_art_1.png", "art", "Dusk skyline in acrylics")
make_thumb(f"{ASSETS}/{SOCIAL}/thumb_music_1.png", "music", "Late night lofi + chat")
make_thumb(f"{ASSETS}/{SOCIAL}/thumb_tech_1.png", "tech", "Building Phlio - day 12")
make_thumb(f"{ASSETS}/{SOCIAL}/thumb_tech_2.png", "tech", "Design systems from scratch")
make_thumb(f"{ASSETS}/{SOCIAL}/thumb_gaming_2.png", "gaming", "1v4 in the final circle")
make_thumb(f"{ASSETS}/{SOCIAL}/thumb_travel_1.png", "travel", "48 hours in Hyderabad")
make_thumb(f"{ASSETS}/{SOCIAL}/thumb_fitness_1.png", "fitness", "Squat form in 60 seconds")

# -- Social creator avatars ----------------------------------------------------
for name, initial, cat in [
    ("pixelpanda", "P", "gaming"), ("artbykiara", "K", "art"),
    ("lofinight", "L", "music"), ("devdiaries", "D", "tech"),
    ("wanderfox", "W", "travel"), ("ironarena", "I", "fitness"),
    ("retroray", "R", "gaming"), ("chefatlas", "C", "food"),
]:
    make_avatar(f"{ASSETS}/{SOCIAL}/avatar_{name}.png", initial, cat)

# -- Shop product shots ----------------------------------------------------------
make_product(f"{ASSETS}/{SHOP}/product_lamp.png", "lamp", "Handcrafted Wooden Lamp")
make_product(f"{ASSETS}/{SHOP}/product_painting.png", "painting", "Sunset Horizons")
make_product(f"{ASSETS}/{SHOP}/product_lantern.png", "lantern", "Folded Leaf Lantern")
make_product(f"{ASSETS}/{SHOP}/product_ceramics.png", "ceramics", "Studio Ceramics")
make_product(f"{ASSETS}/{SHOP}/product_jewelry.png", "jewelry", "Handmade Jewelry")
make_product(f"{ASSETS}/{SHOP}/product_print.png", "print", "Art Prints")

# -- Book listing images ---------------------------------------------------------
make_thumb(f"{ASSETS}/{BOOK}/listing_movie.png", "movie", "Movie: Kingdom · PVR Nexus")
make_thumb(f"{ASSETS}/{BOOK}/listing_dinner.png", "dinner", "Dinner: The Courtyard")
make_thumb(f"{ASSETS}/{BOOK}/listing_cafe.png", "cafe", "Brew & Board")
make_thumb(f"{ASSETS}/{BOOK}/listing_badminton.png", "badminton", "Smash Arena")
make_thumb(f"{ASSETS}/{BOOK}/listing_walk.png", "walk", "Sunrise Walk · KBR Park")
make_thumb(f"{ASSETS}/{BOOK}/listing_travel.png", "travel", "Weekend Getaway")

print("DONE")
