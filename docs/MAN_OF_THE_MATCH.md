# Man of the match

The club votes. Not the scorer, and not the captain — the whole club, including
the people who spent the afternoon on the boundary with a better view of it
than anybody who was playing.

## What already existed

`MatchState::player_of_the_match` has been in the scoring engine since the
cricket work: a `player_of_the_match` scoring event, set from the Live Scorer
screen, replayed like every other ball. That is **the scorer's award** — one
person's opinion, given by whoever happened to be holding the book.

This is the other half, and the two are kept apart on purpose. The vote never
silently overwrites an award the scorer gave; it fills one in when they gave
none.

## The shape of it

When a cricket match reaches `Complete` for the first time:

1. A poll opens for the fixture, with **both team sheets** on the ballot.
   A man of the match is quite often the opposition's opening bowler.
2. A card is posted into the fixture's chat thread — its own if it has one,
   otherwise the club's most recently active thread.
3. Every active member of **both** clubs is notified: stored in the bell, and
   pushed to their phone or browser.

Voting is open for **48 hours**. One vote each, changeable until it closes —
voting again moves your vote rather than adding one, and voting for the person
you already chose takes it back.

When it closes, by a captain calling it early or by the sweeper finding its
time is up:

- The winner is announced in the same thread.
- They get the `motm` achievement on their profile.
- If the scorer never named anybody, the winner is written to the scorecard —
  through the scoring log, like any other change to a match, so it replays the
  same on every device and shows up in the scorer's trail.

## Decisions worth knowing about

**The tally is hidden until you vote.** A running total shown to somebody still
making their mind up is a nudge towards whoever is already ahead. `tally_visible`
says whether the counts in the response are real; before you have voted every
candidate reads zero and the ballot is sorted alphabetically, so the order gives
nothing away either.

**Anybody in either club votes; only players are on the ballot.** That asymmetry
is the feature. The eleven who played are not the eleven best placed to judge
who played best.

**A tie closes with no winner.** Choosing between two players who finished level
is a captain's job, not a tiebreak rule nobody voted for. The card names everyone
who tied and says so.

**A poll belongs to a fixture, not a match.** `motm_polls.event_id` is unique.
A match can reach `Complete` more than once — a scorer correcting the last ball,
a tie going to a super over — and each arrival calls the same code. The second
one tops up the ballot (a substitute who came on late) without reposting the
card, re-notifying two clubs, or splitting the vote across two polls.

**A poll past its closing time is closed**, whatever its status column says. The
sweeper runs every quarter of an hour, so there is always a window where the two
disagree; `MotmPoll::is_open` reads both, and every client does the same.

## API

| | |
|---|---|
| `GET /events/{id}/motm` | The fixture's vote, or 404 |
| `GET /motm/polls/{id}` | One vote, as the caller may see it |
| `POST /motm/polls/{id}/vote` | `{candidate_user_id}` — cast or move |
| `DELETE /motm/polls/{id}/vote` | Take it back |
| `POST /motm/polls/{id}/close` | Captain or secretary; ends it early |

The poll's own fields are flattened into the response beside `candidates`,
`my_vote`, `total_votes`, `tally_visible`, `can_vote` and
`scorer_award_user_id`.

## Where the code is

| | |
|---|---|
| Schema | `backend/db/migrations/20260921000001_man_of_the_match.sql` |
| Types | `backend/domain/src/motm.rs` |
| Queries | `backend/db/src/repos/motm.rs` |
| Opening, closing, announcing | `backend/api/src/services/motm.rs` |
| HTTP | `backend/api/src/routes/motm.rs` |
| Opened from | `backend/api/src/routes/cricket.rs` — `post_events`, on the transition to `Complete` |
| iOS | `ios/Fishers/Views/Chat/ManOfTheMatchCard.swift`, `ViewModels/MotmStore.swift` |
| Web | `web/src/components/ManOfTheMatch.tsx`, `lib/motm.ts` |

## Push to iPhones

Until this change the iOS half of `PushService::send` was a log line: the bell
filled up and no phone ever buzzed. It is now a real APNs client
(`backend/notifications/src/apns.rs`), token-based, signing a short ES256 JWT
from a `.p8` key. The app registers for remote notifications after sign-in —
not on first launch, because iOS shows the permission prompt once and spending
it on a stranger wastes it.

Configure with `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (or
`APNS_PRIVATE_KEY_PATH`), `APNS_BUNDLE_ID` and `APNS_ENVIRONMENT`; see
`.env.example`. Unconfigured is a normal state — the app's bell still works and
the phone simply stays quiet.

`APNS_ENVIRONMENT` must match the build. A Debug or TestFlight token is only
valid against the sandbox, an App Store one only against production, and
getting this the wrong way round is the usual reason a correct setup comes back
`BadDeviceToken`.
