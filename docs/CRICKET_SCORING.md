# Cricket scoring (offline-first)

Ball-by-ball match scoring for cricket fixtures. The scoring device is the live source of truth; the API stores an append-only event log and rebuilds projections with the Rust engine.

## Principles

- **No “Save Score” button** — every ball is appended locally and applied by the on-device engine.
- Status chip only: `Saved` / `Syncing…` / `Offline`.
- **One active scorer** per match (`claim-scorer` lock). Others can open the scorecard read-only when online.
- Undo is a compensating event (`undo_last`), never a silent delete.

## Who can score

Permission `score_match` (`Permission::ScoreMatch`):

- Club secretary (`club_admin`)
- Team captain / vice captain
- Super admin
- Users listed on `cricket_match_officials` for that match (`role = scorer`)

## API (`/api/v1`)

| Method | Path | Notes |
|--------|------|--------|
| `POST` | `/events/{id}/cricket-match` | Create/link match from fixture |
| `GET` | `/events/{id}/cricket-match` | Fetch by fixture |
| `POST` | `/cricket/matches/{id}/claim-scorer` | Body: `{ "device_id": "…" }` |
| `POST` | `/cricket/matches/{id}/events` | Batch sync; idempotent on `client_event_id` |
| `GET` | `/cricket/matches/{id}/events?after_seq=` | Pull log |
| `GET` | `/cricket/matches/{id}` | Match + `state` + `last_seq` |
| `GET` | `/cricket/matches/{id}/scorecard` | Projection (`MatchState`) |
| `POST` | `/cricket/matches/{id}/officials` | Assign scorer (manage events) |

Event payload shape matches domain `ScoringEvent` / `ScoringEventKind` (internally tagged `type`).

## iOS

- `Fishers/Cricket/` — types, engine, SwiftData models, `CricketMatchStore`, `CricketSyncService`
- `Fishers/Views/Cricket/` — setup wizard + LIVE scorer + scorecard
- Entry: **Start Match** on cricket `league_match` / `friendly` in `EventDetailView` when `can_score_match`

Offline: airplane mode mid-match continues scoring; pending events flush when `NWPathMonitor` reports online.

## Engines

Identical rules in:

1. Rust — `backend/domain/src/cricket/` (API replay + unit tests)
2. Swift — `ios/Fishers/Cricket/CricketEngine.swift`

## Manual smoke (offline LIVE)

1. Sign in as captain/secretary on a cricket fixture.
2. Start Match → toss → XI → openers → LIVE.
3. Enable airplane mode; score 0–6, extras, wicket, undo, change bowler.
4. Complete innings / match; confirm scorecard locally.
5. Go online; confirm sync chip returns to `Saved` and `GET …/scorecard` matches.
