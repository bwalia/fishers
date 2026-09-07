# Cricket scoring (offline-first)

Ball-by-ball match scoring for cricket fixtures. The scoring device is the live
source of truth; the API stores an append-only event log and rebuilds the
scorecard by replaying it with the Rust engine.

## Principles

- **No “Save Score” button** — every ball is appended locally and applied by the
  on-device engine. The status chip is the only feedback: `Saved` / `Syncing…` /
  `Offline — saved on this phone`.
- **The log is the record.** Both engines are a fold over it, so replaying the
  same events on the phone and on the API gives the same scorecard.
- **Undo is a compensating event** (`undo_last`), never a silent delete. The API
  replays the stored log to rebuild the undo stack before applying a batch — a
  serialised snapshot cannot undo a ball it never applied.
- **One active scorer** per match (`claim-scorer` lock). Others can open the
  scorecard read-only. A lock idle for 15 minutes, or a `force` claim, can be
  taken over — phones die mid-innings.
- **Names travel with the events.** `xi_selected` carries `{id, name}` per
  player, so the scorecard reads as names on every device, not just the scorer's.

## Who you are playing, and the QR code

Every club and every team has its own QR code (**Clubs → the club → ⋯ → QR
code**). At the toss, one captain shows it and the other scans it from the match
setup screen — no typing, no spelling arguments.

The token is the whole secret, so it can be shown to a side you have never
played. Scanning it returns **only a name**: no roster, no fixtures, no contact
details. A code that has been shared too widely can be retired, which kills the
old one immediately.

Failing that, search by name, or just type one — a scratch side that has never
heard of Fishers is only a name, and that is fine.

## Before a ball is bowled

The two captains settle the terms, and the app makes them say so:

| Setting | Options |
|---|---|
| Overs | 5–50 (presets for the usual formats) |
| Overs per bowler | Defaults to a fifth of the innings, rounded up — 4 for a 20, 10 for a 50. Set to none for a social game. |
| Powerplay | Defaults to what the format usually plays — 6 overs of a 20, 10 of a 50. The scorer sees a banner with the overs left. |
| Fielding restrictions | 2 outside the circle during the powerplay, 5 after it. Two behind square on the leg side throughout, which is not adjustable. |
| Over rate | Overs an hour the side is expected to bowl. 0 means nobody is counting. |
| Ground | Open · Boxed / caged · Indoor |
| Ball | Red · White · Pink · Tennis · Tape |

One captain proposes (`conditions_proposed` — proposing counts as agreeing), the
other accepts (`conditions_agreed`), each recorded against a **name**, because
the away captain rarely has an account and this is a conversation that happens at
the toss. **The toss is refused until both have agreed.** Change anything
afterwards and both agreements are cleared, so nothing gets altered quietly.

The agreed terms appear on the scorecard.

**Umpires and scorers are named at the same time.** An umpire who is a Fishers
member is granted scoring rights on that match, so the square-leg umpire can
pick up the book without holding any club office.

## One book, one pair of hands

While someone is scoring, **nobody else can alter the match**. There is no idle
takeover: the lock moves when the scorer hands it over
(`POST /cricket/matches/{id}/handover`), and only they can do that. Anything not
yet synced goes up before the book moves, so nothing is stranded on the old
phone.

If the phone is genuinely gone, a captain or secretary can take it — `force` on
the claim, which needs `manage_events`. Either way it is written to
`cricket_scorer_handovers` and shown in the app, so there is never a question
about who was scoring when.

## Who can score

Permission `score_match` (`Permission::ScoreMatch`):

- Club secretary (`club_admin`)
- Team captain / vice captain
- Super admin
- Users listed on `cricket_match_officials` for that match (`role = scorer`) —
  a club's regular scorer needn't hold a club office

`GET` on a match returns `can_score` so the app can show the right button
without guessing at the role.

## API (`/api/v1`)

| Method | Path | Notes |
|--------|------|--------|
| `POST` | `/events/{id}/cricket-match` | Create/link. Body may carry `match_id` — see offline start |
| `GET` | `/events/{id}/cricket-match` | Fetch by fixture |
| `POST` | `/cricket/matches/{id}/claim-scorer` | Body: `{ "device_id": "…", "force": false }` |
| `POST` | `/cricket/matches/{id}/events` | Batch sync; idempotent on `client_event_id`, one transaction |
| `GET` | `/cricket/matches/{id}/events?after_seq=` | Pull log |
| `GET` | `/cricket/matches/{id}` | Match + `state` + `last_seq` + `can_score` |
| `GET` | `/cricket/matches/{id}/scorecard` | Projection (`MatchState`) |
| `POST` | `/cricket/matches/{id}/officials` | Assign scorer (needs `manage_events`) |

