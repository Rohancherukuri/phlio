# Rooms messaging and calls

Restart the API after updating these routes. Stop and rebuild the Flutter app;
hot reload does not register the new PDF, video, and WebRTC native plugins.

Direct messages are stored in SQLite at `data/messages.sqlite3` by default.
Private attachments live in `data/dm_files` and are served only to the two
conversation participants through authenticated routes. Back up both paths.
Configure `MESSAGING_DATABASE` and `MESSAGING_MEDIA_ROOT` to move them.
The peer IDs must exist in the configured identity repository; persistent
messaging should be paired with persistent identity storage for deployments.

Calls use WebRTC with authenticated REST signaling. The default ICE
configuration includes STUN. Configure a TURN relay for reliable connections
between restrictive networks, for example in the backend `.env`:

```dotenv
CALLS_ICE_SERVERS=[{"urls":"stun:stun.l.google.com:19302"},{"urls":"turn:your-relay.example:3478","username":"your-user","credential":"your-secret"}]
```

Call negotiation currently lives in memory: use a single API worker or sticky
routing. Restarting the API ends active calls. Incoming invitations are polled
while the app is foregrounded; there is no background push calling yet.
Verify audio/video on two real devices and different networks before release.

The attachment reader renders PDF pages and extracts bounded text samples
from DOCX, XLSX, PPTX, and text formats. Office previews are text, rather than
exact original page layouts. Files at 1 GB or above retain a file card without
preview decoding. Automatic document downloads are limited to 20 MB;
larger supported previews require a tap. Extracted document samples are limited
to 16 MB inputs and 12,000 characters.

Checks:

```powershell
uv run pytest tests/test_messaging.py tests/test_rooms.py -q
# From frontend/ui:
flutter test test/widget/rooms_layout_test.dart test/widget/rooms_screen_test.dart test/widget/attachment_preview_test.dart
flutter build apk --debug
```

Rooms Home offers friend requests and search. Friendships persist in the same
SQLite database, with recipient-only acceptance and participant-only removal.
Search includes DMs belonging to the caller and messages in joined rooms;
People returns public names/handles only. Pins searches existing room pinned
descriptions. Up to 100 content results are returned, with a refine-search hint.
Explore groups public rooms into interest communities and lists public lobbies.
These are discovery views over the existing room membership model.
