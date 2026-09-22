# Fishers web dashboard

Next.js App Router dashboard against the same Fishers API as iOS.

## Run

The stack script is the short way, and the one that gets the ports right — it
starts the API and the dashboard together and writes `web/.env.local` with
whatever port `.env` resolved to:

```bash
../scripts/start.sh --no-ios
```

By hand, when you already have an API running:

```bash
cd web
npm install
npm run dev
```

Both listen on **all interfaces**, so a phone on the same Wi-Fi can reach them.
The ports come from `.env` — `WEB_PORT` for the dashboard, `API_PORT` for the
API — and default to 7311 and 7312, which is what `.env.example` ships. Open
the dashboard on this machine's LAN address rather than localhost if you want a
phone to follow the same link.

`start.sh --status` prints both addresses, so there is no number here to go
stale.

The browser works out the API's host from the page it loaded and only needs its
port; `.env.local.example` has the two overrides for when it is somewhere else.

Demo login: `demo@fishers.test` / `password123`

Swagger lives on the API at `/swagger-ui`.
