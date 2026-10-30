"""Exports Foxy's puppet rigs for the app's live animator
(lib/design_system/widgets/foxy_puppet.dart) into
frontend/ui/assets/foxy_puppet/:

  foxy_puppet_<pose>.png   the pose art on a 640x640 canvas (320 rig px at 2x)
  foxy_puppet_<pose>.json  control points, bones, eyes
  foxy_fx_<name>.png       props (sparkles, heart, sweat drop, ?, z)

    python scripts/media/foxy_rig/puppet_export.py
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).parent))
import rig, pack
import sprites as sp
from bases import BASES

POSES = {
    'neutral': ('sad', pack.L_SAD),
    'wave': ('hi', pack.L_HI),
    'love': ('love', pack.L_LOVE),
    'clap': ('clap', pack.L_CLAP),
}
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[3] / 'frontend/ui/assets/foxy_puppet'
out.mkdir(parents=True, exist_ok=True)
for pose, (base, L) in POSES.items():
    kind, name, kw = BASES[base]
    arr = rig.place(rig.load(kind, name), **kw)          # premultiplied, 640x640
    a = arr[..., 3:4]
    rgb = np.where(a > 1e-4, arr[..., :3] / np.maximum(a, 1e-4), 0)
    img = Image.fromarray((np.concatenate([rgb, a], 2).clip(0, 1) * 255 + 0.5).astype(np.uint8))
    img.save(out / f'foxy_puppet_{pose}.png', optimize=True)
    r, eyes = pack.build(L)
    bone_names = list(r.bones.keys())
    owner = {}
    for b, spec in r.bones.items():
        for n in spec['pts']:
            owner[n] = bone_names.index(b)
    names = list(r.points.keys())
    pts = [[round(r.points[n][0], 2), round(r.points[n][1], 2), owner.get(n, -1)] for n in names]
    pts += [[round(x, 2), round(y, 2), -1] for x, y in r.anchors]
    bones = [dict(name=b, pivot=[round(v, 2) for v in r.bones[b]['pivot']],
                  parent=bone_names.index(r.bones[b]['parent']) if r.bones[b].get('parent') else -1)
             for b in bone_names]
    eye_list = [dict(c=names.index(f'e{k}c'), t=names.index(f'e{k}t'), b=names.index(f'e{k}b')) for k, *_ in eyes]
    ys, xs = np.where(np.array(img)[..., 3] > 30)
    json.dump(dict(size=320, scale=2, points=pts, bones=bones, eyes=eye_list,
                   bounds=[int(xs.min()) / 2, int(ys.min()) / 2, int(xs.max()) / 2, int(ys.max()) / 2],
                   head=list(L['head'])),
              open(out / f'foxy_puppet_{pose}.json', 'w'), separators=(',', ':'))
    print(pose, len(pts), 'points', bone_names, (out / f'foxy_puppet_{pose}.png').stat().st_size // 1024, 'KB')

for name, img in {
    'sparkle_peach': sp.sparkle(sp.PEACH, 64), 'sparkle_violet': sp.sparkle(sp.VIOLET, 64),
    'sparkle_yellow': sp.sparkle(sp.YELLOW, 64), 'heart': sp.heart(64), 'sweat': sp.sweat(36),
    'question': sp.question(72), 'zed': sp.zed(56),
}.items():
    img.save(out / f'foxy_fx_{name}.png', optimize=True)
