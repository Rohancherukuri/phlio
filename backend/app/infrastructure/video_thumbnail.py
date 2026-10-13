"""Thumbnails are decoded from the actual video, never generic cover art."""
import subprocess
from pathlib import Path
from PIL import Image, ImageStat


def fingerprint(path):
    with Image.open(path) as image:
        image = image.convert('L').resize((9, 8))
        pixels = list(image.getdata())
        return sum((pixels[y * 9 + x] > pixels[y * 9 + x + 1]) << (y * 8 + x)
                   for y in range(8) for x in range(8))


def make_thumbnail(source, target, duration, used=None, offset=0):
    """Reject dark/slate frames and perceptual duplicates in a demo batch."""
    used = used if used is not None else []
    target = Path(target)
    for attempt in range(40):
        position = min(duration - .1, .5 + ((offset + attempt * 1.71) % max(1, duration - 1)))
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-ss', str(position),
                        '-i', str(source), '-frames:v', '1', '-vf', 'scale=640:-2', str(target)],
                       check=True, capture_output=True, timeout=30)
        with Image.open(target) as image:
            detail = ImageStat.Stat(image.convert('L')).stddev[0]
        signature = fingerprint(target)
        if detail > 18 and all((signature ^ prior).bit_count() >= 9 for prior in used):
            used.append(signature)
            return position
    target.unlink(missing_ok=True)
    raise ValueError('Could not extract a distinct, visible frame from this video.')
