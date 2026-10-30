"""Bounded, local FFmpeg composition for the DM editor (Phlio Studio).

The Flutter editor (a CapCut-style timeline) sends a plan:

  clips     main track. Per clip: source (photo/video), trim, speed or a speed
            curve, volume, voice changer, noise reduction, rotate/flip, crop,
            reverse, freeze, a 3x4 colour matrix (filters + adjustments, the
            same matrix the app previews with), vignette/sharpen/grain, an
            effect, fill/fit framing with zoom + pan (optionally keyframed),
            Ken Burns motion, fades and the transition into the next clip.
  pips      overlay (picture-in-picture) layers: photo/video placed on the
            canvas with keyframes, opacity, blend mode, a mask (PNG drawn by
            the app, feathered) and chroma key.
  segments  timeline effects / filters / adjustments applied to whatever is
            on screen between two times (CapCut's effect & filter lanes).
  overlays  text, captions and stickers as PNGs rendered by the app, with
            keyframes and in / out / loop animations.
  audios    music, sound effects, text-to-speech, extracted audio and
            voiceovers on the timeline, with trim, volume, fades, voice
            changer and noise reduction.
  cover     a frame (or uploaded photo, optional text PNG) embedded as the
            video's cover art.

Rendering: one encode per clip (normalised to the canvas), a chain joining
them with cuts or xfade transitions, then a final pass for segments, overlay
layers, text and the audio mix. Progress is reported per stage.

Older clients (single global filter/text/music fields) still render.
"""
import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Callable, Literal

from fastapi import HTTPException
from pydantic import BaseModel, Field, model_validator

TRANSITIONS = ('none', 'fade', 'fadeblack', 'fadewhite', 'dissolve', 'slideleft', 'slideright',
               'slideup', 'slidedown', 'wipeleft', 'wiperight', 'circleopen', 'circleclose', 'radial',
               'pixelize', 'hblur', 'zoomin', 'smoothleft', 'squeezeh', 'distance')
EFFECTS = ('none', 'vignette', 'grain', 'blur', 'glitch', 'vhs', 'film', 'mirror', 'shake', 'flash',
           'pixelate', 'soft', 'rgb_split', 'dream', 'neon', 'sepia_flicker')
SEGMENT_EFFECTS = ('vignette', 'grain', 'blur', 'glitch', 'vhs', 'film', 'flash', 'rgb_split', 'dream',
                   'neon', 'sepia_flicker')
VOICES = ('none', 'chipmunk', 'deep', 'robot', 'echo', 'hall', 'radio', 'megaphone', 'vibrato', 'tremolo')
BLENDS = ('normal', 'screen', 'multiply', 'overlay', 'lighten', 'darken', 'addition', 'softlight',
          'hardlight', 'difference', 'exclusion', 'colordodge', 'colorburn')
NEUTRAL = {'screen': 'black', 'multiply': 'white', 'overlay': '0x808080', 'lighten': 'black',
           'darken': 'white', 'addition': 'black', 'softlight': '0x808080', 'hardlight': '0x808080',
           'difference': 'black', 'exclusion': 'black', 'colordodge': 'black', 'colorburn': 'white'}
QUALITY = {'low': 26, 'recommended': 21, 'high': 17}
LIBRARY_PREFIXES = ('/media/stream_music/', '/media/studio_sfx/')
Transition = Literal[TRANSITIONS]  # type: ignore[valid-type]
Effect = Literal[EFFECTS]  # type: ignore[valid-type]
SegmentEffect = Literal[SEGMENT_EFFECTS]  # type: ignore[valid-type]
Voice = Literal[VOICES]  # type: ignore[valid-type]
Blend = Literal[BLENDS]  # type: ignore[valid-type]
FileId = Field(pattern=r'^[a-f0-9]{32}$')
OptionalFileId = Field(default=None, pattern=r'^[a-f0-9]{32}$')
IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]
LEGACY_FILTERS = {
    'mono': [.299, .587, .114, 0, .299, .587, .114, 0, .299, .587, .114, 0],
    'warm': [1.08, 0, 0, 0, 0, 1, 0, 0, 0, 0, .94, 0],
    'cool': [.94, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1.08, 0],
}


def _finite(values, limit):
    return all(math.isfinite(v) and abs(v) <= limit for v in values)


def _valid_color(m):
    if m is not None and not _finite(m, 2):
        raise ValueError('Invalid colour adjustment.')


def _valid_keys(keys, width):
    for k in keys or []:
        if len(k) != width or not _finite(k, 4000):
            raise ValueError('Invalid keyframes.')


class StudioClip(BaseModel):
    file_id: str = FileId
    start: float = Field(default=0, ge=0, le=3600, allow_inf_nan=False)
    end: float = Field(default=3, gt=0, le=3600, allow_inf_nan=False)
    speed: float = Field(default=1, ge=0.1, le=10, allow_inf_nan=False)
    # Speed curve: [[from, to, speed], ...] over the trimmed range (0-1).
    curve: list[list[float]] | None = Field(default=None, max_length=16)
    volume: float = Field(default=1, ge=0, le=2, allow_inf_nan=False)
    voice: Voice = 'none'
    denoise: bool = False
    turns: int = Field(default=0, ge=0, le=3)
    flip: bool = False
    flip_v: bool = False
    reverse: bool = False
    hold: float | None = Field(default=None, ge=.3, le=30, allow_inf_nan=False)  # freeze frame
    crop: list[float] | None = Field(default=None, min_length=4, max_length=4)  # x, y, w, h (0-1)
    color: list[float] | None = Field(default=None, min_length=12, max_length=12)
    vignette: float = Field(default=0, ge=0, le=1, allow_inf_nan=False)
    sharpen: float = Field(default=0, ge=0, le=1, allow_inf_nan=False)
    grain: float = Field(default=0, ge=0, le=1, allow_inf_nan=False)
    effect: Effect = 'none'
    fit: Literal['fill', 'fit'] = 'fill'
    zoom: float = Field(default=1, ge=.5, le=4, allow_inf_nan=False)
    pan_x: float = Field(default=0, ge=-1, le=1, allow_inf_nan=False)
    pan_y: float = Field(default=0, ge=-1, le=1, allow_inf_nan=False)
    keys: list[list[float]] | None = Field(default=None, max_length=40)  # [t_local, zoom, pan_x, pan_y]
    motion: Literal['none', 'zoom_in', 'zoom_out', 'pan_left', 'pan_right'] = 'none'
    anim_in: Literal['none', 'fade', 'fade_white'] = 'none'
    anim_out: Literal['none', 'fade', 'fade_white'] = 'none'
    fade_audio_in: float = Field(default=0, ge=0, le=10, allow_inf_nan=False)
    fade_audio_out: float = Field(default=0, ge=0, le=10, allow_inf_nan=False)
    transition: Transition = 'none'  # into the next clip
    transition_duration: float = Field(default=.5, ge=.1, le=2, allow_inf_nan=False)

    @model_validator(mode='after')
    def valid(self):
        if self.hold is None and self.end - self.start < .3:
            raise ValueError('Each clip must be at least 0.3 seconds.')
        if self.crop:
            x, y, w, h = self.crop
            if not (0 <= x < 1 and 0 <= y < 1 and .05 <= w <= 1 and .05 <= h <= 1 and x + w <= 1.001 and y + h <= 1.001):
                raise ValueError('Invalid crop.')
        _valid_color(self.color)
        _valid_keys(self.keys, 4)
        if self.curve:
            last = 0.0
            for a, b, s in self.curve:
                if not (abs(a - last) < 1e-3 and b > a and .1 <= s <= 10):
                    raise ValueError('Invalid speed curve.')
                last = b
            if abs(last - 1) > 1e-3:
                raise ValueError('Invalid speed curve.')
            if self.reverse:
                raise ValueError('Speed curves cannot be reversed.')
        if self.reverse and self.end - self.start > 30:
            raise ValueError('Reverse works on clips up to 30 seconds.')
        return self

    @property
    def length(self) -> float:
        if self.hold is not None:
            return self.hold
        span = self.end - self.start
        if self.curve:
            return max(.3, sum((b - a) * span / s for a, b, s in self.curve))
        return max(.3, span / self.speed)


