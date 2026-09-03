# Fishers API contract (v1)

The contract shared by the Rust backend (`backend/`) and the iOS client (`ios/`). Both sides are written against this document.

## Conventions

- Base path: `/api/v1` (default dev host `http://localhost:8080`)
- JSON, `snake_case` field names
- IDs: UUID v4 strings
- Timestamps: ISO-8601 UTC (`2026-06-03T18:00:00Z`); availability dates are plain `YYYY-MM-DD`
- Money: integer minor units (pence) + `currency` (default `"GBP"`)
- Auth: `Authorization: Bearer <access JWT>` on all routes except signup/login/refresh, `/health`, and the Stripe webhook
- Tokens: short-lived access JWT (~15 min) + refresh JWT (~30 days); client auto-refreshes on 401

## Auth

| Method | Path | Body → Response |
|---|---|---|
| POST | `/auth/signup` | `{name, email, password}` → `{user, access_token, refresh_token}` |
| POST | `/auth/login` | `{email, password}` → `{user, access_token, refresh_token}` |
| POST | `/auth/refresh` | `{refresh_token}` → `{access_token, refresh_token}` |

## Profile

Setting up the profile is the first stage of the app: after signup the client
keeps the user in setup until `skill_level` is set on their primary sport.

| Method | Path | Body → Response |
|---|---|---|
| GET | `/users/me` | → `user` (including server-computed `reliability`) |
| PATCH | `/users/me` | full profile the client holds → updated `user` |

`user`:

```jsonc
{
  "id": "…", "name": "Bal Walia", "email": "bal@example.com",
  "phone": "+44 7700 900123", "avatar_url": null,
  "emergency_contact": "Sam Walia · +44 7700 900456",
  "primary_sport": "cricket",              // key of one of sport_profiles
  "sports": ["cricket", "badminton"],      // mirrors sport_profiles[].sport
  "position": "All-rounder",               // primary sport, flattened for lists
  "skill_level": "Club standard",          // primary sport, flattened for lists
  "sport_profiles": [ /* see below */ ],
  "location": { /* see below */ },
  "reliability": { /* read-only, see below */ }
}
```

`sport_profiles[]` — one per sport the player picked at setup:

```jsonc
{
  "sport": "cricket",                      // cricket | football | badminton | padel |
                                           // tennis | hockey | netball | rugby | basketball
  "position": "All-rounder",
  "skill_level": "Club standard",          // Beginner … Improver … Intermediate …
                                           // Club standard … Advanced … Elite
  "current_division": "division3",         // social | development | division5 … division1 |
                                           // premier | county
  "target_division": "division1",          // what "levelling up" means for this player
  "age_group": "senior",                   // u11 | u13 | u15 | u17 | senior | vets40 | vets50
  "team_name": "Lords 1st XI",
  "years_playing": 12,
  "stats": [                               // key/value pairs, not an object: the client's
    {"key": "batting_style", "value": "Right-hand"},  // snake_case JSON coder would rewrite
    {"key": "batting_average", "value": "27.4"}       // object keys in transit
  ]
}
```

Stat keys are per sport and open-ended; the iOS catalog lives in
`ios/Fishers/Core/Models/SportStats.swift` (cricket batting/bowling averages,
padel level and side, badminton discipline and ladder position, football goals
and assists, rugby tries and appearances, and so on).

`location` — travel and logistics, used for lift-sharing on away fixtures:

```jsonc
{
  "area": "Kentish Town", "postcode": "NW5",
  "travel_radius_miles": 15,
  "transport": "driverWithSeats",          // driverWithSeats | driver | publicTransport | needsLift
  "spare_seats": 3,
  "preferred_days": [4, 7],                // Calendar weekday numbers, 1 = Sunday
  "notes": "Can do away games if we leave after 12 on Saturdays."
}
```

`reliability` — **read-only**, computed by the backend from past invites,
attendance and payments (`fishers_domain::reliability`, mirrored in the iOS
client so demo mode matches). Weighting: turning up 50%, answering invites 25%,
paying fees 25%, minus 5 per late drop-out. Under three past invites the band
is `unproven`.

```jsonc
{
  "score": 88,                             // 0–100
  "attendance_rate": 0.93, "response_rate": 0.94, "payment_rate": 0.92,
  "late_cancellations": 1, "sample_size": 18,
  "band": "rockSolid"                      // unproven | patchy | dependable | rockSolid
}
```

Teams carry the same grading so a fixture shows both sides' standard:
`team = {id, club_id, sport, name, division, age_group}`.

## Clubs, teams, members

| Method | Path | Notes |
|---|---|---|
| GET/POST | `/clubs` | list my clubs / create club |
| GET | `/clubs/{id}` | club detail |
| GET/POST | `/clubs/{id}/teams` | teams of a club |
| GET/POST | `/clubs/{id}/members` | roster / add member (admin) |

## Events & RSVP

| Method | Path | Notes |
|---|---|---|
| GET | `/events?club_id=&team_id=&from=&to=` | calendar feed |
| POST | `/events` | create (admin/captain); supports `recurrence_rule` |
| GET | `/events/{id}` | detail incl. nets fields when `event_subtype = nets` |
| POST | `/events/{id}/rsvp` | `{status: going \| not_going \| maybe}` |
| GET | `/events/{id}/attendees` | attendee list + headcount |

`event_subtype`: `nets | friendly | league_match | social | generic`. Recurrence rule is an RRULE subset: `FREQ=WEEKLY;INTERVAL=n;BYDAY=…;UNTIL=…`.

## Availability

| Method | Path | Notes |
|---|---|---|
| GET | `/availability?from=&to=` | my availability, date-ranged |
| POST | `/availability` | upsert `{date, status: available \| unavailable \| maybe, note?}` |

Availability is general free/busy signal; RSVP is the binding per-event commitment.

## Invites

| Method | Path | Notes |
|---|---|---|
| POST | `/invites` | invite user to club/team/event |
| GET | `/invites/mine` | my pending invites |
| POST | `/invites/{id}/respond` | accept / decline |

## Payments (Stripe)

| Method | Path | Notes |
|---|---|---|
| POST | `/payments/intent` | `{event_id}` → `{client_secret, …}` |
| POST | `/payments/webhook` | Stripe events, `Stripe-Signature` verified (HMAC-SHA256) |

## Shop & orders

| Method | Path | Notes |
|---|---|---|
| GET | `/products?club_id=` | club shop catalogue |
| POST | `/products` | create product (admin) |
| POST | `/orders` | cart checkout, optional `event_id` link (tea pre-order etc.) |
| GET | `/orders/mine` | order history |

## Notifications

| Method | Path | Notes |
|---|---|---|
| POST | `/notifications/register-device` | `{device_token, platform}` for APNs |

## Health

`GET /health` → `200 OK` (unauthenticated).
