# GIPHY setup

The shared Flutter picker provides GIFs and Stickers only, with direct GIPHY search,
trending/category results, pagination, and account-specific database recents.
It is used by chat attachment menus and Social comments.

Create an API key at https://developers.giphy.com/dashboard/.
Set GIPHY_API_KEY in backend/.env and restart the API. The authenticated
/messaging/giphy/config endpoint supplies this client credential with no-store.
Flutter then calls GIPHY directly; the backend does not proxy search or media.
The installed app picks up the key without recompiling.

Alternatively, override the key for a client build from frontend/ui:

    flutter run --dart-define=GIPHY_API_KEY=YOUR_KEY

Use the same define for flutter build apk. The key is a client API credential;
do not commit it. Without a backend key or build override, the picker reports that GIPHY is not configured.

The backend stores giphy_selection records (owner, kind, GIPHY ID, selected_at).
Messages/comments store giphy:gif:ID or giphy:sticker:ID references.
Media bytes and media URLs are not stored or proxied. Flutter resolves IDs
directly through GIPHY when displaying messages. Recents are private to the
signed-in account. Existing bundled stickers still render in old messages.

Live API validation requires a configured key and network access.
GIPHY requirements: https://developers.giphy.com/docs/api/best-practices/
