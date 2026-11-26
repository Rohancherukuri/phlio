"""Festival banner animations for Phlio (original art, Lottie JSON).

Flat vector scenes in a 320 x 256 canvas, drawn to sit on the right of the
festival banner card: a hero illustration with gentle secondary motion
(flicker, sway, bob) and a few ambient particles. Every animation loops
seamlessly over T frames.

    cd scripts/media/festival_lottie && python build.py ../../../frontend/ui/assets/lottie/festival
"""

from __future__ import annotations

import math
import random
import sys

from lot import (EASE, IN, LINEAR, OUT, SMOOTH, Comp, anim, bob, ellipse, ellipse_anim, fill, group, hex_rgb, ks,
                 path, rect, smooth_path, static, stroke, trim, tr, wave, wave_vec)

W, H = 320, 256


# -- shared pieces ------------------------------------------------------------------------

def looping(c: Comp, name, shapes, T, phase, keys_for, parent=None):
    """A particle on a T-frame cycle starting at phase*T; two copies make the
    wrap seamless. keys_for(t0) returns the layer transform for one cycle."""
    t0 = phase * T
    for start in (t0 - T, t0):
        ip, op = max(0, int(math.floor(start))), min(c.op, int(math.ceil(start + T)))
        if op <= ip:
            continue
        c.layer(name, shapes, keys_for(start), ip=ip, op=op, parent=parent)


def fall(c, T, n, shapes_for, seed, x0=0, x1=W, y0=-20, y1=H + 20, drift=30, spin=180, cycles=1, scale=(60, 110)):
    rnd = random.Random(seed)
    for i in range(n):
        x = rnd.uniform(x0, x1)
        dx = rnd.uniform(-drift, drift)
        s = rnd.uniform(*scale)
        r0 = rnd.uniform(0, 360)
        sp = rnd.choice([-1, 1]) * rnd.uniform(spin * .5, spin)
        dur = T / cycles

        def keys(t, x=x, dx=dx, s=s, r0=r0, sp=sp, dur=dur):
            return ks(p=anim([(t, [x, y0, 0]), (t + dur * .5, [x + dx, (y0 + y1) / 2, 0]), (t + dur, [x, y1, 0])],
                             LINEAR, spatial=True),
                      r=anim([(t, r0), (t + dur, r0 + sp)], LINEAR), s=(s, s, 100))
        for k in range(cycles):
            looping(c, f"fall{i}", shapes_for(i, rnd), T, (rnd.random() + k) / cycles % 1, keys)


def rise(c, T, n, shapes_for, seed, x0, x1, y0, y1, drift=14, scale=(60, 110)):
    rnd = random.Random(seed)
    for i in range(n):
        x = rnd.uniform(x0, x1)
        dx = rnd.uniform(-drift, drift)
        s = rnd.uniform(*scale)

        def keys(t, x=x, dx=dx, s=s):
            return ks(p=anim([(t, [x, y0, 0]), (t + T * .5, [x + dx, (y0 + y1) / 2, 0]), (t + T, [x - dx * .3, y1, 0])],
                             SMOOTH, spatial=True),
                      o=anim([(t, 0), (t + T * .15, 100), (t + T * .7, 80), (t + T, 0)], LINEAR),
                      s=anim([(t, [s, s, 100]), (t + T, [s * .55, s * .55, 100])], LINEAR))
        looping(c, f"rise{i}", shapes_for(i, rnd), T, rnd.random(), keys)


def twinkle(c, T, spots, color="#FFFFFF", size=10, seed=1):
    """Four-point sparkles that pop in and out at fixed spots."""
    rnd = random.Random(seed)
    for i, (x, y) in enumerate(spots):
        s = size * rnd.uniform(.6, 1.2)
        ph = rnd.random()
        t0 = ph * T
        keys = [(t0 - T, 0), (t0 - T * .8, 100), (t0 - T * .6, 0), (t0, 0), (t0 + T * .2, 100), (t0 + T * .4, 0)]
        c.layer(f"spark{i}", [group(star4(s), fill(color))],
                ks(p=(x, y), s=anim([(t, [v, v, 100]) for t, v in keys], EASE), r=anim([(0, 0), (T, 90)], LINEAR)))


def star4(r):
    k = r * .18
    pts = [(0, -r), (k, -k), (r, 0), (k, k), (0, r), (-k, k), (-r, 0), (-k, -k)]
    return path(pts)


def star5(r, inner=.45):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * inner
        pts.append((rr * math.cos(a), rr * math.sin(a)))
    return path(pts)


def heart(s):
    """A rounded heart about 2s wide, point at the bottom."""
    k = s / 10
    v = [(12, 21.35), (10.55, 20.03), (2, 8.5), (7.5, 3), (12, 5.09), (16.5, 3), (22, 8.5), (13.45, 20.04)]
    ins = [(0, 0), (0, 0), (0, 3.78), (-3.08, 0), (-1.09, -1.28), (-1.74, 0), (0, -3.08), (5.15, -4.68)]
    outs = [(0, 0), (-5.15, -4.67), (0, -3.08), (1.74, 0), (1.09, -1.28), (3.08, 0), (0, 3.78), (0, 0)]
    return path([((x - 12) * k, (y - 12) * k) for x, y in v],
                ins=[(x * k, y * k) for x, y in ins], outs=[(x * k, y * k) for x, y in outs])