Event payload shape matches domain `ScoringEvent` / `ScoringEventKind`
(internally tagged `type`). A rejected batch returns **409** with the reason —
usually a sequence gap or another device holding the lock.

## Starting a match with no signal

The device mints the match id before the API is involved:

1. `CricketMatchStore.openLocal` creates the local match and its log.
2. Scoring proceeds against SwiftData only.
3. When there is a network, `CricketSyncService` calls
   `POST /events/{id}/cricket-match` **with that `match_id`**, claims the scorer
   lock, then flushes the pending events.
4. If the fixture already had a match on the server, the device adopts the
   server's id and carries on.

## What the engine handles

- Runs 0–6, boundaries counted separately for the card
- **Extras plus whatever the ball then did.** A wide is one run *and* whatever
  the batters run off it, so a wide they took a single off is 2 (both wides) and
  a wide to the rope is 5. A no ball is one run plus either runs off the bat
  (the batter's, and only the no ball is an extra) or byes (extras, and the
  bowler is charged only for the no ball). Byes, leg byes and penalties too.
- **Wagon wheel on every scoring shot.** The scorer taps the field to say where
  it went and picks the shot — drive, cut, pull, sweep, glance, loft… The shot
  rides on the same event as the ball, so an undo takes both away. The field
  mirrors for a left-hander, so "driven through cover" is right for both.
- **Ball-by-ball commentary**, generated from the log rather than typed:
  `13.4  Cook to Patel, FOUR — driven through cover`
- **Duckworth–Lewis–Stern par**, from the first ball of the second innings, so a
  match abandoned in the chase always has a result
- Wickets: bowled, caught, LBW, run out, stumped, hit wicket, retired out, other
  - the bowler is credited only where the laws credit them
  - a run out can take the batter at **either** end, with runs completed first
  - the batters cross on an odd number of completed runs
- Strike rotation on odd runs and at the end of an over; maidens
- **The bowling Laws**: nobody bowls two overs in a row, and nobody exceeds the
  allocation the captains agreed. The bowler sheet shows overs left per bowler
  and separates who *can* bowl this over from who cannot, with the reason.
- **Free hits.** A no ball sets one, the next legal delivery spends it, and
  while it stands only a run out can get the batter — the scorer sees a banner
  and the other dismissals disappear from the sheet.
- **Retired hurt** costs a batter but not a wicket: no fall of wicket, and they
  can be named to come back later in the innings.
- **Dismissals on a delivery already booked as an extra** — stumped off a wide,
  run out off a no ball — do not count the ball twice, but the bowler still gets
  the wicket.
- **Player of the match**, once the game is over.
- **Penalty runs** with a reason — a slow over rate, the ball hitting a helmet,
  a fielding infringement — awarded to **either side**, against nobody's bowling
  figures. Runs given to a side that has not batted yet wait and open their
  innings, because five runs are five runs whether or not anyone has faced a
  ball for them.
- **Correcting an earlier ball.** Scorers get it wrong three balls back, not
  just on the last one. Pick the ball from the recent list and the innings winds
  back to it — recorded as undo events, so the log stays append-only.
- Fall of wickets with the partnership that just ended, and the unbroken stand
- All out at `team size − 1`, so an eight-a-side game ends at seven down
- Innings closing on overs, on wickets, or on a declaration (`innings_completed`)
- Result: won by runs, won by wickets with balls remaining, or tied

## What a finished match writes back

Completing a match is the moment cricket joins the rest of the app. It runs once
— the first caller claims `stats_recorded_at` inside the transaction, so a
resync or a replayed batch cannot count a hundred twice:

1. **Attendance.** Everyone on either team sheet who is a Fishers member is
   marked `attended`. This is the half of the reliability score that drives
   squad selection, and nothing used to set it.
2. **Season stats.** Batting, bowling, catches and stumpings are folded into
   `player_season_stats` under `source = 'fishers_scoring'`, so scoring never
   fights a Play-Cricket import or a manual entry — `source` is part of the
   unique key.
