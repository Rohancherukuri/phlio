"""Social message media policy; Rooms deliberately uses its own policy."""

import json
import shutil
import subprocess
from pathlib import Path

from fastapi import HTTPException
from pydantic import BaseModel, Field, model_validator

IMAGE_LIMIT = 8_000_000
MEDIA_LIMIT = 25_000_000
PACK = json.loads((Path(__file__).parents[1] / "stickers" / "chat_pack.json").read_text())


def validate_pack(kind: str, value: str):
    expected = "gif" if kind == "gif" else "sticker"
    actual = PACK.get(value)
    if actual == "emoji":
        actual = "sticker"
    if actual != expected:
        raise HTTPException(422, "Choose a predefined sticker or GIF.")


def media_type(name: str):
    extension = Path(name).suffix.lower()
    formats = {
        ".jpg": ("image", "image/jpeg"),
        ".jpeg": ("image", "image/jpeg"),
        ".png": ("image", "image/png"),
        ".gif": ("image", "image/gif"),
        ".webp": ("image", "image/webp"),
        ".heic": ("image", "image/heic"),
        ".mp4": ("video", "video/mp4"),
        ".mov": ("video", "video/quicktime"),
        ".webm": ("video", "video/webm"),
        ".m4v": ("video", "video/mp4"),
        ".mp3": ("audio", "audio/mpeg"),
        ".m4a": ("audio", "audio/mp4"),
        ".wav": ("audio", "audio/wav"),
        ".ogg": ("audio", "audio/ogg"),
        ".aac": ("audio", "audio/aac"),
        ".flac": ("audio", "audio/flac"),
    }
    if extension not in formats:
        raise HTTPException(
            422, "Messages allow images, GIFs, audio and videos only. Share documents in Rooms."
        )
    return formats[extension]


def validate_size(kind: str, size: int):
    limit = IMAGE_LIMIT if kind == "image" else MEDIA_LIMIT
    if size > limit:
        raise HTTPException(
            413,
            f"{'Images/GIFs' if kind == 'image' else 'Audio/videos'} "
            f"must be {limit // 1_000_000} MB or smaller.",
        )
    if size <= 0:
        raise HTTPException(422, "The media file is empty.")


def validate_signature(path: Path, mime: str):
    with path.open("rb") as f:
        data = f.read(32)
    checks = {
        "image/jpeg": data.startswith(b"\xff\xd8\xff"),
        "image/png": data.startswith(b"\x89PNG\r\n\x1a\n"),
        "image/gif": data.startswith((b"GIF87a", b"GIF89a")),
        "image/webp": data.startswith(b"RIFF") and data[8:12] == b"WEBP",
        "image/heic": data[4:8] == b"ftyp",
        "video/mp4": data[4:8] == b"ftyp",
        "video/quicktime": data[4:8] in (b"ftyp", b"moov", b"wide", b"mdat"),
        "video/webm": data.startswith(b"\x1aE\xdf\xa3"),
        "audio/mp4": data[4:8] == b"ftyp",
        "audio/wav": data.startswith(b"RIFF") and data[8:12] == b"WAVE",
        "audio/ogg": data.startswith(b"OggS"),
        "audio/flac": data.startswith(b"fLaC"),
        "audio/mpeg": data.startswith(b"ID3") or (len(data) > 1 and data[0] == 255 and data[1] & 224 == 224),
        "audio/aac": len(data) > 1 and data[0] == 255 and data[1] & 240 == 240,
    }
    if not checks.get(mime, False):
        raise HTTPException(422, "The file contents do not match the selected media format.")


class VideoEdit(BaseModel):
    start: float = Field(default=0, ge=0, le=86400, allow_inf_nan=False)
    end: float = Field(gt=0, le=86400, allow_inf_nan=False)
    mute: bool = False
    turns: int = Field(default=0, ge=0, le=3)

    @model_validator(mode="after")
    def valid_range(self):
        if self.end <= self.start:
            raise ValueError("Choose a non-empty video segment.")
        return self


def edit_video(source: Path, target: Path, edit: VideoEdit):
    binary = shutil.which("ffmpeg")
    probe = shutil.which("ffprobe")
    if binary is None or probe is None:
        raise HTTPException(503, "Video editing is unavailable on this server. Please try again later.")

    def duration(path):
        result = subprocess.run(
            [
                probe,
                "-v",
                "error",
                "-show_entries",
                "format=duration:stream=codec_type",
                "-of",
                "json",
                str(path),
            ],
            capture_output=True,
            check=True,
            timeout=15,
        )
        data = json.loads(result.stdout)
        if not any(stream.get("codec_type") == "video" for stream in data.get("streams", [])):
            raise ValueError("No video stream")
        return float(data["format"]["duration"])

    try:
        source_duration = duration(source)
        if edit.start >= source_duration or edit.end > source_duration + 0.1:
            raise ValueError("Outside clip duration")
    except (subprocess.SubprocessError, OSError, ValueError, KeyError) as exc:
        raise HTTPException(422, "Choose a valid segment within the video duration.") from exc
    filters = ["transpose=1"] * edit.turns
    filters.append("scale=trunc(iw/2)*2:trunc(ih/2)*2")
    command = [
        binary,
        "-nostdin",
        "-v",
        "error",
        "-y",
        "-ss",
        str(edit.start),
        "-i",
        str(source),
        "-t",
        str(edit.end - edit.start),
        "-map",
        "0:v:0",
        "-map",
        "0:a:0?",
        "-vf",
        ",".join(filters),
        "-c:v",
        "libx264",
        "-threads",
        "2",
        "-preset",
        "fast",
        "-crf",
        "24",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-movflags",
        "+faststart",
    ]
    if edit.mute:
        command.append("-an")
    command += ["-fs", str(MEDIA_LIMIT + 1), "-f", "mp4", str(target)]
    try:
        subprocess.run(command, check=True, timeout=120, capture_output=True)
        validate_size("video", target.stat().st_size)
        if duration(target) < edit.end - edit.start - 0.25:
            raise HTTPException(413, "The edited video is too large. Choose a shorter segment.")
    except (subprocess.SubprocessError, OSError, ValueError, KeyError) as exc:
        raise HTTPException(
            422, "Could not export this video. Choose a shorter segment or another format."
        ) from exc
