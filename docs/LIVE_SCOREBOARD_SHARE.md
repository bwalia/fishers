# Live scoreboard share links

Scorers can mint a **secure, revocable** link to the **full live cricket scoreboard** and send it anywhere — WhatsApp, email, Messages, or club chat.

## Flow

1. Scorer opens a LIVE match.
2. **iOS:** tap **Share** → **Share via WhatsApp, Mail…** (system share sheet).  
   **Web:** tap **Share scoreboard** on the match page.
3. API creates (or reuses) a token in `cricket_scoreboard_shares` (default 48h TTL).
4. Anyone with the link opens `/live/{token}` — no login required. The page shows the full scorecard, wagon wheel, and commentary, and polls every 5 seconds.
5. Recipients can tap **Share this scoreboard** to forward the same link again.

Optional: **Share and post to club chat** also drops the link into the fixture/club thread.

## API

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/api/v1/cricket/matches/{id}/share` | JWT club member | Body: `{ post_to_chat?: bool, ttl_hours?: int }` |
| DELETE | `/api/v1/cricket/matches/{id}/share` | JWT scorer | Body: `{ token }` — revoke |
| GET | `/api/v1/public/scoreboard/{token}` | none | Live `MatchState` + player names |

Set `PUBLIC_WEB_BASE` (or `WEB_BASE_URL`) on the API so minted links point at the web app (e.g. `http://192.168.1.99:7311`).

## Security

- Tokens are 48 random hex bytes, unique, expiry-bound, and revocable.
- Public endpoint returns scoreboard data only — no scoring controls or club admin data.
- Revoke from the match share endpoint when a link should stop working.
