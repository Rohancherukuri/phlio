"""Video edits for Moments and Experiences, applied with FFmpeg on upload.

Photos are edited on the phone (crop, rotate and flip are baked into the
picture; adjustments, looks and effects are drawn live from the filter
spec). Videos send their edits as data and the server renders them, so
what friends play is exactly what the editor showed:

    {"trim_start": 1.2, "trim_end": 8.0, "speed": 1.5, "mute": false,
     "rotate": 90, "flip": true, "crop": [0.1, 0, 0.8, 1],
     "motion": "boomerang"}

``crop`` is ``[x, y, width, height]`` as fractions of the frame. ``motion``
is one of the Camera & motion effects that change time itself (they can't
be drawn by a shader): boomerang, slow motion, hyperlapse, motion echo,
ghost trail, stop motion and freeze frame.
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Literal

from fastapi import HTTPException
from pydantic import BaseModel, Field, ValidationError, model_validator

Motion = Literal["none", "boomerang", "slow_motion", "hyperlapse", "motion_echo",
                 "ghost_trail", "stop_motion", "freeze_frame"]


class MediaEdits(BaseModel):
    trim_start: float = Field(default=0, ge=0, le=600)
    trim_end: float | None = Field(default=None, gt=0, le=600)
    speed: float = Field(default=1, ge=0.25, le=4)
    mute: bool = False
    rotate: Literal[0, 90, 180, 270] = 0
    flip: bool = False
    crop: list[float] | None = Field(default=None, min_length=4, max_length=4)
    motion: Motion = "none"

    @model_validator(mode="after")
    def _check(self):
        if self.trim_end is not None and self.trim_end - self.trim_start < 0.3:
            raise ValueError("Keep at least a third of a second.")
        if self.crop is not None:
            x, y, w, h = self.crop
            if not (0 <= x <= 1 and 0 <= y <= 1 and 0.05 <= w <= 1 and 0.05 <= h <= 1
                    and x + w <= 1.0001 and y + h <= 1.0001):
                raise ValueError("Invalid crop.")
        return self

    @property
    def is_identity(self) -> bool:
        full = self.crop is None or self.crop == [0, 0, 1, 1]
        return (self.trim_start == 0 and self.trim_end is None and self.speed == 1 and not self.mute
                and self.rotate == 0 and not self.flip and full and self.motion == "none")


def parse_media_edits(raw: str | None) -> dict | None:
    """Validates the ``edits`` form field; None when empty or a no-op."""
    if not raw or not raw.strip():
        return None
    if len(raw) > 2000:
        raise HTTPException(422, "Invalid edits.")
    try:
        edits = MediaEdits.model_validate(json.loads(raw))
    except (ValueError, ValidationError) as exc:
        raise HTTPException(422, "Invalid edits.") from exc
    return None if edits.is_identity else edits.model_dump()


def _atempo(factor: float) -> list[str]:
    """atempo only takes 0.5-2 per stage; chain stages for 0.25-4."""
    stages = []
    while factor > 2:
        stages.append("atempo=2")
        factor /= 2
    while factor < 0.5:
        stages.append("atempo=0.5")
        factor /= 0.5
    if abs(factor - 1) > 1e-3:
        stages.append(f"atempo={factor:.4f}")
    return stages


def ffmpeg_command(source: Path, target: Path, edits: dict) -> list[str]:
    """The FFmpeg invocation for ``edits`` (exposed for tests)."""
    e = MediaEdits.model_validate(edits)
    video: list[str] = []
    if e.crop is not None and e.crop != [0, 0, 1, 1]:
        x, y, w, h = e.crop
        video.append(f"crop=iw*{w:.4f}:ih*{h:.4f}:iw*{x:.4f}:ih*{y:.4f}")
    video += {90: ["transpose=1"], 180: ["hflip", "vflip"], 270: ["transpose=2"]}.get(e.rotate, [])
    if e.flip:
        video.append("hflip")
    speed = e.speed
    audio_off = e.mute
    if e.motion == "slow_motion":
        speed *= 0.5
    elif e.motion == "hyperlapse":
        speed *= 4
        audio_off = True
    if abs(speed - 1) > 1e-3:
        video.append(f"setpts=PTS/{speed:.4f}")
    video += {
        "motion_echo": ["tmix=frames=4:weights='1 1 1 1'"],
        "ghost_trail": ["lagfun=decay=0.94"],
        "stop_motion": ["fps=8"],
        "freeze_frame": ["loop=loop=36:size=1:start=20"],
    }.get(e.motion, [])
    video.append("scale=trunc(iw/2)*2:trunc(ih/2)*2")
    chain = ",".join(video)
    if e.motion == "boomerang":
        # Forwards then backwards, from the first three seconds.
        graph = f"[0:v]trim=0:3,setpts=PTS-STARTPTS,{chain},split[f][b];[b]reverse[r];[f][r]concat=n=2:v=1:a=0[v]"
        audio_off = True
    else:
        graph = f"[0:v]{chain}[v]"
    if e.motion == "freeze_frame":
        audio_off = True
    cmd = ["ffmpeg", "-nostdin", "-v", "error", "-y"]
    if e.trim_start > 0:
        cmd += ["-ss", f"{e.trim_start:.3f}"]
    if e.trim_end is not None:
        cmd += ["-to", f"{e.trim_end:.3f}"]
    cmd += ["-i", str(source), "-filter_complex", graph, "-map", "[v]"]
    if audio_off:
        cmd += ["-an"]
    else:
        cmd += ["-map", "0:a?"]
        tempo = _atempo(speed)
        if tempo:
            cmd += ["-af", ",".join(tempo)]
        cmd += ["-c:a", "aac", "-b:a", "128k"]
    cmd += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "22", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", str(target)]
    return cmd


async def apply_video_edits(source: Path, edits: dict | None) -> Path:
    """Renders ``edits`` into a new MP4 next to ``source`` and returns it
    (``source`` itself when there's nothing to do or FFmpeg is missing).
    The original file is removed once the edited one is written."""
    if not edits:
        return source
    target = source.with_name(source.stem + "-edit.mp4")
    try:
        process = await asyncio.create_subprocess_exec(
            *ffmpeg_command(source, target, edits),
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE)
        _, err = await asyncio.wait_for(process.communicate(), timeout=180)
    except FileNotFoundError:
        return source  # no FFmpeg on this server: keep the clip as recorded
    except asyncio.TimeoutError as exc:
        target.unlink(missing_ok=True)
        raise HTTPException(422, "This video took too long to edit. Try a shorter clip.") from exc
    if process.returncode != 0 or not target.exists() or target.stat().st_size == 0:
        target.unlink(missing_ok=True)
        raise HTTPException(422, "Could not apply your edits to this video.")
    source.unlink(missing_ok=True)
    return target
