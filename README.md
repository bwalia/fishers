# Fishers

Multi-sport club management app — clubs, teams, and friend groups organising recurring activities (cricket nets, football, badminton, paddle…). Members view club calendars, mark availability, get invited to sessions, RSVP, pay match fees, pre-order food/tea, and buy or hire kit through the club shop.

Reference scenario: **London Lords CC** — a cricket club running weekly nets and matches all summer.

## Repository layout

```
backend/   Rust API — Axum + sqlx + PostgreSQL (workspace of crates: api, domain, db, payments, notifications, jobs)
ios/       Native iOS app — SwiftUI, iOS 17+, MVVM (XcodeGen project)
docker-compose.yml   Local PostgreSQL for development
```

## Quick start

### Backend

```sh
docker compose up -d          # start PostgreSQL
cd backend
cp .env.example .env          # fill in secrets
cargo run -p fishers-api      # serves http://localhost:8080
```

See `backend/README.md` for migrations and configuration.

### iOS app

```sh
brew install xcodegen          # once
cd ios
xcodegen generate              # project.yml is the source of truth; the .xcodeproj is generated
open Fishers.xcodeproj         # build & run the Fishers scheme (iOS 17+ simulator)
```

Regenerate after adding or moving files — sources are globbed from `ios/Fishers`, so no project edits are needed.

The app ships with a **demo mode** (on by default) backed by a mock London Lords dataset, so it runs fully without the backend. See `ios/README.md` to point it at a live API.

First launch opens on **profile setup** (sports, level, division, per-sport stats, travel and logistics) — the app stays there until a sport has a stated level. Replay it any time from Profile → *Redo profile setup*.

## Core concepts

- **Availability vs RSVP** — general availability (available / unavailable / maybe per day) feeds suggested invites; RSVP to a specific event is the binding commitment. They are separate but linked.
- **Events** — one base model with an `event_subtype` (`nets`, `friendly`, `league_match`, `social`, `generic`) so cricket gets first-class treatment (lane auto-splitting for nets, squad selection and match results for games) without hardcoding cricket into the core.
- **Recurrence** — a shared recurrence engine materialises instances of recurring events ("every Wednesday 6–8pm, June–August") for the calendar, invites, payments, and ordering flows.
- **Add-ons per event** — fees, tea/food pre-orders, and kit hire are modelled generically (products + orders linked to events) so the same scaffolding works for any sport.

## Roles

Super Admin (platform), Club Admin/Organiser, Team Captain, Player/Member, Guest/Invitee.

## Build phases

1. Foundation — auth, profiles, clubs/teams, schema + migrations, API skeleton
2. Events & calendar — CRUD, recurrence, availability UI, RSVP
3. Invites & notifications
4. Payments (Stripe, fee splitting)
5. Shop/ordering
6. Admin tools & reporting
7. Polish — offline cache, chat, App Store prep
