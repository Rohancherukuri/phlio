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
npm run dev          # http://localhost:5174, /api is proxied to :8000
```

The first account you create becomes the **owner**. Everyone else joins with
an invite link from **Team**.

## Deploy

1. `npm run build` → static files in `dist/` (Render static site, Netlify,
   Cloudflare Pages, S3 …). Add a rewrite of `/*` → `/index.html`.
2. Set `VITE_API_URL=https://<your-api-host>` at build time.
3. On the backend, add the panel's origin to `CORS_ALLOW_ORIGINS`, and set
   `ADMIN_SIGNUP_CODE` (required in production to create the first owner).

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
