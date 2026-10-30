"""Builds frontend/ui/assets/rive/foxy.riv — Foxy as a Rive state machine.

Foxy's art is never redrawn: every pose and outfit is the original brand PNG
(assets/images/foxy/ and assets/stickers/sticker_costume_*.png), embedded as
WebP. The only touch-up restores alpha on see-through holes the background
cut-out punched into the eyes and nose (their colour data is still there).
Small brand-colour props (sparkles, confetti, Zzz, hearts, rain, snow, smoke
puffs) are drawn here as sprites and animated around him.

Format: Rive runtime binary v7 (rive-flutter 0.13 / rive-runtime), written as
varuint typeKey + (varuint propertyKey, value)* + 0 per object.

    python scripts/media/build_foxy_riv.py [out.riv]

State machine `Foxy` inputs: mood (number), outfit (number), lean (number),
hop / shake / poof (triggers). See assets/rive/README.md.
"""

import io
import math
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

UI = Path(__file__).resolve().parents[2] / 'frontend' / 'ui'
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else UI / 'assets' / 'rive' / 'foxy.riv'
FONT = UI / 'assets' / 'fonts' / 'quicksand-v37-latin-700.ttf'

# ---- Rive keys (rive 0.13.20 generated definitions) ---------------------------
T = dict(Backboard=23, ImageAsset=105, FileAssetContents=106, Artboard=1, Node=2,
         Image=100, LinearAnimation=31, KeyedObject=25, KeyedProperty=26,
         KeyFrameDouble=30, StateMachine=53, StateMachineNumber=56,
         StateMachineTrigger=58, StateMachineLayer=57, EntryState=63, AnyState=62,
         ExitState=64, AnimationState=61, StateTransition=65,
         TransitionNumberCondition=70, TransitionTriggerCondition=68,
         BlendState1D=76, BlendAnimation1D=75)
P = dict(name=4, parentId=5, width=7, height=8, abOriginX=11, abOriginY=12, clip=196,
         x=13, y=14, rotation=15, scaleX=16, scaleY=17, opacity=18,
         assetName=203, assetId=204, assetHeight=207, assetWidth=208, bytes=212,
         imageAssetId=206,
         animName=55, fps=56, duration=57, speed=58, loop=59,
         objectId=51, propertyKey=53, frame=67, interpType=68, kfValue=70,
         smName=138, numValue=140, animationId=149, stateToId=151, tFlags=152,
         tDuration=158, exitTime=160, inputId=155, opValue=156, condValue=157,
         blendInputId=167, blendAnimId=165, blendValue=166)
STRINGS = {P['name'], P['assetName'], P['animName'], P['smName']}
DOUBLES = {P[k] for k in ('width', 'height', 'abOriginX', 'abOriginY', 'x', 'y', 'rotation',
                          'scaleX', 'scaleY', 'opacity', 'assetHeight', 'assetWidth', 'speed',
                          'kfValue', 'numValue', 'condValue', 'blendValue')}


def varuint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | 0x80 if n else b)
        if not n:
            return bytes(out)


class Writer:
    def __init__(self):
        self.buf = bytearray(b'RIVE') + varuint(7) + varuint(0) + varuint(0) + varuint(0)

    def obj(self, type_name, **props):
        self.buf += varuint(T[type_name])
        for key, value in props.items():
            pk = P[key]
            self.buf += varuint(pk)
            if pk in STRINGS:
                data = value.encode()
                self.buf += varuint(len(data)) + data
            elif pk in DOUBLES:
                self.buf += struct.pack('<f', float(value))
            elif pk == P['bytes']:
                self.buf += varuint(len(value)) + value
            elif pk == P['clip']:
                self.buf += bytes([1 if value else 0])
            else:
                assert value >= 0, (key, value)
                self.buf += varuint(int(value))
        self.buf += varuint(0)


# ---- artwork --------------------------------------------------------------------
def restore_holes(path):
    """RGBA array with see-through holes inside the silhouette made opaque again."""
    im = np.array(Image.open(path).convert('RGBA'))
    alpha = im[..., 3]
    labels, _ = ndimage.label(alpha < 128)
    edge = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    inside = ~np.isin(labels, list(edge)) & (alpha < 255)
    im[..., 3] = np.where(inside, 255, alpha)
    return Image.fromarray(im)


def tidy(img, strip_backdrop=False):
    """Drops stray islands left from slicing the brand sheet (bits of the
    neighbouring sticker), and optionally a pale backdrop blob touching the
    right edge (the rainy sticker carries part of the sheet's cloud)."""
    im = np.array(img).astype(float)
    alpha = im[..., 3]
    h, w = alpha.shape
    if strip_backdrop:
        rgb = im[..., :3] / 255
        mx, mn = rgb.max(-1), rgb.min(-1)
        sat = (mx - mn) / (mx + 1e-6)
        pale = (sat < 0.14) & (mx > 0.72) & (alpha > 20)
        labels, n = ndimage.label(pale)
        kill = np.zeros_like(pale)
        for i in range(1, n + 1):
            ys, xs = np.where(labels == i)
            if (xs.max() >= w - 3 or ys.max() >= h - 3) and xs.mean() > w * 0.6:
                kill |= labels == i
        kill = ndimage.binary_dilation(kill, iterations=2) & (sat < 0.25)
        alpha = np.where(kill, 0, alpha)
    labels, n = ndimage.label(alpha > 40)
    if n > 1:
        sizes = ndimage.sum(np.ones_like(alpha), labels, range(1, n + 1))
        keep = {i + 1 for i, size in enumerate(sizes) if size >= sizes.max() * 0.06}
        island = (labels > 0) & ~np.isin(labels, list(keep))
        island = ndimage.binary_dilation(island, iterations=1) & (alpha < 255) | island
        alpha = np.where(island, 0, alpha)
    im[..., 3] = alpha
    return Image.fromarray(im.astype(np.uint8))


