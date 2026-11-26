"""Tiny Lottie (Bodymovin 5.7) builder: shape layers, groups, keyframes.

Only what the festival banners need. Everything is plain dicts, so the
output is a standard Lottie JSON that lottie-web and Flutter's `lottie`
package play the same way.
"""

from __future__ import annotations

import json
import math

FPS = 60

# Easings as (out-tangent, in-tangent) handles.
EASE = ((0.42, 0.0), (0.58, 1.0))  # ease in-out
SMOOTH = ((0.33, 0.0), (0.67, 1.0))
OUT = ((0.16, 1.0), (0.3, 1.0))  # fast start, long settle
IN = ((0.55, 0.0), (0.9, 0.6))
LINEAR = ((0.0, 0.0), (1.0, 1.0))


def hex_rgb(h: str, a: float = 1.0) -> list[float]:
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)] + [a]


def static(v):
    return {"a": 0, "k": v}


def anim(keys, ease=EASE, spatial=False):
    """keys: [(frame, value), ...]; value is a number or a list."""
    out = []
    for n, (t, v) in enumerate(keys):
        k = {"t": t, "s": v if isinstance(v, list) else [v]}
        if n < len(keys) - 1:
            (ox, oy), (ix, iy) = ease
            dim = 1 if spatial else len(k["s"])
            if spatial:
                k["o"] = {"x": ox, "y": oy}
                k["i"] = {"x": ix, "y": iy}
            else:
                k["o"] = {"x": [ox] * dim, "y": [oy] * dim}
                k["i"] = {"x": [ix] * dim, "y": [iy] * dim}
        out.append(k)
    return {"a": 1, "k": out}


def prop(v, **kw):
    """A static value, or keyframes when given a list of (t, v) tuples."""
    if isinstance(v, dict) and "a" in v:
        return v
    if isinstance(v, list) and v and isinstance(v[0], tuple):
        return anim(v, **kw)
    return static(v)


def val(v):
    if isinstance(v, dict):
        return v
    if isinstance(v, tuple):
        return static(list(v))
    if isinstance(v, list) and v and isinstance(v[0], tuple):
        return anim(v)
    return static(v)


def tr(p=(0, 0), a=(0, 0), s=(100, 100), r=0, o=100):
    return {"ty": "tr", "p": val(p), "a": val(a), "s": val(s), "r": val(r), "o": val(o),
            "sk": static(0), "sa": static(0)}


def ks(p=(0, 0), a=(0, 0), s=(100, 100), r=0, o=100):
    """Layer transform. p/s/r/o may be keyframe lists."""
    def fix(v, three):  # three: z value to add to 2D tuples (False = scalar)
        if isinstance(v, tuple):
            v = list(v)
            if three is not False and len(v) == 2:
                v.append(three)
            return static(v)
        if isinstance(v, (int, float)):
            return static(v)
        return v  # already a property dict
    return {"o": fix(o, False), "r": fix(r, False), "p": fix(p, 0), "a": fix(a, 0), "s": fix(s, 100)}


# -- shapes ------------------------------------------------------------------------------

def ellipse(w, h, x=0, y=0):
    return {"ty": "el", "d": 1, "p": static([x, y]), "s": prop([w, h]) if not isinstance(w, dict) else w}


def ellipse_anim(size_keys, x=0, y=0):
    return {"ty": "el", "d": 1, "p": static([x, y]), "s": anim(size_keys)}


def rect(w, h, x=0, y=0, r=0):
    return {"ty": "rc", "d": 1, "p": static([x, y]), "s": static([w, h]), "r": static(r)}


def path(points, closed=True, ins=None, outs=None):
    """points: [(x, y)], optional bezier tangents relative to each point."""
    n = len(points)
    return {"ty": "sh", "ks": static({
        "c": closed,
        "v": [list(p) for p in points],
        "i": [list(t) for t in (ins or [(0, 0)] * n)],
        "o": [list(t) for t in (outs or [(0, 0)] * n)],
    })}


