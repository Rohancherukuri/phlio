# Social graph implementation and local demo

Implements the shared graph and Social/Rooms integration from `Phlio_Social_Graph_Architecture_v1.0.docx`. Domain records, sharing permission and Foxy permission are separate.

## Run locally

From the repository root in PowerShell:

```powershell
./backend/scripts/Start-GraphDemo.ps1 -Seed
cd frontend/ui
flutter run --dart-define=API_BASE_URL=http://localhost:8002/api/v1
```

Prerequisites: uv, Flutter, SurrealDB 2.2.1, Redis, and FFmpeg on PATH. Redis must listen on `127.0.0.1:6379`. Python dependencies include Pillow for generating fixtures. The launcher starts SurrealDB and the API in hidden processes without replacing an API on port 8000. Subsequent starts can omit `-Seed`.

For Android emulators use `http://10.0.2.2:8002/api/v1`. For USB devices run `adb reverse tcp:8002 tcp:8002` and use localhost. For Wi-Fi devices use the development computer's LAN address. API documentation: `http://127.0.0.1:8002/docs`.

Development logins:

- Creator: `demo_creator_001`
- Consumer: `demo_viewer_021`
- Password for all synthetic accounts: `PhlioDemo!2026`

Creators end in 001–020; consumers end in 021–100. These are fictional people with generated illustrated portraits, not scraped identities. Twenty creators own 60 posts (20 text, 20 image, 20 video), 20 video catalog entries and 20 clips. Eighty consumers have likes/views/follows and no authored feed posts or videos. There are 400 follows, 100 pending/accepted friendship records, five rooms and 100 memberships. Videos are playable six-second animated test patterns with quiet generated tones.

The seeder uses stable IDs, never truncates tables and does not delete existing users. The manifest is `backend/data/social_graph_demo.json`. Generated media is reproducible and ignored by Git.

## Data path

Flutter Posts, Videos, Clips, Explore, creator profiles and followed-creator header avatars read backend APIs. The old fictional video catalogs no longer populate these views. Media resolves against the API origin; the existing video player uses HTTP byte-range streaming from `/media`.

- SurrealDB namespace `phlio`, database `phlio_graph_dev`: accounts, posts, rooms, relationships, universal objects, activities, privacy policies, Notes, aliases, hierarchy, audit and outbox.
- `backend/data/phlio_graph_dev_videos.sqlite3`: durable video-domain metadata. Universal video objects live in SurrealDB.
- `backend/data/phlio_graph_dev_messages.sqlite3`: private messages and call signaling.
- `backend/media/demo_graph`: generated media served by the API.
- Redis prefix `phlio:phlio_graph_dev:`: feed/video metadata caches, activity candidates, rate-limit buckets and outbox events. Media bytes are streamed from storage, not placed in Redis.

Feed/video caches expire after 60 seconds. Keys include viewer and authoritative database graph revision; mutations change that revision. Redis outages fall back to database reads. Activity candidates are re-authorized on every read, including policy expiry. A graph mutation commits its outbox event and revision change together. Redis Streams delivery is at least once; consumers must deduplicate `event_id`. The bounded stream is a notification transport, not the source of truth.

## APIs and privacy

Under `/api/v1`:

- `POST /social/friendships`, `POST /social/friendships/{target}/{accept|decline|remove}`
- `PUT|DELETE /social/blocks/{target}`, `GET /social/connections`
- Existing messaging friend and creator-follow endpoints use the canonical graph.
- `POST /objects`, `GET|PATCH /objects/{id}`, `PUT /objects/{id}/aliases`, `GET /objects/{id}/children`
- `POST /objects/{id}/actions`, `GET /objects/{id}/social-context`
- `PUT|GET /privacy/activity`, `GET /activity/friends`
- `POST|GET /notes`, `POST /agent/context`
- Development-only authenticated `GET /social/graph-status`

Objects support platform taxonomy, hierarchy, aliases and tombstones. Public registration wraps existing owned posts/rooms. Commercial records cannot be invented through this API. Current domain hooks cover post/video creation, likes/comments and room membership. Trusted actions such as paid/booked/purchased are rejected as client-submitted facts.