def webp(img, quality=92):
    buf = io.BytesIO()
    img.save(buf, 'WEBP', quality=quality, method=6)
    return buf.getvalue()


def png(img):
    buf = io.BytesIO()
    img.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


PEACH, VIOLET, PINK, TEAL, BLUE = (255, 181, 143), (141, 120, 255), (231, 149, 215), (104, 215, 205), (114, 167, 255)


def supersample(size, draw_fn, blur=0):
    s = 4
    big = Image.new('RGBA', (size[0] * s, size[1] * s), (0, 0, 0, 0))
    draw_fn(big, s)
    if blur:
        big = big.filter(ImageFilter.GaussianBlur(blur * s))
    return big.resize(size, Image.LANCZOS)


def sprite_sparkle(color):
    def draw(im, s):
        d = ImageDraw.Draw(im)
        c, r = 32 * s, 30 * s
        pts = []
        for i in range(64):
            a = i / 64 * 2 * math.pi
            k = abs(math.cos(2 * a)) ** 6  # four sharp points
            rr = r * (0.18 + 0.82 * k)
            pts.append((c + rr * math.cos(a), c + rr * math.sin(a)))
        glow = Image.new('RGBA', im.size, (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse([c - 14 * s, c - 14 * s, c + 14 * s, c + 14 * s], fill=color + (110,))
        im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(7 * s)))
        d.polygon(pts, fill=color + (255,))
        d.ellipse([c - 5 * s, c - 5 * s, c + 5 * s, c + 5 * s], fill=(255, 255, 255, 255))
    return supersample((64, 64), draw)


def sprite_confetti(color):
    def draw(im, s):
        ImageDraw.Draw(im).rounded_rectangle([2 * s, 2 * s, 12 * s, 22 * s], radius=3 * s, fill=color + (255,))
    return supersample((14, 24), draw)


def sprite_heart():
    def draw(im, s):
        w, h = 56 * s, 52 * s
        mask = Image.new('L', (w, h), 0)
        d = ImageDraw.Draw(mask)
        r = 14 * s
        d.ellipse([2 * s, 4 * s, 2 * s + 2 * r, 4 * s + 2 * r], fill=255)
        d.ellipse([w - 2 * s - 2 * r, 4 * s, w - 2 * s, 4 * s + 2 * r], fill=255)
        d.polygon([(3 * s, 22 * s), (w - 3 * s, 22 * s), (w / 2, h - 2 * s)], fill=255)
        grad = Image.new('RGBA', (w, h))
        for y in range(h):
            t = y / h
            col = tuple(int(PINK[i] * (1 - t) + PEACH[i] * t) for i in range(3))
            ImageDraw.Draw(grad).line([(0, y), (w, y)], fill=col + (255,))
        im.paste(grad, (0, 0), mask)
        ImageDraw.Draw(im).ellipse([12 * s, 11 * s, 20 * s, 17 * s], fill=(255, 255, 255, 150))
    return supersample((56, 52), draw)


def sprite_z():
    def draw(im, s):
        font = ImageFont.truetype(str(FONT), 40 * s)
        ImageDraw.Draw(im).text((24 * s, 26 * s), 'z', font=font, anchor='mm', fill=(214, 206, 255, 255))
    return supersample((48, 52), draw)


def sprite_dot():
    def draw(im, s):
        ImageDraw.Draw(im).ellipse([2 * s, 2 * s, 30 * s, 30 * s], fill=(238, 236, 248, 235))
    return supersample((32, 32), draw)


def sprite_drop():
    def draw(im, s):
        d = ImageDraw.Draw(im)
        d.rounded_rectangle([3 * s, 2 * s, 7 * s, 26 * s], radius=2 * s, fill=BLUE + (190,))
    return supersample((10, 28), draw)


def sprite_flake():
    def draw(im, s):
        ImageDraw.Draw(im).ellipse([4 * s, 4 * s, 16 * s, 16 * s], fill=(255, 255, 255, 235))
    return supersample((20, 20), draw, blur=0.6)