def smooth_path(points, closed=True, k=0.33):
    """Catmull-Rom style smooth closed/open path through points."""
    n = len(points)
    ins, outs = [], []
    for i, (x, y) in enumerate(points):
        if not closed and (i == 0 or i == n - 1):
            ins.append((0, 0)); outs.append((0, 0)); continue
        px, py = points[(i - 1) % n]
        nx, ny = points[(i + 1) % n]
        dx, dy = (nx - px) * k / 2, (ny - py) * k / 2
        ins.append((-dx, -dy)); outs.append((dx, dy))
    return path(points, closed, ins, outs)


def fill(color, o=100):
    c = hex_rgb(color) if isinstance(color, str) else color
    return {"ty": "fl", "c": static(c), "o": prop(o), "r": 1}


def stroke(color, w=3, o=100, cap=2):
    c = hex_rgb(color) if isinstance(color, str) else color
    return {"ty": "st", "c": static(c), "o": prop(o), "w": prop(w), "lc": cap, "lj": 2}


def trim(s=0, e=100, o=0):
    return {"ty": "tm", "s": prop(s), "e": prop(e), "o": prop(o), "m": 1}


def group(*items, **t):
    return {"ty": "gr", "it": list(items) + [tr(**t)]}


# -- layers ------------------------------------------------------------------------------

class Comp:
    def __init__(self, name, w=320, h=256, seconds=4.0):
        self.name, self.w, self.h = name, w, h
        self.op = int(round(seconds * FPS))
        self.layers: list[dict] = []

    def layer(self, name, shapes, ks_=None, ip=None, op=None, parent=None):
        lay = {"ddd": 0, "ind": len(self.layers) + 1, "ty": 4, "nm": name, "sr": 1,
               # Shapes are listed back to front here; Lottie draws the first on top.
               "ks": ks_ or ks(), "ao": 0, "shapes": list(reversed(shapes)),
               "ip": 0 if ip is None else ip, "op": self.op if op is None else op, "st": 0, "bm": 0}
        if parent is not None:
            lay["parent"] = parent
        self.layers.append(lay)
        return lay["ind"]

    def null(self, name, ks_):
        lay = {"ddd": 0, "ind": len(self.layers) + 1, "ty": 3, "nm": name, "sr": 1, "ks": ks_,
               "ao": 0, "ip": 0, "op": self.op, "st": 0, "bm": 0}
        self.layers.append(lay)
        return lay["ind"]

    def json(self):
        # Lottie draws the first layer on top; we add back to front, so reverse.
        layers = list(reversed(self.layers))
        return {"v": "5.7.4", "fr": FPS, "ip": 0, "op": self.op, "w": self.w, "h": self.h,
                "nm": self.name, "ddd": 0, "assets": [], "layers": layers, "markers": []}

    def save(self, path):
        with open(path, "w") as f:
            json.dump(self.json(), f, separators=(",", ":"))


# -- motion helpers ----------------------------------------------------------------------

def bob(T, base, amp, phase=0.0, axis=1, cycles=1):
    """Gentle loop up/down (or sideways): seamless over T frames."""
    keys = []
    steps = 4 * cycles
    for i in range(steps + 1):
        t = round(T * i / steps)
        v = list(base)
        v[axis] += amp * math.sin(2 * math.pi * (i / steps * cycles + phase))
        keys.append((t, v + [0] if len(v) == 2 else v))
    return anim(keys, SMOOTH, spatial=True)


def wave(T, base, amp, phase=0.0, cycles=1):
    """A scalar swinging around base (rotation, opacity...), seamless."""
    keys = []
    steps = 4 * cycles
    for i in range(steps + 1):
        keys.append((round(T * i / steps), base + amp * math.sin(2 * math.pi * (i / steps * cycles + phase))))
    return anim(keys, SMOOTH)


def wave_vec(T, base, amp, phase=0.0, cycles=1):
    keys = []
    steps = 4 * cycles
    for i in range(steps + 1):
        f = math.sin(2 * math.pi * (i / steps * cycles + phase))
        keys.append((round(T * i / steps), [b + a * f for b, a in zip(base, amp)]))
    return anim(keys, SMOOTH)


def cycle_keys(T, phase, frames):
    """Shift a list of (fraction, value) keys by phase*T, wrapped into [0, T]."""
    out = []
    shift = phase * T
    for f, v in frames:
        out.append((f * T + shift, v))
    return out
