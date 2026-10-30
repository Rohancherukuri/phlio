"""Small hand-drawn props for the Foxy Moves pack, in the brand palette.
Drawn 4× supersampled; each returns an RGBA PIL image at its natural size
(sticker pixels)."""

import math
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = Path(__file__).resolve().parents[3] / 'frontend/ui/assets/fonts/quicksand-v37-latin-700.ttf'
PEACH, VIOLET, PINK, TEAL, BLUE = (255, 181, 143), (141, 120, 255), (231, 149, 215), (104, 215, 205), (114, 167, 255)
YELLOW, RED, WHITE, INK = (255, 206, 84), (238, 84, 92), (255, 255, 255), (56, 40, 44)
S = 4


def _canvas(w, h):
    return Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))


def _done(im, blur=0.0):
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur * S))
    return im.resize((im.width // S, im.height // S), Image.LANCZOS)


def _outline(im, width=2.0, colour=WHITE):
    """Sticker-style white keyline around a sprite (matches the pack art)."""
    a = im.split()[3]
    grown = a.filter(ImageFilter.MaxFilter(int(width * S) * 2 + 1))
    base = Image.new('RGBA', im.size, colour + (0,))
    base.putalpha(grown)
    base.alpha_composite(im)
    return base


@lru_cache(None)
def sparkle(colour=PEACH, size=40):
    im = _canvas(size, size)
    c, r = size * S / 2, size * S * 0.47
    pts = []
    for i in range(96):
        a = i / 96 * 2 * math.pi
        k = abs(math.cos(2 * a)) ** 2.2
        rr = r * (0.3 + 0.7 * k)
        pts.append((c + rr * math.cos(a), c + rr * math.sin(a)))
    glow = _canvas(size, size)
    ImageDraw.Draw(glow).ellipse([c - r * 0.45, c - r * 0.45, c + r * 0.45, c + r * 0.45], fill=colour + (120,))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(size * S * 0.12)))
    d = ImageDraw.Draw(im)
    d.polygon(pts, fill=colour + (255,))
    d.ellipse([c - r * 0.14, c - r * 0.14, c + r * 0.14, c + r * 0.14], fill=WHITE + (255,))
    return _done(_outline(im, 1.2))


@lru_cache(None)
def heart(size=34, colour=PINK):
    w, h = size, int(size * 0.92)
    im = _canvas(w, h)
    m = Image.new('L', im.size, 0)
    d = ImageDraw.Draw(m)
    W, H = w * S, h * S
    r = W * 0.26
    d.ellipse([W * 0.04, H * 0.06, W * 0.04 + 2 * r, H * 0.06 + 2 * r], fill=255)
    d.ellipse([W * 0.96 - 2 * r, H * 0.06, W * 0.96, H * 0.06 + 2 * r], fill=255)
    d.polygon([(W * 0.06, H * 0.42), (W * 0.94, H * 0.42), (W * 0.5, H * 0.97)], fill=255)
    grad = Image.new('RGBA', im.size)
    gd = ImageDraw.Draw(grad)
    for y in range(H):
        t = y / H
        gd.line([(0, y), (W, y)], fill=tuple(int(colour[i] * (1 - t) + RED[i] * t * 0.6 + PEACH[i] * t * 0.4) for i in range(3)) + (255,))
    im.paste(grad, (0, 0), m)
    ImageDraw.Draw(im).ellipse([W * 0.2, H * 0.2, W * 0.36, H * 0.34], fill=(255, 255, 255, 170))
    return _done(_outline(im, 1.6))


def _glyph(text, size, colour, stroke=WHITE):
    font = ImageFont.truetype(str(FONT), int(size * S))
    w, h = int(size * 1.0), int(size * 1.2)
    im = _canvas(w, h)
    ImageDraw.Draw(im).text((w * S / 2, h * S / 2), text, font=font, anchor='mm', fill=colour + (255,),
                            stroke_width=int(size * S * 0.09), stroke_fill=stroke + (255,))
    return _done(im)