def sprite_puff():
    """A cartoon smoke puff: overlapping lobes, lit from the top."""
    lobes = [(30, 58, 20), (50, 44, 26), (72, 56, 20), (50, 66, 22)]

    def draw(im, s):
        base = Image.new('L', im.size, 0)
        d = ImageDraw.Draw(base)
        for cx, cy, r in lobes:
            d.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s], fill=255)
        shade = Image.new('RGBA', im.size, (200, 194, 232, 255))
        light = Image.new('L', im.size, 0)
        dl = ImageDraw.Draw(light)
        for cx, cy, r in lobes:
            dl.ellipse([(cx - r * 0.8) * s, (cy - r * 0.95) * s, (cx + r * 0.7) * s, (cy + r * 0.45) * s], fill=255)
        light = light.filter(ImageFilter.GaussianBlur(5 * s))
        top = Image.new('RGBA', im.size, (246, 244, 255, 255))
        shade.paste(top, (0, 0), light)
        shade.putalpha(base.filter(ImageFilter.GaussianBlur(0.8 * s)))
        im.alpha_composite(shade)
    return supersample((100, 96), draw)


def sprite_shadow():
    sh = Image.new('L', (220, 44), 0)
    px = sh.load()
    for yy in range(44):
        for xx in range(220):
            d = ((xx - 110) / 110) ** 2 + ((yy - 22) / 22) ** 2
            px[xx, yy] = int(max(0.0, 1 - d) ** 1.6 * 150)
    return Image.merge('RGBA', [Image.new('L', sh.size, 0)] * 3 + [sh])


POSES = ['hello', 'happy', 'curious', 'coffee', 'explorer', 'focused', 'sleepy', 'cozy']
POSE_H = {'hello': 262, 'happy': 275, 'curious': 255, 'coffee': 262, 'explorer': 295,
          'focused': 245, 'sleepy': 165, 'cozy': 285}
# Outfit index = `outfit` input (0 is Foxy's classic look: the mood poses).
OUTFITS = ['classic', 'explorer', 'hoodie', 'space', 'samurai', 'wizard', 'chef', 'student',
           'business', 'rainy', 'winter', 'traveler']
OUTFIT_H = {'explorer': 268, 'hoodie': 268, 'space': 262, 'samurai': 290, 'wizard': 292,
            'chef': 276, 'student': 274, 'business': 290, 'rainy': 250, 'winter': 236,
            'traveler': 228}

assets = []  # (name, bytes, w, h)
art = {}     # name -> (asset index, w, h, bbox)


def add_asset(name, img, encoder=webp):
    a = np.array(img)[..., 3]
    ys, xs = np.where(a > 128)
    bbox = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1) if len(xs) else (0, 0, img.width, img.height)
    art[name] = (len(assets), img.width, img.height, bbox)
    assets.append((name, encoder(img), img.width, img.height))


for n in POSES:
    add_asset('pose_' + n, restore_holes(UI / 'assets' / 'images' / 'foxy' / f'foxy_{n}.png'))
for n in OUTFITS[1:]:
    add_asset('outfit_' + n, tidy(restore_holes(UI / 'assets' / 'stickers' / f'sticker_costume_{n}.png'),
                                  strip_backdrop=n == 'rainy'))
for name, img in [('sparkle', sprite_sparkle(PEACH)), ('sparkle_violet', sprite_sparkle(VIOLET)),
                  ('heart', sprite_heart()), ('z', sprite_z()), ('dot', sprite_dot()),
                  ('drop', sprite_drop()), ('flake', sprite_flake()), ('puff', sprite_puff()),
                  ('shadow', sprite_shadow())] + [
        (f'confetti_{i}', sprite_confetti(c)) for i, c in enumerate([PEACH, VIOLET, PINK, TEAL])]:
    add_asset(name, img, png)

w = Writer()
w.obj('Backboard')
for i, (name, data, aw, ah) in enumerate(assets):
    w.obj('ImageAsset', assetName=name, assetId=i + 1, assetWidth=aw, assetHeight=ah)
    w.obj('FileAssetContents', bytes=data)

# ---- components ------------------------------------------------------------------
W = H = 400
FEET = (200.0, 352.0)
ids = {}
nodes, drawables = [], []


def node(key, parent, **props):
    nodes.append((key, parent, props))


def image(key, parent, asset, **props):
    drawables.append((key, parent, asset, props))


node('lean', None, x=FEET[0], y=FEET[1])
node('hop', 'lean')
node('shake', 'hop')
node('breath', 'shake')
node('pose', 'breath')
node('classic', 'pose')
node('wardrobe', 'pose')
node('weather', None)
node('poof', None, x=200, y=230)

MOOD_FX = {}  # mood -> list of particle keys


def particle_group(group, parent, **props):
    node(group, parent, opacity=0, **props)


# Particles: (key, group, asset, base x, base y, base scale)
particles = []


def particle(key, group, asset, x=0, y=0, scale=1.0):
    particles.append((key, group, asset))
    image(key, group, asset, x=x, y=y, scaleX=scale, scaleY=scale, opacity=0)


particle_group('fx_wave', 'hop')
particle('wave_s1', 'fx_wave', 'sparkle', -92, -210, 0.5)
particle('wave_s2', 'fx_wave', 'sparkle_violet', -118, -170, 0.38)
particle_group('fx_think', 'hop')
for i, (x, y, s) in enumerate([(52, -246, 0.38), (74, -276, 0.52), (102, -312, 0.72)]):
    particle(f'think_d{i}', 'fx_think', 'dot', x, y, s)