def flame(w, h):
    # Teardrop: sharp tip up, round base at (0, 0).
    return path([(0, -h), (w, -h * .18), (0, h * .32), (-w, -h * .18)],
                ins=[(w * .2, h * .2), (0, -h * .38), (w * .62, 0), (0, h * .32)],
                outs=[(-w * .2, h * .2), (0, h * .32), (-w * .62, 0), (0, -h * .38)])


def drop(w, h):
    return flame(w, h)


def leaf(s):
    return path([(0, -s), (s * .5, 0), (0, s), (-s * .5, 0)],
                ins=[(-s * .3, 0), (0, -s * .55), (s * .3, 0), (0, s * .55)],
                outs=[(s * .3, 0), (0, s * .55), (-s * .3, 0), (0, -s * .55)])


def flicker(T, base=100, amp=7, n=8, seed=0):
    rnd = random.Random(seed)
    vals = [base + rnd.uniform(-amp, amp) for _ in range(n)]
    vals.append(vals[0])
    return anim([(round(T * i / n), [v * .97, v * 1.03, 100]) for i, v in enumerate(vals)], SMOOTH)


def backdrop(c, color="#FFFFFF", o=9, r=118, x=W * .55, y=H * .52):
    """A quiet flat disc behind the hero, so it reads on any card colour."""
    c.layer("backdrop", [group(ellipse(r * 2, r * 2), fill(color, o))], ks(p=(x, y)))


# -- motifs --------------------------------------------------------------------------------

def diyas():
    T = 240
    c = Comp("Diyas", seconds=T / 60)
    backdrop(c, "#FFD27A", 10)
    # Slowly turning rangoli ring.
    petals = [group(ellipse(14, 30, 0, -92), fill("#FFD27A", 22), r=a) for a in range(0, 360, 30)]
    dots = [group(ellipse(6, 6, 0, -66), fill("#FFF1C1", 30), r=a + 15) for a in range(0, 360, 30)]
    c.layer("rangoli", petals + dots, ks(p=(W * .55, H * .52), r=anim([(0, 0), (T, 30)], LINEAR)))
    rise(c, T, 14, lambda i, r: [group(ellipse(5, 5), fill(r.choice(["#FFD27A", "#FFF1C1", "#FFB347"])))],
         seed=3, x0=80, x1=300, y0=190, y1=30)
    for i, (x, y, s) in enumerate([(106, 192, .78), (226, 188, .78), (160, 210, 1.0)]):
        base = (x, y)
        # The flame sits on the spout tip.
        c.layer(f"flame{i}", [
            group(flame(12, 36), fill("#FFB703")),
            group(flame(6.5, 21), fill("#FFF1C1"), p=(0, 3)),
        ], ks(p=(x + 46 * s, y - 20 * s), s=flicker(T, 100 * s, 9, seed=i), r=wave(T, 0, 5, phase=i * .3, cycles=4)))
        c.layer(f"diya{i}", [
            group(
                path([(-50, -6), (38, -6), (52, -18), (34, 12), (0, 24), (-38, 14)],
                     ins=[(-2, 12), (-10, 0), (0, 0), (8, -10), (16, 0), (-6, 4)],
                     outs=[(10, 0), (6, 0), (-4, 14), (-12, 10), (-18, 0), (-10, -8)]),
                fill("#D2603F")),
            group(path([(-44, 6), (40, 2), (34, 12), (0, 24), (-38, 14)],
                       ins=[(0, 0), (0, 0), (8, -10), (16, 0), (-6, 4)], outs=[(0, 0), (-2, 6), (-12, 10), (-18, 0), (0, 0)]),
                  fill("#A8432D")),
            group(path([(-50, -6), (38, -6)], closed=False, ins=[(0, 0), (-20, -6)], outs=[(20, -6), (0, 0)]),
                  stroke("#F2B07A", 4)),
            group(ellipse(80, 10, -8, -7), fill("#7A2E21")),  # oil
            group(ellipse(6, 6, -22, 6), fill("#FFD27A")), group(ellipse(6, 6, -6, 9), fill("#FFD27A")),
            group(ellipse(6, 6, 10, 8), fill("#FFD27A")),
        ], ks(p=base, s=(100 * s, 100 * s)))
    return c


