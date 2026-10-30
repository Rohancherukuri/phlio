"""Exports Foxy Moves:
  frontend/ui/assets/stickers/moves/move_<name>.webp  (app, 240 px, 12 fps)
  brand/foxy-moves/discord/foxy_<name>.png            (Discord APNG, 320 px, <= 512 KB)

    python scripts/media/foxy_rig/export.py [name,name,...]

Needs: numpy, scipy, opencv-python, pillow; pngquant and apngasm on PATH.
"""
import sys, os, subprocess, tempfile, glob
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import render, pack
from PIL import Image
ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / 'frontend/ui/assets/stickers/moves'
DISCORD = ROOT / 'brand/foxy-moves/discord'
TMP = Path(tempfile.mkdtemp(prefix='foxy_moves_'))
APP.mkdir(parents=True, exist_ok=True); DISCORD.mkdir(parents=True, exist_ok=True)
names=sys.argv[1].split(',') if len(sys.argv)>1 else list(pack.STICKERS)
for name in names:
    fr=render.render(name, fps=12)
    # App: animated WebP at 240 px (Flutter plays it natively; bubbles show
    # stickers at ~112-150 logical px).
    small=[f.resize((240,240), Image.LANCZOS) for f in fr]
    small[0].save(str(APP / f'move_{name}.webp'), save_all=True, append_images=small[1:], duration=round(1000/12), loop=0,
               quality=74, method=6, alpha_quality=85, minimize_size=True)
    # Discord: APNG, 320x320, <=512 KB, 12 fps. All frames share one
    # palette (quantised as a strip) so unchanged pixels stay identical.
    d15=fr
    strip=Image.new('RGBA',(320*len(d15),320))
    for i,f in enumerate(d15): strip.alpha_composite(f,(i*320,0))
    sp_=str(TMP / f'{name}_strip.png'); strip.save(sp_)
    out=str(DISCORD / f'foxy_{name}.png')
    def build(q, colours, fps=12):
        qp=sp_.replace('.png','_q.png')
        subprocess.run(['pngquant','--force','--nofs','--quality',q,'--speed','1',str(colours),'--output',qp,sp_],check=False)
        if os.path.exists(out): os.remove(out)
        subprocess.run(['apngasm',out,qp,'1',str(fps),f'-hs{len(d15)}','-z1','-i5'],stdout=subprocess.DEVNULL,check=False)
    for q, colours in [('60-90', 256), ('45-75', 160), ('30-60', 96), ('10-40', 64)]:
        build(q, colours)
        if os.path.getsize(out) <= 512000:
            break
    if os.path.getsize(out) > 512000:
        # Still over Discord's limit: drop to 8 fps for this one.
        d15 = render.render(name, fps=8)
        strip=Image.new('RGBA',(320*len(d15),320))
        for i,f in enumerate(d15): strip.alpha_composite(f,(i*320,0))
        strip.save(sp_)
        for q, colours in [('45-75', 160), ('10-40', 64)]:
            build(q, colours, fps=8)
            if os.path.getsize(out) <= 512000:
                break
    print(name, len(fr), os.path.getsize(str(APP / f'move_{name}.webp'))//1024, 'KB webp |', os.path.getsize(out)//1024, 'KB apng', flush=True)