particle_group('fx_celebrate', 'hop')
for i in range(12):
    particle(f'conf_{i}', 'fx_celebrate', f'confetti_{i % 4}', 0, 0, 1.0)
for i in range(3):
    particle(f'cel_s{i}', 'fx_celebrate', 'sparkle' if i != 1 else 'sparkle_violet', 0, 0, 0.5)
particle_group('fx_sleep', 'hop')
for i in range(3):
    particle(f'z{i}', 'fx_sleep', 'z', 0, 0, 0.6)
particle_group('fx_love', 'hop')
for i in range(4):
    particle(f'heart{i}', 'fx_love', 'heart', 0, 0, 0.5)
FX_GROUPS = ['fx_wave', 'fx_think', 'fx_celebrate', 'fx_sleep', 'fx_love']

particle_group('wx_rain', 'weather')
for i in range(9):
    particle(f'rain{i}', 'wx_rain', 'drop', 0, 0, 1.0)
particle_group('wx_snow', 'weather')
for i in range(12):
    particle(f'snow{i}', 'wx_snow', 'flake', 0, 0, 1.0)
particle_group('wx_magic', 'pose')
for i in range(4):
    particle(f'magic{i}', 'wx_magic', 'sparkle_violet' if i % 2 else 'sparkle', 0, 0, 0.4)
particle_group('wx_stars', 'weather')
for i in range(6):
    particle(f'star{i}', 'wx_stars', 'flake', 0, 0, 0.5)
WX_GROUPS = ['wx_rain', 'wx_snow', 'wx_magic', 'wx_stars']

for i in range(6):
    particle(f'puff{i}', 'poof', 'puff', 0, 0, 0.4)


def place(name, parent, target_h, key, **extra):
    index, iw, ih, (x0, y0, x1, y1) = art[name]
    s = target_h / (y1 - y0)
    cx = (x0 + x1) / 2
    image(key, parent, name, x=-(cx - iw / 2) * s, y=-(y1 - ih / 2) * s, scaleX=s, scaleY=s, **extra)
    return s


for n in POSES:
    place('pose_' + n, 'classic', POSE_H[n], n, opacity=1.0 if n == 'hello' else 0.0)
for n in OUTFITS[1:]:
    place('outfit_' + n, 'wardrobe', OUTFIT_H[n], 'o_' + n, opacity=0.0)
image('shadow', None, 'shadow', x=FEET[0], y=FEET[1] - 4, scaleX=0.85, scaleY=0.85)

# Wizard staff tip, measured on the costume art (pixel 198,79 of 230x244).
_, ww, wh, (wx0, wy0, wx1, wy1) = art['outfit_wizard']
_ws = OUTFIT_H['wizard'] / (wy1 - wy0)
STAFF = (-((wx0 + wx1) / 2 - 198) * _ws, -(wy1 - 79) * _ws)

# Space stars sit behind Foxy (just above the shadow).
_back = [d for d in drawables if d[0].startswith('star')]
drawables = [d for d in drawables if not d[0].startswith('star')]
drawables[-1:-1] = _back

# Ids: artboard 0, then nodes, then drawables (earlier drawables draw on top).
order = [k for k, _, _ in nodes] + [k for k, _, _, _ in drawables]
ids = {k: i + 1 for i, k in enumerate(order)}

w.obj('Artboard', name='Foxy', width=W, height=H, abOriginX=0, abOriginY=0, clip=False)
for key, parent, props in nodes:
    w.obj('Node', name=key, parentId=ids[parent] if parent else 0, **props)
for key, parent, asset, props in drawables:
    w.obj('Image', name=key, parentId=ids[parent] if parent else 0,
          imageAssetId=art[asset][0], **props)

# ---- animations --------------------------------------------------------------------
FPS = 60
STEP = 2
animations = []


