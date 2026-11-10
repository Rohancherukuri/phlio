# Publish all local data to Cloudflare R2 + Surreal Cloud (and keep the app fast)

Everything Phlio stores locally ends up in the cloud this way:

| Local | What it holds | Cloud |
|---|---|---|
| SurrealDB `phlio_graph_dev` (port 8001) | Users, posts, comments, likes, follows, Moments/Snaps metadata and edits, profiles and themes, rooms, Book, Shop, news | **Surreal Cloud** (`--only db`) |
| `backend/media/` | Photos, videos, comment media, Moments, wallpapers, Spaces recordings | **R2 media bucket**: public, served via `MEDIA_PUBLIC_URL` (`--only media`) |
| `data/*_messages.sqlite3`, `*_videos.sqlite3`, `music.sqlite3`, `pay_gateway.sqlite3`, `data/dm_files/`, `media_private_memories/` (snap photos) | DMs, DM files, social videos, music links, payments | **R2 state bucket**: **private** (`--only state`) |

The deployed API restores the state bucket when it boots, backs it up every
minute, and redirects `/media/...` to the media bucket.

> **Security:** a public `r2.dev` bucket serves *every* object in it. Older
> setups kept `_state/` (DMs, payments, private snaps) in the public media
> bucket. Step 1 and `--only move-state` move it into a private bucket.

## Steps (Windows PowerShell, from `backend\`)

1. **Cloudflare → R2 → Create bucket** `phlio-state`, with *Public access* left **off**. Then check the R2 API token:
   - It needs **Object Read & Write on both buckets**: edit the token → *Apply to all buckets*, or add `phlio-state`.
2. **`backend\.env.publish`:** add `OBJECT_STORE_STATE_BUCKET=phlio-state`.
   - Also set `SURREAL_CLOUD_DATABASE=phlio_prod` (a **new** database name). Importing into a fresh database avoids duplicate-record errors, and the old one stays as a backup.
3. **Render → phlio-backend → Settings → Suspend service.** This stops the cloud copy writing while you publish; it makes a final backup as it stops.
4. **Start the local stack:** `.\scripts\Start-GraphDemo.ps1`.
5. **Publish**, in this order:

   ```powershell
   uv run python -m scripts.publish_local_data --only move-state   # once: private bucket, removes public _state/
   uv run python -m scripts.publish_local_data --only state        # your local DMs, payments, snaps → private bucket
   uv run python -m scripts.publish_local_data --only db --slim    # SurrealDB → Surreal Cloud (phlio_prod)
   uv run python -m scripts.publish_local_data --only media --workers 8   # resumable; re-run if it stops
   ```

   Local is the source of truth: the cloud database becomes a copy of your local one.
   - Media is about 8 GB, and `space_recordings` is 6.2 GB of that.
   - R2's free tier is 10 GB. Delete recordings you don't need first if you're close to the limit.
6. **Render → Environment.** Set or add:
   - `SURREAL_DATABASE=phlio_prod`
   - `OBJECT_STORE_STATE_BUCKET=phlio-state`
   - `KEEP_AWAKE=true`

   Keep the existing `OBJECT_STORE_*`, `MEDIA_PUBLIC_URL`, `SURREAL_*` and `JWT_SECRET`. Then push the code to `main` and **Resume** the service.
7. **Check the Render logs** for these lines:
   - `Restored N/N state files … in X s`
   - `phlio_native 0.1.0 loaded`
   - `Keep-awake on`
   - `Phlio API started`
8. **Build the app against the cloud API.** Without this the app calls `127.0.0.1` and shows "Unable to reach Phlio":

   ```powershell
   flutter build apk --release --dart-define=API_BASE_URL=https://phlio-backend.onrender.com/api/v1
   ```

## Why it was slow / "out of network", and what changed

| Cause | Fix |
|---|---|
| Render free sleeps after 15 idle minutes, and the first request then waits 30–60 s | `KEEP_AWAKE=true`: the service pings itself and SurrealDB every 10 min (`app/infrastructure/keep_awake.py`). This uses ~744 of the 750 free hours a month. |
| Boot downloaded state files one by one before serving | Downloads run 8 at a time (`media_sync.restore_state`) |
| App launch waited for `/auth/me`; a slow server sent signed-in users to the login screen | The profile is cached on the device: the app opens at once and refreshes in the background (`auth_controller.dart`, `token_storage.dart`) |
| 15 s receive timeout, shorter than a cold start | 45 s, plus one automatic retry for GETs on timeouts, dropped connections and 502/503/504 (`api_client.dart`) |
| Server woke only when the first real request arrived | The app sends a wake-up `/health` request first thing at launch |
| Feeds blank until the server answered | Last session's copy shown after 1.5 s; offline fallback (`response_cache.dart`, previous change) |
| Request logging on in release builds | Off in release builds unless `--dart-define=ENABLE_REQUEST_LOGGING=true` |
