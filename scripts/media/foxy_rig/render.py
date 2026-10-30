import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(__import__('pathlib').Path(__file__).parent))
import rig  # noqa: E402
import sprites as sp  # noqa: E402
import pack  # noqa: E402
from bases import BASES  # noqa: E402

_src = {}


def source(base):
    if base not in _src:
        kind, name, kw = BASES[base]
        _src[base] = rig.place(rig.load(kind, name), **kw)
    return _src[base]


def render(name, fps=pack.FPS):
    st = pack.STICKERS[name]
    L = getattr(pack, 'L_' + name.upper())
    r, eyes = pack.build(L)
    src = source(st['base'])
    n = max(1, round(st['seconds'] * fps))
    frames = []
    for i in range(n):
        t = i / fps
        f = st['fn'](t)
        rest, posed = r.solve(f['pose'])
        names = list(r.points.keys())
        idx = {nm: j for j, nm in enumerate(names)}
        for k, ex, ey, eh in eyes:
            b = f['blink'] if f['eye_blink'] is None else f['eye_blink'][k]
            if b <= 0:
                continue
            c = posed[idx[f'e{k}c']]
            for part in ('t', 'b'):
                j = idx[f'e{k}{part}']
                posed[j] = c + (posed[j] - c) * (1 - 0.82 * b)
        arr = rig.warp(src, rest, posed)
        g = f['glob']
        if g:
            arr = rig.affine(arr, angle=g.get('angle', 0.0), scale=g.get('scale', (1.0, 1.0)),
                             translate=g.get('translate', (0.0, 0.0)), pivot=g.get('pivot', (160, 304)))
        fox = rig.finish(arr)
        frame = Image.new('RGBA', (rig.SIZE, rig.SIZE), (0, 0, 0, 0))
        for spec in f['back']:
            sp.place_sprite(frame, *spec)
        frame.alpha_composite(fox)
        for spec in f['front']:
            sp.place_sprite(frame, *spec)
        frames.append(frame)
    return frames


def strip(frames, path, n=8, bg=(40, 48, 70, 255), size=200):
    pick = [frames[int(i * len(frames) / n)] for i in range(n)]
    out = Image.new('RGBA', (size * n, size), bg)
    for i, f in enumerate(pick):
        out.alpha_composite(f.resize((size, size), Image.LANCZOS), (i * size, 0))
    out.save(path)


if __name__ == '__main__':
    name = sys.argv[1]
    frames = render(name)
    strip(frames, f'strip_{name}.png')
    print(name, len(frames))
