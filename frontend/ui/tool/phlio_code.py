"""Reference implementation of Phlio Codes.

Mirrors ``lib/features/stream/music/phlio_code.dart`` step for step, so a change
to the code format can be tried and tested here (with Pillow) before it is
ported to the app.

Format
------
A code is the Phlio play mark followed by 23 rounded bars. Bars 0, 11 and 22
are always full height: they tell the scanner how tall "full" is, even when
the code is photographed at an angle. The other 20 bars carry 3 bits each
(heights 0-7), 60 bits in all::

    kind (2 bits) | payload (46 bits) | CRC-12 (12 bits)   XOR-ed with MASK

    kind 0  Audius track id: 3-bit length + base-62 value (ids up to 7 chars)
    kind 1  Phlio Stream track: 46-bit FNV-1a hash of its library id
    kind 2  song file on this phone: same hash (only resolves on that phone)

Decoding
--------
Threshold the grey image (Otsu), find connected blobs of foreground pixels,
chain 23 evenly spaced bars starting from a tall one, read each bar's height
relative to the three reference bars, then check the CRC. If that fails, the
five least certain bars are retried at their second-nearest height (the CRC
tells a right guess from a wrong one), and the bars are also tried reversed
for codes that are upside down.

Self-test: ``python3 tool/phlio_code.py`` (needs Pillow) renders, degrades
and decodes random codes.
"""
from __future__ import annotations

import random
from typing import NamedTuple, Sequence

BARS = 23  # bars in a code, references included
REFS = (0, 11, 22)  # always full height
DATA = [i for i in range(BARS) if i not in REFS]  # the 20 bars that carry data
MASK = 0x9E3779B97F4A7C15 & ((1 << 60) - 1)  # whitening, so codes look varied
ALPHA = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"  # Audius id alphabet
MIN_H = 0.18  # height of a level-0 bar as a fraction of a full bar
P46 = (1 << 46) - 1

KIND_AUDIUS, KIND_PHLIO, KIND_DEVICE = 0, 1, 2

Code = tuple[int, int]  # (kind, payload)


class Blob(NamedTuple):
    """A connected group of foreground pixels."""

    x: int  # bounding box left
    y: int  # bounding box top
    w: int  # bounding box width
    h: int  # bounding box height
    area: int  # pixel count
    cx: float  # centre of mass, x
    cy: float  # centre of mass, y


# -- encoding -----------------------------------------------------------------


def crc12(value: int, bits: int = 48) -> int:
    """CRC-12 (polynomial 0x80F) of the low ``bits`` bits of ``value``, MSB first."""
    crc = 0
    for i in range(bits - 1, -1, -1):
        bit = (value >> i) & 1
        top = (crc >> 11) & 1
        crc = (crc << 1) & 0xFFF
        if top ^ bit:
            crc ^= 0x80F
    return crc


def pack(kind: int, payload: int) -> list[int]:
    """Bar heights (0-7) for a code; reference bars are 7."""
    body = ((kind & 3) << 46) | (payload & P46)
    word = ((body << 12) | crc12(body)) ^ MASK
    levels = [7] * BARS
    for j, i in enumerate(DATA):
        # 3 bits per data bar, most significant first.
        levels[i] = (word >> (57 - 3 * j)) & 7
    return levels


def unpack(levels: Sequence[int]) -> Code | None:
    """(kind, payload) for bar heights, or None when the CRC doesn't match."""
    word = 0
    for i in DATA:
        word = (word << 3) | levels[i]
    word ^= MASK
    body, crc = word >> 12, word & 0xFFF
    if crc12(body) != crc:
        return None
    return body >> 46, body & P46


def audius_payload(track_id: str) -> int:
    """Payload for an Audius track id: length in bits 43-45, base-62 value below."""
    value = 0
    for ch in reversed(track_id):
        value = value * 62 + ALPHA.index(ch)
    return (len(track_id) << 43) | value


def audius_id(payload: int) -> str:
    """Inverse of :func:`audius_payload`."""
    n = payload >> 43
    value = payload & ((1 << 43) - 1)
    out = ""
    for _ in range(n):
        out += ALPHA[value % 62]
        value //= 62
    return out