Social's Activity button opens Friends / Notes / Privacy. Defaults are nobody/hidden/no Foxy access. Synthetic accounts deliberately use mixed policies for testing. Anonymous signals omit actor IDs; blocking, object visibility, room membership and expiry are checked. Payment references remain private and never enter group signals. Notes enforce recipient and object visibility. Foxy's request-bound tool receives the authenticated caller and returns minimal authorized evidence; it accepts no raw SQL.

## Verify

```powershell
cd backend
uv run pytest -q
uv run python -m scripts.verify_graph_demo
cd ../frontend/ui
flutter test
flutter build apk --debug --dart-define=API_BASE_URL=http://localhost:8002/api/v1
```

The live smoke test checks login, feeds, videos, follows, cache statistics and HTTP 206 video delivery. Privacy tests cover request consent, directional follows, blocking, anonymity, expiry after cache warmup, Notes, Pay privacy and Foxy consent. `backend/data/graph-verification.json` records the local population audit.

## Implementation scope

Validated with installed SurrealDB **2.2.1** and Python SDK **2.0.0**, rather than the document's illustrative 3.x syntax. Graph tables deny direct client access; the authenticated backend enforces policy. Launcher root credentials are for local development.

This is a shared-graph development implementation, not a production deployment or every future platform. Book listings and bookings now persist in SurrealDB. Pay ledger and Activity retain their existing in-memory domain repositories. News/Stream provider ingestion, commerce reconciliation, cluster-scale load targets and migration of pre-existing SQLite friend/follow records remain separate work. Existing SQLite history is preserved, not silently imported. Defining a universal object type does not authorize recommendation use or private-data disclosure.


## Cross-platform demo content and sharing

Run `backend/scripts/Start-GraphDemo.ps1 -Seed -RunApp` from PowerShell. The seed is repeatable and writes fictional test data to **phlio_graph_dev**, served on **8002**; the independent server on **8000** still uses its existing memory configuration. Use `-RunApp` without `-Seed` for subsequent launches. Physical Android devices need `adb reverse tcp:8002 tcp:8002` when using the localhost APK.

The additional `python -m scripts.seed_platform_content` seed requires the original 100-account graph seed. It supplies 20 landscape videos and 20 portrait clips (10-second animated demo scenes with sound), 24 Shop products, 24 Book experiences, 12 Stream shorts, 12 explicitly fictional News articles, and 6 public merchant profiles. Existing 60 Social posts and 5 Rooms remain. Images and MP4s are served from the backend media directory; metadata lives in SurrealDB and the existing durable video catalog. No real people's profiles are scraped.

Shared cards show up to three tappable liker avatars plus the remaining visible count. The demo accounts opt into identified public likes; real accounts retain their privacy choices. Redis caches discovery and engagement candidates against graph revision; each response rechecks visibility, blocks, and policy expiry. Private or anonymous likes never expose identities.

Long-press public content (or tap its share icon) for **Messages**, **New group**, **Groups**, and **Rooms**. New groups need two other participants and persist membership/messages in SurrealDB. Group inboxes are reachable from Rooms Home and Social Activity. Shared links open a content detail screen with playback where applicable. Existing DMs and Rooms store the links in their normal message history. Group chat supports text and content links with a refresh control; it does not yet duplicate every DM media/call feature. Financial transaction records cannot be shared.

Additional API routes: `GET /content/{platform}`, `GET /content/{platform}/{ref}`, `GET /content/{platform}/{ref}/engagement`, `PUT /content/{platform}/{ref}/like`, `POST /content/{platform}/{ref}/share`, `GET /sharing/destinations`, `GET /messaging/groups`, `GET|POST /messaging/groups/{id}/messages`.

## Social media refresh

