# Foxy rig — Foxy Moves sticker pack

Foxy is a flat illustration, so instead of redrawing him in parts he is
**rigged as a puppet**: each sticker places one piece of his existing art on a
320×320 canvas, drops a bone rig on it from a handful of landmarks (head,
eyes, ears, arm/paw, tail, a held prop) and animates the bones. The image is
bent with moving-least-squares rigid warping, so paws wave, tails wag, heads
tilt and bow, ears twitch and eyes blink while the art, colours and line work
stay exactly his. Props (sparkles, hearts, Zzz, tears, steam, notes,
confetti, a pancake, a sword trail) are drawn in brand colours by `sprites.py`.

| File | What it does |
|------|--------------|
| `rig.py` | Loads and repairs the source art, MLS warp, bones, global transforms |
| `bases.py` | Which artwork each sticker uses and how it sits on the canvas |
| `pack.py` | The 24 stickers: landmarks (`L_<NAME>`) and motion (`@sticker`) |
| `sprites.py` | Props |
| `render.py` | Renders a sticker to frames (`python render.py hi` writes a strip) |
| `export.py` | Writes the app WebPs and the Discord APNGs |

```
pip install numpy scipy opencv-python pillow
# plus pngquant and apngasm (apt install pngquant apngasm / brew install pngquant apngasm)
python scripts/media/foxy_rig/export.py            # all 24
python scripts/media/foxy_rig/export.py hi,wizard  # some
```

To add a sticker: add its art to `BASES`, read the landmark coordinates off a
grid render, add `L_<NAME>` and an `@sticker('<name>', seconds)` function
returning bone angles/offsets per time `t`, then add the id to
`FoxyPack.moves` (app) and `chat_pack.json` (backend).

Keep motions moderate around overlapping parts (e.g. the samurai's blade is
painted over his ear, so its swing stays small and a lunge sells the
strike) — a rig bends paint, it can't reveal what was never drawn.

## Live puppet (onboarding)

`puppet_export.py` exports the same rigs for the app's **live** Foxy
(`lib/design_system/widgets/foxy_puppet.dart`): the pose art plus a JSON of
control points, bones and eyes for four poses (neutral, wave, love, clap) and
a few props. The app builds a 44×44 textured mesh over the art and poses the
bones every frame — breathing, random blinks and ear twitches, talking nods,
head turns toward what you type, eyes-shut "not peeking", head tilts, nods,
an "oops" head-shake, hops, waves and claps — so onboarding gets smooth,
device-rate animation from ~1 MB of art.

    python scripts/media/foxy_rig/puppet_export.py