def fnv46(text: str) -> int:
    """64-bit FNV-1a of the UTF-8 bytes, folded to 46 bits (Phlio / device tracks)."""
    h = 0xCBF29CE484222325
    for b in text.encode():
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h & P46


# -- decoding -----------------------------------------------------------------


def otsu(gray: Sequence[int]) -> int:
    """Otsu's threshold: the grey level that best splits the histogram in two."""
    hist = [0] * 256
    for v in gray:
        hist[v] += 1
    total = len(gray)
    weighted = sum(i * hist[i] for i in range(256))
    sum_b = 0.0
    w_b = 0
    best, threshold = -1.0, 128
    for t in range(256):
        w_b += hist[t]
        if w_b == 0:
            continue
        w_f = total - w_b
        if w_f == 0:
            break
        sum_b += t * hist[t]
        m_b = sum_b / w_b
        m_f = (weighted - sum_b) / w_f
        between = w_b * w_f * (m_b - m_f) ** 2  # between-class variance
        if between > best:
            best, threshold = between, t
    return threshold


def components(mask: Sequence[bool], w: int, h: int) -> list[Blob]:
    """4-connected blobs of True pixels (iterative flood fill)."""
    seen = [False] * (w * h)
    blobs: list[Blob] = []
    stack: list[int] = []
    for start in range(w * h):
        if not mask[start] or seen[start]:
            continue
        seen[start] = True
        stack.append(start)
        x0 = x1 = start % w
        y0 = y1 = start // w
        area = sx = sy = 0
        while stack:
            p = stack.pop()
            x, y = p % w, p // w
            area += 1
            sx += x
            sy += y
            x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
            neighbours = (p - 1 if x > 0 else -1, p + 1 if x < w - 1 else -1,
                          p - w if y > 0 else -1, p + w if y < h - 1 else -1)
            for q in neighbours:
                if q >= 0 and mask[q] and not seen[q]:
                    seen[q] = True
                    stack.append(q)
        blobs.append(Blob(x0, y0, x1 - x0 + 1, y1 - y0 + 1, area, sx / area, sy / area))
    return blobs