class StudioOverlay(BaseModel):
    """Text / caption / sticker PNG."""
    file_id: str = FileId
    x: float = Field(ge=-2, le=3, allow_inf_nan=False)  # static: top-left of the (rotated) PNG
    y: float = Field(ge=-2, le=3, allow_inf_nan=False)
    w: float = Field(gt=0, le=4, allow_inf_nan=False)  # width, fraction of canvas width
    start: float = Field(default=0, ge=0, le=3600, allow_inf_nan=False)
    end: float = Field(default=3600, gt=0, le=3600, allow_inf_nan=False)
    anim_in: Literal['none', 'fade', 'slide_up', 'slide_left', 'pop', 'drop'] = 'fade'
    anim_out: Literal['none', 'fade', 'slide_down', 'shrink'] = 'fade'
    loop: Literal['none', 'bounce', 'pulse', 'wiggle', 'float', 'blink'] = 'none'
    # Dynamic placement (keyframes / loops / pop): PNG is unrotated at scale 1.
    cx: float | None = Field(default=None, ge=-2, le=3, allow_inf_nan=False)
    cy: float | None = Field(default=None, ge=-2, le=3, allow_inf_nan=False)
    rotation: float = Field(default=0, ge=-50, le=50, allow_inf_nan=False)
    keys: list[list[float]] | None = Field(default=None, max_length=40)  # [t, cx, cy, scale, rot, opacity]

    @model_validator(mode='after')
    def valid(self):
        _valid_keys(self.keys, 6)
        return self

    @property
    def dynamic(self) -> bool:
        return self.cx is not None and (bool(self.keys) or self.loop != 'none'
                                        or self.anim_in in ('pop', 'drop') or self.anim_out == 'shrink')


class StudioPip(BaseModel):
    """Overlay media layer (picture-in-picture)."""
    file_id: str = FileId
    at: float = Field(default=0, ge=0, le=3600, allow_inf_nan=False)
    start: float = Field(default=0, ge=0, le=3600, allow_inf_nan=False)
    end: float = Field(default=3, gt=0, le=3600, allow_inf_nan=False)
    speed: float = Field(default=1, ge=.25, le=4, allow_inf_nan=False)
    volume: float = Field(default=1, ge=0, le=2, allow_inf_nan=False)
    cx: float = Field(default=.5, ge=-2, le=3, allow_inf_nan=False)
    cy: float = Field(default=.5, ge=-2, le=3, allow_inf_nan=False)
    w: float = Field(default=.5, gt=0, le=4, allow_inf_nan=False)
    rotation: float = Field(default=0, ge=-50, le=50, allow_inf_nan=False)
    flip: bool = False
    opacity: float = Field(default=1, ge=0, le=1, allow_inf_nan=False)
    blend: Blend = 'normal'
    mask_id: str | None = OptionalFileId  # grayscale PNG, same aspect as the layer
    chroma: str | None = Field(default=None, pattern=r'^#[0-9a-fA-F]{6}$')
    chroma_strength: float = Field(default=.3, ge=.01, le=1, allow_inf_nan=False)
    color: list[float] | None = Field(default=None, min_length=12, max_length=12)
    keys: list[list[float]] | None = Field(default=None, max_length=40)  # [t, cx, cy, scale, rot, opacity]
    anim_in: Literal['none', 'fade'] = 'none'
    anim_out: Literal['none', 'fade'] = 'none'

    @model_validator(mode='after')
    def valid(self):
        _valid_color(self.color)
        _valid_keys(self.keys, 6)
        if self.end - self.start < .2:
            raise ValueError('Overlay clips must be at least 0.2 seconds.')
        return self

    @property
    def length(self) -> float:
        return max(.2, (self.end - self.start) / self.speed)


class StudioSegment(BaseModel):
    """An effect / filter / adjustment over a stretch of the timeline."""
    kind: Literal['effect', 'color']
    effect: SegmentEffect | None = None
    color: list[float] | None = Field(default=None, min_length=12, max_length=12)
    vignette: float = Field(default=0, ge=0, le=1, allow_inf_nan=False)
    sharpen: float = Field(default=0, ge=0, le=1, allow_inf_nan=False)
    grain: float = Field(default=0, ge=0, le=1, allow_inf_nan=False)
    start: float = Field(ge=0, le=3600, allow_inf_nan=False)
    end: float = Field(gt=0, le=3600, allow_inf_nan=False)

    @model_validator(mode='after')
    def valid(self):
        _valid_color(self.color)
        if self.kind == 'effect' and not self.effect:
            raise ValueError('Choose an effect.')
        return self


class StudioAudio(BaseModel):
    file_id: str | None = OptionalFileId
    library_url: str | None = Field(default=None, max_length=300)  # Stream track or sound effect
    at: float = Field(default=0, ge=0, le=3600, allow_inf_nan=False)  # timeline position
    start: float = Field(default=0, ge=0, le=7200, allow_inf_nan=False)  # in-point in the source
    end: float | None = Field(default=None, gt=0, le=7200, allow_inf_nan=False)
    volume: float = Field(default=1, ge=0, le=2, allow_inf_nan=False)
    fade_in: float = Field(default=0, ge=0, le=10, allow_inf_nan=False)
    fade_out: float = Field(default=0, ge=0, le=10, allow_inf_nan=False)
    voice: Voice = 'none'
    denoise: bool = False
    loop: bool = False

    @model_validator(mode='after')
    def one_source(self):
        if bool(self.file_id) == bool(self.library_url):
            raise ValueError('Each audio item needs exactly one source.')
        if self.library_url and (not self.library_url.startswith(LIBRARY_PREFIXES)
                                 or '..' in self.library_url):
            raise ValueError('Only Phlio library sounds can be used.')
        return self


class StudioCover(BaseModel):
    time: float | None = Field(default=None, ge=0, le=3600, allow_inf_nan=False)
    file_id: str | None = OptionalFileId  # uploaded photo
    overlay_id: str | None = OptionalFileId  # cover text PNG (full-canvas)


