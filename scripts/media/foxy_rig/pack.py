"""Foxy Moves — a rigged, animated sticker pack (Discord-style).

Each sticker takes one piece of Foxy's existing art, builds a bone rig on it
from a few landmarks (head, eyes, ears, arm, tail, prop), and animates the
bones: waving paws, wagging tails, blinks, head tilts, bows, hops. The art
itself is never redrawn — it is bent, like a puppet.
"""

import math
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(__import__('pathlib').Path(__file__).parent))
import rig  # noqa: E402
import sprites as sp  # noqa: E402
from bases import BASES  # noqa: E402

FPS = 25
ease = rig.ease
TAU = 2 * math.pi


def sn(t, period, phase=0.0):
    return math.sin(TAU * (t / period + phase))


def pulse(t, start, length):
    """0→1→0 bump inside [start, start+length]."""
    if t < start or t > start + length:
        return 0.0
    return math.sin(math.pi * (t - start) / length)


def blink_at(t, times, length=0.18):
    return max([pulse(t, s, length) for s in times] + [0.0])


# --------------------------------------------------------------- rig builder
def circle(c, r, n=8, start=0.0):
    return [(c[0] + r * math.cos(start + i * TAU / n), c[1] + r * math.sin(start + i * TAU / n)) for i in range(n)]


def build(L):
    """Landmarks -> (Rig, eye info). Landmark keys (sticker px):
    head=(x,y), head_r, neck, eyes=[(x,y,half_height)], ears=[tip], arm=dict(
    shoulder, paw, r), prop=dict(pivot, pts, parent), tail=dict(base, tip),
    anchors=[...], body=(x,y)."""
    points, bones, anchors = {}, {}, list(L.get('anchors', []))
    hc, hr = L['head'], L.get('head_r', 64)
    neck = L.get('neck', (hc[0], hc[1] + hr * 0.95))
    head_pts = []
    for i, pt in enumerate(circle(hc, hr * 0.82, 8, 0.4)):
        points[f'h{i}'] = pt
        head_pts.append(f'h{i}')
    points['hc'] = hc
    head_pts.append('hc')
    for i, pt in enumerate(L.get('head_extra', [])):
        points[f'hx{i}'] = pt
        head_pts.append(f'hx{i}')
    eyes = []
    for k, (ex, ey, eh) in enumerate(L.get('eyes', [])):
        for nm, pt in [('c', (ex, ey)), ('t', (ex, ey - eh)), ('b', (ex, ey + eh)),
                       ('rl', (ex - eh * 2.0, ey)), ('rr', (ex + eh * 2.0, ey)),
                       ('rt', (ex, ey - eh * 2.3)), ('rb', (ex, ey + eh * 2.3))]:
            points[f'e{k}{nm}'] = pt
            head_pts.append(f'e{k}{nm}')
        eyes.append((k, ex, ey, eh))
    bones['head'] = dict(pivot=neck, pts=head_pts, parent='body')
    for k, tip in enumerate(L.get('ears', [])):
        base = (tip[0] + (hc[0] - tip[0]) * 0.42, tip[1] + (hc[1] - tip[1]) * 0.42)
        points[f'ear{k}'] = tip
        points[f'ear{k}m'] = ((tip[0] + base[0]) / 2, (tip[1] + base[1]) / 2)
        bones[f'ear{k}'] = dict(pivot=base, pts=[f'ear{k}', f'ear{k}m'], parent='head')
    if 'arm' in L:
        a = L['arm']
        pr = a.get('r', 16)
        pts = []
        for i, pt in enumerate(circle(a['paw'], pr, 5) + [a['paw']]):
            points[f'paw{i}'] = pt
            pts.append(f'paw{i}')
        mid = ((a['shoulder'][0] + a['paw'][0]) / 2, (a['shoulder'][1] + a['paw'][1]) / 2)
        points['arm_mid'] = mid
        bones['arm'] = dict(pivot=a['shoulder'], pts=['arm_mid'], parent='body')
        bones['paw'] = dict(pivot=mid, pts=pts, parent='arm')
    if 'prop' in L:
        pr = L['prop']
        names = []
        for i, pt in enumerate(pr['pts']):
            points[f'prop{i}'] = pt
            names.append(f'prop{i}')
        bones['prop'] = dict(pivot=pr['pivot'], pts=names, parent=pr.get('parent', 'body'))
    if 'tail' in L:
        t = L['tail']
        b, tip = t['base'], t['tip']
        names = []
        for i, f in enumerate((0.45, 0.8, 1.0)):
            points[f'tail{i}'] = (b[0] + (tip[0] - b[0]) * f, b[1] + (tip[1] - b[1]) * f)
            names.append(f'tail{i}')
        bones['tail'] = dict(pivot=b, pts=names, parent='body')
    body = L.get('body')
    bones['body'] = dict(pivot=L.get('hips', (160, 300)), pts=[], parent=None)
    if body:
        points['body'] = body
        bones['body']['pts'] = ['body']
    return rig.Rig(points, bones, anchors), eyes


