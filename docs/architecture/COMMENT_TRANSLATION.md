# Comment translation

See translation uses POST /social/content/{ref}/comments/{comment_id}/translate?platform=shop (or the originating platform). The API rechecks comment access and blocks/deletion before consulting the cache. Clients cannot submit arbitrary text or choose another user's comment outside its item. Target language is English. Results are cached for 24 hours by text digest and model version; comment edits get a new cache entry.

A loopback-only worker at 127.0.0.1:8010 runs MADLAD-400-3B with CTranslate2 CPU INT8, four threads and one inference at a time. It does not send comments to a third party. One worker serves both development APIs, avoiding duplicate model memory. Busy requests return a retryable error. This translates text comments, not microphone speech.

Model: https://huggingface.co/google/madlad400-3b-mt (Apache-2.0).
Pinned community CTranslate2 conversion: santhosh/madlad400-3b-ct2 at c32ad0cf118807ea6258d14be137547155842723. Only model data is downloaded, no remote Python code executes. Coverage is 400+ languages, including Indian languages; quality varies, especially slang, transliteration, and mixed-language text. This is not a claim that the model is the newest or best on every language.

Setup from backend: `uv sync`, then `uv run python -m scripts.prepare_translation`. Start `uv run python -m scripts.translation_server`, or use Start-GraphDemo.ps1 after downloading. /health on port 8010 reports model-file readiness and whether loaded. The first translation loads the model and is slower. Keep the worker private; only the authenticated Phlio API should be exposed. No API subscription is required, but hosting and inference use machine resources. Model files live in ignored backend/data.