def lanterns():
    T = 240
    c = Comp("Lanterns", seconds=T / 60)
    backdrop(c, "#FFD27A", 9)
    twinkle(c, T, [(70, 60), (290, 40), (250, 170), (90, 200), (300, 120)], "#FFE29A", 9, seed=4)
    for i, (x, length, s, ph) in enumerate([(96, 64, .74, 0), (182, 30, 1.0, .35), (272, 84, .7, .7)]):
        pivot = c.null(f"pivot{i}", ks(p=(x, 0), r=wave(T, 0, 5, phase=ph)))
        body_y = length + 44 * s
        c.layer(f"lantern{i}", [
            group(path([(0, 0), (0, length)], closed=False), stroke("#F4B942", 2)),
            group(rect(30 * s, 10 * s, 0, length + 5 * s, 3), fill("#F4B942")),
            group(ellipse(96 * s, 78 * s, 0, body_y), fill("#FF4D4D")),
            group(ellipse(60 * s, 78 * s, 0, body_y), stroke("#A4161A", 3), fill("#E63946", 0)),
            group(ellipse(24 * s, 78 * s, 0, body_y), stroke("#A4161A", 3), fill("#E63946", 0)),
            group(ellipse(50 * s, 50 * s, 0, body_y), fill("#FFB38A", 45)),
            group(rect(30 * s, 10 * s, 0, body_y + 39 * s + 4 * s, 3), fill("#F4B942")),
            group(path([(0, body_y + 48 * s), (0, body_y + 80 * s)], closed=False), stroke("#F4B942", 3 * s)),
            group(path([(-6 * s, body_y + 50 * s), (-8 * s, body_y + 78 * s)], closed=False), stroke("#F4B942", 2 * s)),
            group(path([(6 * s, body_y + 50 * s), (8 * s, body_y + 78 * s)], closed=False), stroke("#F4B942", 2 * s)),
        ], ks(), parent=pivot)
    return c


def _crescent(R, cut, dx):
    pts = []
    n = 28
    # Outer arc from top to bottom on the left, inner arc back.
    a0 = math.acos(max(-1, min(1, (R * R - cut * cut + dx * dx) / (2 * dx * R))))
    for i in range(n + 1):
        a = a0 + (2 * math.pi - 2 * a0) * i / n
        pts.append((R * math.cos(a), R * math.sin(a)))
    b0 = math.atan2(pts[-1][1], pts[-1][0] - dx)
    b1 = math.atan2(pts[0][1], pts[0][0] - dx)
    if b1 < b0:
        b1 += 2 * math.pi
    for i in range(1, n):
        b = b0 - (b0 - (b1 - 2 * math.pi)) * i / n
        pts.append((dx + cut * math.cos(b), cut * math.sin(b)))
    return smooth_path(pts, k=.33)


def crescent():
    T = 240
    c = Comp("Crescent", seconds=T / 60)
    backdrop(c, "#FFE29A", 9)
    twinkle(c, T, [(78, 70), (120, 30), (300, 60), (285, 205), (95, 190), (230, 28)], "#FFE29A", 9, seed=7)
    c.layer("moon", [group(_crescent(62, 54, 30), fill("#FFE29A"), r=-25)],
            ks(p=bob(T, (150, 112), 5), s=(100, 100)))
    c.layer("star", [group(star5(13), fill("#FFF4CC"))],
            ks(p=(196, 96), s=wave_vec(T, [100, 100, 100], [14, 14, 0], cycles=2), r=wave(T, 0, 10)))
    pivot = c.null("fanous", ks(p=(262, 0), r=wave(T, 0, 6, phase=.25)))
    c.layer("fanous", [
        group(path([(0, 0), (0, 70)], closed=False), stroke("#F4C95D", 2)),
        group(ellipse(14, 14, 0, 74), stroke("#F4C95D", 3), fill("#000000", 0)),
        group(path([(-10, 84), (10, 84), (24, 104), (-24, 104)]), fill("#F4C95D")),
        group(path([(-24, 104), (24, 104), (20, 150), (-20, 150)]), fill("#D9A441")),
        group(path([(-14, 110), (14, 110), (12, 144), (-12, 144)]), fill("#FFE8A3", 80)),
        group(path([(-20, 150), (20, 150), (10, 162), (-10, 162)]), fill("#F4C95D")),
        group(path([(0, 162), (0, 176)], closed=False), stroke("#F4C95D", 3)),
    ], ks(), parent=pivot)
    c.layer("fanous_glow", [group(ellipse(20, 26, 0, 127), fill("#FFF4CC", 60))],
            ks(o=wave(T, 70, 30, cycles=3)), parent=pivot)
    return c


