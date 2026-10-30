"""Foxy rig engine: places a brand image on a 320×320 sticker canvas and
deforms it with a bone rig (moving-least-squares rigid image warping), so a
single flat illustration can wave, wag, blink, tilt and bounce without being
redrawn.

Coordinates are in sticker space (0..320). Rendering happens at SS× and is
downsampled for clean edges.
"""

import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

SIZE = 320
SS = 2
UI = Path(__file__).resolve().parents[3] / 'frontend' / 'ui'


# ---------------------------------------------------------------- source art
def _disk(r):
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return x * x + y * y <= r * r


def repair(img, close=13, keep_colour=True):
    """Restores cut-out damage from the asset sheet: holes inside the
    silhouette (keyed-out white fur, see-through eyes) are made opaque again,
    keeping the original colour where it survived, cream fur where it didn't."""
    im = np.array(img.convert('RGBA')).astype(float)
    a = im[..., 3]
    pad = close + 6
    solid = np.pad(a > 100, pad)
    filled = ndimage.binary_fill_holes(ndimage.binary_closing(solid, structure=_disk(close)))[pad:-pad, pad:-pad]
    hole = filled & (a < 200)
    rgb_alive = im[..., :3].max(-1) > 8
    # Pixels whose colour data survived the cut-out keep it.
    keep = hole & rgb_alive & (im[..., :3].min(-1) < 250) & keep_colour
    cream = np.array([250, 238, 226.0])
    al = (a / 255)[..., None]
    rgb = im[..., :3].copy()
    fill = hole & ~keep
    rgb[fill] = (im[..., :3] * al + cream * (1 - al))[fill]
    out_a = np.where(hole, 255, a)
    # Drop stray islands from slicing the sheet.
    labels, n = ndimage.label(out_a > 40)
    if n > 1:
        sizes = ndimage.sum(np.ones_like(out_a), labels, range(1, n + 1))
        keep_ids = [i + 1 for i, s in enumerate(sizes) if s >= sizes.max() * 0.005]
        out_a = np.where(np.isin(labels, keep_ids) | (labels == 0), out_a, 0)
    return Image.fromarray(np.dstack([rgb, out_a]).clip(0, 255).astype(np.uint8))


def strip_backdrop(img):
    """Removes a pale blob of the sheet's backdrop touching the right edge
    (the rainy sticker carries part of a cloud)."""
    im = np.array(img.convert('RGBA')).astype(float)
    alpha = im[..., 3]
    h, w = alpha.shape
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
    im[..., 3] = np.where(kill, 0, alpha)
    return Image.fromarray(im.astype(np.uint8))


def load(kind, name):
    path = {
        'pose': UI / 'assets/images/foxy' / f'foxy_{name}.png',
        'emoji': UI / 'assets/emoji' / f'emoji_foxy_{name}.png',
        'costume': UI / 'assets/stickers' / f'sticker_costume_{name}.png',
    }[kind]
    img = Image.open(path)
    if name == 'rainy':
        img = repair(strip_backdrop(img), close=2, keep_colour=True)
        a = np.array(img)
        labels, n = ndimage.label(a[..., 3] > 40)
        if n > 1:
            sizes = ndimage.sum(np.ones(labels.shape), labels, range(1, n + 1))
            big = int(np.argmax(sizes)) + 1
            a[..., 3] = np.where((labels == big) | (labels == 0), a[..., 3], 0)
        return Image.fromarray(a)
    return repair(img, close=13 if kind == 'emoji' else 4, keep_colour=kind != 'emoji')


