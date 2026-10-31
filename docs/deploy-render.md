# Deploying Phlio's backend to Render with your local data

Render's free plan has no persistent disk, so the deployed API keeps its
data in two free cloud services:

| What | Where | How it gets there |
|---|---|---|
| Accounts, posts, moments, rooms, shop, books… (SurrealDB `phlio/phlio_graph_dev`) | Surreal Cloud (free, 1 GB) | `publish_local_data.py` exports locally and imports |
| Photos, videos, recordings (`backend/media`, ~4.2 GB) | Cloudflare R2 bucket (free, 10 GB) | `publish_local_data.py` uploads; `/media/...` redirects there |
| DMs, social videos, music links, payments (SQLite) and DM files | Same R2 bucket, under `_state/` | Uploaded once; the API restores on boot and backs up every minute |

Code: `backend/app/infrastructure/object_store.py` (S3 client),
`backend/app/infrastructure/media_sync.py` (restore / backup / upload),
`MediaFiles` in `backend/app/main.py` (redirect), `backend/scripts/publish_local_data.py`.

## 1. Surreal Cloud

1. Sign up at surrealdb.com/cloud and create a free instance (pick the region
   closest to Render's Singapore, and the same major version as `surreal version`).
2. In the instance, create a root (system) user with a password.
3. Note the endpoint from Connect, e.g. `wss://<instance>.aws-aps1.surreal.cloud`.

## 2. Cloudflare R2

1. In the Cloudflare dashboard → R2, create a bucket, e.g. `phlio-media`.
2. Bucket → Settings → Public access → enable the `r2.dev` subdomain. Copy the
   public URL (`https://pub-<id>.r2.dev`).
3. R2 → Manage API tokens → create a token with Object Read & Write on the
   bucket. Copy the Access Key ID, Secret Access Key and the S3 endpoint
   (`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`).

## 3. Publish your local data

Create `backend/.env.publish` (git-ignored; don't put these in `backend/.env`):

```
OBJECT_STORE_ENDPOINT=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
OBJECT_STORE_BUCKET=phlio-media
OBJECT_STORE_ACCESS_KEY=...
OBJECT_STORE_SECRET_KEY=...
SURREAL_CLOUD_ENDPOINT=wss://<instance>.surreal.cloud
SURREAL_CLOUD_USER=...
SURREAL_CLOUD_PASSWORD=...
```

Start the local stack (`backend\scripts\Start-GraphDemo.ps1`), then from `backend/`:

```
uv run python -m scripts.publish_local_data --slim
```

`--slim` leaves the event-outbox history out of the database (keeps it well
under 1 GB). Media upload is resumable: rerun with `--only media` if it stops.
To refresh just the DMs and other SQLite data later: `--only state`.

## 4. Render

Set these on the service (Environment), then push the code to `main` (or
Manual Deploy):

| Key | Value |
|---|---|
| `DATABASE_BACKEND` | `surreal` |
| `SURREAL_URL` | `wss://<instance>.surreal.cloud/rpc` |
| `SURREAL_USER` / `SURREAL_PASSWORD` | the Surreal Cloud root user |
| `SURREAL_NAMESPACE` / `SURREAL_DATABASE` | `phlio` / `phlio_graph_dev` |
| `MESSAGING_DATABASE` | `data/phlio_graph_dev_messages.sqlite3` |
| `SOCIAL_VIDEO_DATABASE` | `data/phlio_graph_dev_videos.sqlite3` |
| `OBJECT_STORE_ENDPOINT` / `_BUCKET` / `_ACCESS_KEY` / `_SECRET_KEY` | from R2 |
| `MEDIA_PUBLIC_URL` | `https://pub-<id>.r2.dev` |

`render.yaml` lists the same keys.

## 5. The app

```
flutter run --dart-define=API_BASE_URL=https://phlio-backend.onrender.com/api/v1
```

Sign in with the same accounts as locally (tokens from your local API won't
work, since the JWT secret differs).

## Notes

* Render free sleeps after 15 minutes idle; the first request takes ~1 minute.
* Surreal Cloud's free instance pauses after 7 days unused, and becomes
  read-only above 1 GB.
* `r2.dev` URLs are rate-limited and meant for development; connect a custom
  domain to the bucket for real use.
* Not on Render: LiveKit (live Spaces / calls), Redis, the local translation
  and audio-enhancement models.