def snow():
    T = 300
    c = Comp("Snow", seconds=T / 60)
    backdrop(c, "#FFFFFF", 8)
    fall(c, T, 26, lambda i, r: [group(ellipse(7, 7), fill("#FFFFFF", r.uniform(55, 95)))], seed=11, drift=24,
         spin=0, scale=(50, 120))
    tree = []
    for (w, top, bottom, col, side) in [(150, 120, 206, "#2F8F5B", "#24724A"), (116, 82, 160, "#3AA36B", "#2F8F5B"),
                                        (80, 46, 112, "#4DBB7E", "#3AA36B")]:
        tree.append(group(path([(0, top - (bottom - top) * .25), (w / 2, bottom), (-w / 2, bottom)],
                               ins=[(0, 0), (0, 0), (w * .3, 8)], outs=[(0, 0), (-w * .3, 8), (0, 0)]),
                          fill(col)))
        tree.append(group(path([(0, top - (bottom - top) * .25), (w / 2, bottom), (6, bottom + 2)]), fill(side, 70)))
    c.layer("trunk", [group(rect(22, 24, 0, 218, 4), fill("#8A5A3B"))], ks(p=(176, 0)))
    c.layer("tree", tree, ks(p=(176, 0)))
    rnd = random.Random(5)
    for i, (x, y) in enumerate([(-30, 190), (28, 186), (-16, 150), (18, 132), (-4, 104), (40, 200), (-48, 200),
                                (6, 168)]):
        col = ["#E63946", "#F4B942", "#FFFFFF", "#72A7FF"][i % 4]
        ph = rnd.random()
        c.layer(f"ball{i}", [group(ellipse(11, 11), fill(col))],
                ks(p=(176 + x, y), o=wave(T, 80, 20, phase=ph, cycles=3)))
    c.layer("star", [group(star5(16), fill("#F4B942"))],
            ks(p=(176, 26), s=wave_vec(T, [100, 100, 100], [8, 8, 0], cycles=2), r=wave(T, 0, 8, cycles=1)))
    return c


def fireworks():
    T = 240
    c = Comp("Fireworks", seconds=T / 60)
    backdrop(c, "#FFFFFF", 7)
    bursts = [(168, 104, "#FFD166", 0.0, 58), (258, 84, "#FF7EB6", .33, 46), (212, 156, "#7FDBFF", .66, 42)]
    for b, (x, y, col, ph, R) in enumerate(bursts):
        t0 = ph * T
        rnd = random.Random(b)
        for start in (t0 - T, t0):
            # Rocket: a short streak climbing, then the burst.
            c.layer(f"trail{b}", [group(path([(x - 6, H + 10), (x, y + 6)], closed=False), stroke(col, 3),
                                        trim(s=anim([(start, 0), (start + 30, 70), (start + 42, 100)], OUT),
                                             e=anim([(start, 0), (start + 34, 100)], OUT)))],
                    ks(), ip=max(0, int(start)), op=min(c.op, int(start + 44)))
            rays = [group(ellipse_anim([(start + 34, [4, 4]), (start + 44, [30, 30]), (start + 56, [0, 0])]),
                          fill("#FFFFFF", 90))]
            n = 14
            for k in range(n):
                a = 2 * math.pi * (k + rnd.uniform(-.2, .2)) / n
                L = R * rnd.uniform(.72, 1.0)
                x1, y1 = R * .18 * math.cos(a), R * .18 * math.sin(a)
                x2, y2 = L * math.cos(a), L * math.sin(a)
                c2 = col if k % 3 else "#FFFFFF"
                rays.append(group(path([(x1, y1), (x2, y2)], closed=False), stroke(c2, 3.4),
                                  trim(s=anim([(start + 50, 0), (start + 104, 100)], OUT),
                                       e=anim([(start + 34, 0), (start + 70, 100)], OUT))))
                # Embers drift down as they fade.
                ex, ey = L * 1.14 * math.cos(a), L * 1.14 * math.sin(a)
                rays.append(group(ellipse(4.5, 4.5), fill(c2),
                                  p=anim([(start + 62, [ex, ey]), (start + 130, [ex * 1.08, ey + 22])], OUT),
                                  o=anim([(start + 60, 0), (start + 70, 100), (start + 130, 0)], EASE)))
            c.layer(f"burst{b}", rays, ks(p=(x, y), s=anim([(start + 34, [76, 76, 100]), (start + 120, [104, 104, 100])], OUT)),
                    ip=max(0, int(start + 33)), op=min(c.op, int(start + 132)))
    twinkle(c, T, [(80, 50), (300, 120), (110, 200), (290, 30)], "#FFFFFF", 7, seed=9)
    return c


def hearts():
    T = 180
    c = Comp("Hearts", seconds=T / 60)
    backdrop(c, "#FFFFFF", 9)
    rise(c, T, 12, lambda i, r: [group(heart(r.uniform(7, 11)), fill(r.choice(["#FFFFFF", "#FFC2D1", "#FF8FAB"])))],
         seed=13, x0=70, x1=300, y0=230, y1=20, drift=20)
    beat = [(0, 100), (12, 113), (22, 100), (32, 109), (46, 100), (T, 100)]
    c.layer("heart", [
        group(heart(58), fill("#E03157"), p=(0, 5)),
        group(heart(58), fill("#FF4D6D")),
        group(path([(-38, -34), (-26, -46), (-12, -48)], closed=False, ins=[(0, 0), (-6, 4), (0, 0)],
                   outs=[(4, -6), (6, -2), (0, 0)]), stroke("#FFFFFF", 7), o=75),
    ], ks(p=(180, 128), s=anim([(t, [v, v, 100]) for t, v in beat], EASE), r=wave(T, -6, 3)))
    c.layer("heart2", [group(heart(26), fill("#FF8FAB"))],
            ks(p=bob(T, (250, 74), 6, phase=.3), r=wave(T, 14, 6)))
    c.layer("heart3", [group(heart(18), fill("#FFC2D1"))],
            ks(p=bob(T, (110, 70), 5, phase=.7), r=wave(T, -16, 6)))
    return c


