# Fishers

Multi-sport club management — organise recurring activities (cricket nets, football, badminton, paddle), mark availability, RSVP, pay fees, and order food/kit.

| Layer | Stack |
|-------|--------|
| iOS | SwiftUI, iOS 17+, MVVM, Keychain JWT |
| Web | Next.js dashboard (`web/`) |
| API | Rust, Axum, sqlx, JWT + argon2 · Swagger at `/swagger-ui` |
| DB | PostgreSQL 16 |

## Quick start

One command brings up the whole stack — Postgres, the API, the dashboard, and
the app in a Simulator — all pointed at this Mac's LAN address, so a phone on
the same Wi-Fi reaches the same API:

```bash
./scripts/start.sh                # everything
./scripts/start.sh --no-ios       # just the API and dashboard (a second or two)
./scripts/start.sh --seed         # …and demo@fishers.test / password123 to sign in with
```

Then open the dashboard at `http://<your-lan-ip>:7311/login` — the script prints
the address it found.

Services run detached, so re-running is safe and Ctrl-C during an Xcode build
does not take the API down with it:

```bash
./scripts/start.sh --status       # what is running, and where
./scripts/start.sh --logs api     # follow api | web | ios-build
./scripts/start.sh --restart      # replace whatever is running
./scripts/start.sh --stop         # stop the API and dashboard
./scripts/start.sh --stop --all   # …and Postgres
./scripts/start.sh --reset        # wipe the database and start clean
./scripts/start.sh --ios-only     # rebuild and relaunch just the app
```

Two things it deliberately does *not* do, because both used to cost an
afternoon:

- **It does not move to a free port.** 7311/7312/7313 are fixed (override them
  in `.env`). A drifting API port left the app, the dashboard and every share
  link pointing at nothing. If a port is held by something outside this project
  the script names the process and stops rather than killing it.
- **It does not bake an IP address into anything.** The LAN address is resolved
  from the default route on every run and handed to the app at launch, so a new
  DHCP lease costs a re-run instead of an edit to `AppConfig.swift`.

It also checks that the API can actually reach Postgres before saying it is up.
`/health` is a constant string, so an API whose database has gone away keeps
answering it while every real request hangs — `/health/ready` is what the script
waits on. The steps below are the manual equivalent.

### 1. Database

Postgres is mapped to host port **7313** (well clear of a local 5432/5433).

```bash
cp .env.example .env
docker compose up -d
```

If that is taken, set `POSTGRES_PORT` and the matching `DATABASE_URL` port in `.env`.

### 2. Backend

```bash
./scripts/run-api.sh
# or: cd backend && cargo run -p fishers-api
```

API: `http://127.0.0.1:7312` · Liveness: `GET /health` · Readiness: `GET /health/ready` (checks Postgres) · Swagger: `/swagger-ui` · Routes: `/api/v1/...`

Keep this process running while using the Simulator, a physical iPhone, or the web dashboard. Migrations run on startup.

**Device / LAN tip:** bind with `API_HOST=[::]` (dual-stack) and set `PUBLIC_WEB_BASE` and `CORS_ALLOWED_ORIGINS` to this Mac's LAN address — `./scripts/start.sh` does all three for you. If sign-in fails with a connection error, the API is not running or not reachable on the LAN.

Optional smoke test (signup → London Lords club → Wednesday nets, Saturday league, Sunday social):

```bash
chmod +x scripts/smoke.sh && ./scripts/smoke.sh
```

### 3. iOS

`./scripts/start.sh` generates the project, builds it, boots a Simulator and
launches the app already pointed at the API. `--device "iPhone 16 Pro"` picks a
specific one; otherwise it uses whichever Simulator is already booted, or the
newest iPhone installed.

To work in Xcode instead:

```bash
cd ios
xcodegen generate
open Fishers.xcodeproj
```

No server address is compiled into the app. `AppConfig` resolves it from
`FISHERS_API_URL` in the environment, then `FishersAPIBaseURL` in UserDefaults,
then Info.plist, and falls back to loopback — which is the right answer on the
Simulator, since it shares the Mac's network stack. `start.sh` writes today's
LAN address into the Simulator's defaults, so running from Xcode afterwards
still reaches the same API. For a physical iPhone, set `FISHERS_API_URL` to the
LAN address the script prints in the scheme's run arguments.

### 4. Web dashboard

```bash
cd web
npm install
npm run dev
```

Open `http://127.0.0.1:7311`, or this Mac's LAN address on the same port from
another device. The dashboard derives the API host from whatever address the
page was loaded on, so one dev server serves both without a rebuild;
`start.sh` writes the port into `web/.env.local`.

Signed-out pages show a sign-in prompt rather than data. `./scripts/seed-demo.sh`
creates `demo@fishers.test` / `password123` with a club, fixtures, shop stock and
a part-scored match, and prints a public live-scoreboard link. It is safe to
re-run — it reuses what already exists instead of duplicating it.

**CI / TestFlight:** see [docs/IOS_RELEASE.md](docs/IOS_RELEASE.md) — same Fastlane + Vault pattern as KubePilot.

- PR build + tests: `.github/workflows/ios.yml`
- **Auto TestFlight on merge to `main`** (when `ios/**` changes): `.github/workflows/ios_release.yml`
- Patch tags on `main`: `.github/workflows/auto-tag.yml`
- Manual TestFlight / App Store: same release workflow (`workflow_dispatch`)

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
web/              Next.js dashboard
scripts/
  start.sh        the whole stack: Postgres, API, dashboard, app in a Simulator
  run-api.sh      shorthand for start.sh --api-only
  seed-demo.sh    demo account with club, fixtures, shop and a live match
  smoke.sh        End-to-end API check
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
