"""Text to speech and auto captions for Phlio Studio (both run locally).

TTS uses Kokoro (kokoro-onnx). Its model files (~340 MB) are downloaded on
first use into ``data/models/kokoro``. Captions use faster-whisper (the
``base`` model is downloaded by the library on first use).
"""
import threading
import urllib.request
from pathlib import Path

from fastapi import HTTPException

KOKORO_BASE = 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/'
KOKORO_FILES = ('kokoro-v1.0.onnx', 'voices-v1.0.bin')
# Studio voice id -> (Kokoro voice, language)
VOICES = {
    'nova': ('af_nova', 'en-us', 'Nova', 'Bright'),
    'heart': ('af_heart', 'en-us', 'Heart', 'Warm'),
    'bella': ('af_bella', 'en-us', 'Bella', 'Lively'),
    'sky': ('af_sky', 'en-us', 'Sky', 'Calm'),
    'adam': ('am_adam', 'en-us', 'Adam', 'Narrator'),
    'michael': ('am_michael', 'en-us', 'Michael', 'Deep'),
    'puck': ('am_puck', 'en-us', 'Puck', 'Playful'),
    'emma': ('bf_emma', 'en-gb', 'Emma', 'British'),
    'george': ('bm_george', 'en-gb', 'George', 'British'),
}
_lock = threading.Lock()
_kokoro = None
_whisper = None


def model_dir() -> Path:
    root = Path(__file__).resolve().parents[3] / 'data' / 'models' / 'kokoro'
    root.mkdir(parents=True, exist_ok=True)
    return root


def _load_kokoro():
    global _kokoro
    with _lock:
        if _kokoro is None:
            try:
                from kokoro_onnx import Kokoro
            except ImportError as exc:
                raise HTTPException(503, 'Text to speech is not installed on this server.') from exc
            root = model_dir()
            for name in KOKORO_FILES:
                path = root / name
                if not path.exists():
                    tmp = path.with_suffix('.part')
                    try:
                        urllib.request.urlretrieve(KOKORO_BASE + name, tmp)
                        tmp.replace(path)
                    except OSError as exc:
                        tmp.unlink(missing_ok=True)
                        raise HTTPException(503, 'Could not download the voice model. Try again later.') from exc
            _kokoro = Kokoro(str(root / KOKORO_FILES[0]), str(root / KOKORO_FILES[1]))
    return _kokoro


def speak(text: str, voice: str, speed: float, destination: Path) -> float:
    """Render speech to an m4a file and return its duration."""
    import subprocess
    import numpy as np
    kokoro = _load_kokoro()
    name, lang = VOICES.get(voice, VOICES['nova'])[:2]
    samples, rate = kokoro.create(text, voice=name, speed=speed, lang=lang)
    pcm = (np.clip(samples, -1, 1) * 32767).astype('<i2').tobytes()
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(rate), '-ac', '1', '-i', '-',
                    '-c:a', 'aac', '-b:a', '128k', str(destination)], input=pcm, check=True, timeout=60)
    return round(len(samples) / rate, 3)


def _load_whisper():
    global _whisper
    with _lock:
        if _whisper is None:
            try:
                from faster_whisper import WhisperModel
            except ImportError as exc:
                raise HTTPException(503, 'Auto captions are not installed on this server.') from exc
            try:
                _whisper = WhisperModel('base', device='cpu', compute_type='int8')
            except Exception as exc:
                raise HTTPException(503, 'Could not load the captions model. Try again later.') from exc
    return _whisper


def transcribe(wav: Path, language: str | None = None) -> list[dict]:
    """Phrases with word timings, grouped into short caption lines."""
    model = _load_whisper()
    segments, _ = model.transcribe(str(wav), language=language or None, word_timestamps=True,
                                   vad_filter=True)
    lines, words = [], []

    def flush():
        if words:
            lines.append(dict(start=words[0]['start'], end=words[-1]['end'],
                              text=' '.join(w['word'] for w in words).strip(), words=list(words)))
            words.clear()

    for segment in segments:
        for w in segment.words or []:
            word = dict(word=w.word.strip(), start=round(w.start, 3), end=round(w.end, 3))
            if not word['word']:
                continue
            if words and (len(words) >= 6 or word['start'] - words[-1]['end'] > .6
                          or words[-1]['word'][-1:] in '.?!'):
                flush()
            words.append(word)
        flush()
    return lines