def petals():
    T = 300
    c = Comp("Petals", seconds=T / 60)
    backdrop(c, "#FFFFFF", 9)
    fall(c, T, 14, lambda i, r: [group(leaf(r.uniform(7, 10)), fill(r.choice(["#FF8FAB", "#FFC2D1", "#FFB703"])))],
         seed=17, drift=40, spin=260)
    flower = []
    for k in range(10):
        flower.append(group(ellipse(46, 66, 0, -38), fill("#E85D88" if k % 2 else "#FB6F92"), r=k * 36))
    for k in range(10):
        flower.append(group(ellipse(30, 44, 0, -24), fill("#FFC2D1"), r=k * 36 + 18))
    flower.append(group(ellipse(34, 34), fill("#FFB703")))
    flower.append(group(ellipse(16, 16, -4, -4), fill("#FFD166")))
    c.layer("flower", flower, ks(p=(186, 124), r=anim([(0, 0), (T, 36)], LINEAR),
                                 s=wave_vec(T, [100, 100, 100], [4, 4, 0], cycles=2)))
    c.layer("bud", [group(ellipse(14, 30, 0, -16), fill("#FB6F92"), r=r) for r in (-30, 0, 30)] +
            [group(ellipse(12, 12), fill("#FFB703"))],
            ks(p=bob(T, (268, 70), 5), s=(80, 80), r=wave(T, 0, 10)))
    return c


def kites():
    T = 240
    c = Comp("Kites", seconds=T / 60)
    backdrop(c, "#FFFFFF", 8)
    for i, (y, w, ph) in enumerate([(56, 90, 0), (200, 70, .5)]):
        def cloud(x0, y0, w=w):
            return [group(rect(w, 26, x0, y0, 13), fill("#FFFFFF", 85)),
                    group(ellipse(w * .45, w * .45, x0 - w * .12, y0 - 10), fill("#FFFFFF", 85))]
        c.layer(f"cloud{i}", cloud(0, 0), ks(p=wave_vec(T, [80 + i * 170, y, 0], [16, 0, 0], phase=ph)))
    for i, (x, y, s, cols, ph) in enumerate([(170, 96, 1.0, ("#FF6B35", "#FFD166"), 0),
                                             (262, 70, .7, ("#3F88C5", "#7FDBFF"), .4)]):
        a, b = cols
        tail_a = [(0, 52), (10, 76), (-6, 100), (8, 124), (0, 146)]
        tail_b = [(0, 52), (-10, 76), (6, 100), (-8, 124), (2, 146)]

        def tail_shape(pts):
            return {"c": False, "v": [list(p) for p in pts], "i": [[0, -8]] * len(pts), "o": [[0, 8]] * len(pts)}
        tail = {"ty": "sh", "ks": anim([(0, [tail_shape(tail_a)]), (T / 2, [tail_shape(tail_b)]), (T, [tail_shape(tail_a)])],
                                       SMOOTH)}
        for k in tail["ks"]["k"]:
            k["s"] = k["s"]  # shape keyframes keep a one-item list
        c.layer(f"kite{i}", [
            group(tail, stroke("#FFFFFF", 2.2), fill("#000000", 0)),
            group(path([(-8, 84), (8, 84), (0, 92)]), fill(b)),
            group(path([(-8, 118), (8, 118), (0, 126)]), fill(a)),
            group(path([(0, -52), (40, 0), (0, 52), (-40, 0)]), fill(a)),
            group(path([(0, -52), (40, 0), (0, 0)]), fill(b)),
            group(path([(0, 52), (-40, 0), (0, 0)]), fill(b)),
            group(path([(0, -52), (0, 52)], closed=False), stroke("#FFFFFF", 2, o=70)),
            group(path([(-40, 0), (40, 0)], closed=False), stroke("#FFFFFF", 2, o=70)),
        ], ks(p=bob(T, (x, y), 9, phase=ph), s=(70 * s, 70 * s), r=wave(T, 8, 6, phase=ph)))
    return c


def _blob(r, seed, n=9, j=.28):
    rnd = random.Random(seed)
    pts = [(r * (1 + rnd.uniform(-j, j)) * math.cos(2 * math.pi * k / n), r * (1 + rnd.uniform(-j, j)) * math.sin(2 * math.pi * k / n))
           for k in range(n)]
    return smooth_path(pts, k=.55)