3. **The tournament table.** If the fixture belongs to a block, the result and
   points land on `event_entrants`. Nobody has to type the score in twice.
4. The fixture flips to `completed` and the scorecard is stored on
   `match_results`.

Not modelled: individual fielding positions — the app counts fielders in the two
places the Laws restrict, it does not know where any one of them is standing.
Nor does it call anything: a field that breaks the restriction is a no ball, and
a slow over rate may be a penalty, but both are the umpire's call and the app
only records what follows.

## The field, and the clock

Two things the app can measure and an umpire has to act on. It does neither for
you — it tells you where you stand.

**The field.** The scorer records the two counts the Laws actually restrict —
fielders outside the circle, and fielders behind square on the leg side — and
the app says when the field breaks them, on the setting sheet and as a banner on
the LIVE screen. It does **not** call a no ball: the umpire does that, and the
scorer records it. Nothing tracks individual fielding positions.

**The clock.** Every event the app writes is stamped, and the server keeps the
stamp when it replays, so the over rate survives a sync. When an over rate is
agreed, the LIVE screen shows overs an hour and how far ahead or behind the
clock the side is. Deciding whether that costs anyone five runs is the umpire's,
and the penalty is then recorded like any other.

## Super overs

A tied match offers one, and the scorer starts it from the LIVE screen: one over
a side, two wickets, and the side that batted second in the match bats first.
Tie the super over and it offers another, counting them as it goes. The margin
reads *"Hemel won the super over by 4 runs"*.

## Rain, and DLS

`overs_revised` records a weather reduction against one innings — the scorer
reaches it from **⋯ → Overs reduced (rain)**. Every derived number moves with
it: balls remaining, the required rate, when the innings closes, and the DLS
par score.

Par is shown from the first ball of the chase, on the device and in the API:

```
par at any point  = S₁ × (resources team 2 has used) ÷ (resources team 1 had)
target, R₂ ≤ R₁   = S₁ × R₂ ÷ R₁, floored, + 1
target, R₂ > R₁   = S₁ + G50 × (R₂ − R₁) ÷ 100, floored, + 1
```

That arithmetic is exact. The **resource table is an approximation**: the ICC's
Standard Edition table is licensed and is not reproduced here, so what ships is
the published Duckworth–Lewis functional form with parameters fitted to it. It
reproduces the published zero-wicket column to within 0.1 of a percentage point
at every five-over mark, and every screen labels it *"DLS (Standard Edition
approximation)"*.

A league holding the official table can supply it as CSV — one
`overs,w0,w1,…,w9` row per line, overs ascending from 0 — and point
`DLS_RESOURCE_TABLE` at the file. The maths is unchanged and the label becomes
*"DLS (supplied resource table)"*. `DLS_G50` overrides G50 (245 by default).

## Engines

Identical rules, mirrored line for line:

1. Rust — `backend/domain/src/cricket/` (API replay + 19 unit tests)
2. Swift — `ios/Fishers/Cricket/CricketEngine.swift` (19 matching tests)

The test names match on both sides. If you change one engine, change the other
and its test.

## iOS

- `Fishers/Cricket/` — types, engine, SwiftData models, `CricketMatchStore`,
  `CricketSyncService`
- `Fishers/Views/Cricket/` — setup wizard, LIVE scorer, full scorecard
- Entry: **Start match** on a cricket `friendly` / `league_match` / `tournament`
  fixture in `EventDetailView`, when the API says `can_score`

Team sheets are picked from the club roster (whoever is on the fixture) plus
guests added by name, so the opposition needs no accounts. Batting order is the
order of the sheet — drag to change it.

## Manual smoke (offline LIVE)

1. Sign in as captain/secretary on a cricket fixture.
2. **Start match** → names and overs → toss → team sheets → openers → LIVE.
3. Enable airplane mode; score 0–6, a wide, a no ball with runs, a run out of
   the non-striker, and an undo. The chip reads `Offline — saved on this phone`.
4. Force-quit the app and reopen the fixture: it resumes exactly where it was.
5. Complete the innings and the chase; check the scorecard reads correctly.
6. Go back online; the chip returns to `Saved` and
   `GET /cricket/matches/{id}/scorecard` matches the device.