`python -m scripts.enrich_social_demo` runs after the platform seed (also included in `Start-GraphDemo.ps1 -Seed`). It updates only `is_test_user` demo accounts and their demo media. Ninety fictional profiles now use photographic test portraits from [Random User Generator](https://randomuser.me/documentation); ten retain illustrated avatars. Profile names remain fictional and do not identify the people pictured. Portraits are cached locally under `media/demo_graph/portrait_*.jpg`, with source attribution in `data/social-enrichment.json`.

Twenty demo videos run 60–300 seconds and twenty portrait clips run 15–120 seconds. They are synthetic animated scenes repeated to the requested runtime, not real creator recordings. The manifest records both requested and ffprobe-measured duration. Videos excludes clips, while Clips only displays clips; duration labels come from backend metadata.

The bottom plus menu now owns post/video/clip creation. Uploads validate playable video tracks and duration (videos 60–300 seconds, clips 15–120 seconds), with a 2 GB size cap. Duplicate feed upload prompts are removed. `ffprobe` must be available to the backend for new uploads.

Hold a content card or video picture to open the rounded share sheet: searchable three-column recipient grid, Messages, New group, Groups and Rooms. The bottom action row supports Add to story (24-hour content reshare), WhatsApp, Copy link, native Share and Rooms. Native sharing exposes installed apps; WhatsApp Status availability is controlled by the installed app, not a fabricated in-app destination. Stories are available from the Social story strip's first tile and visible to accepted friends/followers, with content permissions rechecked. Expired stories are excluded from reads.

Profile stacks first show known followers (people you follow or are friends with who follow this profile), matching Instagram's "Followed by" context. When there are none, they show mutual accepted friends. Both return up to three avatars and the true count, excluding blocked users. Demo friendships overlap to exercise this UI. `phlio://app/shared/{platform}/{id}` links open authenticated content details on Android/iOS, preserving the pending destination through login. This development build still requires access to its local backend; it is not a publicly hosted sharing website.

The VS Code launch configuration **Phlio populated demo (8002)** targets the populated persistent database. Start `backend/scripts/Start-GraphDemo.ps1` before launching. The independent memory server on 8000 remains available for unrelated development.

## News and normal-app feed repair (2026-10-09)

The local backend `.env` now uses the populated `phlio_graph_dev` Surreal database,
video SQLite database, and Redis namespace on the normal port 8000. The existing
`rohanoxob` account was found in this database and retained. The previous empty
feed came from the normal server using memory while demo content lived in the
isolated database. `Start-GraphDemo.ps1` now starts both normal and demo ports.
On an attached Android device use `adb reverse tcp:8000 tcp:8000` for localhost.

News ingestion is opt-in via `NEWS_INGESTION_ENABLED`. The local profile enables
it. The worker refreshes publisher RSS every 30 minutes, persists attributed
headlines, publication dates, images supplied in RSS, and original article URLs.
It retains the last successful data on feed failures and never copies full
article bodies. Sources: The Guardian section feeds
(https://www.theguardian.com/help/feeds) and The Hindu Hyderabad RSS.
Production syndication must use publisher-approved licensing/terms.

Home includes horizontal categories and a headlines carousel; Explore searches
headlines, publisher names, topics and URLs. Local News is explicitly Hyderabad.
For You prioritizes topics previously liked or saved, otherwise newest stories.
Blindspot means unread stories in less-represented imported topics; it is not a
political-bias analysis or a claim of comprehensive source coverage.

Social and News expose bookmarks, shares, unique views and repost counts alongside
like avatars. Save/repost toggle durable graph activities; view is idempotent per
viewer and content. Counts honor the graph's existing visibility policies rather
than disclosing private activity. Bookmarks and repost libraries are available in
the share sheet. Video views record successful playback; news views record source
opening, and shared detail views record opening the detail. Internal DM/group/room
shares increment the durable shared activity; opening an external share chooser
is not treated as proof a message was delivered.

Verification: normal API returned 20 videos and 20 clips; byte-range request
returned HTTP 206; repeated feed access reported Redis hits. Publisher topics
were populated including Hyderabad, Politics and AI. Tests cover action toggles,
unique views, feed parsing and narrow News layouts.

### Empty-feed follow-up: actual mobile request (2026-10-09)

Earlier API verification omitted the cursor. Dio serialized the absent first-page
cursor as `?before=`, causing SQLite to exclude every video. The client now omits
absent cursors, the backend normalizes blanks, and the cache key version changed.
Regression tests cover both outgoing Dio parameters and the incoming empty query.

News now bulk-checks current public publisher-object state and blocking instead
of making hundreds of sequential authorization queries. Measured request time
fell from 8.8 seconds to 0.145 seconds. Platform screens initialize on first visit,
reducing startup requests. Confirmed video feed, clip playback and populated News
cards on the connected Android phone after installing the update.
