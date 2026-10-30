# Foxy voice enhancement

DMs: hold your sent audio message and choose **Improve with Foxy AI**. The same
message is updated after successful processing. The original remains available via
**Restore original audio**. Recipients see the Foxy label and improved attachment;
only the sender can replace it. This is denoising, not voice cloning or speech generation.

## Model and setup

[DeepFilterNet3](https://github.com/Rikorose/DeepFilterNet) runs locally with the
v0.5.6 native Rust executable and explicit DF3 ONNX model. Upstream code/model
licensing is MIT/Apache-2.0; license files are downloaded beside the model.
No paid API credentials or external audio uploads are used.

From backend: `uv run python scripts/prepare_audio_enhancement.py` installs the
pinned, SHA-256 checked Windows x64 runtime and model into ignored data storage.
Install FFmpeg/ffprobe on PATH. For another OS, install the matching upstream
native binary and set `PHLIO_DEEP_FILTER_BIN`; keep the same model path.

The endpoint `/messaging/peers/{peer}/messages/{id}/improve-audio` takes
`attachment_id` and optional `restore`. It enforces conversation authorization,
sender ownership, block checks, five requests/minute, a five-minute audio limit,
and one inference per API process. Existing attachments stay untouched on errors.
Temporary PCM files are removed after processing. Output is mono 48 kHz AAC,
with 30 dB attenuation limit and peak limiting. No quality improvement is guaranteed
for every voice/noise combination; restoration is always available.

Both original and enhanced files stay in the existing private messaging file store
and follow its retention/access rules. Only model work runs in a thread; SQLite
updates stay on the API thread. Authorization/message version is rechecked after
inference so unsent or changed messages are not recreated.

## Live calls

LiveKit's WebRTC capture explicitly enables noise suppression, echo cancellation,
automatic gain control and high-pass filtering. DM recording enables the recorder's
platform noise suppression and echo cancellation. Support varies by device.
These live paths are **not DeepFilterNet3 neural inference**. A native PCM processing
integration is still needed to use DF3 on calls; offline server inference must not
be inserted into the real-time call path because it introduces latency.

## Verification

`uv run pytest tests/test_audio_enhancement.py tests/test_messaging.py` exercises
sender/recipient/outsider permissions, original preservation, repeat requests,
restoration and processing failures. A local real-model smoke test additionally
verified DF3 decoding and AAC output. Human listening tests and noisy two-device
call tests remain necessary to assess perceptual quality.