@lru_cache(None)
def zed(size=30):
    return _glyph('z', size, (150, 132, 255))


@lru_cache(None)
def question(size=46):
    return _glyph('?', size, VIOLET)


@lru_cache(None)
def exclaim(size=46):
    return _glyph('!', size, RED)


@lru_cache(None)
def dot(size=18):
    im = _canvas(size, size)
    ImageDraw.Draw(im).ellipse([S, S, (size - 1) * S, (size - 1) * S], fill=(246, 244, 255, 245))
    return _done(_outline(im, 1.0, (200, 196, 230)))


def _drop(w, h, colour, alpha=235):
    im = _canvas(w, h)
    d = ImageDraw.Draw(im)
    W, H = w * S, h * S
    r = W * 0.42
    d.ellipse([W / 2 - r, H - 2 * r - S, W / 2 + r, H - S], fill=colour + (alpha,))
    d.polygon([(W / 2, S), (W / 2 - r * 0.92, H - r * 1.3), (W / 2 + r * 0.92, H - r * 1.3)], fill=colour + (alpha,))
    d.ellipse([W / 2 - r * 0.45, H - r * 1.5, W / 2 - r * 0.05, H - r * 1.0], fill=(255, 255, 255, 190))
    return im


@lru_cache(None)
def tear(size=16):
    return _done(_drop(size, int(size * 1.4), (130, 196, 255)))


@lru_cache(None)
def sweat(size=20):
    return _done(_outline(_drop(size, int(size * 1.45), (150, 210, 255)), 1.2))


@lru_cache(None)
def raindrop():
    im = _canvas(6, 20)
    ImageDraw.Draw(im).rounded_rectangle([S, S, 5 * S, 19 * S], radius=2 * S, fill=BLUE + (200,))
    return _done(im)


@lru_cache(None)
def flake(size=12):
    im = _canvas(size, size)
    ImageDraw.Draw(im).ellipse([2 * S, 2 * S, (size - 2) * S, (size - 2) * S], fill=(255, 255, 255, 240))
    return _done(im, 0.4)


@lru_cache(None)
def anger(size=40):
    """The manga anger vein: four curved ticks, red with a white keyline."""
    im = _canvas(size, size)
    d = ImageDraw.Draw(im)
    W = size * S
    c = W / 2
    lw = int(W * 0.11)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        x, y = c + math.cos(a) * W * 0.2, c + math.sin(a) * W * 0.2
        box = [x - W * 0.2, y - W * 0.2, x + W * 0.2, y + W * 0.2]
        start = math.degrees(a) + 90 + 35
        d.arc(box, start, start + 110, fill=RED + (255,), width=lw)
    return _done(_outline(im, 1.6))


@lru_cache(None)
def puff(size=40, colour=(244, 242, 255)):
    lobes = [(0.3, 0.6, 0.2), (0.5, 0.46, 0.26), (0.72, 0.58, 0.2), (0.5, 0.66, 0.22)]
    im = _canvas(size, size)
    d = ImageDraw.Draw(im)
    W = size * S
    for cx, cy, r in lobes:
        d.ellipse([(cx - r) * W, (cy - r) * W, (cx + r) * W, (cy + r) * W], fill=colour + (235,))
    return _done(im, 0.5)


