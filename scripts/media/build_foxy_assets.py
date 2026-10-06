"""Build the Foxy mascot asset pack for the Flutter app.

Sources (in I:/Rohan/projects/phlio_blueprint):
  foxy_poses.png  - 9 poses + 7 expression heads + hero art (dark navy bg)
  foxy.png        - explorer fox hero (goggles + scarf)
  phlio_logo.png  - logo lockup (P mark + wordmark + tagline on black)

Outputs (into frontend/ui/assets):
  images/foxy/foxy_<pose>.png   transparent pose art
  images/foxy/foxy_hero.png     explorer hero art
  images/logo/logo_mark.png     gradient P mark (luminance keyed)
  images/logo/logo_wordmark.png "Phlio" wordmark
  images/logo/logo_lockup.png   full lockup with tagline
  stickers/sticker_foxy_<name>.png  sticker pack (expressions + poses)
  animations/foxy_<anim>.gif    looping mascot GIFs
"""
from PIL import Image, ImageFilter, ImageDraw, ImageFont
import numpy as np
import os

SRC = "I:/Rohan/projects/phlio_blueprint"
OUT = "I:/Rohan/projects/phlio/frontend/ui/assets"

# ---------------------------------------------------------------- keying utils

def key_out_background(img, bg_rgb, strength=60.0, feather=1.5, erode=1):
    """Soft alpha matte: alpha from color distance to bg, feathered."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    dist = np.sqrt(((a - np.array(bg_rgb, dtype=np.float32)) ** 2).sum(axis=2))
    alpha = np.clip((dist - strength * 0.35) / (strength * 0.65), 0.0, 1.0)
    alpha = (alpha * 255).astype(np.uint8)
    am = Image.fromarray(alpha, "L")
    if erode:
        am = am.filter(ImageFilter.MinFilter(erode * 2 + 1))
    if feather:
        am = am.filter(ImageFilter.GaussianBlur(feather))
    out = img.convert("RGBA")
    out.putalpha(am)
    return out


def luminance_key(img, lo=18.0, hi=90.0, feather=1.2):
    """Alpha from brightness (for bright art on black bg, e.g. logo)."""
    g = np.asarray(img.convert("L")).astype(np.float32)
    alpha = np.clip((g - lo) / (hi - lo), 0.0, 1.0)
    alpha = (alpha * 255).astype(np.uint8)
    am = Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(feather))
    out = img.convert("RGBA")
    out.putalpha(am)
    return out


def trim(img, pad=8, thresh=8):
    """Trim transparent borders, keep `pad` px margin."""
    al = np.asarray(img.getchannel("A"))
    ys, xs = np.where(al > thresh)
    if len(xs) == 0:
        return img
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    x0 = max(0, x0 - pad); y0 = max(0, y0 - pad)
    x1 = min(img.width, x1 + pad + 1); y1 = min(img.height, y1 + pad + 1)
    return img.crop((x0, y0, x1, y1))


def save_png(img, rel):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print("wrote", rel, img.size)


# ---------------------------------------------------------------- crops

sheet = Image.open(f"{SRC}/foxy_poses.png").convert("RGB")
BG = (8.8, 16.2, 24.8)

POSES = {
    "happy":       (246, 74, 506, 350),
    "explorer":    (544, 70, 802, 346),
    "cozy":        (884, 62, 1166, 368),
    "adventurous": (1212, 96, 1534, 358),
    "sleepy":      (28, 468, 286, 638),
    "focused":     (350, 440, 630, 654),
    "coffee":      (696, 434, 866, 658),
    "curious":     (946, 448, 1170, 658),
    "hello":       (1228, 444, 1442, 658),
}
EXPRESSIONS = {
    "idle":        (60, 780, 122, 842),
    "listening":   (170, 778, 230, 842),
    "thinking":    (272, 782, 334, 842),
    "excited":     (374, 782, 436, 842),
    "surprised":   (478, 784, 540, 840),
    "sad":         (586, 782, 646, 842),
    "determined":  (692, 782, 754, 842),
}
HERO_SHEET_BOX = (1202, 738, 1534, 954)

poses = {}
for name, box in POSES.items():
    crop = sheet.crop(box)
    keyed = key_out_background(crop, BG, strength=70, feather=1.6, erode=1)
    keyed = trim(keyed)
    poses[name] = keyed
    save_png(keyed, f"images/foxy/foxy_{name}.png")

expressions = {}
for name, box in EXPRESSIONS.items():
    crop = sheet.crop(box)
    keyed = key_out_background(crop, BG, strength=70, feather=1.0, erode=1)
    keyed = trim(keyed)
    expressions[name] = keyed
    save_png(keyed, f"stickers/sticker_foxy_{name}.png")

# hero from sheet (fox with backpack viewing city) - keep some scene, soft round mask
hero_crop = sheet.crop(HERO_SHEET_BOX)
hero_keyed = key_out_background(hero_crop, BG, strength=70, feather=2.0, erode=1)
hero_keyed = trim(hero_keyed)
save_png(hero_keyed, "images/foxy/foxy_journey.png")

# explorer fox hero from foxy.png
foxy = Image.open(f"{SRC}/foxy.png").convert("RGB")
foxy_keyed = key_out_background(foxy, (10, 12, 22), strength=80, feather=2.0, erode=1)
foxy_keyed = trim(foxy_keyed)
save_png(foxy_keyed, "images/foxy/foxy_explorer.png")

# ---------------------------------------------------------------- logo

logo = Image.open(f"{SRC}/phlio_logo.png").convert("RGB")
lw, lh = logo.size
# P mark occupies roughly x 480..790, y 320..680 of the 1254px image
mark = logo.crop((int(lw*0.37), int(lh*0.24), int(lw*0.65), int(lh*0.55)))
mark_keyed = luminance_key(mark, lo=14, hi=80)
mark_keyed = trim(mark_keyed)
save_png(mark_keyed, "images/logo/logo_mark.png")

# wordmark "Phlio" ~ y 700..860
word = logo.crop((int(lw*0.30), int(lh*0.545), int(lw*0.70), int(lh*0.70)))
word_keyed = luminance_key(word, lo=30, hi=110)
word_keyed = trim(word_keyed)
save_png(word_keyed, "images/logo/logo_wordmark.png")

# tagline ~ y 880..950
tag = logo.crop((int(lw*0.20), int(lh*0.70), int(lw*0.80), int(lh*0.78)))
tag_keyed = luminance_key(tag, lo=30, hi=110)
tag_keyed = trim(tag_keyed)
save_png(tag_keyed, "images/logo/logo_tagline.png")

# full lockup (mark+word+tagline)
lock = logo.crop((int(lw*0.18), int(lh*0.22), int(lw*0.82), int(lh*0.80)))
lock_keyed = luminance_key(lock, lo=14, hi=80)
lock_keyed = trim(lock_keyed)
save_png(lock_keyed, "images/logo/logo_lockup.png")

# ---------------------------------------------------------------- stickers from poses
for name in ("hello", "happy", "sleepy", "coffee", "excited") :
    src_img = expressions.get(name) or poses.get(name)
for name, img in poses.items():
    if name in ("hello", "happy", "sleepy", "coffee"):
        save_png(img, f"stickers/sticker_foxy_{name}.png")
save_png(expressions["excited"], "stickers/sticker_foxy_wave.png")

# ---------------------------------------------------------------- GIFs

def make_gif(frames_imgs, path, size=320, hold_ms=650, blend_frames=4, blend_ms=90):
    """Cross-fade loop between pose frames."""
    canvas_frames = []
    for im in frames_imgs:
        im2 = im.copy()
        im2.thumbnail((size, size), Image.LANCZOS)
        canvas = Image.new("RGBA", (size, size), (10, 14, 20, 255))
        canvas.alpha_composite(im2, ((size - im2.width) // 2, (size - im2.height) // 2))
        canvas_frames.append(canvas.convert("RGB"))

    seq = []
    n = len(canvas_frames)
    for i in range(n):
        a = canvas_frames[i]
        seq.append(a)
        for k in range(1, blend_frames + 1):
            b = canvas_frames[(i + 1) % n]
            t = k / (blend_frames + 1)
            seq.append(Image.blend(a, b, t))
    # durations: hold on key frames, quick on blends
    dur = []
    for i in range(n):
        dur.append(hold_ms)
        dur.extend([blend_ms] * blend_frames)
    seq[0].save(path, save_all=True, append_images=seq[1:], loop=0,
                duration=dur, optimize=True)
    print("wrote", os.path.relpath(path, OUT), f"({len(seq)} frames)")


ANIM_DIR = os.path.join(OUT, "animations")
os.makedirs(ANIM_DIR, exist_ok=True)

make_gif([poses["hello"], poses["happy"]], f"{ANIM_DIR}/foxy_wave.gif")
make_gif([poses["curious"], poses["focused"]], f"{ANIM_DIR}/foxy_think.gif", hold_ms=800)
make_gif([poses["sleepy"], poses["cozy"]], f"{ANIM_DIR}/foxy_sleep.gif", hold_ms=1000, blend_frames=6)
make_gif([poses["happy"], poses["hello"], poses["coffee"]], f"{ANIM_DIR}/foxy_celebrate.gif", hold_ms=500)
make_gif([poses["explorer"], poses["adventurous"]], f"{ANIM_DIR}/foxy_explore.gif", hold_ms=900)
make_gif([expressions["idle"], expressions["thinking"], expressions["excited"]],
         f"{ANIM_DIR}/foxy_moods.gif", size=160, hold_ms=700)

print("DONE")
