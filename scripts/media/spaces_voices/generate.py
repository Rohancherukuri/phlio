"""Speak the seeded Spaces with Kokoro TTS, one track per speaker.

    pip install kokoro-onnx soundfile numpy
    # model files: https://github.com/thewh1teagle/kokoro-onnx/releases (model-files-v1.0)
    python scripts/media/spaces_voices/generate.py backend/media/spaces_seed \
        --model kokoro-v1.0.onnx --voices voices-v1.0.bin [space keys...]


Output per Space (backend/media/spaces_seed/<key>/):
  <role>.ogg      one Opus track per speaker, silence while others talk
  mix.m4a         the whole conversation (used for seeded recordings)
  timeline.json   [[start, end, role], ...] + duration + peaks
"""
import json, os, random, subprocess, sys
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

sys.path.insert(0, os.path.dirname(__file__))
from conversations import SPACES

import argparse
ap = argparse.ArgumentParser()
ap.add_argument('out')
ap.add_argument('keys', nargs='*')
ap.add_argument('--model', default='kokoro-v1.0.onnx')
ap.add_argument('--voices', default='voices-v1.0.bin')
args = ap.parse_args()
OUT = args.out
SR = 24000
k = Kokoro(args.model, args.voices)


def trim(x, thr=0.008):
    idx = np.where(np.abs(x) > thr)[0]
    if len(idx) == 0:
        return x
    a, b = max(0, idx[0] - int(0.03 * SR)), min(len(x), idx[-1] + int(0.08 * SR))
    return x[a:b]


def peaks(x, n=96):
    chunks = np.array_split(np.abs(x), n)
    p = np.array([float(np.sqrt(np.mean(c ** 2))) if len(c) else 0 for c in chunks])
    p = p / (p.max() or 1)
    return [round(float(v), 3) for v in p]


only = set(args.keys)
for sp in SPACES:
    if only and sp['key'] not in only:
        continue
    rnd = random.Random(sp['key'])
    d = os.path.join(OUT, sp['key'])
    os.makedirs(d, exist_ok=True)
    clips = []
    speed = {r: 1.0 + rnd.uniform(-0.03, 0.06) for r in sp['cast']}
    for role, text in sp['lines']:
        voice = sp['cast'][role][1]
        audio, sr = k.create(text, voice=voice, speed=speed[role], lang='en-us')
        assert sr == SR
        clips.append((role, trim(audio.astype(np.float32)), text))
    t = 2.0
    timeline = []
    prev_role = None
    for role, a, text in clips:
        short = len(a) < 1.2 * SR
        gap = rnd.uniform(0.12, 0.3) if short else rnd.uniform(0.32, 0.75)
        if prev_role == role:
            gap = rnd.uniform(0.5, 0.9)
        start = t + gap
        timeline.append([round(start, 3), round(start + len(a) / SR, 3), role])
        t = start + len(a) / SR
        prev_role = role
    total = t + 4.0
    n = int(total * SR)
    tracks = {r: np.zeros(n, np.float32) for r in sp['cast']}
    for (start, end, role), (_, a, _) in zip(timeline, clips):
        i = int(start * SR)
        tracks[role][i:i + len(a)] += a
    mix = sum(tracks.values())
    gain = 0.92 / max(1e-6, float(np.abs(mix).max()))
    for r, x in tracks.items():
        wav = os.path.join(d, r + '.wav')
        sf.write(wav, np.clip(x * gain, -1, 1), SR, subtype='PCM_16')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libopus',
                        '-b:a', '32k', '-ac', '1', os.path.join(d, r + '.ogg')], check=True)
        os.remove(wav)
    wav = os.path.join(d, 'mix.wav')
    sf.write(wav, np.clip(mix * gain, -1, 1), SR, subtype='PCM_16')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'aac', '-b:a', '64k',
                    '-ac', '1', os.path.join(d, 'mix.m4a')], check=True)
    os.remove(wav)
    json.dump(dict(duration=round(total, 2), timeline=timeline, peaks=peaks(mix)),
              open(os.path.join(d, 'timeline.json'), 'w'))
    print(sp['key'], round(total, 1), 's', flush=True)

# The runner reads the cast/titles from spaces.json.
meta = [{k: v for k, v in sp.items() if k != 'lines'} for sp in SPACES]
for m in meta:
    m['cast'] = {r: list(v) for r, v in m['cast'].items()}
json.dump(meta, open(os.path.join(OUT, 'spaces.json'), 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
