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
cd backend
cargo run -p fishers-api
```

API: `http://localhost:8080` · Health: `GET /health` · Routes: `/api/v1/...`

Migrations run on startup.

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

## Profile setup — the app's first stage

A new account lands on profile setup and stays there until it has a sport with a stated standard (`profile_complete` on `GET /me`). Setup adds one step per sport picked:

- **Level** — Beginner → Improver → Intermediate → Club standard → Advanced → Elite, with the next rung shown as a target
- **League** — team, age group (U11–U17 / Senior / Vets), division played and division aimed for
- **Stats per sport** — cricket batting/bowling styles and averages, padel level and side, badminton discipline and ladder position, football goals/assists, rugby tries, and so on (`ios/Fishers/Models/SportStats.swift`)
- **Travel** — area, postcode, radius, transport, spare seats for lifts, usual days

`PATCH /me` takes the whole profile: `primary_sport`, `sport_profiles[]` (each with `skill_level`, `current_division`, `target_division`, `age_group`, `stats{}`), and `location`.

**Reliability** is read-only and computed by the API from attendance history — turning up 50%, answering invites 25%, paying fees 25%, minus 5 per late drop-out; `unproven` under three past games (`backend/domain/src/reliability.rs`, mirrored in the client so both agree).

## Repo layout

```
backend/          Cargo workspace
  api/            Axum HTTP handlers
  domain/         Models & business logic
  db/             sqlx pool + migrations
  payments/       Stripe stubs (Phase 4)
  notifications/  APNs stubs (Phase 3)
  jobs/           Recurring events & reminders
ios/              SwiftUI app (XcodeGen)
scripts/smoke.sh  End-to-end API check
```

## Build phases

1. **Foundation** — auth, profile setup (per-sport level, division, stats, logistics, reliability), clubs/teams, schema ✅
2. **Events & calendar** — CRUD, recurrence, availability, RSVP ✅
3. **Invites & push** — invite links, APNs stubs ✅ / wire APNs next
4. **Payments** — Stripe intent stubs ✅ / real Stripe next
5. **Shop** — products, cart, checkout ✅
6. **Admin reports** — attendance & revenue (next)
7. **Polish** — SwiftData offline, chat, App Store

## Example: London Lords

In the app: create **London Lords CC** → **Add Wednesday nets** on the club screen → mark availability on Calendar → open the event to RSVP / pay / use squad picker for friendlies.

## Roles

`super_admin` · `club_admin` · `team_captain` · `member` · `guest`