# --------------------------------------------------------------- stickers
STICKERS = {}


def sticker(name, seconds, base=None):
    def deco(fn):
        STICKERS[name] = dict(fn=fn, seconds=seconds, base=base or name)
        return fn
    return deco


def F(**kw):
    """A frame description."""
    d = dict(pose={}, blink=0.0, eye_blink=None, glob={}, front=[], back=[])
    d.update(kw)
    return d


# ---------------------------------------------------------------- helpers
def twinkle(sprite, x, y, t, period, phase=0.0, size=1.0, active=True):
    u = ((t / period) + phase) % 1.0
    life = math.sin(math.pi * min(1.0, u / 0.5)) if u < 0.5 else 0.0
    alpha = min(1.0, life / 0.15)
    return (sprite, x, y, size * (0.1 + 1.0 * life), 15 * math.sin(TAU * u), alpha if active else 0.0)


def rise(sprite, t, period, phase, start, end, size=(0.6, 1.0), spin=0.0, sway=0.0, fade_in=0.15, fade_out=0.35, pop=False):
    """A prop drifting from start to end. Solid props (hearts, notes, Zzz)
    `pop`: they grow in and shrink out instead of fading, because a
    half-transparent coloured shape reads as a dull ghost on dark chats."""
    u = ((t / period) + phase) % 1.0
    x = start[0] + (end[0] - start[0]) * u + sway * math.sin(TAU * u * 1.5)
    y = start[1] + (end[1] - start[1]) * u
    scale = size[0] + (size[1] - size[0]) * u
    if pop:
        grow = ease(u / fade_in)
        shrink = ease((1 - u) / fade_out)
        return (sprite, x, y, scale * grow * shrink, spin * u, 1.0 if grow * shrink > 0.05 else 0.0)
    alpha = min(1.0, u / fade_in) * min(1.0, (1 - u) / fade_out)
    return (sprite, x, y, scale, spin * u, alpha)


def fall(sprite, t, period, phase, x, y0=-10, y1=330, drift=0.0, size=1.0, angle=0.0):
    u = ((t / period) + phase) % 1.0
    alpha = min(1.0, u / 0.08) * min(1.0, (1 - u) / 0.1)
    return (sprite, x + drift * u, y0 + (y1 - y0) * u, size, angle, alpha)


def breathe(period=2.4, amount=0.012, t=0.0):
    # Whole-body breathing would change every pixel of every frame (and
    # balloon file sizes); the local motions carry these stickers instead.
    return {}


CONFETTI = [sp.PEACH, sp.VIOLET, sp.PINK, sp.TEAL, sp.YELLOW]


# ---------------------------------------------------------------- 1. hi
L_HI = dict(head=(170, 178), head_r=62, eyes=[(144, 166, 8), (200, 178, 9)],
            head_extra=[(112, 140), (106, 180), (118, 112), (98, 124), (92, 140)],
            ears=[(134, 60), (240, 120)], arm=dict(shoulder=(104, 214), paw=(72, 166), r=20),
            anchors=[(125, 290), (188, 290), (160, 262), (215, 250), (110, 255)], body=(160, 250))