class StudioPlan(BaseModel):
    clips: list[StudioClip] = Field(min_length=1, max_length=30)
    pips: list[StudioPip] = Field(default_factory=list, max_length=6)
    segments: list[StudioSegment] = Field(default_factory=list, max_length=20)
    overlays: list[StudioOverlay] = Field(default_factory=list, max_length=80)
    audios: list[StudioAudio] = Field(default_factory=list, max_length=12)
    cover: StudioCover | None = None
    mute_original: bool = False
    ratio: Literal['original', '9:16', '16:9', '1:1', '4:5', '3:4', '4:3', '2:1', '2.35:1', '5.8in'] = '9:16'
    resolution: Literal[480, 720, 1080] = 720
    fps: Literal[24, 25, 30, 50, 60] = 30
    quality: Literal['low', 'recommended', 'high'] = 'recommended'
    background: str = Field(default='blur', pattern=r'^(blur|#[0-9a-fA-F]{6})$')
    blur: float = Field(default=.6, ge=0, le=1, allow_inf_nan=False)
    image_format: Literal['jpg', 'png'] = 'jpg'
    # Legacy (v1 editor) fields.
    music_id: str | None = OptionalFileId
    music_volume: float = Field(default=.3, ge=0, le=1, allow_inf_nan=False)
    transition: Literal['none', 'fade', 'dissolve', 'slideleft'] = 'none'
    filter: Literal['normal', 'mono', 'warm', 'cool'] = 'normal'
    brightness: float = Field(default=0, ge=-.3, le=.3, allow_inf_nan=False)
    contrast: float = Field(default=1, ge=.5, le=1.5, allow_inf_nan=False)
    saturation: float = Field(default=1, ge=0, le=2, allow_inf_nan=False)
    text: str = Field(default='', max_length=180)

    @model_validator(mode='after')
    def bounded(self):
        if sum(c.length for c in self.clips) > 300:
            raise ValueError('Keep projects within five minutes.')
        return self

    @property
    def total(self) -> float:
        total = 0.0
        for i, clip in enumerate(self.clips):
            total += clip.length
            if i and self.clips[i - 1].transition != 'none':
                total -= overlap(self.clips[i - 1], clip)
        return total

    @property
    def image_only(self) -> bool:
        c = self.clips[0]
        return (len(self.clips) == 1 and c.motion == 'none' and not c.keys and not self.audios
                and not self.music_id and not self.pips and not self.segments
                and not any(o.dynamic for o in self.overlays)
                and c.anim_in == 'none' and c.anim_out == 'none' and c.effect not in ('shake', 'flash'))


def overlap(a: StudioClip, b: StudioClip) -> float:
    return min(a.transition_duration, a.length / 3, b.length / 3)


def legacy_matrix(plan: StudioPlan) -> list[float] | None:
    """v1 editor: one filter + eq sliders for the whole project."""
    if plan.filter == 'normal' and plan.brightness == 0 and plan.contrast == 1 and plan.saturation == 1:
        return None
    m = LEGACY_FILTERS.get(plan.filter, IDENTITY)
    s = plan.saturation
    lr, lg, lb = .2126 * (1 - s), .7152 * (1 - s), .0722 * (1 - s)
    sat = [lr + s, lg, lb, 0, lr, lg + s, lb, 0, lr, lg, lb + s, 0]
    k = plan.contrast
    con = [k, 0, 0, .5 * (1 - k) + plan.brightness, 0, k, 0, .5 * (1 - k) + plan.brightness,
           0, 0, k, .5 * (1 - k) + plan.brightness]
    return mul(con, mul(sat, m))


def mul(a, b):
    """3x4 affine colour matrices: a ∘ b."""
    out = []
    for r in range(3):
        row = a[r * 4:r * 4 + 4]
        for col in range(3):
            out.append(sum(row[k] * b[k * 4 + col] for k in range(3)))
        out.append(sum(row[k] * b[k * 4 + 3] for k in range(3)) + row[3])
    return out


def atempo(speed: float) -> str:
    parts = []
    while speed > 2:
        parts.append('atempo=2')
        speed /= 2
    while speed < .5:
        parts.append('atempo=0.5')
        speed /= .5
    parts.append(f'atempo={speed:.5f}')
    return ','.join(parts)


def voice_filters(voice: str, denoise: bool) -> list[str]:
    out = ['afftdn=nf=-25'] if denoise else []
    pitch = {'chipmunk': 1.4, 'deep': .74}.get(voice)
    if pitch:
        out += ['aresample=48000', f'asetrate={round(48000 * pitch)}', 'aresample=48000', atempo(1 / pitch)]
    out += {
        'robot': ["afftfilt=real='hypot(re,im)*sin(0)':imag='hypot(re,im)*cos(0)':win_size=512:overlap=0.75"],
        'echo': ['aecho=0.8:0.85:120:0.45'],
        'hall': ['aecho=0.8:0.9:500|900|1400:0.35|0.25|0.18'],
        'radio': ['highpass=f=320', 'lowpass=f=3200', 'acompressor=threshold=-18dB:ratio=6', 'volume=1.6'],
        'megaphone': ['highpass=f=600', 'lowpass=f=2800', 'volume=2.4', 'alimiter=limit=0.9'],
        'vibrato': ['vibrato=f=6:d=0.6'],
        'tremolo': ['tremolo=f=7:d=0.7'],
    }.get(voice, [])
    return out


RATIOS = {'9:16': 9 / 16, '16:9': 16 / 9, '1:1': 1, '4:5': 4 / 5, '3:4': 3 / 4, '4:3': 4 / 3, '2:1': 2,
          '2.35:1': 2.35, '5.8in': 1125 / 2436}


def canvas(plan: StudioPlan, first: dict) -> tuple[int, int]:
    clip = plan.clips[0]
    w, h = first['width'], first['height']
    if clip.turns % 2:
        w, h = h, w
    if clip.crop:
        w, h = w * clip.crop[2], h * clip.crop[3]
    ratio = RATIOS.get(plan.ratio, w / h)
    short = plan.resolution
    width = short if ratio <= 1 else short * ratio
    height = short / ratio if ratio <= 1 else short
    scale = min(1, 1920 / max(width, height))
    return int(width * scale) // 4 * 4, int(height * scale) // 4 * 4


def color_chain(m, vignette=0.0, sharpen=0.0, grain=0.0, enable='') -> list[str]:
    out = []
    if m and [round(v, 4) for v in m] != IDENTITY:
        out.append('colorchannelmixer=' + ':'.join(
            f'{n}={v:.4f}' for n, v in zip(
                ['rr', 'rg', 'rb', 'gr', 'gg', 'gb', 'br', 'bg', 'bb'],
                [m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]])) + enable)
        offsets = [m[3], m[7], m[11]]
        if any(abs(o) > .002 for o in offsets):
            out.append("lutrgb=" + ':'.join(
                f"{c}='clip(val+{round(o * 255)},0,255)'" for c, o in zip('rgb', offsets)) + enable)
    if sharpen > 0:
        out.append(f'unsharp=5:5:{sharpen * 1.6:.2f}' + enable)
    if grain > 0:
        out.append(f'noise=alls={round(grain * 28)}:allf=t+u' + enable)
    if vignette > 0:
        out.append(f'vignette=angle={0.25 + vignette * 0.55:.3f}' + enable)
    return out


