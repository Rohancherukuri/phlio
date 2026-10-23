# Stream music catalog

Run from backend: `uv run python -m scripts.import_stream_music`.
The importer resumes safely, uses SurrealDB phlio_graph_dev, stores eight tracks
from the composer's public JSON catalog, and serves downloaded MP3s through the
existing byte-range media server. Catalog responses use the existing Redis cache
and graph revision invalidation. Start-GraphDemo.ps1 -Seed includes this import.

Source: https://www.incompetech.com/music/royalty-free/music.html
Catalog: https://www.incompetech.com/music/royalty-free/pieces.json
Artist: Kevin MacLeod
License: https://creativecommons.org/licenses/by/4.0/
Each catalog description contains attribution and the license link. Audio is
unchanged. Artwork is a waveform derived from that specific recording, not
publisher album artwork. No Spotify subscription or API token is required.

Stream playlists carry media_mode=audio or video. The plus button uses the
current Stream mode; the backend rejects content from the other mode.
Existing untyped collections remain available through the generic playlist API.