def colors():
    T = 240
    c = Comp("Colors", seconds=T / 60)
    palette = ["#FF4D6D", "#FFD166", "#06D6A0", "#4D96FF", "#B15EFF", "#FF8C42"]
    spots = [(120, 90), (230, 70), (190, 170), (280, 150), (95, 190), (160, 120), (260, 220)]
    for i, (x, y) in enumerate(spots):
        col = palette[i % len(palette)]
        t0 = i / len(spots) * T
        for start in (t0 - T, t0):
            c.layer(f"puff{i}", [group(_blob(34 + (i % 3) * 8, i), fill(col, 85)),
                                 group(_blob(14, i + 40), fill(col), p=(30, -26)),
                                 group(ellipse(9, 9, -36, 22), fill(col))],
                    ks(p=(x, y), s=anim([(start, [10, 10, 100]), (start + 50, [100, 100, 100]), (start + 150, [112, 112, 100])], OUT),
                       o=anim([(start, 0), (start + 14, 100), (start + 110, 100), (start + 160, 0)], EASE),
                       r=anim([(start, 0), (start + 160, 25)], LINEAR)),
                    ip=max(0, int(start)), op=min(c.op, int(start + 162)))
    return c


def splash():
    T = 200
    c = Comp("Splash", seconds=T / 60)
    backdrop(c, "#FFFFFF", 9)
    for i, (x, ph) in enumerate([(120, 0), (232, .2), (176, .4), (270, .6), (148, .8)]):
        t0 = ph * T
        for start in (t0 - T, t0):
            c.layer(f"drop{i}", [group(drop(15, 38), fill("#9BE7FF")), group(drop(5, 13), fill("#FFFFFF", 85), p=(-5, -6))],
                    ks(p=anim([(start, [x, -40, 0]), (start + 60, [x, 186, 0])], ((0.4, 0.0), (1.0, 1.0)), spatial=True),
                       s=anim([(start, [100, 100, 100]), (start + 56, [90, 115, 100]), (start + 62, [140, 40, 100])], EASE)),
                    ip=max(0, int(start)), op=min(c.op, int(start + 62)))
            for k, d in enumerate((0, 14)):
                c.layer(f"ripple{i}{k}", [group(ellipse(60, 16), stroke("#FFFFFF", 3), fill("#000000", 0))],
                        ks(p=(x, 192), s=anim([(start + 60 + d, [10, 10, 100]), (start + 130 + d, [120, 120, 100])], OUT),
                           o=anim([(start + 60 + d, 100), (start + 130 + d, 0)], EASE)),
                        ip=max(0, int(start + 60 + d)), op=min(c.op, int(start + 131 + d)))
            for k, (dx, dy) in enumerate([(-22, -34), (20, -40), (-8, -52)]):
                c.layer(f"spray{i}{k}", [group(ellipse(7, 7), fill("#BDEBFF"))],
                        ks(p=anim([(start + 60, [x, 186, 0]), (start + 74, [x + dx, 186 + dy, 0]), (start + 92, [x + dx * 1.4, 196, 0])],
                                  EASE, spatial=True),
                           o=anim([(start + 60, 100), (start + 92, 0)], LINEAR)),
                        ip=max(0, int(start + 60)), op=min(c.op, int(start + 93)))
    c.layer("pool", [group(ellipse(240, 26), fill("#7FDBFF", 35))], ks(p=(200, 196)))
    return c


def leaves():
    T = 300
    c = Comp("Leaves", seconds=T / 60)
    backdrop(c, "#FFFFFF", 8)
    fall(c, T, 14, lambda i, r: [group(leaf(r.uniform(10, 14)), fill(r.choice(["#FF8C42", "#F4B942", "#E4572E", "#A1C181"])),
                                       group(path([(0, -10), (0, 10)], closed=False), stroke("#7A3E1D", 1.4, o=60)))],
         seed=21, drift=50, spin=300)
    big = [group(leaf(70), fill("#FF8C42")), group(path([(0, -70), (0, 0), (-35, 0)]), fill("#E4572E", 70)),
           group(path([(0, -62), (0, 74)], closed=False), stroke("#7A3E1D", 3))]
    for k, (y, d) in enumerate([(-30, 1), (0, -1), (26, 1)]):
        big.append(group(path([(0, y), (24 * d, y - 18)], closed=False), stroke("#7A3E1D", 2.2)))
    c.layer("leaf", big, ks(p=bob(T, (196, 120), 7), r=wave(T, -18, 8), s=(90, 90)))
    return c


