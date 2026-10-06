# Social videos

Restart the API and rebuild the Flutter app after updating. No external video service is required.

- Uploaded video metadata and creator follows persist in `SOCIAL_VIDEO_DATABASE` (default `data/social_videos.sqlite3`). Keep this database and `MEDIA_ROOT` on persistent storage.
- Identity persistence follows the existing repository configuration. Use the persistent identity backend for accounts that must survive server restarts.
- Authenticated routes: `GET /api/v1/social/videos`, `POST /api/v1/social/videos` (multipart `title` and `file`), `GET /api/v1/social/following`, `PUT`/`DELETE /api/v1/social/creators/{username}/follow`.
- Videos are public Social uploads, served under `/media/social/` with byte-range support. Maximum file size is 2 GiB; accepted extensions are MP4, MOV, M4V and WebM. Playback depends on the device codec support.
- The Videos tab uses uploaded videos; the old demo thumbnails have no playable sources. Open video plays a local file without publishing it.
- Floating playback stays inside Phlio. Switching to another app pauses playback; native OS picture-in-picture is not implemented.
- Speed, seek, volume, repeat and fit/fill work on the source stream. Adaptive quality and captions need transcoded variants/subtitle tracks and are not offered without those assets.
