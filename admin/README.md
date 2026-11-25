# Phlio Admin

The web admin panel for Phlio: sign up / sign in, a dashboard for every
platform (Social, Messages, Rooms, Pay, Book, Shop, Stream, News, Agent),
live numbers over a WebSocket, the user list, the admin team and analytics
integrations (Google Analytics 4, PostHog, Plausible, Umami, Matomo).

**Stack:** React 18 + TypeScript + Vite, Tailwind CSS, Recharts (interactive
charts), TanStack Query. It's a static single-page app, with no server of its
own: everything comes from the Phlio FastAPI backend (`/api/v1/admin/*`), which
reads SurrealDB and caches in Redis.

## Run locally

```bash
# 1. the backend (from backend/)
uvicorn app.main:app --reload --port 8000

# 2. the panel (from admin/)
npm install
npm run dev          # http://localhost:5174
```

`npm run dev` proxies `/api` to the backend. It picks the first of
`127.0.0.1:8000` and `127.0.0.1:8002` that's running (8002 is what the
Flutter app's `dart_defines.json` uses). To use another address, put
`VITE_API_PROXY=http://127.0.0.1:9000` in `admin/.env.local`. **Start the
backend before the panel**, or restart `npm run dev` after starting it: if
nothing answers, the login page says "The Phlio API isn't running".

The first account you create becomes the **owner**. Everyone else joins with
an invite link from **Team**.

## Deploy

1. `npm run build` → static files in `dist/` (Render static site, Netlify,
   Cloudflare Pages, S3 …). Add a rewrite of `/*` → `/index.html`.
2. Set `VITE_API_URL=https://<your-api-host>` at build time.
3. On the backend, add the panel's origin to `CORS_ALLOW_ORIGINS`, and set
   `ADMIN_SIGNUP_CODE` (required in production to create the first owner).

## Sign in with Google / Apple

The login and signup pages have **Continue with Google** and **Continue with
Apple**. They reuse the app's server-side token checks
(`app/api/v1/auth_security.py`), so they use the same settings:

- **Google:** `GOOGLE_SERVER_CLIENT_ID` (the Web OAuth client). In Google
  Cloud → Credentials → that client, add the panel's address (e.g.
  `https://admin.phlio.app`, `http://localhost:5174`) to *Authorized
  JavaScript origins*.
- **Apple:** `APPLE_SERVICE_ID` (a Services ID). In Apple Developer →
  Identifiers → that Services ID → Sign in with Apple, add the panel's domain
  and `https://<panel>/login` as a return URL. Apple needs HTTPS, so it
  doesn't work on localhost.

An existing admin is matched by their Google/Apple account, then by verified
email (so a password admin can also use Google with the same email). New
people still need an invite code (or, for the first owner, the signup code):
type it on the signup page, then press the Google/Apple button.

## Roles

| Role | Can |
|---|---|
| viewer | see dashboards, live numbers and users (emails masked) |
| analyst | + full user emails |
| admin | + integrations, invites |
| owner | + change roles, turn admins off |

## Security notes

- Admin tokens are separate from app tokens (type `admin`, audience
  `phlio-admin`, 8 h) and live in `sessionStorage`.
- The live WebSocket gets the token in its first message, never in the URL.
- Login and signup are rate-limited; integration secrets are never sent
  back to the browser.