@sticker('hi', 2.4)
def hi(t):
    env = min(1, t / 0.2) * (1 if t < 1.7 else max(0, 1 - (t - 1.7) / 0.25))
    w = sn(t, 0.6) * env
    w = (0.42 if w < 0 else 0.22) * w
    on = t < 1.75
    return F(pose={'arm': (w * 0.4, 0, 0), 'paw': (w * 0.75, 0, 0), 'head': (0.05 * sn(t, 1.2), 0, 0),
                   'ear0': (-0.14 * pulse(t, 0.9, 0.3), 0, 0)},
             blink=blink_at(t, [2.05]), glob=breathe(2.4, 0.01, t),
             front=[twinkle(sp.sparkle(sp.PEACH, 30), 40, 128, t, 0.6, 0.0, 1.0, on),
                    twinkle(sp.sparkle(sp.VIOLET, 24), 34, 198, t, 0.6, 0.5, 1.0, on)])


# ---------------------------------------------------------------- 2. thumbs up
L_THUMBS_UP = dict(head=(161, 166), head_r=62, eyes=[(139, 181, 9), (193, 175, 9)],
                   ears=[(93, 75), (211, 59)], arm=dict(shoulder=(196, 266), paw=(224, 214), r=22),
                   anchors=[(95, 292), (225, 292), (150, 268), (110, 240)], body=(150, 262))


@sticker('thumbs_up', 1.6)
def thumbs_up(t):
    pump = max(0.0, sn(t, 0.8))
    return F(pose={'arm': (-0.2 * pump, 0, -4 * pump), 'head': (0.035 * pump, 0, 2 * pump)},
             blink=blink_at(t, [1.25]), glob=breathe(1.6, 0.01, t),
             front=[twinkle(sp.sparkle(sp.YELLOW, 32), 246, 170, t, 0.8, 0.05, 1.0),
                    twinkle(sp.sparkle(sp.PEACH, 22), 262, 206, t, 0.8, 0.25, 1.0)])


# ---------------------------------------------------------------- 3. clap
L_CLAP = dict(head=(159, 164), head_r=62, ears=[(81, 74), (225, 61)],
              arm=dict(shoulder=(128, 252), paw=(155, 224), r=11),
              prop=dict(pivot=(196, 252), pts=[(183, 224), (185, 212), (185, 238)]),
              anchors=[(90, 292), (220, 292), (160, 282), (169, 252)], body=(160, 270))


@sticker('clap', 1.2)
def clap(t):
    u = (t % 0.4) / 0.4
    open_ = math.sin(math.pi * u) ** 1.5
    hit = pulse(t % 0.4, 0.0, 0.12)
    return F(pose={'arm': (0.2 * open_, 0, 0), 'prop': (-0.2 * open_, 0, 0),
                   'head': (0.03 * sn(t, 0.8), 0, 2 * hit)},
             glob=breathe(1.2, 0.012, t),
             front=[(sp.sparkle(sp.YELLOW, 26), 169 + dx, 196 + dy, 0.5 + 0.6 * hit, 0, hit)
                    for dx, dy in [(-26, -10), (26, -10), (0, -26)]])


# ---------------------------------------------------------------- 4. giggle
L_GIGGLE = dict(head=(161, 186), head_r=68, eyes=[(136, 199, 10), (205, 189, 10)],
                ears=[(61, 80), (252, 86)], anchors=[(90, 296), (250, 296), (174, 285)], body=(170, 280))


@sticker('giggle', 1.2)
def giggle(t):
    shake = 0.06 * sn(t, 0.2)
    bounce = abs(sn(t, 0.6))
    tears = []
    for k, (x, y, d) in enumerate([(116, 196, -1), (228, 186, 1)]):
        u = ((t / 0.6) + k * 0.5) % 1.0
        tears.append((sp.tear(14), x + d * 26 * u, y - 18 * math.sin(math.pi * u) + 10 * u, 0.9, d * -30, math.sin(math.pi * u)))
    return F(pose={'head': (shake, 0, -2 * bounce)}, blink=0.55,
             glob=dict(translate=(0, -5 * bounce), scale=(1 + 0.015 * bounce, 1 - 0.015 * bounce)),
             front=tears)


# ---------------------------------------------------------------- 5. love
L_LOVE = dict(head=(160, 172), head_r=70, eyes=[(203, 189, 7)], ears=[(69, 68), (238, 64)],
              anchors=[(94, 292), (225, 292), (169, 256)], body=(160, 270))