def decode(gray: Sequence[int], w: int, h: int) -> Code | None:
    """Finds and reads a code in a grey image (row-major, 0-255), or None.

    Both polarities are tried: dark bars on a light card and light on dark.
    """
    threshold = otsu(gray)
    for dark in (True, False):
        mask = [(v <= threshold) if dark else (v > threshold) for v in gray]
        # Bars are small and narrow; skip specks and anything wider than 1/12 of the image.
        blobs = [b for b in components(mask, w, h) if b.area >= 4 and b.w <= w // 12]
        found = _find(blobs)
        if found:
            return found
    return None


def _soft(raw: Sequence[float]) -> Code | None:
    """Nearest heights first; then the least certain data bars at their
    second-nearest height (up to 5 bars, 31 combinations)."""
    levels = [max(0, min(7, round(v))) for v in raw]
    out = unpack(levels)
    if out:
        return out
    doubtful = sorted(DATA, key=lambda i: -abs(raw[i] - round(raw[i])))[:5]
    for combo in range(1, 1 << len(doubtful)):
        trial = list(levels)
        valid = True
        for k, i in enumerate(doubtful):
            if combo >> k & 1:
                alt = levels[i] + (1 if raw[i] > levels[i] else -1)
                if not 0 <= alt <= 7:
                    valid = False
                    break
                trial[i] = alt
        if valid and (out := unpack(trial)):
            return out
    return None


def _find(blobs: list[Blob]) -> Code | None:
    """Tries every tall blob as the first reference bar and follows the chain."""
    blobs = sorted(blobs, key=lambda b: b.cx)
    refs = [b for b in blobs if b.h >= 3.2 * b.w and b.h >= 12]
    for a in refs:
        bw, bh = a.w, a.h
        # Bar-like blobs to the right, near a's centre line (allowing a slight tilt).
        cand = [b for b in blobs
                if 0.55 * bw <= b.w <= 1.7 * bw and b.h <= bh * 1.3 and b.cx > a.cx
                and abs(b.cy - a.cy) <= bh * 0.5 + (b.cx - a.cx) * 0.12]
        if len(cand) < BARS - 1:
            continue
        pitch = cand[0].cx - a.cx  # the nearest neighbour fixes the bar spacing
        if pitch < bw * 0.9 or pitch > bw * 3.5:
            continue
        bars = [a]
        slope = 0.0
        prev = a
        for _ in range(BARS - 1):
            ex, ey = prev.cx + pitch, prev.cy + slope * pitch  # where the next bar should be
            best: Blob | None = None
            for b in cand:
                dx = abs(b.cx - ex)
                if dx <= pitch * 0.35 and abs(b.cy - ey) <= bh * 0.2 and (best is None or dx < abs(best.cx - ex)):
                    best = b
            if best is None:
                break
            pitch = 0.7 * pitch + 0.3 * (best.cx - prev.cx)  # follow perspective gently
            bars.append(best)
            prev = best
            if len(bars) >= 3:
                slope = (bars[-1].cy - bars[0].cy) / (bars[-1].cx - bars[0].cx)
        if len(bars) < BARS:
            continue
        r = [bars[i].h for i in REFS]
        if min(r) < 0.8 * max(r):
            continue  # the "references" aren't equally tall: not a code
        # Blur grows every bar by the same few pixels: estimate the growth from
        # the bar width (true width = full height / 8) and take half of it off.
        widths = sorted(b.w for b in bars)
        wm = widths[len(widths) // 2]
        raw: list[float] = []
        for i, b in enumerate(bars):
            # Full height at this bar, interpolated between the references.
            ref = r[0] + (r[1] - r[0]) * i / 11 if i <= 11 else r[1] + (r[2] - r[1]) * (i - 11) / 11
            unit = max(1.0, (ref - wm) / 7)
            grow = 0.5 * max(0.0, min(wm - unit, ref * 0.25))
            frac = (b.h - grow) / max(1.0, ref - grow)
            raw.append(max(-0.49, min(7.49, (frac - MIN_H) / (1 - MIN_H) * 7)))
        out = _soft(raw) or _soft(raw[::-1])  # reversed = upside-down code
        if out:
            return out
    return None


# -- self-test ----------------------------------------------------------------


def _self_test(trials: int = 40) -> None:
    """Renders random codes, rotates / scales / blurs them and decodes them."""
    from PIL import Image, ImageDraw, ImageFilter

    def render(levels: Sequence[int], unit: int = 8) -> Image.Image:
        """White code on Phlio violet, drawn like PhlioCodeView."""
        fg, bg = (255, 255, 255), (124, 92, 255)
        hmax = 8 * unit
        img = Image.new("RGB", (int(6 * unit + hmax + 1.5 * unit + (2 * BARS - 1) * unit), hmax + 6 * unit), bg)
        d = ImageDraw.Draw(img)
        cy, x = img.height / 2, 3.0 * unit
        d.ellipse([x, cy - hmax / 2, x + hmax, cy + hmax / 2], fill=fg)
        d.polygon([(x + hmax * .38, cy - hmax * .22), (x + hmax * .38, cy + hmax * .22), (x + hmax * .72, cy)], fill=bg)
        x += hmax + 1.5 * unit
        for lv in levels:
            bar = max(unit, hmax * (MIN_H + (1 - MIN_H) * lv / 7))
            d.rounded_rectangle([x, cy - bar / 2, x + unit, cy + bar / 2], radius=unit / 2, fill=fg)
            x += 2 * unit
        return img

    rng = random.Random(3)
    ok = 0
    for t in range(trials):
        tid = "".join(rng.choice(ALPHA) for _ in range(rng.randint(4, 7)))
        img = render(pack(KIND_AUDIUS, audius_payload(tid)))
        angle = (180 if t % 2 else 0) + rng.uniform(-3, 3)
        img = img.rotate(angle, expand=True, fillcolor=(124, 92, 255))
        scale = rng.uniform(.6, 1.0)
        img = img.resize((int(img.width * scale), int(img.height * scale)), Image.Resampling.BILINEAR)
        img = img.filter(ImageFilter.GaussianBlur(rng.uniform(0, 1.2))).convert("L")
        out = decode(list(img.tobytes()), img.width, img.height)
        ok += out is not None and audius_id(out[1]) == tid
    print(f"decoded {ok}/{trials} (half upside down)")


if __name__ == "__main__":
    _self_test()
