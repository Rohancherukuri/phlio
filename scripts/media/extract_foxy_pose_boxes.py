"""Detect connected components (fox poses) in the foxy_poses.png sheet.

Strategy: the sheet background is dark navy. Flood-fill background from the
borders, then find connected components of foreground pixels, merge nearby
components into pose blobs, and print bounding boxes so poses can be cropped.
"""
from PIL import Image
import numpy as np
from collections import deque

im = Image.open("I:/Rohan/projects/phlio_blueprint/foxy_poses.png").convert("RGB")
a = np.asarray(im).astype(np.int16)
h, w, _ = a.shape
print("size", w, h)

# Background estimate: sample corners
corners = np.concatenate([
    a[:40, :40].reshape(-1, 3), a[:40, -40:].reshape(-1, 3),
    a[-40:, :40].reshape(-1, 3), a[-40:, -40:].reshape(-1, 3),
])
bg = corners.mean(axis=0)
print("bg estimate", bg)

# Foreground mask: pixels far from bg color
dist = np.abs(a - bg).sum(axis=2)
fg = dist > 60  # generous threshold

# remove alpha-ish noise: also require some saturation/brightness variety
mask = fg

# Connected components via BFS (4-connectivity), downsample by 2 for speed
scale = 2
ms = mask[::scale, ::scale]
hs, ws = ms.shape
labels = np.zeros((hs, ws), dtype=np.int32)
cur = 0
comps = []
for y in range(hs):
    for x in range(ws):
        if ms[y, x] and labels[y, x] == 0:
            cur += 1
            q = deque([(y, x)])
            labels[y, x] = cur
            n = 0
            minx = maxx = x
            miny = maxy = y
            while q:
                cy, cx = q.popleft()
                n += 1
                minx = min(minx, cx); maxx = max(maxx, cx)
                miny = min(miny, cy); maxy = max(maxy, cy)
                for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
                    ny, nx = cy+dy, cx+dx
                    if 0 <= ny < hs and 0 <= nx < ws and ms[ny, nx] and labels[ny, nx] == 0:
                        labels[ny, nx] = cur
                        q.append((ny, nx))
            comps.append((cur, n, minx*scale, miny*scale, maxx*scale, maxy*scale))

comps.sort(key=lambda c: -c[1])
print("components (id, pixels, x0,y0,x1,y1):")
for c in comps[:40]:
    _, n, x0, y0, x1, y1 = c
    print(f"  px={n:7d}  box=({x0},{y0})-({x1},{y1})  size={x1-x0}x{y1-y0}")