def bats():
    T = 240
    c = Comp("Halloween", seconds=T / 60)
    backdrop(c, "#FF7518", 8)
    c.layer("moon", [group(ellipse(110, 110), fill("#FFE29A")), group(ellipse(22, 22, -20, -14), fill("#F4D27A")),
                     group(ellipse(14, 14, 22, 18), fill("#F4D27A"))], ks(p=(244, 70)))
    for i, (y, sc, ph) in enumerate([(66, 1.0, 0), (96, .7, .45), (44, .6, .75)]):
        wing = path([(0, 0), (-30, -14), (-22, -2), (-14, 4)], ins=[(0, 0), (8, -6), (0, 0), (0, 0)],
                    outs=[(-10, -10), (0, 0), (0, 0), (0, 0)])
        t0 = ph * T
        for start in (t0 - T, t0):
            c.layer(f"bat{i}", [
                group(wing, fill("#1A1A2E"), s=anim([(start + k * 10, [100, 100 if k % 2 == 0 else -40]) for k in range(int(T / 10) + 1)], EASE)),
                group(wing, fill("#1A1A2E"), s=anim([(start + k * 10, [-100, 100 if k % 2 == 0 else -40]) for k in range(int(T / 10) + 1)], EASE)),
                group(ellipse(12, 14), fill("#1A1A2E")),
            ], ks(p=anim([(start, [-30, y + 20, 0]), (start + T * .5, [W / 2, y - 10, 0]), (start + T, [W + 30, y + 14, 0])],
                         SMOOTH, spatial=True), s=(100 * sc, 100 * sc)),
                ip=max(0, int(start)), op=min(c.op, int(start + T)))
    pumpkin = [group(rect(10, 22, 0, -66, 4), fill("#4C7A34"), r=8)]
    for x, w, col in [(-34, 62, "#E05E00"), (34, 62, "#E05E00"), (-16, 64, "#FF7518"), (16, 64, "#FF7518"), (0, 56, "#FF8C2E")]:
        pumpkin.append(group(ellipse(w, 108, x, 0), fill(col)))
    face = "#FFD166"
    face_o = wave(T, 85, 15, cycles=6)
    pumpkin += [group(path([(-28, -16), (-12, -16), (-20, -32)]), fill(face, face_o)),
                group(path([(12, -16), (28, -16), (20, -32)]), fill(face, face_o)),
                group(path([(-34, 10), (34, 10), (26, 26), (12, 20), (0, 30), (-12, 20), (-26, 26)]), fill(face, face_o))]
    c.layer("pumpkin", pumpkin, ks(p=bob(T, (170, 178), 3), s=(104, 96)))
    return c


def confetti():
    T = 240
    c = Comp("Confetti", seconds=T / 60)
    backdrop(c, "#FFFFFF", 8)
    cols = ["#FFD166", "#FF4D6D", "#06D6A0", "#4D96FF", "#FFFFFF", "#B15EFF"]
    fall(c, T, 24, lambda i, r: [group(rect(10, 5) if i % 3 else ellipse(7, 7), fill(r.choice(cols)))],
         seed=31, drift=30, spin=540)
    # Gift box: lid pops, ribbon.
    box = [group(rect(120, 86, 0, 30, 8), fill("#4D96FF")), group(rect(120, 20, 0, -4, 0), fill("#3A7BE0", 60)),
           group(rect(22, 86, 0, 30, 0), fill("#FFD166"))]
    c.layer("box", box, ks(p=(186, 170)))
    lid = [group(rect(136, 28, 0, 0, 8), fill("#5BA4FF")), group(rect(24, 28, 0, 0, 0), fill("#FFD166")),
           group(ellipse(30, 22, -16, -18), stroke("#FFD166", 7), fill("#000000", 0), r=-25),
           group(ellipse(30, 22, 16, -18), stroke("#FFD166", 7), fill("#000000", 0), r=25)]
    pop = [(0, [186, 134, 0]), (90, [186, 134, 0]), (104, [186, 104, 0]), (120, [186, 112, 0]), (190, [186, 112, 0]),
           (206, [186, 134, 0]), (T, [186, 134, 0])]
    c.layer("lid", lid, ks(p=anim(pop, EASE, spatial=True),
                           r=anim([(0, 0), (90, 0), (104, -8), (120, -5), (190, -5), (206, 0), (T, 0)], EASE)))
    return c


def candles():
    T = 240
    c = Comp("Menorah", seconds=T / 60)
    backdrop(c, "#FFFFFF", 9)
    gold, deep = "#F4C95D", "#D9A441"
    meno = [group(rect(14, 60, 0, 196, 4), fill(gold)), group(rect(90, 12, 0, 228, 6), fill(deep))]
    for k in range(1, 5):
        r = k * 26
        meno.append(group(path([(-r, 132), (r, 132)], closed=False, ins=[(0, 0), (r * .2, r * .9)],
                               outs=[(-r * .2, r * .9), (0, 0)]), stroke(gold, 6), fill("#000000", 0)))
    c.layer("menorah", meno, ks(p=(186, 0)))
    for k in range(-4, 5):
        x = 186 + k * 26
        top = 106 if k == 0 else 116
        c.layer(f"candle{k}", [group(rect(10, 28, 0, top + 14, 3), fill("#72A7FF" if k else "#FFFFFF"))], ks(p=(x, 0)))
        c.layer(f"flame{k}", [group(flame(6, 16), fill("#FFB703")), group(flame(3, 9), fill("#FFF1C1"))],
                ks(p=(x, top - 2), s=flicker(T, 100, 10, seed=k + 9), r=wave(T, 0, 5, phase=(k + 4) / 9, cycles=3)))
    twinkle(c, T, [(70, 60), (300, 50), (290, 200), (80, 190)], "#FFFFFF", 8, seed=12)
    return c