@sticker('love', 2.4)
def love(t):
    hearts = [rise(sp.heart(40), t, 2.4, ph, (x, 150), (x + dx, 30), size=(0.7, 1.1), sway=10, pop=True)
              for ph, x, dx in [(0.0, 220, 20), (0.33, 105, -15), (0.66, 245, 5)]]
    return F(pose={'head': (0.06 * sn(t, 1.2, 0.25), 0, 0), 'ear1': (0.1 * sn(t, 1.2), 0, 0)},
             eye_blink=[blink_at(t, [1.6])], glob=dict(angle=0.045 * sn(t, 2.4)), front=hearts)


# ---------------------------------------------------------------- 6. sad
L_SAD = dict(head=(160, 172), head_r=70, eyes=[(114, 199, 8), (183, 208, 9)],
             ears=[(108, 74), (252, 111)], anchors=[(105, 290), (202, 290), (155, 272)], body=(155, 265))


@sticker('sad', 3.0)
def sad(t):
    droop = ease(t / 0.8) * (1 - ease((t - 2.3) / 0.6))
    u = (t % 1.5) / 1.5
    tear = (sp.tear(16), 114 - 6 * u, 214 + 46 * ease(u), 1.0, 0, min(1, u / 0.1) * (1 - ease((u - 0.7) / 0.3)))
    return F(pose={'head': (0.07 * droop, 0, 6 * droop), 'ear0': (-0.28 * droop, 0, 0), 'ear1': (0.28 * droop, 0, 0)},
             blink=blink_at(t, [2.6], 0.3), front=[tear])


# ---------------------------------------------------------------- 7. angry
L_ANGRY = dict(head=(159, 150), head_r=72, ears=[(94, 75), (231, 69)],
               anchors=[(90, 292), (230, 292), (162, 262)], body=(160, 262))


@sticker('angry', 1.2)
def angry(t):
    beat = abs(sn(t, 0.4))
    steam = [rise(sp.puff(44), t, 0.6, ph, (x, 92), (x + dx, 34), size=(0.5, 1.15)) for ph, x, dx in [(0, 86, -22), (0.5, 232, 22)]]
    return F(pose={'ear0': (0.16, 0, 0), 'ear1': (-0.16, 0, 0), 'head': (0, 0, 2)},
             glob=dict(translate=(2.2 * sn(t, 1 / 12), 0)),
             front=steam + [(sp.anger(56), 250, 128, 0.85 + 0.25 * beat, 0, 1.0)])


# ---------------------------------------------------------------- 8. confused
L_CONFUSED = dict(head=(156, 165), head_r=68, eyes=[(141, 196, 6), (200, 193, 6)],
                  ears=[(75, 71), (238, 83)], anchors=[(95, 290), (220, 290), (160, 272)], body=(160, 265))


@sticker('confused', 2.4)
def confused(t):
    tilt = 0.13 * sn(t, 2.4)
    pop = min(1.0, t / 0.25)
    return F(pose={'head': (tilt, 0, 0), 'ear0': (-0.12 * max(0, sn(t, 2.4)), 0, 0), 'ear1': (0.12 * max(0, -sn(t, 2.4)), 0, 0)},
             blink=blink_at(t, [1.6]),
             front=[(sp.question(48), 250, 66 + 5 * sn(t, 1.2), 0.6 + 0.4 * ease(pop), -12 * sn(t, 2.4), pop)])


# ---------------------------------------------------------------- 9. sorry
L_SORRY = dict(head=(162, 128), head_r=64, eyes=[(200, 153, 5)], ears=[(109, 66), (206, 59)],
               prop=dict(pivot=(169, 206), pts=[(169, 206), (150, 200), (188, 200)], parent='head'),
               anchors=[(119, 286), (209, 286), (165, 268)], body=(165, 255))


@sticker('sorry', 2.4)
def sorry(t):
    bow = pulse(t, 0.2, 0.7) + pulse(t, 1.2, 0.7)
    u = (t % 2.4) / 2.4
    drop = (sp.sweat(20), 228, 88 + 22 * ease(u), 1.0, 0, min(1, u / 0.1) * (1 - ease((u - 0.6) / 0.4)))
    return F(pose={'head': (0.02 * bow, 0, 10 * bow)}, eye_blink=[blink_at(t, [0.5, 1.5], 0.3)],
             glob=dict(scale=(1 + 0.01 * bow, 1 - 0.02 * bow)), front=[drop])