SEGMENT_FILTERS = {
    'vignette': ['vignette=angle=PI/4'],
    'grain': ['noise=alls=16:allf=t+u'],
    'blur': ['gblur=sigma=8'],
    'glitch': ['rgbashift=rh=-10:bh=10', 'noise=alls=10:allf=t'],
    'rgb_split': ['rgbashift=rh=-7:bv=7'],
    'vhs': ['curves=preset=vintage', 'rgbashift=rh=4:bh=-4', 'noise=alls=12:allf=t', 'eq=saturation=1.25'],
    'film': ['hue=s=0', 'eq=contrast=1.15', 'noise=alls=18:allf=t+u', 'vignette=angle=PI/4'],
    'flash': ["eq=brightness='0.3*pow(max(0,sin(t*5)),8)':eval=frame"],
    'dream': ['gblur=sigma=3', "eq=brightness=0.06:saturation=1.2", 'curves=preset=lighter'],
    'neon': ['eq=saturation=1.8:contrast=1.2', 'unsharp=7:7:1.2'],
    'sepia_flicker': ['colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131',
                      "eq=brightness='0.04*sin(t*23)':eval=frame", 'noise=alls=10:allf=t'],
}


def effect_graph(effect: str, src: str, dst: str, W: int, H: int) -> str:
    if effect in SEGMENT_FILTERS:
        return f"[{src}]{','.join(SEGMENT_FILTERS[effect])}[{dst}]"
    simple = {
        'none': 'null',
        'shake': (f"crop=w=iw*0.9:h=ih*0.9:x=(iw-ow)/2+sin(t*37)*iw*0.025:y=(ih-oh)/2+cos(t*29)*ih*0.025,"
                  f"scale={W}:{H}"),
        'pixelate': f'scale={max(8, W // 18)}:{max(8, H // 18)},scale={W}:{H}:flags=neighbor',
    }
    if effect in simple:
        return f'[{src}]{simple[effect]}[{dst}]'
    if effect == 'mirror':
        return (f'[{src}]crop=iw/2:ih:0:0,split[{dst}l][{dst}r];[{dst}r]hflip[{dst}f];'
                f'[{dst}l][{dst}f]hstack,scale={W}:{H}[{dst}]')
    if effect == 'soft':
        return (f'[{src}]split[{dst}a][{dst}b];[{dst}b]gblur=sigma=14[{dst}g];'
                f'[{dst}a][{dst}g]blend=all_mode=screen:all_opacity=0.35[{dst}]')
    return f'[{src}]null[{dst}]'


def motion_filter(clip: StudioClip, W: int, H: int, fps: int) -> str | None:
    if clip.motion == 'none':
        return None
    frames = max(1, round(clip.length * fps))
    p = f'min(on/{frames},1)'
    z = {'zoom_in': f'1+0.18*{p}', 'zoom_out': f'1.18-0.18*{p}'}.get(clip.motion, '1.15')
    x = {'pan_left': f'(iw-iw/zoom)*(1-{p})', 'pan_right': f'(iw-iw/zoom)*{p}'}.get(
        clip.motion, 'iw/2-(iw/zoom/2)')
    # Upscale first so the slow zoom doesn't stair-step.
    return (f"fps={fps},scale={W * 2}:{H * 2},zoompan=z='{z}':x='{x}':y='ih/2-(ih/zoom/2)'"
            f":d=1:s={W}x{H}:fps={fps}")


def _n(v: float) -> str:
    return f'{v:.5f}'.rstrip('0').rstrip('.') if v != int(v) else str(int(v))


def lerp(points: list[tuple[float, float]], var: str = 't') -> str:
    """Piecewise smoothstep between keyframes — the app eases the same way."""
    pts = sorted(points)
    if not pts:
        return '0'
    if len(pts) == 1 or all(abs(v - pts[0][1]) < 1e-6 for _, v in pts):
        return _n(pts[0][1])
    expr = _n(pts[-1][1])
    for i in range(len(pts) - 2, -1, -1):
        (t0, v0), (t1, v1) = pts[i], pts[i + 1]
        dt = max(1e-3, t1 - t0)
        p = f'(({var}-{_n(t0)})/{_n(dt)})'
        seg = f'({_n(v0)}+({_n(v1 - v0)})*{p}*{p}*(3-2*{p}))'
        expr = f'if(lt({var},{_n(t1)}),{seg},{expr})'
    return f'if(lt({var},{_n(pts[0][0])}),{_n(pts[0][1])},{expr})'


class Progress:
    """Maps each FFmpeg stage onto a slice of 0-1."""

    def __init__(self, report: Callable[[float, str], None] | None):
        self.report = report or (lambda p, s: None)
        self.done = 0.0

    def stage(self, weight: float, label: str):
        start = self.done
        self.done += weight
        self.report(start, label)
        return lambda f: self.report(start + weight * max(0.0, min(1.0, f)), label)