def rainbow():
    T = 240
    c = Comp("Rainbow", seconds=T / 60)
    backdrop(c, "#FFFFFF", 8)
    for k, col in enumerate(["#FF4D6D", "#FF8C42", "#FFD166", "#06D6A0", "#4D96FF", "#B15EFF"]):
        r = 104 - k * 12
        arc = path([(-r, 0), (0, -r), (r, 0)], closed=False,
                   ins=[(0, 0), (-r * .552, 0), (0, -r * .552)], outs=[(0, -r * .552), (r * .552, 0), (0, 0)])
        d = k * 6
        c.layer(f"arc{k}", [group(arc, stroke(col, 11, cap=1),
                                  trim(e=anim([(0 + d, 0), (60 + d, 100), (180, 100), (225, 0), (T, 0)], EASE),
                                       s=anim([(0, 0), (180, 0), (225 - d * .5, 0), (T, 0)], EASE)))],
                ks(p=(186, 190)))
    for i, (x, y) in enumerate([(92, 196), (272, 196)]):
        c.layer(f"cloud{i}", [group(ellipse(56, 40, -18, 0), fill("#FFFFFF")), group(ellipse(64, 50, 12, -10), fill("#FFFFFF")),
                              group(rect(90, 24, 0, 10, 12), fill("#FFFFFF"))],
                ks(p=bob(T, (x, y), 4, phase=i * .5)))
    twinkle(c, T, [(120, 50), (250, 40), (186, 24)], "#FFFFFF", 9, seed=19)
    return c


def sparkles():
    T = 240
    c = Comp("Sparkles", seconds=T / 60)
    backdrop(c, "#FFFFFF", 9)
    c.layer("orbit", [group(ellipse(8, 8, 74, 0), fill("#FFFFFF", 80)), group(ellipse(6, 6, -74, 0), fill("#FFE29A")),
                      group(ellipse(5, 5, 0, 74), fill("#FFFFFF", 60))],
            ks(p=(186, 126), r=anim([(0, 0), (T, 360)], LINEAR)))
    c.layer("big", [group(star4(52), fill("#FFFFFF")), group(star4(22), fill("#FFE29A"), r=45)],
            ks(p=(186, 126), s=wave_vec(T, [100, 100, 100], [10, 10, 0], cycles=2), r=wave(T, 0, 8)))
    twinkle(c, T, [(110, 70), (262, 60), (270, 190), (120, 196), (300, 120), (80, 130), (220, 30)], "#FFFFFF", 12, seed=23)
    return c


def sale():
    T = 240
    c = Comp("Sale", seconds=T / 60)
    backdrop(c, "#FFFFFF", 8)
    cols = ["#FFD166", "#FF4D6D", "#FFFFFF"]
    fall(c, T, 14, lambda i, r: [group(rect(9, 4) if i % 2 else ellipse(6, 6), fill(r.choice(cols)))],
         seed=41, drift=24, spin=420)
    bag = [group(path([(-28, -36), (0, -74), (28, -36)], closed=False,
                      ins=[(0, 0), (-18, 0), (0, -20)], outs=[(0, -20), (18, 0), (0, 0)]),
                 stroke("#FF8FAB", 7), fill("#000000", 0)),
           group(path([(-56, -40), (56, -40), (64, 66), (-64, 66)]), fill("#FF4D6D")),
           group(path([(-56, -40), (56, -40), (58, -18), (-58, -18)]), fill("#E03157")),
           group(ellipse(8, 8, -30, -30), fill("#1A1A2E")), group(ellipse(8, 8, 30, -30), fill("#1A1A2E"))]
    c.layer("bag", bag, ks(p=bob(T, (176, 150), 5), r=wave(T, 0, 2)))
    pivot = c.null("tagpivot", ks(p=(234, 98), r=wave(T, -10, 14, phase=.2)))
    c.layer("tag", [group(path([(0, 0), (0, 22)], closed=False), stroke("#FFFFFF", 2)),
                    group(path([(-20, 22), (20, 22), (20, 74), (0, 88), (-20, 74)]), fill("#FFD166")),
                    group(ellipse(8, 8, 0, 32), fill("#1A1A2E")),
                    group(path([(-9, 62), (9, 44)], closed=False), stroke("#1A1A2E", 3)),
                    group(ellipse(6, 6, -8, 46), fill("#1A1A2E")), group(ellipse(6, 6, 8, 62), fill("#1A1A2E"))],
            ks(), parent=pivot)
    return c


MOTIFS = {
    "diyas": diyas, "lanterns": lanterns, "crescent": crescent, "snow": snow, "fireworks": fireworks,
    "hearts": hearts, "petals": petals, "kites": kites, "colors": colors, "splash": splash, "leaves": leaves,
    "bats": bats, "confetti": confetti, "candles": candles, "rainbow": rainbow, "sparkles": sparkles, "sale": sale,
}


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    only = sys.argv[2:] or list(MOTIFS)
    for name in only:
        MOTIFS[name]().save(f"{out}/{name}.json")
        print("wrote", name)