# ---------------------------------------------------------------- 10. good job
L_GOOD_JOB = dict(head=(180, 150), head_r=62, eyes=[(158, 172, 8), (214, 166, 8)],
                  ears=[(111, 69), (224, 59)],
                  prop=dict(pivot=(200, 252), pts=[(224, 228), (224, 204), (246, 228), (224, 250), (204, 226)]),
                  anchors=[(86, 275), (218, 294), (150, 272), (130, 230)], body=(150, 262))


@sticker('good_job', 1.6)
def good_job(t):
    wig = 0.26 * sn(t, 0.8)
    return F(pose={'prop': (wig, 0, -3 * abs(sn(t, 0.8))), 'head': (0.04 * sn(t, 0.8, 0.25), 0, 0)},
             blink=blink_at(t, [1.25]), glob=breathe(1.6, 0.01, t),
             front=[twinkle(sp.sparkle(sp.YELLOW, 30), 262, 190, t, 0.8, 0.0),
                    twinkle(sp.sparkle(sp.PEACH, 22), 268, 250, t, 0.8, 0.35),
                    twinkle(sp.sparkle(sp.YELLOW, 20), 205, 196, t, 0.8, 0.65)])


# ---------------------------------------------------------------- 11. cheers
L_CHEERS = dict(head=(178, 158), head_r=60, ears=[(106, 74), (225, 64)],
                prop=dict(pivot=(200, 268), pts=[(200, 236), (200, 214), (222, 236), (200, 258), (178, 236)]),
                tail=dict(base=(118, 262), tip=(60, 236)),
                anchors=[(144, 288), (206, 288), (150, 262)], body=(160, 262))


@sticker('cheers', 2.0)
def cheers(t):
    lift = pulse(t, 0.3, 0.9)
    steam = [rise(sp.steam(18), t, 1.0, ph, (x, 206 - 16 * lift), (x + 4, 160 - 16 * lift), size=(0.7, 1.0)) for ph, x in [(0, 192), (0.5, 208)]]
    return F(pose={'prop': (-0.14 * lift, 0, -16 * lift), 'head': (-0.05 * lift, 0, -2 * lift),
                   'tail': (0.18 * sn(t, 1.0), 0, 0)},
             glob=breathe(2.0, 0.01, t),
             front=steam + [twinkle(sp.sparkle(sp.YELLOW, 30), 232, 170, t, 2.0, 0.08, 1.0, lift > 0.5)])


# ---------------------------------------------------------------- 12. wink
L_WINK = dict(head=(164, 188), head_r=76, ears=[(80, 83), (274, 74)],
              arm=dict(shoulder=(108, 272), paw=(68, 236), r=20),
              anchors=[(118, 296), (205, 296), (160, 288)], body=(160, 285))


@sticker('wink', 1.6)
def wink(t):
    return F(pose={'arm': (0.2 * sn(t, 0.4), 0, 0), 'head': (0.06 * sn(t, 1.6), 0, 0), 'ear1': (0.12 * pulse(t, 0.6, 0.3), 0, 0)},
             glob=breathe(1.6, 0.01, t),
             front=[twinkle(sp.sparkle(sp.PINK, 32), 236, 150, t, 0.8, 0.0, 1.1),
                    twinkle(sp.sparkle(sp.PEACH, 22), 256, 196, t, 0.8, 0.4)])


# ---------------------------------------------------------------- 13. yay
L_YAY = dict(head=(190, 156), head_r=64, ears=[(128, 88), (240, 69)],
             tail=dict(base=(144, 262), tip=(59, 250)),
             anchors=[(162, 288), (231, 281), (190, 252)], body=(190, 250))


