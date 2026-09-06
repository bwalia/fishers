# Live scoreboard share links

Scorers can mint a **secure, revocable** link to the live cricket scoreboard and post it into club chat.

## Flow

1. Scorer opens a LIVE match and taps **Share live**.
2. API creates (or reuses) a token in `cricket_scoreboard_shares` (default 48h TTL).
3. A `system` chat message is posted to the fixture/club thread with the URL and metadata `{ kind: "scoreboard_share", token, url, match_id }`.
4. Anyone with the link opens `/live/{token}` on the web app — no login required.
5. The page polls `GET /api/v1/public/scoreboard/{token}` every 5 seconds.

## API

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/api/v1/cricket/matches/{id}/share` | JWT club member | Body: `{ post_to_chat?: bool, ttl_hours?: int }` |
| DELETE | `/api/v1/cricket/matches/{id}/share` | JWT scorer | Body: `{ token }` — revoke |
| GET | `/api/v1/public/scoreboard/{token}` | none | Live `MatchState` + player names |

Set `PUBLIC_WEB_BASE` (or `WEB_BASE_URL`) on the API so minted links point at the web app (e.g. `http://127.0.0.1:3000`).

## Security

- Tokens are 48 random hex bytes, unique, expiry-bound, and revocable.
- Public endpoint returns scoreboard data only — no scoring controls or club admin data.
- Revoke from the match share endpoint when a link should stop working.
