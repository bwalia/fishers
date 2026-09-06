# Play-Cricket season stats

Fishers stores **season aggregates** (runs, wickets, records) and links out to [Play-Cricket](https://play-cricket.com/) (ECB).

All Play-Cricket buttons open **`https://play-cricket.com/`** (the live public site). Fabricated sample deep paths are not used.

## Why sample data?

Play-Cricket does **not** expose a dedicated public statistics API for startups. Clubs can request an API token for match/result feeds. Until a club configures `PLAY_CRICKET_API_TOKEN`, Fishers serves a rich **sample import** seeded for cricket clubs and members (including `demo@fishers.test`).

## Schema

| Table | Purpose |
|-------|---------|
| `play_cricket_club_sites` | Club ↔ Play-Cricket `site_id` + public URL |
| `play_cricket_player_links` | User ↔ Play-Cricket `player_id` + profile URL |
| `player_season_stats` | Runs, wickets, batting/bowling detail per season |
| `club_season_stats` | Club W–L–D, runs for/against |
| `achievement_defs` / `user_achievements` | Catalogue + awards (fifty, five-fer, club champion, …) |

Migration: `20260905000008_play_cricket_stats.sql`  
Sample squad (8 extra players): `20260905000009_play_cricket_sample_squad.sql`

## API

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/v1/me/stats?season=2026` | Links, seasons, achievements for the signed-in user |
| GET | `/api/v1/users/{id}/stats` | Teammate season board (shared club) |
| GET | `/api/v1/users/{id}/achievements` | Awards |
| GET | `/api/v1/clubs/{id}/stats?season=2026` | Club board + top batters/bowlers |
| POST | `/api/v1/clubs/{id}/stats/sync` | Secretary: refresh sync stamp; uses token if set |
| GET | `/api/v1/achievements` | Achievement catalogue |

## Clients

- **iOS Profile** — **Season stats** section (always visible): runs / wickets / achievements + “View on Play-Cricket”
- **iOS Club detail** — Season stats → club board  
- **Web** — `/stats` dashboard

Sign in as `demo@fishers.test` / `password123` for the sample showcase season (412 runs, 23 wickets).

If Profile shows a decode/network error under Season stats, confirm the API is running (`./scripts/run-api.sh`) and rebuild the iOS app so fractional ISO-8601 timestamps decode correctly.

## Live sync (optional)

```bash
export PLAY_CRICKET_API_TOKEN=your_club_token
```

With a token, `POST …/stats/sync` marks the club synced. Full result→stats import can be wired onto the same path later.