@sticker('yay', 1.6)
def yay(t):
    u = (t % 0.8)
    air = math.sin(math.pi * u / 0.5) if u < 0.5 else 0.0
    land = pulse(u, 0.5, 0.2)
    crouch = pulse(u, 0.0, 0.08)
    burst = []
    for k in range(10):
        ang = TAU * k / 10 + 0.3
        c = CONFETTI[k % len(CONFETTI)]
        uu = min(1.0, (u) / 0.6)
        burst.append((sp.confetti(c), 190 + math.cos(ang) * (70 + 80 * uu), 70 + math.sin(ang) * (26 + 50 * uu) + 60 * uu * uu,
                      1.0, k * 40 + uu * 300, (1 - uu) * (t >= 0)))
    return F(pose={'ear0': (0.25 * land - 0.1 * air, 0, 0), 'ear1': (-0.25 * land + 0.1 * air, 0, 0),
                   'tail': (0.3 * sn(t, 0.8), 0, 0), 'head': (0.04 * sn(t, 0.8), 0, 0)},
             glob=dict(translate=(0, -30 * air), scale=(1 + 0.06 * (land + crouch), 1 - 0.07 * (land + crouch) + 0.04 * air),
                       pivot=(190, 300)),
             front=burst)


# ---------------------------------------------------------------- 14. wag
L_WAG = dict(head=(149, 160), head_r=62, ears=[(125, 69), (227, 88)],
             tail=dict(base=(196, 252), tip=(264, 225)),
             anchors=[(80, 290), (242, 292), (150, 245), (150, 282)], body=(150, 245))


@sticker('wag', 1.6)
def wag(t):
    flakes = [fall(sp.flake(10), t, 1.6, ph, x, drift=8) for ph, x in [(0, 40), (0.3, 120), (0.55, 260), (0.8, 300), (0.15, 200)]]
    return F(pose={'tail': (0.38 * sn(t, 0.4), 0, 0), 'head': (0.05 * sn(t, 1.6), 0, 0),
                   'ear1': (0.18 * pulse(t, 1.1, 0.25), 0, 0)},
             glob=breathe(1.6, 0.01, t), front=flakes)


# ---------------------------------------------------------------- 15. coffee
L_COFFEE = dict(head=(160, 160), head_r=66, ears=[(116, 77), (250, 80)],
                prop=dict(pivot=(147, 290), pts=[(147, 249), (147, 222), (175, 249), (147, 274), (120, 249)]),
                anchors=[(81, 294), (206, 294), (200, 260)], body=(170, 280))


@sticker('coffee', 2.4)
def coffee(t):
    sip = pulse(t, 0.6, 1.2) ** 0.7
    steam = [rise(sp.steam(24), t, 1.2, ph, (x, 206), (x + 6, 150), size=(0.8, 1.15)) for ph, x in [(0, 136), (0.5, 160)]]
    for s in steam:
        pass
    alpha = 1 - sip
    steam = [(s[0], s[1], s[2], s[3], s[4], s[5] * alpha) for s in steam]
    return F(pose={'prop': (-0.1 * sip, 0, -12 * sip), 'head': (-0.06 * sip, 0, -2 * sip)},
             glob=breathe(2.4, 0.01, t), front=steam)


# ---------------------------------------------------------------- 16. sleep
L_SLEEP = dict(head=(225, 250), head_r=46, ears=[(231, 137), (109, 169)],
               anchors=[(60, 282), (150, 286), (290, 286)], body=(150, 252))


@sticker('sleep', 3.2)
def sleep(t):
    s = 0.5 - 0.5 * math.cos(TAU * t / 1.6)
    zs = [rise(sp.zed(40), t, 3.2, ph, (246, 190), (290, 60), size=(0.55, 1.2), spin=-15, sway=8, pop=True) for ph in (0, 0.33, 0.66)]
    return F(pose={'ear0': (-0.28 * pulse(t, 2.2, 0.25), 0, 0)},
             glob=dict(scale=(1 + 0.01 * s, 1 + 0.03 * s), pivot=(160, 290)), front=zs)


# ---------------------------------------------------------------- 17. wizard
L_WIZARD = dict(head=(184, 154), head_r=58, eyes=[(159, 153, 8), (209, 150, 8)], head_extra=[(69, 106), (250, 66)],
                prop=dict(pivot=(253, 202), pts=[(259, 128), (256, 160), (247, 250), (241, 292)]),
                tail=dict(base=(96, 240), tip=(47, 206)),
                anchors=[(130, 294), (200, 294), (160, 252), (120, 240)], body=(160, 252))