def place(img, height=250, max_width=280, bottom=304, cx=160):
    """Scales the art onto the sticker canvas (at SS×). Returns RGBA float
    array (premultiplied) of shape (SIZE*SS, SIZE*SS, 4)."""
    a = np.array(img)[..., 3]
    ys, xs = np.where(a > 40)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    crop = img.crop((x0, y0, x1, y1))
    s = min(height / crop.height, max_width / crop.width)
    w, h = round(crop.width * s * SS), round(crop.height * s * SS)
    crop = crop.resize((w, h), Image.LANCZOS)
    canvas = Image.new('RGBA', (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    canvas.alpha_composite(crop, (round(cx * SS - w / 2), round(bottom * SS - h)))
    arr = np.array(canvas).astype(np.float32) / 255
    arr[..., :3] *= arr[..., 3:4]  # premultiply for clean resampling
    return arr


# ---------------------------------------------------------------- MLS warp
def mls_rigid(v, p, q, alpha=1.6, eps=1e-6):
    """Rigid moving-least-squares map of points v using control p -> q.
    v: (N,2), p,q: (K,2). Returns (N,2)."""
    d = v[:, None, :] - p[None, :, :]
    w = 1.0 / (np.sum(d * d, axis=2) ** alpha + eps)          # (N,K)
    ws = w.sum(1, keepdims=True)
    p_star = (w @ p) / ws
    q_star = (w @ q) / ws
    ph = p[None] - p_star[:, None]                            # (N,K,2)
    qh = q[None] - q_star[:, None]
    vp = v - p_star                                           # (N,2)
    # fr = Σ w (qh * [ph·vp, ph⊥·vp] rotated) — compact rigid form.
    a = np.sum(w * (ph[..., 0] * vp[:, None, 0] + ph[..., 1] * vp[:, None, 1]), axis=1)
    b = np.sum(w * (ph[..., 0] * vp[:, None, 1] - ph[..., 1] * vp[:, None, 0]), axis=1)
    # Rotation that best maps ph -> qh (weighted), applied to vp.
    c = np.sum(w * (ph[..., 0] * qh[..., 0] + ph[..., 1] * qh[..., 1]), axis=1)
    s = np.sum(w * (ph[..., 0] * qh[..., 1] - ph[..., 1] * qh[..., 0]), axis=1)
    norm = np.sqrt(c * c + s * s) + eps
    cos, sin = c / norm, s / norm
    out = np.stack([cos * vp[:, 0] - sin * vp[:, 1], sin * vp[:, 0] + cos * vp[:, 1]], 1)
    del a, b
    return out + q_star


def warp(src, p, q, step=6, alpha=1.6):
    """Warps premultiplied RGBA `src` (SS space) so control points p (rest)
    move to q (posed). p,q in sticker space."""
    if p is None or len(p) == 0:
        return src
    p = np.asarray(p, np.float64) * SS
    q = np.asarray(q, np.float64) * SS
    if np.allclose(p, q):
        return src
    H, W = src.shape[:2]
    xs = np.arange(0, W + step, step, dtype=np.float64)
    ys = np.arange(0, H + step, step, dtype=np.float64)
    gx, gy = np.meshgrid(xs, ys)
    grid = np.stack([gx.ravel(), gy.ravel()], 1)
    # Inverse map: for each output pixel find where it came from (q -> p).
    srcpos = mls_rigid(grid, q, p, alpha=alpha)
    smx = srcpos[:, 0].reshape(gx.shape).astype(np.float32)
    smy = srcpos[:, 1].reshape(gy.shape).astype(np.float32)
    ix = np.tile((np.arange(W, dtype=np.float32) / step)[None, :], (H, 1))
    iy = np.tile((np.arange(H, dtype=np.float32) / step)[:, None], (1, W))
    mx = cv2.remap(smx, ix, iy, cv2.INTER_LINEAR)
    my = cv2.remap(smy, ix, iy, cv2.INTER_LINEAR)
    out = cv2.remap(src, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    # Keep pixels that barely move bit-identical to the source, so frames
    # differ only where Foxy actually moves (small, delta-friendly files).
    disp = np.hypot(mx - np.arange(W, dtype=np.float32)[None, :], my - np.arange(H, dtype=np.float32)[:, None])
    m = np.clip((disp - 0.06) / 0.25, 0, 1)[..., None]
    return src * (1 - m) + out * m


def affine(src, angle=0.0, scale=(1.0, 1.0), translate=(0.0, 0.0), pivot=(160, 304)):
    """Global transform in sticker space about `pivot` (radians, ccw+ is
    screen-clockwise since y points down)."""
    if angle == 0 and scale == (1.0, 1.0) and translate == (0.0, 0.0):
        return src
    px, py = pivot[0] * SS, pivot[1] * SS
    c, s = math.cos(angle), math.sin(angle)
    sx, sy = scale
    m = np.array([[c * sx, -s * sy, 0], [s * sx, c * sy, 0]], np.float64)
    m[:, 2] = np.array([px, py]) - m[:, :2] @ np.array([px, py]) + np.array(translate) * SS
    H, W = src.shape[:2]
    return cv2.warpAffine(src, m, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)


def finish(arr):
    """Premultiplied SS-space float RGBA -> straight-alpha PIL image at SIZE."""
    small = cv2.resize(arr, (SIZE, SIZE), interpolation=cv2.INTER_AREA)
    a = small[..., 3:4]
    rgb = np.where(a > 1e-4, small[..., :3] / np.maximum(a, 1e-4), 0)
    out = np.concatenate([rgb, a], 2)
    return Image.fromarray((out.clip(0, 1) * 255 + 0.5).astype(np.uint8))


# ---------------------------------------------------------------- rig model
def rot(pt, pivot, ang):
    x, y = pt[0] - pivot[0], pt[1] - pivot[1]
    c, s = math.cos(ang), math.sin(ang)
    return (pivot[0] + c * x - s * y, pivot[1] + s * x + c * y)


class Rig:
    """Named control points grouped into bones. Each bone has a pivot and
    an optional parent; a pose is {bone: (angle, dx, dy)}. Unlisted points
    are anchors."""

    def __init__(self, points, bones, anchors):
        self.points = points          # name -> (x, y)
        self.bones = bones            # name -> dict(pivot, parent, pts=[names])
        self.anchors = anchors        # list of (x, y)

    def solve(self, pose, blink=None):
        """Returns (rest, posed) arrays of control points."""
        rest, posed = [], []
        owner = {}
        for b, spec in self.bones.items():
            for n in spec['pts']:
                owner[n] = b

        def chain(b):
            out = []
            while b:
                out.append(b)
                b = self.bones[b].get('parent')
            return out[::-1]  # root first

        def apply(pt, b):
            # Apply child transforms first in the child's frame, then parents.
            for bone in chain(b)[::-1]:
                ang, dx, dy = pose.get(bone, (0.0, 0.0, 0.0))
                pv = self.bones[bone]['pivot']
                pt = rot(pt, pv, ang)
                pt = (pt[0] + dx, pt[1] + dy)
            return pt

        for n, pt in self.points.items():
            rest.append(pt)
            posed.append(apply(pt, owner[n]) if n in owner else pt)
        for pt in self.anchors:
            rest.append(pt)
            posed.append(pt)
        return np.array(rest), np.array(posed)


def ease(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def wave(t, period, phase=0.0):
    return math.sin(2 * math.pi * (t / period + phase))
