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
docker compose up -d
cp .env.example .env
```

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

1. **Foundation** — auth, profiles, clubs/teams, schema ✅
2. **Events & calendar** — CRUD, recurrence, availability, RSVP ✅
3. **Invites & push** — invite links, APNs stubs ✅ / wire APNs next
4. **Payments** — Stripe intent stubs ✅ / real Stripe next
5. **Shop** — products, cart, checkout ✅
6. **Admin reports** — attendance & revenue (next)
7. **Polish** — SwiftData offline, chat, App Store

## Example: London Lords

In the app: create **London Lords CC** → **Add Wednesday nets** on the club screen → mark availability on Calendar → open the event to RSVP / pay / use squad picker for friendlies.

## Roles

`super_admin` · **club secretary** (`club_admin`) · **team captain** · `member` · `guest`

Only a **captain or club secretary** can invite players to a fixture. See [docs/RBAC.md](docs/RBAC.md).