@sticker('wizard', 2.0)
def wizard(t):
    ang = 0.24 * sn(t, 1.0)
    top = rig.rot((259, 128), (253, 202), ang)
    orbit = []
    for k in range(4):
        a = TAU * (t / 1.0 + k / 4)
        orbit.append(twinkle(sp.sparkle(sp.VIOLET if k % 2 else sp.PEACH, 30), top[0] + 30 * math.cos(a), top[1] + 20 * math.sin(a), t, 1.0, k / 4, 1.0))
    return F(pose={'prop': (ang, 0, 0), 'tail': (0.15 * sn(t, 1.0, 0.25), 0, 0), 'head': (0.035 * sn(t, 2.0), 0, 0)},
             blink=blink_at(t, [1.5]), glob=breathe(2.0, 0.01, t), front=orbit)


# ---------------------------------------------------------------- 18. chef
L_CHEF = dict(head=(161, 166), head_r=60, eyes=[(146, 159, 8), (193, 156, 8)], head_extra=[(146, 59), (139, 212)],
              prop=dict(pivot=(246, 178), pts=[(249, 81), (249, 110), (247, 140)]),
              tail=dict(base=(108, 252), tip=(55, 238)),
              anchors=[(130, 294), (220, 294), (160, 252)], body=(160, 252))


@sticker('chef', 1.6)
def chef(t):
    flick = pulse(t, 0.1, 0.35)
    u = (t - 0.25) / 0.85
    flying = 0 <= u <= 1
    px = 249 - 18 * math.sin(math.pi * u) if flying else 249
    py = 84 - 90 * math.sin(math.pi * u) if flying else 84
    look = math.sin(math.pi * u) if flying else 0.0
    return F(pose={'prop': (-0.32 * flick, 0, -6 * flick), 'head': (-0.05 * look, 0, -2 * look),
                   'tail': (0.15 * sn(t, 0.8), 0, 0)},
             blink=blink_at(t, [1.35]), glob=breathe(1.6, 0.01, t),
             front=[(sp.pancake(36), px, py, 1.0, 360 * u if flying else 0, 1.0)])


# ---------------------------------------------------------------- 19. samurai
L_SAMURAI = dict(head=(178, 178), head_r=62, eyes=[(159, 180, 7), (203, 177, 7)],
                 head_extra=[(110, 100), (150, 92), (200, 104), (215, 140), (110, 140)],
                 prop=dict(pivot=(262, 200), pts=[(178, 49), (205, 95), (235, 145)]),
                 tail=dict(base=(112, 262), tip=(45, 232)),
                 anchors=[(130, 296), (210, 296), (170, 252)], body=(170, 252))


@sticker('samurai', 1.6)
def samurai(t):
    # The blade is painted over his ear, so the swing stays small and the
    # lunge and slash trail sell the strike.
    if t < 0.5:
        a = -0.07 * ease(t / 0.5)
    elif t < 0.68:
        a = -0.07 + 0.19 * ease((t - 0.5) / 0.18)
    else:
        a = 0.12 * (1 - ease((t - 0.68) / 0.7))
    lunge = pulse(t, 0.5, 0.5)
    trail = pulse(t, 0.52, 0.32)
    return F(pose={'prop': (a, 0, 0), 'tail': (0.14 * sn(t, 0.8), 0, 0)},
             blink=blink_at(t, [1.35]),
             glob=dict(translate=(6 * lunge, -3 * lunge), angle=0.05 * lunge - 0.03 * pulse(t, 0.0, 0.5), pivot=(170, 300)),
             front=[(sp.slash(150), 262, 112, 1.0, -45, trail * 0.9)])


# ---------------------------------------------------------------- 20. space
L_SPACE = dict(head=(164, 152), head_r=64, eyes=[(161, 155, 9), (214, 149, 9)],
               tail=dict(base=(108, 226), tip=(61, 214)),
               anchors=[(130, 292), (220, 292), (165, 240)], body=(165, 240))


@sticker('space', 3.0)
def space(t):
    stars = [twinkle(sp.sparkle(c, 18), x, y, t, 1.5, ph, 0.9)
             for (x, y, ph, c) in [(40, 60, 0, sp.PEACH), (280, 40, 0.3, sp.VIOLET), (300, 180, 0.6, sp.PEACH),
                                   (26, 200, 0.45, sp.VIOLET), (120, 30, 0.8, sp.YELLOW)]]
    return F(pose={'tail': (0.22 * sn(t, 1.5), 0, 0)}, blink=blink_at(t, [2.2]),
             glob=dict(translate=(0, -6 - 8 * sn(t, 3.0)), angle=0.07 * sn(t, 3.0, 0.25), pivot=(165, 200)),
             back=stars)


