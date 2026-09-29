# World cricket scores

Live scores from internationals and domestic competitions, on the web, iOS and
Android — separate from the club's own matches, which this app scores itself.

Source: [Highlightly Cricket API](https://highlightly.net/cricket-api/), free
plan.

## The constraint everything here is shaped by

**The free plan allows 100 requests a day for the whole deployment**, not per
user. So no request anybody makes ever reaches the provider:

- A background job (`backend/jobs/src/world_cricket.rs`) reads the feed a few
  times an hour and writes what it finds into Postgres.
- `GET /api/v1/cricket/world-scores` answers from those tables alone.

The number of people watching therefore has no effect on what we owe the
provider. It also means the scores are **minutes behind live play**, which every
screen says out loud rather than hiding.

## Why 100 a day is enough

| | |
|---|---|
| **One request covers every match being played.** | Asking the feed for a date returns every match *in progress on* that date, four-day Tests included — a Test that began on Monday comes back in Wednesday's answer. So a refresh of the whole world's cricket costs one request, not one per match. |
| **Finished cricket is never asked about twice.** | A past day whose matches have all ended is marked `settled` in `world_cricket_days` and skipped for good. |
| **The rate follows the audience.** | Fast while somebody is watching play, slower when nobody is, hourly overnight — and slower still as the day's allowance runs down, so it degrades instead of stopping dead at teatime. |

Reading the scores writes `watched_at`, throttled to once a minute; that is what
tells the poller somebody is there.

## The daily limit is enforced, not hoped for

`world_cricket::try_spend` claims an allowance **before** the call is made, in
one statement:

```sql
INSERT INTO world_cricket_budget (day, spent) VALUES (today, 1)
ON CONFLICT (day) DO UPDATE SET spent = world_cricket_budget.spent + 1
 WHERE world_cricket_budget.spent < $cap
RETURNING spent
```

No row back means the allowance is gone and the provider is not contacted.
Checking a count and *then* calling would leave a gap in the middle, and prod
runs more than one API pod — two of them reading "99 spent" at the same moment
would both spend the hundredth. Verified against Postgres: 20 concurrent
claimers with 5 requests left granted exactly 5, final spend exactly the cap.

A request that never reached the provider is refunded, so a bad half-hour of
networking does not eat the day's cricket. Every response also carries
`x-ratelimit-requests-remaining`; the poller writes that back and takes the
lower of the two figures, so anything else sharing the key is accounted for
too.

## Configuration

`CRICKET_FEED_KEY` is read from `kv/<brand>/<ring>/config` like every other
secret — the chart takes it via `envFrom`, so **no chart change is needed**.

| Variable | Default | Notes |
|---|---|---|
| `CRICKET_FEED_KEY` | unset | Unset = the feature is off and the clients hide it entirely. |
| `CRICKET_FEED_CAP` | `95` | Requests a day we will make. Under the plan's 100 so a miscount has room. Raise it with the plan and the refresh speeds up on its own. |
| `CRICKET_FEED_LIVE_SECS` | `180` | Seconds between refreshes while play is on and somebody is watching. The feed itself only updates once a minute, so below 60 buys nothing. |
| `CRICKET_FEED_URL` | `https://cricket.highlightly.net` | |

**Set the key on prod only.** int, test and acc share a deployment's worth of
allowance with nobody watching; a ring that nobody uses will otherwise spend
prod's. GullyCricket is a separate database and deployment, so it needs its own
signup and its own key — the two brands do not share an allowance.

## API

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/api/v1/cricket/world-scores` | JWT | `{ enabled, as_of, live[], upcoming[], recent[] }` |
| GET | `/api/v1/cricket/world-scores/{id}` | JWT | `{ summary, detail, detail_as_of }` — the scorecard |

`enabled` is false where no key is configured; clients hide the section rather
than showing an empty one. The three lists are split server-side so web, iOS and
Android cannot disagree about what counts as live — an interval is not an
ending, so a Test at `Tea` or `Stumps` is still in `live`.

Scores are **strings**, not numbers: a Test innings reads `"128 & 59/5"`.

## The scorecard page

Tapping a match opens its full card: who is at the crease, the batting and
bowling for every innings, extras and fall of wickets.

**This one costs a request per match**, where the list costs one for every match
being played anywhere. So it is guarded three ways, and all three are verified
against a live database rather than assumed:

| Guard | Effect |
|---|---|
| **A finished card is fetched once, ever.** | Stored `final`, and a finished match can never change. Five further views of a finished match cost nothing. Over a season this is most of the looking. |
| **Single flight.** | A Postgres advisory lock on the match id: ten people opening the same live match at the same moment spend one request between them, not ten. Measured — 10 concurrent first-views, `spent` went up by 1. |
| **It gives way to the list.** | Below `DETAIL_FLOOR` (30) requests left, scorecards stop being fetched at all. The list is what everybody sees; a card is what one person opened. |

A live card is refreshed at most every `LIVE_DETAIL_SECS` (180); a match that has
not started at most hourly.

### What the API decides, so three clients cannot disagree

- **The dismissal phrase.** `how_out` arrives written: `c Kotian b Mulani`,
  `c & b Mulani` (a catch by the bowler is never "c X b X"), `run out (Padikkal)`
  (no bowler is credited), `st Kushagra b Mulani`, `not out`, `did not bat`. An
  unrecognised word is passed through as itself — a card reading "retired hurt"
  is right, one silently reading "not out" is not. Some matches send
  `dismissalBowler: {}`, so the bowler is omitted rather than invented.
- **The innings total.** The feed sends none, but cricket's identity does: runs
  off the bat plus extras. Verified against a real match — 255 + 27 = 282, and
  the summary said `282/7`.
- **The crease lines.** `101 (153b, 7x4, 3x6)` and `1/19 (11.6 ov)`.
- **`did not bat` vs `not out`.** Different things, and the bottom of a card is
  where the difference shows.

Innings are **tabs**, not a stack: a Test has four, and two belong to each side,
so a tab is labelled `MWC 2nd` while the heading below says
`Maiwand Champions · 2nd innings`. The card then uses the full width — batting
on the left, bowling and fall of wickets beside it.

The page header reads its scores off the card when there is one. The summary
comes from the list poll and the card from this endpoint, so the two can be a
quarter of an hour apart; two different numbers for the same thing on one screen
reads as a bug.

## Tables

| Table | Holds |
|---|---|
| `world_cricket_matches` | One row per match, teams and league written in rather than referenced — the feed returns them attached, so normalising would save bytes and not one request. |
| `world_cricket_days` | What we have asked about, and whether it is `settled`. |
| `world_cricket_budget` | A row per UTC day: spend, the provider's own figure, and when anybody last looked. |
| `world_cricket_match_details` | One scorecard per match, as a single JSONB document of **our** types (parsed on the way in, so a change at the feed's end fails in the parser rather than leaking into a schema). `final` means never fetch again. |

Matches older than 45 days are pruned.

## Known gaps

- **No ball-by-ball, scorecards, or highlights.** The allowance does not stretch
  to them; the feed offers all three on a paid plan.
- **No favourite teams and no push on a wicket.** Push would need to know the
  moment a wicket falls, which is a different order of request volume.
- **Leagues are not filtered.** Every competition the feed covers is shown,
  which on a quiet day includes some obscure ones.
