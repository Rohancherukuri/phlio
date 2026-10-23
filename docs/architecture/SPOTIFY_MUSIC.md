# Spotify music selection

The shared Flutter picker is `frontend/ui/lib/shared/music/song_picker.dart`.
Search is debounced, paginated in pages of 10 and uses Spotify catalog data.
For you uses the connected account's top tracks. Trending means most saved on
Phlio, not a Spotify chart. Saved is a private Phlio music bookmark library.
Original audio explains that uploaded media supplies its own audio; it is not a
Spotify download, audio mixer or separate original-audio catalog.

## Configuration and connection

Backend reads SPOTIFY_CLIENT_ID and SPOTIFY_CALLBACK_URL (SPOTIFY_REDIRECT_URI
is an accepted alias). The implemented callback is `/auth/spotify/callback`.
The current development callback is http://127.0.0.1:8000/auth/spotify/callback;
it must exactly match the Spotify developer dashboard. The phone browser needs
the same USB port mapping as the app for this local callback. Deployment needs
an HTTPS callback on the deployed API. Allow test users in the Spotify developer
application as required by its access tier.

Connect uses authorization-code PKCE, expiring single-use state and a browser
consent page. Return to Phlio after approving; the picker refreshes on resume.
No client secret is required for PKCE. Tokens are encrypted in MUSIC_DATABASE
(default data/music.sqlite3) using a key derived from JWT_SECRET. Use a strong,
private JWT_SECRET; rotating it requires reconnecting Spotify. OAuth callback
query parameters are excluded from Uvicorn access logs. Redis caches catalog
responses for 60 seconds, scoped by the Phlio account. Disconnect removes tokens.

## Persistence and current scope

Posts, videos and clips attach the selected reference on publication. Public
readback checks social graph visibility and ownership. Notes carry music metadata
through their existing recipient authorization. Profile selections persist on
the backend. Moment and experience music selections are private drafts because
those publishing workflows have not yet been implemented.

Each selection displays the title, artist and a link to Spotify. Spotify audio
is not downloaded, mixed into uploads or automatically played with visual media.
Local audio/profile file selection continues to use the existing upload flow.
No fabricated catalog rows are shipped. Connecting a real account is required
to validate live catalog access; automated tests mock Spotify upstream responses.

Official references:
- https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow
- https://developer.spotify.com/documentation/web-api/concepts/redirect_uri
- https://developer.spotify.com/documentation/web-api/references/changes/february-2026
- https://developer.spotify.com/policy