# ---------------------------------------------------------------- 21. rainy
L_RAINY = dict(head=(162, 196), head_r=50, eyes=[(144, 206, 8), (194, 200, 8)],
               prop=dict(pivot=(225, 231), pts=[(156, 69), (80, 112), (240, 92), (156, 104), (110, 150)]),
               anchors=[(90, 296), (230, 296), (160, 272)], body=(160, 272))


@sticker('rainy', 2.0)
def rainy(t):
    drops = [fall(sp.raindrop(), t, 0.5, (k * 0.37) % 1, 12 + k * 30, -20, 330, drift=-24, angle=-6) for k in range(11)]
    return F(pose={'prop': (0.07 * sn(t, 2.0), 0, 0), 'head': (0.03 * sn(t, 1.0), 0, 2 * sn(t, 1.0))},
             blink=blink_at(t, [1.4]), glob=breathe(2.0, 0.01, t), front=drops)


# ---------------------------------------------------------------- 22. winter
L_WINTER = dict(head=(180, 188), head_r=64, eyes=[(155, 194, 9), (205, 200, 9)],
                prop=dict(pivot=(222, 136), pts=[(242, 103)], parent='head'),
                anchors=[(120, 296), (250, 296), (180, 272)], body=(180, 272))


@sticker('winter', 2.0)
def winter(t):
    flakes = [fall(sp.flake(12), t, 2.0, (k * 0.29) % 1, 14 + k * 26, -10, 330, drift=12, size=0.7 + 0.3 * (k % 3) / 2) for k in range(12)]
    breath = rise(sp.puff(30), t, 2.0, 0.0, (176, 236), (130, 222), size=(0.4, 1.0), fade_in=0.1, fade_out=0.5)
    return F(pose={'prop': (0.25 * sn(t, 0.5), 0, 0)}, blink=blink_at(t, [1.4]),
             glob=dict(translate=(1.4 * sn(t, 0.1), 0)), front=flakes + [breath])


# ---------------------------------------------------------------- 23. hoodie
L_HOODIE = dict(head=(187, 176), head_r=62, ears=[(128, 61), (262, 74)],
                tail=dict(base=(110, 238), tip=(59, 218)),
                anchors=[(130, 296), (230, 296), (180, 262)], body=(180, 262))


@sticker('hoodie', 2.0)
def hoodie(t):
    beat = 0.5 - 0.5 * math.cos(TAU * t / 0.5)
    notes = [rise(sp.note(38, c, dbl), t, 2.0, ph, (x, 120), (x + dx, 30), size=(0.7, 1.1), spin=dx / 2, sway=6, pop=True)
             for ph, x, dx, c, dbl in [(0, 260, 20, sp.VIOLET, False), (0.5, 92, -20, sp.PINK, True)]]
    return F(pose={'head': (0.05 * sn(t, 2.0), 0, 4 * beat), 'tail': (0.14 * sn(t, 0.5), 0, 0)},
             glob=dict(angle=0.025 * sn(t, 2.0)), front=notes)


# ---------------------------------------------------------------- 24. student
L_STUDENT = dict(head=(174, 156), head_r=60, eyes=[(158, 155, 7), (208, 158, 7)], ears=[(127, 55), (246, 64)],
                 prop=dict(pivot=(199, 272), pts=[(199, 243), (199, 222), (226, 243), (199, 262), (172, 243)]),
                 tail=dict(base=(108, 262), tip=(80, 249)),
                 anchors=[(130, 296), (230, 296), (160, 282)], body=(160, 280))


@sticker('student', 2.4)
def student(t):
    return F(pose={'head': (0.04 * sn(t, 1.2), 0, 2 * sn(t, 1.2)), 'prop': (0.03 * sn(t, 1.2, 0.3), 0, 2 * sn(t, 1.2, 0.3)),
                   'ear0': (-0.15 * pulse(t, 1.7, 0.25), 0, 0)},
             blink=blink_at(t, [0.9, 2.1]), glob=breathe(2.4, 0.01, t),
             front=[twinkle(sp.sparkle(sp.YELLOW, 22), 236, 214, t, 1.2, 0.2)])
