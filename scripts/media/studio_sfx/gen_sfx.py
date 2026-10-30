"""Generate Phlio Studio's built-in sound effects (synthesised, royalty-free)."""
import json, subprocess, sys
from pathlib import Path
import numpy as np
SR = 44100
out = Path(sys.argv[1] if len(sys.argv) > 1 else 'studio_sfx'); out.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(7)
t_ = lambda d: np.arange(int(SR * d)) / SR
def env(n, a=.005, r=.2):
    t = np.arange(n) / SR; e = np.minimum(1, t / max(a, 1e-4)); return e * np.exp(-t / r)
def tone(f, d, r=.2, kind='sin'):
    t = t_(d); ph = 2 * np.pi * np.cumsum(np.broadcast_to(f, t.shape)) / SR
    w = np.sin(ph) if kind == 'sin' else np.sign(np.sin(ph)) * .5
    return w * env(len(t), r=r)
def noise(d, r=.2, lp=None):
    x = rng.standard_normal(int(SR * d))
    if lp:
        k = int(SR / lp); x = np.convolve(x, np.ones(k) / k, 'same') * np.sqrt(k)
    return x * env(len(x), r=r) * .4
fx = {
 'pop': ('Pop', 'Cartoon', tone(np.linspace(900, 300, int(SR*.12)), .12, .03)),
 'whoosh': ('Whoosh', 'Transitions', noise(.7, .25, lp=2000) * np.sin(np.linspace(0, np.pi, int(SR*.7)))),
 'swoosh_up': ('Swoosh up', 'Transitions', noise(.5, .3, lp=900) * np.linspace(0, 1, int(SR*.5))**2),
 'ding': ('Ding', 'Notification', tone(1320, 1.2, .35) + .4 * tone(2640, 1.2, .2)),
 'chime': ('Chime', 'Notification', sum(tone(f, 1.5, .5) * (.6 ** i) for i, f in enumerate([880, 1108.7, 1318.5]))),
 'click': ('Click', 'UI', noise(.04, .006)),
 'boing': ('Boing', 'Cartoon', tone(220 + 120 * np.sin(np.linspace(0, 30, int(SR*.6))), .6, .25)),
 'laser': ('Laser', 'Game', tone(np.geomspace(2400, 200, int(SR*.35)), .35, .2, 'sq')),
 'coin': ('Coin', 'Game', np.concatenate([tone(988, .08, 1, 'sq'), tone(1319, .4, .15, 'sq')])),
 'boom': ('Boom', 'Impact', tone(np.geomspace(120, 35, int(SR*1.2)), 1.2, .4) + noise(1.2, .15, lp=300)),
 'riser': ('Riser', 'Transitions', tone(np.geomspace(200, 1600, int(SR*2)), 2, 9) * np.linspace(0, 1, int(SR*2))**2 + noise(2, 9, lp=3000) * np.linspace(0, 1, int(SR*2))**3),
 'drumroll': ('Drum roll', 'Impact', sum(np.roll(np.pad(noise(.05, .02), (0, int(SR*1.6))), int(SR*.04*i))[:int(SR*1.6)] * (.5 + i/80) for i in range(38))),
 'record_scratch': ('Record scratch', 'Funny', noise(.5, .2, lp=1200) * np.abs(np.sin(np.linspace(0, 9, int(SR*.5))))),
 'camera': ('Camera shutter', 'UI', np.concatenate([noise(.05, .01), np.zeros(int(SR*.06)), noise(.08, .02)])),
 'heartbeat': ('Heartbeat', 'Ambient', np.concatenate([tone(55, .25, .08), np.zeros(int(SR*.05)), tone(50, .3, .1), np.zeros(int(SR*.5))]) * 2),
 'applause': ('Applause', 'Crowd', sum(np.roll(np.pad(noise(.03, .01), (0, int(SR*2.5))), int(rng.integers(0, int(SR*2.2))))[:int(SR*2.5)] for _ in range(260)) * np.minimum(1, np.linspace(3, 0, int(SR*2.5)))),
}
index = []
for key, (name, cat, x) in fx.items():
    x = np.asarray(x, dtype=np.float64); x = x / (np.abs(x).max() or 1) * .85
    pcm = (x * 32767).astype('<i2').tobytes()
    dst = out / f'{key}.m4a'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(SR), '-ac', '1', '-i', '-',
                    '-c:a', 'aac', '-b:a', '128k', str(dst)], input=pcm, check=True)
    index.append(dict(id=key, name=name, category=cat, duration=round(len(x) / SR, 2),
                      url=f'/media/studio_sfx/{key}.m4a'))
(out / 'index.json').write_text(json.dumps(index, indent=1))
print(len(index), 'effects')