@lru_cache(None)
def note(size=30, colour=VIOLET, double=False):
    im = _canvas(size, size)
    d = ImageDraw.Draw(im)
    W = size * S
    lw = int(W * 0.09)
    if double:
        heads = [(0.28, 0.78), (0.72, 0.68)]
        for hx, hy in heads:
            d.ellipse([(hx - 0.16) * W, (hy - 0.11) * W, (hx + 0.12) * W, (hy + 0.11) * W], fill=colour + (255,))
            d.line([((hx + 0.1) * W, hy * W), ((hx + 0.1) * W, (hy - 0.55) * W)], fill=colour + (255,), width=lw)
        d.polygon([(0.38 * W, 0.12 * W), (0.82 * W, 0.02 * W), (0.82 * W, 0.16 * W), (0.38 * W, 0.26 * W)], fill=colour + (255,))
    else:
        d.ellipse([0.18 * W, 0.62 * W, 0.52 * W, 0.88 * W], fill=colour + (255,))
        d.line([(0.49 * W, 0.75 * W), (0.49 * W, 0.12 * W)], fill=colour + (255,), width=lw)
        d.line([(0.49 * W, 0.14 * W), (0.78 * W, 0.34 * W)], fill=colour + (255,), width=lw)
    return _done(_outline(im, 1.4))


@lru_cache(None)
def confetti(colour, w=8, h=14):
    im = _canvas(w, h)
    ImageDraw.Draw(im).rounded_rectangle([S, S, (w - 1) * S, (h - 1) * S], radius=2 * S, fill=colour + (255,))
    return _done(im)


@lru_cache(None)
def pancake(size=34):
    im = _canvas(size, size // 2)
    d = ImageDraw.Draw(im)
    W, H = size * S, size // 2 * S
    d.ellipse([S, H * 0.2, W - S, H - S], fill=(214, 150, 78, 255))
    d.ellipse([W * 0.12, H * 0.14, W * 0.88, H * 0.72], fill=(240, 196, 120, 255))
    d.rounded_rectangle([W * 0.38, H * 0.18, W * 0.58, H * 0.36], radius=S * 2, fill=(255, 236, 160, 255))
    return _done(_outline(im, 1.2))


@lru_cache(None)
def slash(size=150):
    """A crescent motion trail for the sword swing."""
    im = _canvas(size, size)
    m = Image.new('L', im.size, 0)
    d = ImageDraw.Draw(m)
    W = size * S
    d.pieslice([0, 0, W, W], 200, 340, fill=255)
    d.pieslice([W * 0.12, W * 0.16, W * 0.88, W * 1.0], 190, 350, fill=0)
    col = Image.new('RGBA', im.size, (236, 240, 255, 210))
    im.paste(col, (0, 0), m.filter(ImageFilter.GaussianBlur(S * 1.5)))
    return _done(im)


@lru_cache(None)
def steam(size=26):
    im = _canvas(size, size * 2)
    d = ImageDraw.Draw(im)
    W, H = size * S, size * 2 * S
    pts = [(W / 2 + math.sin(t / 10 * math.pi * 2) * W * 0.22, H * (0.95 - t / 10 * 0.9)) for t in range(11)]
    d.line(pts, fill=(255, 255, 255, 200), width=int(W * 0.16), joint='curve')
    return _done(im, 0.8)


def place_sprite(frame, sprite, x, y, scale=1.0, angle=0.0, alpha=1.0):
    """Composites `sprite` centred at (x, y) on the 320 frame."""
    if alpha <= 0.01 or scale <= 0.01:
        return
    sp = sprite
    if scale != 1.0:
        sp = sp.resize((max(1, round(sp.width * scale)), max(1, round(sp.height * scale))), Image.LANCZOS)
    if angle:
        sp = sp.rotate(angle, resample=Image.BICUBIC, expand=True)
    if alpha < 1.0:
        a = sp.split()[3].point(lambda v: int(v * alpha))
        sp = sp.copy()
        sp.putalpha(a)
    ox, oy = round(x - sp.width / 2), round(y - sp.height / 2)
    # Clip to the frame (alpha_composite refuses negative offsets).
    l, t = max(0, -ox), max(0, -oy)
    r, b = min(sp.width, frame.width - ox), min(sp.height, frame.height - oy)
    if r <= l or b <= t:
        return
    frame.alpha_composite(sp.crop((l, t, r, b)), (ox + l, oy + t))
