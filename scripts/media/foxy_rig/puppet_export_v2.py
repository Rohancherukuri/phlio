"""Foxy v2 puppet export: rigs the new Foxy reference art (blue shorts,
button, cream tufts) for the app's real-time mesh animator.

  ref/<name>.png            reference art (flat background, may carry lettering)
  -> cutout.py              background, lettering and speed lines removed
  -> rig.place              scaled onto the 320 px sticker canvas (640 px @2x)
  -> LANDMARKS              hand-placed bones: head ring, eyes, ears, arm/paw,
                            tail, an extra limb (`prop`: leg, phone…), anchors
  => assets/foxy_puppet/foxy_puppet_<pose>.png + .json

Usage: python scripts/media/foxy_rig/puppet_export_v2.py [out_dir]
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
import rig  # noqa: E402
from cutout import cutout, RECIPES  # noqa: E402

# pose -> (reference image, landmarks in sticker px). See pack.build for keys.
LANDMARKS = {
    # Bright-eyed, paw out: idle / talking.
    'neutral': ('hello', dict(
        head=(130, 150), head_r=60, neck=(128, 214),
        eyes=[(95, 153, 11), (148, 152, 12)],
        ears=[(135, 48), (293, 205)],
        arm=dict(shoulder=(165, 228), paw=(212, 245), r=15),
        tail=dict(base=(62, 286), tip=(30, 216)),
        anchors=[(100, 304), (150, 304), (82, 300), (175, 300)],
        body=(128, 268), hips=(128, 306))),
    # Paw on head, one eye winking: hello / greeting.
    'wave': ('wink', dict(
        head=(152, 146), head_r=52, neck=(150, 205),
        eyes=[(156, 145, 9)],
        ears=[(200, 48), (297, 215)],
        arm=dict(shoulder=(146, 205), paw=(100, 132), r=18),
        tail=dict(base=(210, 262), tip=(266, 286)),
        anchors=[(75, 284), (160, 288), (110, 298), (232, 298), (60, 300)],
        body=(140, 250), hips=(150, 300))),
    # Blissful, paw to cheek: love.
    'love': ('bliss', dict(
        head=(112, 140), head_r=66, neck=(140, 222),
        ears=[(28, 225), (230, 182)],
        arm=dict(shoulder=(175, 198), paw=(190, 124), r=16),
        tail=dict(base=(205, 270), tip=(283, 228)),
        anchors=[(80, 304), (200, 304), (140, 300)],
        body=(150, 262), hips=(150, 306))),
    # Full body, mid-stride, pointing ahead: cheer / clap ("Let's go!").
    'clap': ('go', dict(
        head=(205, 158), head_r=48, neck=(185, 205),
        eyes=[(176, 160, 10), (232, 160, 10)],
        ears=[(185, 48), (62, 92)],
        arm=dict(shoulder=(178, 205), paw=(255, 200), r=14),
        prop=dict(pivot=(128, 248), pts=[(86, 262), (100, 268), (80, 254)], parent='body'),
        tail=dict(base=(112, 236), tip=(76, 142)),
        anchors=[(200, 294), (160, 298), (215, 286)],
        body=(150, 240), hips=(170, 296))),
    # Paws over his face: "I'm not looking" (password).
    'peek': ('sorry', dict(
        head=(175, 140), head_r=62, neck=(180, 222),
        ears=[(20, 90), (290, 100)],
        arm=dict(shoulder=(195, 245), paw=(225, 192), r=18),
        tail=dict(base=(100, 282), tip=(64, 210)),
        anchors=[(130, 304), (220, 304), (175, 300)],
        body=(180, 270), hips=(175, 306))),
    # Glasses on, paw at chin: thinking.
    'think': ('smart', dict(
        head=(132, 140), head_r=62, neck=(140, 218),
        ears=[(70, 48), (285, 78)],
        arm=dict(shoulder=(78, 240), paw=(72, 186), r=14),
        anchors=[(200, 288), (262, 288), (290, 300), (150, 302), (60, 302)],
        body=(150, 268), hips=(150, 306))),
    # Turned away, ears down: sad.
    'sad': ('sad', dict(
        head=(112, 140), head_r=64, neck=(150, 192),
        ears=[(110, 50), (283, 76)],
        tail=dict(base=(205, 266), tip=(286, 282)),
        anchors=[(60, 292), (140, 296), (100, 292), (180, 296)],
        body=(140, 240), hips=(140, 300))),
    # Phone to his ear: asking for a number.
    'phone': ('tel', dict(
        head=(150, 160), head_r=55, neck=(140, 226),
        eyes=[(107, 170, 10), (147, 175, 10)],
        ears=[(135, 48), (295, 198)],
        arm=dict(shoulder=(88, 246), paw=(50, 186), r=26),
        anchors=[(90, 304), (150, 304), (210, 304), (225, 255)],
        body=(130, 268), hips=(140, 306))),
    # Sheepish grin, sweat: oops.
    'oops': ('nervous', dict(
        head=(150, 155), head_r=60, neck=(155, 230),
        ears=[(18, 146), (300, 112)],
        arm=dict(shoulder=(162, 252), paw=(150, 210), r=12),
        tail=dict(base=(195, 272), tip=(242, 260)),
        anchors=[(110, 304), (170, 304), (140, 300)],
        body=(150, 275), hips=(150, 306))),
    # Full body, both arms up mid-hop: "hey!" — the splash finale.
    'hooray': ('seeyou2_x2', dict(
        head=(185, 140), head_r=50, neck=(165, 192),
        eyes=[(192, 147, 9)],
        ears=[(212, 48), (288, 195)],
        arm=dict(shoulder=(100, 176), paw=(68, 100), r=16),
        prop=dict(pivot=(122, 168), pts=[(118, 88), (114, 112)], parent='body'),
        tail=dict(base=(88, 232), tip=(42, 170)),
        anchors=[(105, 296), (150, 270), (176, 222)],
        body=(130, 232), hips=(118, 292))),
    # Curled up asleep on his pillow: quiet empty states.
    'sleep': ('sleep', dict(
        head=(215, 180), head_r=50, neck=(185, 214),
        ears=[(150, 58), (300, 129)],
        tail=dict(base=(112, 205), tip=(74, 124)),
        anchors=[(132, 166), (292, 250), (182, 282), (240, 282), (72, 266), (110, 258)],
        body=(120, 222), hips=(150, 272))),
}

PLACE = {'sleep': dict(height=262, max_width=290, bottom=290)}


def export(out: Path):
    import pack  # noqa: E402  (pack.build: landmarks -> Rig)
    out.mkdir(parents=True, exist_ok=True)
    for pose, (ref, L) in LANDMARKS.items():
        art = cutout(HERE / 'ref' / f'{ref}.png', **RECIPES[ref])
        arr = rig.place(art, **PLACE.get(pose, dict(height=262, max_width=290, bottom=306)))
        a = arr[..., 3:4]
        rgb = np.where(a > 1e-4, arr[..., :3] / np.maximum(a, 1e-4), 0)
        img = Image.fromarray((np.concatenate([rgb, a], 2).clip(0, 1) * 255 + 0.5).astype(np.uint8))
        png = out / f'foxy_puppet_{pose}.png'
        img.save(png, optimize=True)
        if shutil.which('pngquant'):  # ~300 KB -> ~100 KB, visually identical
            subprocess.run(['pngquant', '--quality=60-95', '--speed', '1', '--strip',
                            '-f', '--ext', '.png', str(png)], check=False)
        r, eyes = pack.build(L)
        bone_names = list(r.bones.keys())
        owner = {n: bone_names.index(b) for b, spec in r.bones.items() for n in spec['pts']}
        names = list(r.points.keys())
        pts = [[round(r.points[n][0], 2), round(r.points[n][1], 2), owner.get(n, -1)] for n in names]
        pts += [[round(x, 2), round(y, 2), -1] for x, y in r.anchors]
        bones = [dict(name=b, pivot=[round(v, 2) for v in r.bones[b]['pivot']],
                      parent=bone_names.index(r.bones[b]['parent']) if r.bones[b].get('parent') else -1)
                 for b in bone_names]
        eye_list = [dict(c=names.index(f'e{k}c'), t=names.index(f'e{k}t'), b=names.index(f'e{k}b'))
                    for k, *_ in eyes]
        ys, xs = np.where(np.array(img)[..., 3] > 30)
        json.dump(dict(size=320, scale=2, points=pts, bones=bones, eyes=eye_list,
                       bounds=[int(xs.min()) / 2, int(ys.min()) / 2, int(xs.max()) / 2, int(ys.max()) / 2],
                       head=list(L['head'])),
                  open(out / f'foxy_puppet_{pose}.json', 'w'), separators=(',', ':'))
        print(pose, ref, len(pts), 'points', bone_names,
              (out / f'foxy_puppet_{pose}.png').stat().st_size // 1024, 'KB')


if __name__ == '__main__':
    export(Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[2] / 'frontend/ui/assets/foxy_puppet')
