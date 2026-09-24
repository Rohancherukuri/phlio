"""Home aggregation — composes data from other domains for the home screen.

Not a "domain" in the same sense as identity/social/rooms/art/agent: it
owns no entities or storage of its own. It exists because the Home screen
in the reference UI (Image 1) is explicitly cross-domain — quick actions,
a "for you" strip, and an upcoming plan all come from different services.
Keeping that composition in one small backend service means the Flutter
app makes one request instead of orchestrating three, and keeps that
composition logic out of the client (architecture doc section 39: business
rules belong on the server, not the frontend).
"""
