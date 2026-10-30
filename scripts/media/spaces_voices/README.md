# Seeded Spaces voices

`conversations.py` holds the six community Spaces (title, topics, whether it
is recorded, which demo account hosts/speaks and every line they say).
`generate.py` speaks them with Kokoro TTS — one Opus track per speaker with
silence while others talk, so each speaker's own LiveKit track lights up
their speaking ring — plus a `mix.m4a` and `timeline.json` (who talks when,
waveform peaks) used for the pre-seeded recordings.

Output lives in `backend/media/spaces_seed/` and is played by
`backend/scripts/run_seeded_spaces.py` (started by Start-GraphDemo.ps1 when
LiveKit is set up).

    pip install kokoro-onnx soundfile numpy
    python scripts/media/spaces_voices/generate.py backend/media/spaces_seed \
        --model kokoro-v1.0.onnx --voices voices-v1.0.bin

Speakers never say each other's names (display names come from the
database). Even demo indices are women and odd are men, matching the
humanized profiles, so voices are picked to match.
