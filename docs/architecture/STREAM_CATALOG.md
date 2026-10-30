# Phlio Stream catalog

No API keys are needed for these integrations:

- TVmaze: https://www.tvmaze.com/api — TV metadata, full episode lists and cast. CC BY-SA 4.0 attribution and license links are displayed. No episode playback URLs are supplied by TVmaze.
- Jikan: https://docs.api.jikan.moe/ — anime metadata, studios, trailers and external streaming links. The API is open source; that does not license the anime itself for redistribution.
- Kitsu: https://github.com/hummingbird-me/api-docs — independent anime metadata fallback when Jikan is unavailable. Ratings are converted from 100 to 10. Streaming links open externally; availability varies by country and subscription.
- Blender Foundation open films: Big Buck Bunny and Tears of Steel, CC BY 3.0, with complete original credits. https://peach.blender.org/about/ and https://mango.blender.org/about/

`app/domains/stream/catalog.py` normalizes and stores catalogs in `platform_content` and registers graph objects so existing likes, comments, views, shares and playlists work. Provider data refreshes daily; unsuccessful refreshes retry after five minutes and preserve saved records. Details are cached for one day, with a one-minute failure backoff. No credentials or arbitrary user-supplied URLs are passed to provider fetches.

The starter shelves include 12 TV titles, 12 anime titles and two licensed films. Search in the app filters the loaded catalog; it is not an exhaustive provider-wide search. TV episodes are metadata, not playable streams. Provider fields that are unavailable are omitted rather than invented.

The local development library already contains `media/live_recordings/big-buck-bunny.mp4` and its poster. Tears of Steel uses `media/stream_films/tears-of-steel.mp4` when present, otherwise its official Blender download URL. Missing local media is never advertised as playable. To recreate Big Buck Bunny, use the existing `scripts/import_live_recordings.py`. The original Tears of Steel source imported by `scripts/import_licensed_social.py` can be remuxed with:

```powershell
ffmpeg -i media/licensed_social/tears-of-steel-source.mov -c:v copy -c:a aac -b:a 128k -movflags +faststart media/stream_films/tears-of-steel.mp4
```

Run `uv run python -m scripts.refresh_stream_catalog` to warm the graph demo catalog and validate provider details. Normal deployment populates its own database on the first Stream catalog request. Artwork and metadata may have separate source terms; an open-source API does not grant rights to commercial films or artwork. Keep source attributions and obtain content/provider licenses before adding commercial in-app streams.