def render_studio(sources, music, plan: StudioPlan, destination: Path, overlays=None, audios=None,
                  progress: Callable[[float, str], None] | None = None, pips=None, extras=None) -> str:
    """sources: per clip {path, mime}; overlays: per overlay {path};
    audios: [{path, spec}]; pips: per pip {path, mime, mask_path?};
    extras: {'cover_path'?, 'cover_overlay'?}."""
    ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    if not ffmpeg or not ffprobe:
        raise HTTPException(503, 'Media rendering is unavailable.')
    overlays = overlays or []
    audios = audios or []
    pips = pips or []
    extras = extras or {}
    track = Progress(progress)

    def run(args, timeout=300, seconds=None, report=None):
        if not report or not seconds:
            return subprocess.run(args, capture_output=True, check=True, timeout=timeout)
        args = args[:1] + ['-progress', 'pipe:1', '-nostats'] + args[1:]
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            for line in proc.stdout:
                if line.startswith('out_time_us='):
                    try:
                        report(int(line.split('=')[1]) / 1e6 / seconds)
                    except ValueError:
                        pass
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            raise
        if proc.returncode:
            raise subprocess.CalledProcessError(proc.returncode, args, stderr=proc.stderr.read())
        report(1)
        return proc

    base = [ffmpeg, '-v', 'error', '-nostdin', '-y', '-threads', '2', '-filter_threads', '1',
            '-filter_complex_threads', '1']
    crf = QUALITY[plan.quality]
    enc = ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', str(crf), '-pix_fmt', 'yuv420p']

    def probe(path):
        return json.loads(run([ffprobe, '-v', 'error', '-show_streams', '-show_format', '-of', 'json',
                               str(path)], 15).stdout)

    legacy = legacy_matrix(plan)
    fps = plan.fps
    try:
        with tempfile.TemporaryDirectory(prefix='phlio-studio-') as temp:
            work = Path(temp)
            first = next(s for s in probe(sources[0]['path'])['streams'] if s['codec_type'] == 'video')
            W, H = canvas(plan, first)
            image_mode = plan.image_only and sources[0]['mime'].startswith('image/')
            caption = None
            if plan.text:
                caption = work / 'caption.txt'
                caption.write_text(plan.text, encoding='utf-8')

            def frame_stage(clip: StudioClip) -> str:
                """[src] → [framed]: fill/fit, zoom/pan (optionally keyframed)."""
                ox, oy = clip.pan_x, clip.pan_y
                keys = sorted(clip.keys or [])
                if clip.fit == 'fill':
                    if keys:
                        tv = f'(on/{fps})'
                        z = lerp([(k[0], max(1.0, k[1])) for k in keys], tv)
                        px = lerp([(k[0], k[2]) for k in keys], tv)
                        py = lerp([(k[0], k[3]) for k in keys], tv)
                        return (f'[src]fps={fps},scale={W * 2}:{H * 2}:force_original_aspect_ratio=increase,'
                                f'crop={W * 2}:{H * 2},setsar=1,'
                                f"zoompan=z='{z}':x='iw/2-(iw/2)*(1+({px}))/zoom':"
                                f"y='ih/2-(ih/2)*(1+({py}))/zoom':d=1:s={W}x{H}:fps={fps}[framed];")
                    # Same maths as the app preview: scale about the centre,
                    # then shift by pan × half the canvas (crop clamps at edges).
                    z = max(1.0, clip.zoom)
                    sw, sh = int(W * z) // 2 * 2, int(H * z) // 2 * 2
                    return (f'[src]scale={sw}:{sh}:force_original_aspect_ratio=increase,'
                            f"crop={W}:{H}:x='(iw-{W})/2-{ox:.3f}*{W}/2':"
                            f"y='(ih-{H})/2-{oy:.3f}*{H}/2'[framed];")
                chain = ''
                if plan.background == 'blur':
                    sigma = 6 + plan.blur * 34
                    chain += ('[src]split[bgsrc][fgsrc];'
                              f'[bgsrc]scale={W}:{H}:force_original_aspect_ratio=increase,'
                              f'crop={W}:{H},gblur=sigma={sigma:.1f},eq=brightness=-0.04[bg];')
                else:
                    chain += (f'[src]null[fgsrc];color=c={plan.background}:s={W}x{H}:r={fps},'
                              f'format=yuv420p[bg];')
                if keys:
                    z = lerp([(k[0], k[1]) for k in keys])
                    px = lerp([(k[0], k[2]) for k in keys])
                    py = lerp([(k[0], k[3]) for k in keys])
                    chain += (f"[fgsrc]scale={W}:{H}:force_original_aspect_ratio=decrease,"
                              f"scale=w='trunc(iw*({z})/2)*2':h=-2:eval=frame[fg];"
                              f"[bg][fg]overlay=x='(W-w)/2+({px})*W/2':y='(H-h)/2+({py})*H/2':shortest=1[framed];")
                else:
                    fw, fh = int(W * clip.zoom) // 2 * 2, int(H * clip.zoom) // 2 * 2
                    chain += (f'[fgsrc]scale={fw}:{fh}:force_original_aspect_ratio=decrease[fg];'
                              f"[bg][fg]overlay=x='(W-w)/2+{ox:.3f}*W/2':y='(H-h)/2+{oy:.3f}*H/2'"
                              f":shortest=1[framed];")
                return chain

            def clip_graph(clip: StudioClip, photo: bool, has_audio: bool) -> str:
                """Full graph for one clip: [v] and (if has_audio) [a]."""
                pre = []
                if clip.reverse and not photo:
                    pre.append('reverse')
                pre += ['transpose=1'] * clip.turns
                if clip.flip:
                    pre.append('hflip')
                if clip.flip_v:
                    pre.append('vflip')
                if clip.crop:
                    x, y, w, h = clip.crop
                    pre.append(f'crop=iw*{w:.4f}:ih*{h:.4f}:iw*{x:.4f}:ih*{y:.4f}')
                graph = ''
                span = clip.end - clip.start
                curve = clip.curve if (clip.curve and not photo and clip.hold is None) else None
                if curve:
                    n = len(curve)
                    graph += f"[0:v]{','.join(pre + ['setsar=1']) or 'null'},split={n}" + ''.join(
                        f'[cv{i}]' for i in range(n)) + ';'
                    for i, (a, b, s) in enumerate(curve):
                        graph += (f'[cv{i}]trim=start={a * span:.3f}:end={b * span:.3f},'
                                  f'setpts=(PTS-STARTPTS)/{s}[cp{i}];')
                    graph += ''.join(f'[cp{i}]' for i in range(n)) + f'concat=n={n}:v=1:a=0[raw];'
                    pre2 = []
                else:
                    if not photo and clip.hold is None:
                        pre.append(f'setpts=(PTS-STARTPTS)/{clip.speed}')
                    graph += f"[0:v]{','.join(pre) or 'null'}[raw];"
                    pre2 = []
                pre2 += color_chain(clip.color or legacy, clip.vignette, clip.sharpen, clip.grain)
                pre2.append('setsar=1')
                graph += f"[raw]{','.join(pre2)}[src];"
                graph += frame_stage(clip)
                graph += effect_graph(clip.effect, 'framed', 'fx', W, H) + ';'
                post = []
                mot = motion_filter(clip, W, H, fps) if not clip.keys else None
                if mot:
                    post.append(mot)
                if not image_mode:
                    post.append(f'fps={fps}')
                if caption:
                    escaped = str(caption).replace('\\', '/').replace(':', r'\:')
                    post.append(f"drawtext=textfile='{escaped}':expansion=none:fontcolor=white:"
                                f"fontsize={max(18, W // 22)}:box=1:boxcolor=black@0.5:boxborderw=10:"
                                f"x=(w-tw)/2:y=h-th-h*0.08")
                length = clip.length
                for kind, at in (('in', clip.anim_in), ('out', clip.anim_out)):
                    if at != 'none' and not image_mode:
                        d = min(.5, length / 3)
                        st = 0 if kind == 'in' else length - d
                        color = ':color=white' if at == 'fade_white' else ''
                        post.append(f'fade=t={kind}:st={st:.3f}:d={d:.3f}{color}')
                post += ['format=yuv420p', 'setsar=1']
                if not image_mode:
                    post.append('settb=AVTB')
                graph += f"[fx]{','.join(post)}[v]"
                if has_audio:
                    afx = []
                    if clip.reverse:
                        afx.append('areverse')
                    if curve:
                        n = len(curve)
                        graph += f';[0:a]asplit={n}' + ''.join(f'[ca{i}]' for i in range(n)) + ';'
                        for i, (a, b, s) in enumerate(curve):
                            graph += (f'[ca{i}]atrim=start={a * span:.3f}:end={b * span:.3f},'
                                      f'asetpts=PTS-STARTPTS,{atempo(s)}[cq{i}];')
                        graph += ''.join(f'[cq{i}]' for i in range(n)) + f'concat=n={n}:v=0:a=1[araw]'
                        src = 'araw'
                    else:
                        afx.append(atempo(clip.speed))
                        src = '0:a'
                    afx += voice_filters(clip.voice, clip.denoise)
                    afx.append(f'volume={clip.volume}')
                    if clip.fade_audio_in:
                        afx.append(f'afade=t=in:d={clip.fade_audio_in:.2f}')
                    if clip.fade_audio_out:
                        afx.append(f'afade=t=out:st={max(0, length - clip.fade_audio_out):.2f}'
                                   f':d={clip.fade_audio_out:.2f}')
                    afx += ['aresample=48000', 'apad']
                    graph += f";[{src}]{','.join(afx)}[a]"
                else:
                    graph += ';[1:a]anull[a]'
                return graph

            # ---- 1. clips ------------------------------------------------------
            segments_out, lengths = [], []
            weight = .55 if not image_mode else .9
            for i, (source, clip) in enumerate(zip(sources, plan.clips)):
                report = track.stage(weight / len(plan.clips), f'Rendering clip {i + 1} of {len(plan.clips)}')
                photo = source['mime'].startswith('image/')
                path = source['path']
                info = probe(path)
                if not photo and clip.hold is None and clip.end > float(info['format']['duration']) + .15:
                    raise HTTPException(422, 'Trim range exceeds the source video.')
                if clip.hold is not None and not photo:
                    frame = work / f'freeze{i}.png'
                    run(base + ['-ss', f'{clip.start:.3f}', '-i', path, '-frames:v', '1', str(frame)])
                    path, photo = str(frame), True
                has_audio = (not photo and not plan.mute_original
                             and any(s['codec_type'] == 'audio' for s in info['streams']))
                graph = clip_graph(clip, photo, has_audio)
                if image_mode:
                    args = base + ['-i', path]
                    for ov in overlays:
                        args += ['-i', ov['path']]
                    final = graph.split(';[1:a]')[0].replace('[v]', '[base]')
                    cur = 'base'
                    for k, ov in enumerate(overlays):
                        spec = plan.overlays[k]
                        ow = max(2, int(spec.w * W) // 2 * 2)
                        final += (f';[{k + 1}:v]format=rgba,scale={ow}:-1[o{k}];'
                                  f'[{cur}][o{k}]overlay=x={int(spec.x * W)}:y={int(spec.y * H)}[c{k}]')
                        cur = f'c{k}'
                    final += f';[{cur}]null[out]'
                    q = ['-q:v', '2'] if plan.image_format == 'jpg' else []
                    run(args + ['-filter_complex', final, '-map', '[out]', '-frames:v', '1'] + q
                        + [str(destination)])
                    report(1)
                    track.stage(.1, 'Finishing')(1)
                    return 'image'
                length = clip.length
                if photo:
                    args = base + ['-loop', '1', '-framerate', str(fps), '-t', f'{length:.3f}', '-i', path]
                else:
                    args = base + ['-ss', f'{clip.start:.3f}', '-t', f'{clip.end - clip.start:.3f}', '-i', path]
                if not has_audio:
                    args += ['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo']
                segment = work / f'{i}.mp4'
                run(args + ['-filter_complex', graph, '-map', '[v]', '-map', '[a]', '-t', f'{length:.3f}',
                            '-r', str(fps), '-ac', '2'] + enc + ['-c:a', 'aac', '-b:a', '160k', str(segment)],
                    600, length, report)
                segments_out.append(segment)
                lengths.append(length)

            # ---- 2. join -------------------------------------------------------
            merged = work / 'merged.mp4'
            total = plan.total
            report = track.stage(.12, 'Joining clips')
            if len(segments_out) == 1:
                shutil.copyfile(segments_out[0], merged)
                report(1)
            else:
                args = base.copy()
                for segment in segments_out:
                    args += ['-i', str(segment)]
                parts = []
                v, a = '0:v', '0:a'
                acc = lengths[0]
                legacy_t = plan.transition if plan.transition != 'none' else None
                for i in range(1, len(segments_out)):
                    prev = plan.clips[i - 1]
                    kind = prev.transition if prev.transition != 'none' else legacy_t
                    if kind:
                        d = overlap(prev, plan.clips[i]) if prev.transition != 'none' else min(
                            .4, lengths[i - 1] / 3, lengths[i] / 3)
                        parts += [f'[{v}][{i}:v]xfade=transition={kind}:duration={d:.3f}:offset={acc - d:.3f}[v{i}]',
                                  f'[{a}][{i}:a]acrossfade=d={d:.3f}[a{i}]']
                        acc += lengths[i] - d
                    else:
                        parts.append(f'[{v}][{a}][{i}:v][{i}:a]concat=n=2:v=1:a=1[v{i}][a{i}]')
                        acc += lengths[i]
                    v, a = f'v{i}', f'a{i}'
                total = acc
                run(args + ['-filter_complex', ';'.join(parts), '-map', f'[{v}]', '-map', f'[{a}]'] + enc
                    + ['-c:a', 'aac', '-b:a', '160k', str(merged)], 900, total, report)

            # ---- 3. segments, overlay layers, text and sound -----------------------------
            items = list(audios)
            if music:  # legacy single music track
                items.append(dict(path=music['path'], spec=StudioAudio(
                    file_id=plan.music_id, volume=plan.music_volume, loop=True)))
            needs_video = bool(overlays or pips or plan.segments)
            report = track.stage(.28 if extras.get('cover') else .33, 'Adding layers, text and sound')
            out = destination if not extras.get('cover') else work / 'final.mp4'
            if not needs_video and not items:
                shutil.copyfile(merged, out)
                report(1)
            else:
                args = base + ['-i', str(merged)]
                graph, cur, n = [], '0:v', 1
                # Timeline effects / filters.
                for k, seg in enumerate(plan.segments):
                    s, e = max(0.0, seg.start), min(total, seg.end)
                    if e - s < .05:
                        continue
                    enable = f":enable='between(t,{s:.3f},{e:.3f})'"
                    if seg.kind == 'effect':
                        filters = [f + enable if 'eval=frame' not in f else f + enable
                                   for f in SEGMENT_FILTERS[seg.effect]]
                    else:
                        filters = color_chain(seg.color, seg.vignette, seg.sharpen, seg.grain, enable)
                    if filters:
                        graph.append(f"[{cur}]{','.join(filters)}[s{k}]")
                        cur = f's{k}'
                pip_audio = []
                # Overlay media layers.
                for k, (pip, spec) in enumerate(zip(pips, plan.pips)):
                    photo = pip['mime'].startswith('image/')
                    length = spec.length
                    if photo:
                        args += ['-loop', '1', '-framerate', str(fps), '-t', f'{length:.3f}', '-i', pip['path']]
                    else:
                        args += ['-ss', f'{spec.start:.3f}', '-t', f'{spec.end - spec.start:.3f}', '-i', pip['path']]
                    src = n
                    n += 1
                    chain = [f'setpts=(PTS-STARTPTS)/{spec.speed}' if not photo else 'setpts=PTS-STARTPTS',
                             f'fps={fps}']
                    if spec.flip:
                        chain.append('hflip')
                    if spec.chroma:
                        chain.append(f'chromakey=0x{spec.chroma[1:]}:{0.05 + spec.chroma_strength * 0.35:.3f}:0.08')
                    chain += color_chain(spec.color)
                    pw = max(2, int(spec.w * W) // 2 * 2)
                    chain += ['format=rgba', f'scale={pw}:-2', f'setpts=PTS+{spec.at:.3f}/TB']
                    graph.append(f"[{src}:v]{','.join(chain)}[p{k}raw]")
                    layer = f'p{k}raw'
                    if pip.get('mask_path'):
                        args += ['-loop', '1', '-t', f'{total:.3f}', '-i', pip['mask_path']]
                        graph.append(f'[{n}:v]format=gray[m{k}];[m{k}][{layer}]scale2ref[m{k}s][p{k}b];'
                                     f'[p{k}b][m{k}s]alphamerge[p{k}m]')
                        layer = f'p{k}m'
                        n += 1
                    layer = _animate_layer(graph, layer, f'p{k}', spec.keys, spec.cx, spec.cy, spec.rotation,
                                           spec.opacity, 'none', spec.at, spec.at + length,
                                           spec.anim_in, spec.anim_out, pw)
                    s, e = spec.at, min(total, spec.at + length)
                    xy = _position(spec.keys, spec.cx, spec.cy, W, H, 'none', s)
                    if spec.blend == 'normal':
                        graph.append(f"[{cur}][{layer}]overlay=x='{xy[0]}':y='{xy[1]}':"
                                     f"enable='between(t,{s:.3f},{e:.3f})':eof_action=pass[c{k}p]")
                    else:
                        graph.append(f'color=c={NEUTRAL[spec.blend]}:s={W}x{H}:r={fps}:d={total:.3f},format=rgba[nb{k}]')
                        graph.append(f"[nb{k}][{layer}]overlay=x='{xy[0]}':y='{xy[1]}':"
                                     f"enable='between(t,{s:.3f},{e:.3f})':eof_action=pass,format=gbrp[l{k}]")
                        graph.append(f'[{cur}]format=gbrp[b{k}];[b{k}][l{k}]blend=all_mode={spec.blend},'
                                     f'format=yuv420p[c{k}p]')
                    cur = f'c{k}p'
                    if not photo and spec.volume > 0 and not plan.mute_original:
                        info = probe(pip['path'])
                        if any(st['codec_type'] == 'audio' for st in info['streams']):
                            delay = int(spec.at * 1000)
                            pip_audio.append(f'[{src}:a]{atempo(spec.speed)},volume={spec.volume},'
                                             f'adelay={delay}|{delay},aresample=48000')
                # Text, captions, stickers.
                for k, ov in enumerate(overlays):
                    spec = plan.overlays[k]
                    s, e = max(0.0, spec.start), min(total, spec.end)
                    args += ['-loop', '1', '-t', f'{total:.3f}', '-i', ov['path']]
                    ow = max(2, int(spec.w * W) // 2 * 2)
                    if spec.dynamic:
                        layer = _animate_layer(graph, f'{n}:v', f'o{k}', spec.keys, spec.cx, spec.cy,
                                               spec.rotation, 1.0, spec.loop, s, e, spec.anim_in,
                                               spec.anim_out, ow, rgba=False)
                        x, y = _position(spec.keys, spec.cx, spec.cy, W, H, spec.anim_in, s,
                                         spec.anim_out, e, spec.loop)
                    else:
                        d = min(.35, max(.05, (e - s) / 4))
                        chain = f'[{n}:v]format=rgba,scale={ow}:-1'
                        if spec.anim_in == 'fade':
                            chain += f',fade=t=in:st={s:.3f}:d={d:.3f}:alpha=1'
                        if spec.anim_out in ('fade', 'slide_down'):
                            chain += f',fade=t=out:st={max(s, e - d):.3f}:d={d:.3f}:alpha=1'
                        graph.append(chain + f'[o{k}]')
                        layer = f'o{k}'
                        X, Y = int(spec.x * W), int(spec.y * H)
                        ramp = f'(1-min(max(t-{s:.3f},0)/0.35,1))'
                        out_ramp = f'(1-min(max({e:.3f}-t,0)/0.35,1))'
                        x = f'{X}+{ramp}*{W * .12:.0f}' if spec.anim_in == 'slide_left' else str(X)
                        y = f'{Y}+{ramp}*{H * .06:.0f}' if spec.anim_in == 'slide_up' else str(Y)
                        if spec.anim_out == 'slide_down':
                            y = f'{y}+{out_ramp}*{H * .06:.0f}'
                    graph.append(f"[{cur}][{layer}]overlay=x='{x}':y='{y}':enable='between(t,{s:.3f},{e:.3f})'[c{k}]")
                    cur = f'c{k}'
                    n += 1
                mixes = ['[0:a]anull[base]']
                labels = ['[base]']
                for j, pa in enumerate(pip_audio):
                    mixes.append(pa + f'[pa{j}]')
                    labels.append(f'[pa{j}]')
                for j, item in enumerate(items):
                    spec: StudioAudio = item['spec']
                    if spec.loop:
                        args += ['-stream_loop', '-1']
                    args += ['-i', item['path']]
                    f = [f'atrim=start={spec.start:.3f}' + (f':end={spec.end:.3f}' if spec.end else '')]
                    f += ['asetpts=PTS-STARTPTS'] + voice_filters(spec.voice, spec.denoise) + [f'volume={spec.volume}']
                    room = max(.3, total - spec.at)
                    if spec.end:
                        room = min(room, (spec.end - spec.start))
                    f.append(f'atrim=end={room:.3f}')
                    if spec.fade_in:
                        f.append(f'afade=t=in:d={spec.fade_in:.2f}')
                    if spec.fade_out:
                        f.append(f'afade=t=out:st={max(0, room - spec.fade_out):.2f}:d={spec.fade_out:.2f}')
                    delay = int(spec.at * 1000)
                    f += [f'adelay={delay}|{delay}', 'aresample=48000']
                    mixes.append(f'[{n}:a]{",".join(f)}[m{j}]')
                    labels.append(f'[m{j}]')
                    n += 1
                if len(labels) > 1:
                    mixes.append(''.join(labels) + f'amix=inputs={len(labels)}:duration=first:normalize=0,'
                                 'alimiter=limit=0.95[aout]')
                else:
                    mixes.append('[base]anull[aout]')
                if needs_video:
                    graph.append(f'[{cur}]format=yuv420p[vout]')
                    vmap = '[vout]'
                else:
                    vmap = '0:v'
                full = ';'.join(graph + mixes)
                vcodec = enc if needs_video else ['-c:v', 'copy']
                run(args + ['-filter_complex', full, '-map', vmap, '-map', '[aout]', '-t', f'{total:.3f}']
                    + vcodec + ['-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', str(out)],
                    900, total, report)

            # ---- 4. cover art -------------------------------------------------------
            cover = extras.get('cover')
            if cover:
                report = track.stage(1 - track.done, 'Adding your cover')
                image = work / 'cover.jpg'
                spec = plan.cover
                if cover.get('path'):
                    src = ['-i', cover['path']]
                    scale = f'scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H}'
                else:
                    src = ['-ss', f'{min(spec.time or 0, max(0, total - .05)):.3f}', '-i', str(out)]
                    scale = 'null'
                if cover.get('overlay'):
                    run(base + src + ['-i', cover['overlay'], '-filter_complex',
                                      f'[0:v]{scale}[b];[1:v]scale={W}:{H}[t];[b][t]overlay',
                                      '-frames:v', '1', '-q:v', '2', str(image)])
                else:
                    run(base + src + ['-vf', scale, '-frames:v', '1', '-q:v', '2', str(image)])
                run(base + ['-i', str(out), '-i', str(image), '-map', '0', '-map', '1', '-c', 'copy',
                            '-disposition:v:1', 'attached_pic', '-movflags', '+faststart', str(destination)])
                report(1)
            return 'video'
    except HTTPException:
        raise
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or b'')
        if isinstance(detail, bytes):
            detail = detail.decode(errors='replace')
        import logging
        logging.getLogger('phlio.studio').warning('FFmpeg failed: %s', detail[-2000:])
        raise HTTPException(422, 'Could not render this project. Check the clips and try a shorter export.') from exc
    except (OSError, ValueError, KeyError, StopIteration, subprocess.SubprocessError) as exc:
        raise HTTPException(422, 'Could not render this project. Check the clips and try a shorter export.') from exc


LOOP = {
    # (dx, dy, scale, rotation) offsets as ffmpeg expressions of t
    'bounce': ('0', '-abs(sin(t*4))*H*0.025', '1', '0'),
    'pulse': ('0', '0', '(1+0.07*sin(t*6))', '0'),
    'wiggle': ('0', '0', '1', '(0.09*sin(t*9))'),
    'float': ('sin(t*1.6)*W*0.01', 'sin(t*2.1)*H*0.015', '1', '0'),
    'blink': ('0', '0', '1', '0'),
}


def _animate_layer(graph, src, name, keys, cx, cy, rotation, opacity, loop, s, e, anim_in, anim_out,
                   width, rgba=True) -> str:
    """Scale / rotate / fade a layer over time. Returns the output label."""
    keys = sorted(keys or [])
    chain = [] if rgba else ['format=rgba']
    scale = lerp([(k[0], k[3]) for k in keys]) if keys else '1'
    rot = lerp([(k[0], k[4]) for k in keys]) if keys else _n(rotation)
    op = lerp([(k[0], k[5]) for k in keys]) if keys else _n(opacity)
    op_frame = lerp([(k[0], k[5]) for k in keys], 'T') if keys else op
    if anim_in == 'pop':
        scale = f'({scale})*(1+0.25*(1-min(max(t-{s:.3f},0)/0.3,1))*sin(min(max(t-{s:.3f},0)/0.3,1)*PI)-0.6*(1-min(max(t-{s:.3f},0)/0.15,1)))'
    if anim_out == 'shrink':
        scale = f'({scale})*min(max({e:.3f}-t,0)/0.3,1)'
    if loop in LOOP:
        if LOOP[loop][2] != '1':
            scale = f'({scale})*{LOOP[loop][2]}'
        if LOOP[loop][3] != '0':
            rot = f'({rot})+{LOOP[loop][3]}'
    dynamic_scale = scale != '1'
    if dynamic_scale:
        chain.append(f"scale=w='max(2,trunc({width}*({scale})/2)*2)':h='max(2,trunc(ow*ih/iw/2)*2)':eval=frame")
    else:
        chain.append(f'scale={width}:-2')
    if rot not in ('0', '0.0'):
        chain.append(f"rotate=a='{rot}':ow='hypot(iw,ih)':oh=ow:c=none")
    if op != '1':
        if keys and len({k[5] for k in keys}) > 1:
            chain.append(f"geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*clip({op_frame},0,1)'")
        else:
            chain.append(f'colorchannelmixer=aa={float(op):.3f}')
    if loop == 'blink':
        chain.append("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*(0.55+0.45*sin(T*5))'")
    d = min(.35, max(.05, (e - s) / 4))
    if anim_in == 'fade':
        chain.append(f'fade=t=in:st={s:.3f}:d={d:.3f}:alpha=1')
    if anim_out == 'fade':
        chain.append(f'fade=t=out:st={max(s, e - d):.3f}:d={d:.3f}:alpha=1')
    graph.append(f"[{src}]{','.join(chain)}[{name}a]")
    return f'{name}a'


def _position(keys, cx, cy, W, H, anim_in, s, anim_out='none', e=0.0, loop='none'):
    """overlay x/y expressions centring the layer on (cx, cy)."""
    keys = sorted(keys or [])
    px = lerp([(k[0], k[1]) for k in keys]) if keys else _n(cx if cx is not None else .5)
    py = lerp([(k[0], k[2]) for k in keys]) if keys else _n(cy if cy is not None else .5)
    x = f'({px})*{W}-w/2'
    y = f'({py})*{H}-h/2'
    ramp = f'(1-min(max(t-{s:.3f},0)/0.35,1))'
    if anim_in == 'slide_up':
        y += f'+{ramp}*{H * .06:.0f}'
    if anim_in == 'slide_left':
        x += f'+{ramp}*{W * .12:.0f}'
    if anim_in == 'drop':
        y += f'-({ramp}*{ramp}*{H * .15:.0f})'
    if anim_out == 'slide_down':
        y += f'+(1-min(max({e:.3f}-t,0)/0.35,1))*{H * .06:.0f}'
    if loop in LOOP:
        x += f'+({LOOP[loop][0]})'
        y += f'+({LOOP[loop][1]})'
    return x, y


# -- previews for the timeline ------------------------------------------------------

def filmstrip(path: str, mime: str, destination: Path, frames: int = 12, height: int = 96):
    """Horizontal JPEG strip of evenly spaced frames (one per tile)."""
    ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    if not ffmpeg:
        raise HTTPException(503, 'Media previews are unavailable.')
    if mime.startswith('image/'):
        subprocess.run([ffmpeg, '-v', 'error', '-y', '-i', path, '-vf',
                        f'scale=-2:{height},crop=min(iw\\,{height * 3 // 4}):{height}', '-frames:v', '1',
                        '-q:v', '4', str(destination)], check=True, capture_output=True, timeout=30)
        return 1
    info = json.loads(subprocess.run([ffprobe, '-v', 'error', '-show_format', '-of', 'json', path],
                                     check=True, capture_output=True, timeout=15).stdout)
    duration = max(.1, float(info['format']['duration']))
    rate = frames / duration
    tile = height * 3 // 4
    subprocess.run([ffmpeg, '-v', 'error', '-y', '-i', path, '-vf',
                    f'fps={rate:.5f},scale={tile}:{height}:force_original_aspect_ratio=increase,'
                    f'crop={tile}:{height},tile={frames}x1', '-frames:v', '1', '-q:v', '5', str(destination)],
                   check=True, capture_output=True, timeout=120)
    return frames


def waveform(path: str, points: int = 200) -> dict:
    import numpy as np
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        raise HTTPException(503, 'Media previews are unavailable.')
    raw = subprocess.run([ffmpeg, '-v', 'error', '-i', path, '-vn', '-ac', '1', '-ar', '4000', '-f', 's16le', '-'],
                         check=True, capture_output=True, timeout=120).stdout
    x = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768
    duration = len(x) / 4000
    if not len(x):
        return dict(duration=0, peaks=[])
    chunks = np.array_split(np.abs(x), min(points, len(x)))
    peaks = np.array([float(c.max()) for c in chunks])
    top = float(np.percentile(peaks, 99)) or 1.0
    return dict(duration=round(duration, 3), peaks=[round(float(min(1, v / top)), 3) for v in peaks])


def extract_speech(path: str, start: float, end: float, speed: float, destination: Path):
    """16 kHz mono WAV of a trimmed clip at its edited speed (for captions)."""
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        raise HTTPException(503, 'Media processing is unavailable.')
    subprocess.run([ffmpeg, '-v', 'error', '-y', '-ss', f'{start:.3f}', '-t', f'{max(.1, end - start):.3f}',
                    '-i', path, '-vn', '-af', atempo(speed), '-ac', '1', '-ar', '16000', str(destination)],
                   check=True, capture_output=True, timeout=180)
