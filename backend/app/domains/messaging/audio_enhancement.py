"""Local DeepFilterNet3 inference. No conversation audio leaves this server."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from fastapi import HTTPException

ROOT = Path(__file__).resolve().parents[3] / 'data' / 'audio-enhancement'


def enhance_audio(source: Path, output: Path) -> None:
    binary = Path(os.environ.get('PHLIO_DEEP_FILTER_BIN', str(ROOT / 'deep-filter.exe')))
    model = ROOT / 'DeepFilterNet3_onnx.tar.gz'
    ffmpeg, probe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    if not binary.is_file() or not model.is_file() or not ffmpeg or not probe:
        raise HTTPException(503, 'Foxy audio enhancement is not installed on this server.')
    def run(args, timeout=60):
        return subprocess.run(args, check=True, capture_output=True, timeout=timeout,
                              creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    try:
        info = json.loads(run([probe, '-v', 'error', '-show_entries', 'format=duration',
                               '-of', 'json', str(source)]).stdout)
        duration = float(info['format']['duration'])
        if not 0 < duration <= 300:
            raise HTTPException(422, 'Improve voice messages up to five minutes long.')
        with tempfile.TemporaryDirectory(prefix='phlio-voice-') as work:
            work = Path(work)
            wav = work / 'voice.wav'
            run([ffmpeg, '-v', 'error', '-nostdin', '-y', '-i', str(source), '-vn',
                 '-t', '300', '-ar', '48000', '-ac', '1', '-c:a', 'pcm_f32le', str(wav)])
            run([str(binary), '-m', str(model), '-D', '-a', '30', '-o', str(work / 'clean'), str(wav)], 180)
            # Moderate attenuation retains voice character. The limiter prevents clipping.
            run([ffmpeg, '-v', 'error', '-nostdin', '-y', '-i', str(work / 'clean' / 'voice.wav'),
                 '-af', 'alimiter=limit=0.95:level=false', '-c:a', 'aac', '-b:a', '96k',
                 '-movflags', '+faststart', str(output)])
    except HTTPException:
        raise
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        output.unlink(missing_ok=True)
        raise HTTPException(503, 'Could not improve this recording. Your original is unchanged.') from exc
