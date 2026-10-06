"""Slice the Foxy asset pack sheet (Foxy_asset_pack.png) into app assets.

v2 matte pipeline — the first cut keyed per-pixel color distance against the
background with tight thresholds, which turned cream fur translucent and left
tile-gradient halos. v2 instead:

  1. model the tile background as a bilinear gradient from its corner colors
  2. definite foreground = large color distance (saturated orange / dark navy)
  3. silhouette = close + fill-holes of that core (padded, so fur open at the
     crop border still closes) — keeps cream/white fur fully opaque
  4. alpha = 1.0 inside the silhouette, a smoothstep of color distance only in
     the outer 2px band (anti-aliased edge), 0 outside — no halos, no translucency
  5. 2x Lanczos upscale + unsharp (RGB only) so the ~100px sheet cells render
     crisp at sticker size

Sheet layout (1536x1024): cells sit on designed tiles —
  - Hero art (fox on rock, "Explore more.")            x   0..432, y   0..416
  - 21 expression emoji tiles, 7 cols x 3 rows         x 436..1100, y   8..416
  - 12 costume/theme tiles, 4 cols x 3 rows            x1108..1532, y   8..416
  - 15 text sticker tiles, 5 cols x 3 rows             x   8..668, y 420..780
  - 13 animation preview tiles (dark navy), 6 + 7      x 648..1520, y 478..780

Outputs (into frontend/ui/assets, filenames unchanged so the app code and
FoxyPack ids stay valid):
  emoji/emoji_foxy_<name>.png          21 expression emoji cutouts
  stickers/sticker_costume_<name>.png  12 costume cutouts
  stickers/sticker_text_<name>.png     15 hand-lettered cutouts
  animations/anim_<name>.gif           looping bob GIFs (transparent fox)
  images/foxy/foxy_explore_more.png    hero illustration (rounded scene)
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

SRC = "I:/Rohan/projects/phlio_blueprint/Foxy_asset_pack.png"
OUT = "I:/Rohan/projects/phlio/frontend/ui/assets"
QA = "I:/Rohan/projects/phlio/scripts/media/_qa_foxy_pack.png"
SCALE = 2  # sheet cells are ~100px; 2x gives stickers room at display size

sheet = Image.open(SRC).convert("RGB")
A = np.asarray(sheet).astype(np.int32)


# ---------------------------------------------------------------- detection

def ring_bg(crop, inset=2):
    a = np.asarray(crop.convert("RGB")).astype(np.int32)
    ring = np.concatenate([
        a[inset:inset + 3].reshape(-1, 3), a[-inset - 3:-inset].reshape(-1, 3),
        a[:, inset:inset + 3].reshape(-1, 3), a[:, -inset - 3:-inset].reshape(-1, 3),
    ])
    return np.median(ring, axis=0)


def color_tiles(crop, bg, thresh=30, area=(2500, 90000)):
    """Designed tiles on a light panel: components differing from panel bg."""
    a = np.asarray(crop.convert("RGB")).astype(np.int32)
    d = np.abs(a - bg).sum(axis=2)
    m = ndimage.binary_closing(d > thresh, np.ones((3, 3)))
    lbl, n = ndimage.label(m)
    out = []
    for i in range(1, n + 1):
        ys, xs = np.where(lbl == i)
        w, h = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
        if not (area[0] <= len(xs) <= area[1]):
            continue
        if max(w / h, h / w) > 2.2:  # section borders / header swipes
            continue
        out.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    out.sort(key=lambda b: (round(b[1] / 70.0), b[0]))  # reading order
    return out


def dark_tiles(x0, y0, x1, y1, area=(8000, 22000)):
    """Dark navy animation tiles: dark connected components inside a region."""
    dark = (A.sum(axis=2) < 320) & (A[:, :, 2] >= A[:, :, 0])
    dark[:y0, :] = dark[y1:, :] = False
    dark[:, :x0] = dark[:, x1:] = False
    lbl, n = ndimage.label(dark)
    masks, boxes = [], []
    for i in range(1, n + 1):
        ys, xs = np.where(lbl == i)
        if not (area[0] <= len(xs) <= area[1]):
            continue
        boxes.append((
            max(0, xs.min() - 1), max(0, ys.min() - 1),
            min(A.shape[1], xs.max() + 2), min(A.shape[0], ys.max() + 2),
        ))
        masks.append(lbl == i)
    order = sorted(range(len(boxes)), key=lambda k: (round(boxes[k][1] / 70.0), boxes[k][0]))
    return [boxes[k] for k in order], [masks[k] for k in order]


# ---------------------------------------------------------------- matte v2

def _smoothstep(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _bg_gradient(rgb):
    """Bilinear background model from the four corner patches (tiles carry a
    soft gradient; per-pixel distance from a flat color leaves halos)."""
    h, w = rgb.shape[:2]
    c00 = np.median(rgb[0:4, 0:4].reshape(-1, 3), axis=0)
    c10 = np.median(rgb[0:4, -4:].reshape(-1, 3), axis=0)
    c01 = np.median(rgb[-4:, 0:4].reshape(-1, 3), axis=0)
    c11 = np.median(rgb[-4:, -4:].reshape(-1, 3), axis=0)
    u = np.linspace(0, 1, w)[None, :, None]
    v = np.linspace(0, 1, h)[:, None, None]
    top = c00[None, None] + (c10 - c00)[None, None] * u
    bottom = c01[None, None] + (c11 - c01)[None, None] * u
    return (top + (bottom - top) * v).astype(np.float32)


def _keep_components(mask, min_area, min_h):
    """Keep the largest component plus any others big enough to be real art
    (letters, props, confetti) — drops neighbor bleed and noise."""
    lbl, n = ndimage.label(mask)
    if n <= 1:
        return mask
    keep = np.zeros(n + 1, bool)
    largest = 1 + int(np.argmax(ndimage.sum(mask, lbl, range(1, n + 1))))
    for i in range(1, n + 1):
        ys, xs = np.where(lbl == i)
        h = ys.max() - ys.min() + 1
        keep[i] = (i == largest) or (h >= min_h and len(xs) >= min_area)
    return keep[lbl]


def matte_cutout(cell, core_t=140.0, edge=(60.0, 120.0), min_area=150, min_h=10,
                 kill_pockets=False):
    """Cut the subject off the tile with a clean, fully-removed background.

    Returns an RGBA crop at SCALE x with: opaque silhouette interior (cream
    fur survives), a 2px distance-based soft edge (no halo), transparent
    elsewhere.

    How the light fur is kept: cream/white fur is warm while the badge
    backgrounds are cool, so warm near-bg pixels join the pre-fill mask
    directly (they leak to the tile edge on bust crops, where hole-filling
    alone can't reach them). Enclosed pockets of actual background — badge
    bg between head and ears, letter counters — are removed per component
    by mean distance + hue (cool, near-bg pockets die; warm fur pockets
    and dark-brown markings, which are real art, survive).
    """
    rgb = np.asarray(cell.convert("RGB")).astype(np.float32)
    bgm = _bg_gradient(rgb)
    d = np.abs(rgb - bgm).sum(axis=2)

    core = d > core_t
    # warm near-bg pixels = cream fur leaking to the tile edge on bust crops
    bg_is_cool = float((bgm[:, :, 2] - bgm[:, :, 0]).mean()) > 4.0
    light_warm = (d < 60) & (rgb[:, :, 0] > rgb[:, :, 2] + 4)
    pre = core | (light_warm & bg_is_cool)

    # pad before closing+filling so a silhouette that runs into the crop
    # border (fox feet at the tile edge) still closes into a solid region
    p = 6
    pre_p = np.pad(pre, p, mode="edge")
    pre_p = ndimage.binary_closing(pre_p, np.ones((3, 3)))
    pre_p = ndimage.binary_fill_holes(pre_p)
    region = _keep_components(pre_p[p:-p, p:-p], min_area, min_h)

    if kill_pockets:
        pockets = region & ~core
        lbl, n = ndimage.label(pockets)
        kill = np.zeros_like(region)
        for i in range(1, n + 1):
            m = lbl == i
            if m.sum() < 40:
                continue
            ys, xs = np.where(m)
            if ys.max() - ys.min() + 1 < 8:
                continue
            # cool + chromatically near the bg model = background showing
            # through, not fur (fur is warm; dark-brown markings are core)
            if d[m].mean() < 110 and rgb[..., 2][m].mean() >= rgb[..., 0][m].mean():
                kill |= m
        trimmed = region & ~kill
        # safety valve: never let pocket removal eat the subject
        if trimmed.sum() > 0.6 * region.sum():
            region = trimmed

    band = region & ~ndimage.binary_erosion(region, iterations=2)
    # floor the band so light-fur edges (low contrast vs the badge) stay
    # solid instead of fading out; true background sits below d=28
    band_alpha = np.maximum(_smoothstep(d, edge[0], edge[1]),
                            np.where(d > 28, 0.82, 0.0))
    alpha = np.where(band, band_alpha, region.astype(np.float32))
    alpha = ndimage.gaussian_filter(alpha, 0.6)
    alpha = np.clip(alpha, 0.0, 1.0)

    rgba = np.dstack([rgb, alpha * 255]).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    if SCALE != 1:
        img = img.resize((img.width * SCALE, img.height * SCALE), Image.LANCZOS)
        r, g, b, a = img.split()
        sharp = Image.merge("RGB", (r, g, b)).filter(
            ImageFilter.UnsharpMask(radius=2, percent=80, threshold=2))
        img = Image.merge("RGBA", (*sharp.split(), a))
    return trim(img)


def trim(img, pad=4, thresh=8):
    al = np.asarray(img.getchannel("A"))
    ys, xs = np.where(al > thresh)
    if len(xs) == 0:
        return img
    x0, x1 = max(0, xs.min() - pad), min(img.width, xs.max() + pad + 1)
    y0, y1 = max(0, ys.min() - pad), min(img.height, ys.max() + pad + 1)
    return img.crop((x0, y0, x1, y1))


def save(img, rel):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print(f"wrote {rel} {img.size}")
    return path


# ---------------------------------------------------------------- sections

SECTIONS = {
    "emoji": ((436, 8, 1100, 416), None, [
        "happy", "excited", "laughing", "winking", "love", "surprised", "curious",
        "thinking", "confused", "sad", "determined", "angry", "sleepy", "blushing",
        "thumbs_up", "hello", "good_job", "clap", "cheers", "sorry", "thanks",
    ]),
    "costume": ((1108, 8, 1532, 416), None, [
        "explorer", "hoodie", "space", "samurai",
        "wizard", "chef", "student", "business",
        "rainy", "winter", "sporty", "traveler",
    ]),
    # fixed bg: this panel's ring is polluted by the dark anim panel to its
    # right, so the median-ring estimate lands on the wrong color
    "text": ((8, 420, 668, 780), np.array([248, 248, 248]), [
        "hi", "good_morning", "good_night", "on_my_way", "lets_go",
        "nice", "awesome", "oops", "hmmm", "lol",
        "thank_you", "congrats", "stay_cozy", "take_a_break", "done",
    ]),
}

# per-section matte tuning: emoji/text get enclosed-bg-pocket removal;
# costumes must NOT — the space suit is cool-white, low-distance and
# outline-enclosed, i.e. indistinguishable from a background pocket by
# color alone (one thin sliver by the rainy umbrella is the lesser evil)
MATTE_TUNE = {
    "emoji": dict(min_area=150, min_h=10, kill_pockets=True),
    "costume": dict(min_area=700, min_h=12),
    "text": dict(min_area=200, min_h=10, kill_pockets=True),
}

saved = {}
for key, ((x0, y0, x1, y1), fixed_bg, names) in SECTIONS.items():
    crop = sheet.crop((x0, y0, x1, y1))
    bg = fixed_bg if fixed_bg is not None else ring_bg(crop)
    boxes = color_tiles(crop, bg)
    print(f"{key}: {len(boxes)} tiles, {len(names)} names")
    entries = []
    for i, (bx0, by0, bx1, by1) in enumerate(boxes):
        name = names[i] if i < len(names) else f"{key}_{i:02d}"
        cell = crop.crop((max(0, bx0 - 1), max(0, by0 - 1), bx1 + 1, by1 + 1))
        keyed = matte_cutout(cell, **MATTE_TUNE[key])
        rel = {
            "emoji": f"emoji/emoji_foxy_{name}.png",
            "costume": f"stickers/sticker_costume_{name}.png",
            "text": f"stickers/sticker_text_{name}.png",
        }[key]
        entries.append((name, save(keyed, rel)))
    saved[key] = entries

# animation tiles: keep the designed dark rounded card (it reads as a
# cutout on the app's dark surfaces). Alpha comes straight from the tile's
# own silhouette mask — the caption strip is painted out first. (A bg-model
# matte here squared the rounded corners and dragged panel pixels in as a
# white fringe along the bottom.)
ANIM_NAMES = [
    "idle_blink", "tail_wag", "happy_jump", "wave", "typing", "drink_coffee",
    "sleep", "thinking", "celebration", "loading", "heart", "reading", "fly",
]
boxes, masks = dark_tiles(640, 470, 1532, 786)
print(f"anim: {len(boxes)} tiles, {len(ANIM_NAMES)} names")
anim_entries = []
for i, ((bx0, by0, bx1, by1), m) in enumerate(zip(boxes, masks)):
    name = ANIM_NAMES[i] if i < len(ANIM_NAMES) else f"anim_{i:02d}"
    cell = np.asarray(sheet.crop((bx0, by0, bx1, by1))).astype(np.float32)
    # exact tile silhouette (dark mask, holes filled so the fox is inside)
    tile = ndimage.binary_fill_holes(ndimage.binary_closing(m, np.ones((3, 3))))
    tile = tile[by0:by1, bx0:bx1]
    # the caption ("Celebration", "Loading", …) is white text in the bottom
    # strip — paint it with the tile color, inside the tile only
    h = cell.shape[0]
    band_top = int(h * 0.80)
    strip = cell[band_top:]
    text_px = (strip.max(axis=2) > 120) & tile[band_top:]
    tile_color = np.median(cell[band_top - 8:band_top - 2][tile[band_top - 8:band_top - 2]]
                           .reshape(-1, 3), axis=0)
    strip[text_px] = tile_color
    cell[band_top:] = strip
    # alpha = tile silhouette, softly feathered; interior fully opaque
    alpha = ndimage.gaussian_filter(tile.astype(np.float32), 0.7)
    rgba = np.dstack([cell, np.clip(alpha, 0, 1) * 255]).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    img = img.resize((img.width * SCALE, img.height * SCALE), Image.LANCZOS)
    r, g, b, a = img.split()
    sharp = Image.merge("RGB", (r, g, b)).filter(
        ImageFilter.UnsharpMask(radius=2, percent=80, threshold=2))
    img = Image.merge("RGBA", (*sharp.split(), a))
    anim_entries.append((name, save(img, f"animations/_still_{name}.png")))
saved["anim"] = anim_entries

# hero: rounded-corner scene tile (art touches panel whites — keep as a
# rounded card, it is the "Explore more. Together." illustration)
hero = sheet.crop((12, 12, 424, 410)).convert("RGBA")
mask = Image.new("L", hero.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, hero.size[0] - 1, hero.size[1] - 1], 28, fill=255)
hero.putalpha(mask)
save(hero, "images/foxy/foxy_explore_more.png")

# ---------------------------------------------------------------- GIFs
# Looping bob + gentle scale pulse from the transparent stills; disposal=2
# keeps every frame's transparency independent.

def bob_gif(src_path, out_path, size=280, frames=16):
    im = Image.open(src_path).convert("RGBA")
    im.thumbnail((size - 24, size - 24), Image.LANCZOS)
    seq = []
    for f in range(frames):
        t = f / frames
        dy = -6 * np.sin(2 * np.pi * t)
        s = 1.0 + 0.02 * np.sin(2 * np.pi * t + np.pi / 2)
        w, h = int(im.width * s), int(im.height * s)
        frame = im.resize((w, h), Image.LANCZOS)
        canvas = Image.new("RGBA", (size, size + 16), (0, 0, 0, 0))
        canvas.alpha_composite(frame, ((size - w) // 2, (size + 16 - h) // 2 + int(dy)))
        seq.append(canvas)
    seq[0].save(out_path, save_all=True, append_images=seq[1:], loop=0,
                duration=70, optimize=True, disposal=2)
    print(f"wrote {os.path.relpath(out_path, OUT)} ({frames} frames)")

for name, _ in saved["anim"]:
    src = os.path.join(OUT, "animations", f"_still_{name}.png")
    bob_gif(src, os.path.join(OUT, "animations", f"anim_{name}.gif"))
    os.remove(src)

# ---------------------------------------------------------------- QA montage
# On the app's dark background: halos and leftover tile backgrounds show
# worst on dark — exactly where they would ship.

items = []
for key in ("emoji", "costume", "text", "anim"):
    for name, _ in saved[key]:
        ext = "gif" if key == "anim" else "png"
        folder = {"emoji": "emoji", "costume": "stickers", "text": "stickers", "anim": "animations"}[key]
        prefix = {"emoji": "emoji_foxy_", "costume": "sticker_costume_", "text": "sticker_text_", "anim": "anim_"}[key]
        items.append((f"{key}:{name}", os.path.join(OUT, folder, f"{prefix}{name}.{ext}")))
items.append(("hero:explore_more", os.path.join(OUT, "images/foxy/foxy_explore_more.png")))

cols, cell, pad = 6, 180, 14
rows = (len(items) + cols - 1) // cols
canvas = Image.new("RGB", (cols * (cell + pad) + pad, rows * (cell + 46) + pad), (10, 14, 20))
draw = ImageDraw.Draw(canvas)
for i, (label, path) in enumerate(items):
    r, c = divmod(i, cols)
    x = pad + c * (cell + pad)
    y = pad + r * (cell + 46)
    try:
        im = Image.open(path).convert("RGBA")
        im.thumbnail((cell, cell), Image.LANCZOS)
        canvas.paste(im, (x + (cell - im.width) // 2, y + (cell - im.height) // 2), im)
    except Exception as e:
        print("montage skip", label, e)
    draw.text((x + 4, y + cell + 6), f"{i:02d} {label}", fill=(240, 240, 240))
canvas.save(QA)
print("QA montage ->", QA)
