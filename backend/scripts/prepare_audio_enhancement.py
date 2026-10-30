"""Install the pinned Windows DeepFilterNet3 runtime: uv run python scripts/prepare_audio_enhancement.py."""
from pathlib import Path
import hashlib
import urllib.request

ROOT = Path(__file__).resolve().parents[1] / 'data' / 'audio-enhancement'
FILES = {
 'deep-filter.exe': ('https://github.com/Rikorose/DeepFilterNet/releases/download/v0.5.6/deep-filter-0.5.6-x86_64-pc-windows-msvc.exe', '75e11fa16445f560cb6b021521ddb89e89270d13b83089705d98776f58fd7915'),
 'DeepFilterNet3_onnx.tar.gz': ('https://raw.githubusercontent.com/Rikorose/DeepFilterNet/v0.5.6/models/DeepFilterNet3_onnx.tar.gz', 'c94d91f70911001c946e0fabb4aa9adc37045f45a03b56008cb0c8244cb63616'),
}
if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    for name, (url, digest) in FILES.items():
        dest = ROOT / name
        if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest() == digest:
            continue
        data = urllib.request.urlopen(url, timeout=120).read()
        if hashlib.sha256(data).hexdigest() != digest:
            raise RuntimeError('Download checksum mismatch: ' + name)
        dest.write_bytes(data)
    for license in ['LICENSE', 'LICENSE-MIT', 'LICENSE-APACHE']:
        (ROOT / license).write_bytes(urllib.request.urlopen(
            'https://raw.githubusercontent.com/Rikorose/DeepFilterNet/v0.5.6/' + license, timeout=30).read())
    print('DeepFilterNet3 ready. FFmpeg and ffprobe must also be on PATH.')
