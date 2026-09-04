# Fishers

Multi-sport club management — organise recurring activities (cricket nets, football, badminton, paddle), mark availability, RSVP, pay fees, and order food/kit.

| Layer | Stack |
|-------|--------|
| iOS | SwiftUI, iOS 17+, MVVM, Keychain JWT |
| API | Rust, Axum, sqlx, JWT + argon2 |
| DB | PostgreSQL 16 |

## Quick start

### 1. Database

Postgres is mapped to host port **5433** (avoids clashing with a local 5432).

```bash
cp .env.example .env
docker compose up -d
```

If 5433 is already taken, set `POSTGRES_PORT` and the matching `DATABASE_URL` port in `.env`.

### 2. Backend

```bash
./scripts/run-api.sh
# or: cd backend && cargo run -p fishers-api
```

API: `http://127.0.0.1:8080` · Health: `GET /health` · Routes: `/api/v1/...`

Keep this process running while using the Simulator. Migrations run on startup.

**Simulator tip:** the app points at `http://127.0.0.1:8080`. If sign-in fails with a connection error, the API is not running.

Optional smoke test (signup → London Lords club → Wednesday nets):

```bash
chmod +x scripts/smoke.sh && ./scripts/smoke.sh
```

### 3. iOS

```bash
cd ios
xcodegen generate
open Fishers.xcodeproj
```

Run on Simulator. API base URL defaults to `http://localhost:8080` in `Fishers/Config/AppConfig.swift`.

**CI / TestFlight:** see [docs/IOS_RELEASE.md](docs/IOS_RELEASE.md).

- PR build + tests: `.github/workflows/ios.yml`
- TestFlight / App Store: `.github/workflows/ios_release.yml` (Vault + fastlane, same pattern as KubePilot)

## Squad selection

Availability first, then a side is picked — by a captain, by the deterministic ranking, or by the assistant — then players reconfirm a couple of days out and reserves fill the gaps on their own.

| Method | Path | Notes |
|---|---|---|
| GET/POST | `/events/{id}/selection` | the captain's board / commit a squad (`publish: true` announces it) |
| POST | `/events/{id}/selection/suggest` | deterministic pick, no model involved |
| POST | `/events/{id}/selection/agent` | the assistant decides; auto-publishes only on `auto_publish` |
| POST | `/events/{id}/selection/publish` | announce the squad as it stands |
| POST | `/events/{id}/selection/respond` | the player's reconfirmation (`{confirming}`) |
| POST | `/events/{id}/selection/promote` | pull up reserves now |
| POST | `/events/{id}/status` | delayed, called off, back on — announced to the squad |
| GET/POST | `/clubs/{id}/fees/outstanding` \| `/fees/chase` | who owes, and chase them now |
| POST | `/fixture-blocks` · `/fixture-blocks/{id}/selection` | a tour or tournament, and squads across all of it |

**Ranking** (`backend/domain/src/selection.rs`, 21 unit tests) weighs availability first — picking someone who said no wastes the place — then reliability, then *rotation debt*: fixtures a player was available for and left out of. Position quotas are filled first (a cricket XI wants a keeper and two seamers), and any quota the pool can't satisfy is reported rather than hidden. Across a block the same engine spreads appearances so nobody sits out a whole tour.

**The assistant** starts from that ranking and may depart from it when the thread justifies it — an injury mentioned in chat, someone who can only make half of it — and has to say why. It writes the announcement too.

**Per-club policy** (defaults, all changeable per club): `selection_autonomy = 'suggest'` (the assistant proposes, a human publishes; `auto_publish` lets it announce alone, `off` disables it), `confirm_lead_hours = 48`, `drop_lead_hours = 24`, `fee_chase_after_hours = 24`, `fee_chase_max_reminders = 3`.

The scheduler (`backend/jobs`) asks for reconfirmations as the deadline nears, drops the unconfirmed at the drop deadline and promotes reserves, and chases unpaid match fees — so a captain and a treasurer aren't keeping lists.

## Repo layout

```
backend/          Cargo workspace
  api/            Axum HTTP handlers
  domain/         Models & business logic
  db/             sqlx pool + migrations
  payments/       Stripe stubs (Phase 4)
  notifications/  APNs stubs (Phase 3)
  jobs/           Recurring events & reminders
  agent/          Claude client for the chat assistant
ios/              SwiftUI app (XcodeGen)
scripts/smoke.sh  End-to-end API check
```

## Build phases

1. **Foundation** — auth, profile setup (per-sport level, division, stats, logistics, reliability), clubs/teams, schema ✅
2. **Events & calendar** — CRUD, recurrence, availability, RSVP ✅
3. **Invites & push** — invite links, APNs stubs ✅ / wire APNs next
3b. **Chat & assistant** — threads, unread state, agent proposals with human approval ✅
4. **Payments** — Stripe intent stubs ✅ / real Stripe next
5. **Shop** — products, cart, checkout ✅
6. **Admin reports** — attendance & revenue (next)
7. **Polish** — SwiftData offline, chat, App Store

## Example: London Lords

In the app: create **London Lords CC** → **Add Wednesday nets** on the club screen → mark availability on Calendar → open the event to RSVP / pay / use squad picker for friendlies.

## Roles

`super_admin` · **club secretary** (`club_admin`) · **team captain** · `member` · `guest`

Only a **captain or club secretary** can invite players to a fixture. See [docs/RBAC.md](docs/RBAC.md).
