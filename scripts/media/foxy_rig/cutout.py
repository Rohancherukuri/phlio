"""Cuts Foxy reference art out of its flat sticker background.
Flood-fills the backdrop from the border, keeps the biggest island (drops
lettering, hearts, doodles) and un-mixes the anti-aliased outline from the
backdrop colour so there is no light halo on dark screens."""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

def ink_mask(im, rects):
    """Lettering / speed lines: bluish-purple ink inside the given rects."""
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    blue = (b > r + 12) & (b >= g - 4)
    m = np.zeros(blue.shape, bool)
    for x0, y0, x1, y1 in rects:
        m[y0:y1, x0:x1] = blue[y0:y1, x0:x1]
    white = im.min(-1) > 205
    for x0, y0, x1, y1 in rects:
        m[y0:y1, x0:x1] |= white[y0:y1, x0:x1]
    return m


def cutout(path, tol=48, keep=1, extra_keep=0.0, erase=(), fade_bottom=0, open_holes=False):
    im = np.array(Image.open(path).convert('RGB')).astype(float)
    h, w, _ = im.shape
    ink = ink_mask(im, erase) if erase else np.zeros((h, w), bool)
    border = np.concatenate([im[0], im[-1], im[:, 0], im[:, -1]])
    bgc = np.median(border, 0)
    dist = np.sqrt(((im - bgc) ** 2).sum(-1))
    near = dist < tol
    lab, n = ndimage.label(near)
    edge_ids = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(edge_ids))
    fg = ~bg & ~ink
    # Biggest island = Foxy; text, hearts and marks are separate islands.
    lab2, n2 = ndimage.label(fg)
    sizes = ndimage.sum(np.ones_like(lab2), lab2, range(1, n2 + 1))
    order = np.argsort(sizes)[::-1]
    keepset = [order[i] + 1 for i in range(min(keep, n2))]
    keepset += [i + 1 for i, s in enumerate(sizes) if s >= sizes.max() * extra_keep and extra_keep > 0]
    fg = np.isin(lab2, keepset)
    filled = ndimage.binary_fill_holes(fg)
    if open_holes:
        # Backdrop enclosed by limbs (e.g. between raised arms) stays see-through.
        gaps, ng = ndimage.label(near & ~bg)
        for i in range(1, ng + 1):
            if (gaps == i).sum() > 30:
                filled[gaps == i] = False
    fg = filled
    # Soft edge: in a 2px band outside the solid core, alpha from distance to bg colour.
    core = ndimage.binary_erosion(fg, iterations=1)
    band = ndimage.binary_dilation(fg, iterations=2) & ~core
    full = np.sqrt(((np.array([60, 40, 35.0]) - bgc) ** 2).sum())
    a = np.where(core, 1.0, 0.0)
    a = np.where(band, np.clip(dist / max(full, 1) * 1.15, 0, 1), a)
    # Don't let the band grab other islands.
    near_fg = ndimage.binary_dilation(fg, iterations=2)
    a = np.where(near_fg & (fg | ~ink), a, 0)
    al = np.maximum(a, 1e-3)[..., None]
    rgb = np.where(a[..., None] > 0, (im - (1 - a[..., None]) * bgc) / al, 0)
    rgb = np.clip(rgb, 0, 255)
    if fade_bottom:
        ys = np.where(fg.any(1))[0]
        y1 = ys.max()
        ramp = np.clip((y1 - np.arange(h)) / fade_bottom, 0, 1)
        a = a * (ramp * ramp * (3 - 2 * ramp))[:, None]
    out = np.dstack([rgb, a * 255]).astype(np.uint8)
    img = Image.fromarray(out, 'RGBA')
    return img.crop(img.getbbox())

if __name__ == '__main__':
    src, dst = sys.argv[1], sys.argv[2]
    tol = float(sys.argv[3]) if len(sys.argv) > 3 else 48
    cutout(src, tol).save(dst)


# Source -> cut-out recipes (source px rects of lettering/lines to erase).
RECIPES = {
    'hello': dict(fade_bottom=26),
    'bliss': dict(fade_bottom=26),
    'smart': dict(fade_bottom=22),
    'nervous': dict(fade_bottom=26),
    'go': dict(erase=[(244, 8, 372, 120)]),
    'tel': dict(erase=[(222, 4, 372, 108)], fade_bottom=24),
    'sorry': dict(erase=[(170, 4, 368, 84)], fade_bottom=24),
    'sad': dict(erase=[(175, 4, 420, 204)]),
    'wink': dict(),
    # Upscaled 4x with Real-ESRGAN (anime) then halved: the source is tiny.
    'seeyou2_x2': dict(tol=40, erase=[(292, 252, 476, 416)], open_holes=True),
    'sleep': dict(),
}