def ease(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def anim(name, seconds, tracks, loop=1):
    frames = max(1, round(seconds * FPS))
    animations.append(name)
    w.obj('LinearAnimation', animName=name, fps=FPS, duration=frames, loop=loop)
    by_obj = {}
    for (ckey, prop), spec in tracks.items():
        by_obj.setdefault(ckey, []).append((prop, spec))
    for ckey, props in by_obj.items():
        w.obj('KeyedObject', objectId=ids[ckey])
        for prop, spec in props:
            w.obj('KeyedProperty', propertyKey=P[prop])
            if callable(spec):
                for f in list(range(0, frames, STEP)) + [frames]:
                    w.obj('KeyFrameDouble', frame=f, interpType=1, kfValue=spec(f / FPS))
            else:
                for t, v in spec:
                    w.obj('KeyFrameDouble', frame=round(t * FPS), interpType=1, kfValue=v)
    return len(animations) - 1


def crossfade(seconds, timeline, fade=0.18):
    tracks = {}
    for n in POSES:
        keys = []
        for i, (start, pose) in enumerate(timeline):
            on = 1.0 if pose == n else 0.0
            nxt = timeline[i + 1][0] if i + 1 < len(timeline) else seconds
            keys += [(start, on), (max(start, nxt - fade), on)]
        keys.append((seconds, 1.0 if timeline[0][1] == n else 0.0))
        dedup = []
        for t, v in keys:
            if dedup and abs(dedup[-1][0] - t) < 1e-6:
                dedup[-1] = (t, v)
            else:
                dedup.append((t, v))
        tracks[(n, 'opacity')] = dedup
    return tracks


def cyc(t, period, phase=0.0):
    return ((t / period) + phase) % 1.0


def twinkle(key, period, phase=0.0, base=0.5):
    """A sparkle that pops in, spins a quarter turn and fades."""
    def life(t):
        u = cyc(t, period, phase)
        return math.sin(math.pi * min(1, u / 0.45)) if u < 0.45 else 0.0
    return {(key, 'opacity'): lambda t: life(t),
            (key, 'scaleX'): lambda t: base * (0.3 + 0.7 * life(t)),
            (key, 'scaleY'): lambda t: base * (0.3 + 0.7 * life(t)),
            (key, 'rotation'): lambda t: cyc(t, period, phase) * 1.6}


POSE_DEFAULTS = {'x': 0.0, 'y': 0.0, 'rotation': 0.0, 'scaleX': 1.0, 'scaleY': 1.0}


def mood(name, seconds, tracks, fx=None):
    for prop, value in POSE_DEFAULTS.items():
        tracks.setdefault(('pose', prop), [(0, value)])
    for group in FX_GROUPS:
        tracks[(group, 'opacity')] = [(0, 1.0 if group == fx else 0.0)]
    return anim('mood_' + name, seconds, tracks)


def static(pose):
    return {(n, 'opacity'): [(0, 1.0 if n == pose else 0.0)] for n in POSES}


def sway(period, amp, phase=0.0):
    return lambda t: amp * math.sin(2 * math.pi * (t / period + phase))


moods = []
# 0 wave: paw up and rocking, two sparkles by the paw, then a happy squint.
t = crossfade(2.6, [(0, 'hello'), (1.6, 'happy')])
t[('pose', 'rotation')] = lambda s: (0.07 * math.sin(2 * math.pi * s / 0.8) if s < 1.6 else 0.0) * min(1, s / 0.2)
t.update(twinkle('wave_s1', 1.3, 0.0, 0.55))
t.update(twinkle('wave_s2', 1.3, 0.45, 0.4))
moods.append(mood('wave', 2.6, t, 'fx_wave'))
# 1 think: laptop focus with a slow head tilt; thought dots bubble up in turn.
t = crossfade(3.6, [(0, 'focused'), (2.2, 'curious')])
t[('pose', 'rotation')] = lambda s: -0.05 * ease(s / 0.6) if s < 3.0 else -0.05 * (1 - ease((s - 3.0) / 0.6))
for i, (x, y, sc) in enumerate([(52, -246, 0.38), (74, -276, 0.52), (102, -312, 0.72)]):
    def dot_alpha(s, i=i):
        u = cyc(s, 1.8)
        start = i * 0.18
        if u < start:
            return 0.0
        if u < start + 0.12:
            return (u - start) / 0.12
        return 1.0 if u < 0.82 else max(0.0, 1 - (u - 0.82) / 0.12)
    t[(f'think_d{i}', 'opacity')] = dot_alpha
    t[(f'think_d{i}', 'y')] = lambda s, y=y, i=i: y + 3 * math.sin(2 * math.pi * (s / 1.8 + i * 0.2))
moods.append(mood('think', 3.6, t, 'fx_think'))
# 2 celebrate: bouncing, a wave, a mug raised — confetti falls throughout.
t = crossfade(3.2, [(0, 'happy'), (1.1, 'hello'), (2.1, 'coffee')])
t[('pose', 'y')] = lambda s: -22 * abs(math.sin(math.pi * s / 0.55)) if s < 1.1 else 0.0
t[('pose', 'scaleY')] = lambda s: 1 + 0.04 * math.sin(2 * math.pi * s / 0.55) if s < 1.1 else 1.0
t[('pose', 'rotation')] = lambda s: 0.06 * math.sin(2 * math.pi * (s - 1.1) / 0.5) if 1.1 <= s < 2.1 else 0.0
rng = np.random.default_rng(7)
for i in range(12):
    x0 = float(rng.uniform(-150, 150))
    phase = float(rng.uniform(0, 1))
    spin = float(rng.uniform(4, 9)) * (1 if i % 2 else -1)
    drift = float(rng.uniform(10, 26))
    period = 1.6

    def life(s, phase=phase):
        u = cyc(s, period, phase)
        return min(1.0, u / 0.08) * min(1.0, (1 - u) / 0.15)
    t[(f'conf_{i}', 'x')] = lambda s, x0=x0, phase=phase, drift=drift: x0 + drift * math.sin(2 * math.pi * cyc(s, period, phase) * 1.5)
    t[(f'conf_{i}', 'y')] = lambda s, phase=phase: -340 + 330 * cyc(s, period, phase)
    t[(f'conf_{i}', 'rotation')] = lambda s, phase=phase, spin=spin: spin * cyc(s, period, phase)
    t[(f'conf_{i}', 'scaleX')] = lambda s, phase=phase: 0.25 + 0.75 * abs(math.cos(2 * math.pi * cyc(s, period, phase) * 2))
    t[(f'conf_{i}', 'opacity')] = life
for i, (x, y) in enumerate([(-120, -250), (128, -200), (96, -300)]):
    t[(f'cel_s{i}', 'x')] = [(0, x)]
    t[(f'cel_s{i}', 'y')] = [(0, y)]
    t.update(twinkle(f'cel_s{i}', 1.6, i * 0.33, 0.55))
moods.append(mood('celebrate', 3.2, t, 'fx_celebrate'))
# 3 explore: map in paws, scanning the horizon.
t = static('explorer')
t[('pose', 'rotation')] = sway(3.0, 0.04)
t[('pose', 'x')] = sway(3.0, 4.0, 0.25)
moods.append(mood('explore', 3.0, t))
# 4 sleep: slow breaths, Zzz drifting up.
t = static('sleepy')
t[('pose', 'scaleY')] = lambda s: 1 + 0.035 * (0.5 - 0.5 * math.cos(2 * math.pi * s / 3.6))
t[('pose', 'scaleX')] = lambda s: 1 + 0.012 * (0.5 - 0.5 * math.cos(2 * math.pi * s / 3.6))
for i in range(3):
    ph = i / 3
    t[(f'z{i}', 'x')] = lambda s, ph=ph: 40 + 70 * cyc(s, 3.6, ph) + 8 * math.sin(2 * math.pi * cyc(s, 3.6, ph) * 2)
    t[(f'z{i}', 'y')] = lambda s, ph=ph: -150 - 150 * cyc(s, 3.6, ph)
    t[(f'z{i}', 'scaleX')] = lambda s, ph=ph: 0.35 + 0.55 * cyc(s, 3.6, ph)
    t[(f'z{i}', 'scaleY')] = lambda s, ph=ph: 0.35 + 0.55 * cyc(s, 3.6, ph)
    t[(f'z{i}', 'rotation')] = lambda s, ph=ph: -0.2 + 0.25 * cyc(s, 3.6, ph)
    t[(f'z{i}', 'opacity')] = lambda s, ph=ph: min(1, cyc(s, 3.6, ph) / 0.15) * min(1, (1 - cyc(s, 3.6, ph)) / 0.3)
moods.append(mood('sleep', 3.6, t, 'fx_sleep'))
# 5 hello
t = static('hello')
t[('pose', 'rotation')] = sway(2.4, 0.035)
moods.append(mood('hello', 2.4, t))
# 6 curious: a head tilt that lingers.
t = static('curious')
t[('pose', 'rotation')] = lambda s: 0.06 * ease(s / 0.5) if s < 2.6 else 0.06 * (1 - ease((s - 2.6) / 0.5))
moods.append(mood('curious', 3.2, t))
# 7 noPeeking: eyes squeezed shut, a tiny giggle wiggle.
t = static('happy')
t[('pose', 'rotation')] = sway(0.9, 0.018)
moods.append(mood('no_peeking', 1.8, t))
# 8 focused
t = static('focused')
t[('pose', 'y')] = lambda s: -2.0 * abs(math.sin(2 * math.pi * s / 0.6)) if (s % 2.4) < 0.6 else 0.0
moods.append(mood('focused', 2.4, t))
# 9 cozy
t = static('cozy')
t[('pose', 'rotation')] = sway(3.4, 0.025)
moods.append(mood('cozy', 3.4, t))
# 10 love: happy squint, hearts float up and sway.
t = static('happy')
t[('pose', 'scaleY')] = lambda s: 1 + 0.025 * max(0.0, math.sin(2 * math.pi * s / 0.9)) ** 3
for i, x0 in enumerate([-70, 60, -20, 95]):
    ph = i / 4
    t[(f'heart{i}', 'x')] = lambda s, x0=x0, ph=ph: x0 + 14 * math.sin(2 * math.pi * cyc(s, 2.8, ph) * 1.5)
    t[(f'heart{i}', 'y')] = lambda s, ph=ph: -170 - 170 * cyc(s, 2.8, ph)
    t[(f'heart{i}', 'scaleX')] = lambda s, ph=ph: 0.28 + 0.3 * math.sin(math.pi * min(1, cyc(s, 2.8, ph) / 0.3))
    t[(f'heart{i}', 'scaleY')] = lambda s, ph=ph: 0.28 + 0.3 * math.sin(math.pi * min(1, cyc(s, 2.8, ph) / 0.3))
    t[(f'heart{i}', 'opacity')] = lambda s, ph=ph: min(1, cyc(s, 2.8, ph) / 0.12) * min(1, (1 - cyc(s, 2.8, ph)) / 0.35)
moods.append(mood('love', 2.8, t, 'fx_love'))

# Outfits: classic shows the mood poses; others swap in a costume. Each keys
# every costume, so switching never strands one.
WEATHER = {'rainy': 'wx_rain', 'winter': 'wx_snow', 'wizard': 'wx_magic', 'space': 'wx_stars'}
outfits = []
for k, name in enumerate(OUTFITS):
    t = {('classic', 'opacity'): [(0, 1.0 if name == 'classic' else 0.0)]}
    for other in OUTFITS[1:]:
        t[('o_' + other, 'opacity')] = [(0, 1.0 if other == name else 0.0)]
    for g in WX_GROUPS:
        t[(g, 'opacity')] = [(0, 1.0 if WEATHER.get(name) == g else 0.0)]
    seconds = 2.4
    if name == 'rainy':
        seconds = 2.4
        for i in range(9):
            x0 = 30 + i * 42
            ph = (i * 0.37) % 1
            t[(f'rain{i}', 'x')] = lambda s, x0=x0, ph=ph: x0 - 30 * cyc(s, 0.8, ph)
            t[(f'rain{i}', 'y')] = lambda s, ph=ph: -20 + 420 * cyc(s, 0.8, ph)
            t[(f'rain{i}', 'rotation')] = [(0, 0.07)]
            t[(f'rain{i}', 'opacity')] = lambda s, ph=ph: 0.75 * min(1, cyc(s, 0.8, ph) / 0.1) * min(1, (1 - cyc(s, 0.8, ph)) / 0.1)
    elif name == 'winter':
        seconds = 4.8
        for i in range(12):
            x0 = 20 + i * 32
            ph = (i * 0.29) % 1
            sc = 0.45 + 0.4 * ((i * 7) % 5) / 4
            t[(f'snow{i}', 'x')] = lambda s, x0=x0, ph=ph: x0 + 14 * math.sin(2 * math.pi * cyc(s, 4.8, ph) * 2)
            t[(f'snow{i}', 'y')] = lambda s, ph=ph: -10 + 400 * cyc(s, 4.8, ph)
            t[(f'snow{i}', 'scaleX')] = [(0, sc)]
            t[(f'snow{i}', 'scaleY')] = [(0, sc)]
            t[(f'snow{i}', 'opacity')] = lambda s, ph=ph: 0.9 * min(1, cyc(s, 4.8, ph) / 0.1) * min(1, (1 - cyc(s, 4.8, ph)) / 0.15)
    elif name == 'wizard':
        seconds = 2.0
        for i in range(4):
            ang = i / 4 * 2 * math.pi
            t[(f'magic{i}', 'x')] = lambda s, ang=ang: STAFF[0] + 22 * math.cos(ang + 2 * math.pi * s / 2.0)
            t[(f'magic{i}', 'y')] = lambda s, ang=ang: STAFF[1] + 14 * math.sin(ang + 2 * math.pi * s / 2.0)
            t.update({k2: v for k2, v in twinkle(f'magic{i}', 1.0, i * 0.25, 0.42).items()
                      if k2[1] != 'rotation'})
    elif name == 'space':
        seconds = 3.0
        for i, (x, y) in enumerate([(70, 90), (330, 70), (52, 220), (350, 200), (120, 40), (290, 140)]):
            t[(f'star{i}', 'x')] = [(0, x)]
            t[(f'star{i}', 'y')] = [(0, y)]
            t[(f'star{i}', 'opacity')] = lambda s, i=i: 0.25 + 0.75 * (0.5 + 0.5 * math.sin(2 * math.pi * (s / 1.5 + i * 0.17)))
    outfits.append(anim('outfit_' + name, seconds, t))

breath = anim('idle_breath', 2.8, {
    ('breath', 'scaleY'): lambda s: 1 + 0.018 * (0.5 - 0.5 * math.cos(2 * math.pi * s / 2.8)),
    ('breath', 'scaleX'): lambda s: 1 - 0.006 * (0.5 - 0.5 * math.cos(2 * math.pi * s / 2.8)),
})


def hop_y(s):
    return -46 * math.sin(math.pi * s / 0.42) if s < 0.42 else 0.0


def hop_sy(s):
    if s < 0.1:
        return 1 + 0.07 * math.sin(math.pi * s / 0.1)
    if 0.42 <= s < 0.6:
        return 1 - 0.08 * math.sin(math.pi * (s - 0.42) / 0.18)
    return 1.0


def hop_sx(s):
    return 1 + 0.06 * math.sin(math.pi * (s - 0.42) / 0.18) if 0.42 <= s < 0.6 else 1.0


hop = anim('hop', 0.6, {
    ('hop', 'y'): hop_y, ('hop', 'scaleY'): hop_sy, ('hop', 'scaleX'): hop_sx,
    ('shadow', 'scaleX'): lambda s: 0.85 * (1 + hop_y(s) / 46 * 0.35),
    ('shadow', 'opacity'): lambda s: 1 + hop_y(s) / 46 * 0.5,
}, loop=0)
shake = anim('shake', 0.5, {
    ('shake', 'rotation'): lambda s: 0.09 * math.sin(2 * math.pi * s * 4) * (1 - s / 0.5),
}, loop=0)
rest = anim('rest', 0.1, {('hop', 'y'): [(0, 0.0)], ('shake', 'rotation'): [(0, 0.0)]}, loop=0)

POOF_DIRS = [(math.cos(a), math.sin(a)) for a in [i / 6 * 2 * math.pi + 0.3 for i in range(6)]]
t = {('poof', 'opacity'): [(0, 1.0)]}
for i, (dx, dy) in enumerate(POOF_DIRS):
    t[(f'puff{i}', 'x')] = lambda s, dx=dx: dx * (70 + 70 * ease(s / 0.6))
    t[(f'puff{i}', 'y')] = lambda s, dy=dy: dy * (60 + 55 * ease(s / 0.6)) - 16 * ease(s / 0.6)
    t[(f'puff{i}', 'scaleX')] = lambda s: 0.4 + 0.55 * ease(s / 0.6)
    t[(f'puff{i}', 'scaleY')] = lambda s: 0.4 + 0.55 * ease(s / 0.6)
    t[(f'puff{i}', 'opacity')] = lambda s: (min(1, s / 0.08)) * (1 - ease((s - 0.14) / 0.46)) * 0.9
poof = anim('poof', 0.6, t, loop=0)
poof_rest = anim('poof_rest', 0.1, {(f'puff{i}', 'opacity'): [(0, 0.0)] for i in range(6)}, loop=0)

lean_l = anim('lean_left', 0.1, {('lean', 'rotation'): [(0, -0.08)], ('lean', 'x'): [(0, FEET[0] - 7)]})
lean_0 = anim('lean_center', 0.1, {('lean', 'rotation'): [(0, 0.0)], ('lean', 'x'): [(0, FEET[0])]})
lean_r = anim('lean_right', 0.1, {('lean', 'rotation'): [(0, 0.08)], ('lean', 'x'): [(0, FEET[0] + 7)]})

# ---- state machine ------------------------------------------------------------------------
EXIT_AT_END = (1 << 2) | (1 << 3)  # enableExitTime | exitTimeIsPercentage
INPUTS = ['mood', 'lean', 'hop', 'shake', 'outfit', 'poof']
w.obj('StateMachine', animName='Foxy')
w.obj('StateMachineNumber', smName='mood', numValue=0)
w.obj('StateMachineNumber', smName='lean', numValue=0)
w.obj('StateMachineTrigger', smName='hop')
w.obj('StateMachineTrigger', smName='shake')
w.obj('StateMachineNumber', smName='outfit', numValue=0)
w.obj('StateMachineTrigger', smName='poof')
I = {n: i for i, n in enumerate(INPUTS)}


def selector_layer(name, input_name, anims, fade_ms):
    """Entry → state 0; Any → state k when input == k."""
    w.obj('StateMachineLayer', smName=name)
    w.obj('EntryState')
    w.obj('StateTransition', stateToId=3)
    w.obj('AnyState')
    for k in range(len(anims)):
        w.obj('StateTransition', stateToId=3 + k, tDuration=fade_ms)
        w.obj('TransitionNumberCondition', inputId=I[input_name], opValue=0, condValue=float(k))
    w.obj('ExitState')
    for a in anims:
        w.obj('AnimationState', animationId=a)


def loop_layer(name, a):
    w.obj('StateMachineLayer', smName=name)
    w.obj('EntryState')
    w.obj('StateTransition', stateToId=3)
    w.obj('AnyState')
    w.obj('ExitState')
    w.obj('AnimationState', animationId=a)


def trigger_layer(name, rest_anim, shots):
    """shots: [(trigger input, animation)] — one-shots that return to rest."""
    w.obj('StateMachineLayer', smName=name)
    w.obj('EntryState')
    w.obj('StateTransition', stateToId=3)
    w.obj('AnyState')
    for k, (inp, _) in enumerate(shots):
        w.obj('StateTransition', stateToId=4 + k, tDuration=0)
        w.obj('TransitionTriggerCondition', inputId=I[inp])
    w.obj('ExitState')
    w.obj('AnimationState', animationId=rest_anim)
    for _ in shots:
        w.obj('AnimationState', animationId=_[1])
        w.obj('StateTransition', stateToId=3, tFlags=EXIT_AT_END, exitTime=100, tDuration=0)


selector_layer('Mood', 'mood', moods, 320)
selector_layer('Outfit', 'outfit', outfits, 260)
loop_layer('Breath', breath)
w.obj('StateMachineLayer', smName='Lean')
w.obj('EntryState')
w.obj('StateTransition', stateToId=3)
w.obj('AnyState')
w.obj('ExitState')
w.obj('BlendState1D', blendInputId=I['lean'])
w.obj('BlendAnimation1D', blendAnimId=lean_l, blendValue=-100)
w.obj('BlendAnimation1D', blendAnimId=lean_0, blendValue=0)
w.obj('BlendAnimation1D', blendAnimId=lean_r, blendValue=100)
trigger_layer('Reactions', rest, [('hop', hop), ('shake', shake)])
trigger_layer('Poof', poof_rest, [('poof', poof)])

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(bytes(w.buf))
print(f'{OUT}: {len(w.buf) / 1024:.0f} KB · {len(assets)} images · {len(animations)} animations · '
      f'{len(moods)} moods · {len(outfits)} outfits')
