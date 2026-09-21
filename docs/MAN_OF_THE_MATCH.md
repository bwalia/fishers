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

Since the post-match awards work there is a third thing in the picture, and
the three form a precedence rather than a competition:

| | | |
|---|---|---|
| Scorer's pick | `player_of_the_match`, stored in the log | wins if it is set |
| The club's vote | this feature | fills the field when the scorer named nobody |
| The computed ranking | `MatchState::impact()` | shown when the field is still empty, captioned "Worked out from the card" |

So the club's vote replaces the app's suggestion on the scorecard rather than
sitting beside it, and a scorer who has already given the award keeps it.

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

**A result can change after the card goes up.** A tie sets the status with no
winner, and the super over that settles it is played *afterwards* — so the vote
opens, correctly, on a scoreline about to be overtaken. Deferring the vote until
a super over could not happen would be worse: a tie left as a tie is ordinary at
club level and would get no vote at all. Instead `motm_polls.result` holds the
scoreline the card was posted with, and a later completion that differs posts one
note to the thread. The ballot is untouched — it was the same twenty-two players
either way — and nobody is pushed a second time.

The comparison is the write: `UPDATE … WHERE result IS DISTINCT FROM $2` means
only the replica whose update changed the row announces it, so two API pods
watching the same last ball land do not both post.

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
| Schema | `backend/db/migrations/20260921000001_man_of_the_match.sql`, `…000002_motm_result_line.sql` |
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

### Getting a key

Only a person with the Apple Developer account can do this, and the `.p8`
downloads exactly once — Apple keeps no copy.

1. developer.apple.com → Certificates, Identifiers & Profiles → **Keys** → **+**
2. Name it (`Fishers APNs`), tick **Apple Push Notifications service (APNs)**,
   Continue → Register
3. **Download** the `.p8`. Note the **Key ID** on that page.
4. The **Team ID** is the ten characters top-right of the portal, and is
   already in `ios/project.yml` as `DEVELOPMENT_TEAM`.

It is one key per team, not per app — if one already exists under Keys with
APNs enabled, use that rather than making a second.

### Configuring it

```
APNS_KEY_ID=ABC123DEFG
APNS_TEAM_ID=PAS2QUVJHC
APNS_BUNDLE_ID=com.fishers.app
APNS_PRIVATE_KEY_PATH=.dev/AuthKey_ABC123DEFG.p8   # or APNS_PRIVATE_KEY=<the PEM>
APNS_ENVIRONMENT=sandbox                           # production for App Store builds
```

`.dev/` is gitignored, which is where a local key belongs. In the cluster the
same names go into Vault at `kv/fishers/<ring>/config` — the ExternalSecret
uses `dataFrom.extract`, so a key added there reaches the API on the next
deploy with no chart change.

`APNS_PRIVATE_KEY` takes the key in whatever shape the store hands back:

- the PEM itself, as `cat AuthKey_XXX.p8` prints it;
- the PEM with literal `\n`, because a `.env` file cannot hold a newline;
- **base64 of the whole file**, which is how this repo already keeps the App
  Store Connect key (`ASC_PRIVATE_KEY_B64`) — secret UIs mangle multi-line
  values, and `ios/ci/load-ios-vault-secrets.sh` has the scar tissue to prove
  it. `base64 -i AuthKey_XXX.p8 | pbcopy`.

Unconfigured is a normal state — the bell still fills up and the phone stays
quiet. The API says which at startup:

```
INFO fishers_notifications::apns: iOS push on bundle_id="com.fishers.app" host="https://api.sandbox.push.apple.com"
INFO fishers_notifications::apns: APNS_KEY_ID / APNS_TEAM_ID / APNS_PRIVATE_KEY not all set: iOS push is off
```

### Checking it

```bash
./scripts/apns-check.sh                  # the key, the ids, and an ES256 JWT
./scripts/apns-check.sh <device-token>   # …and send a real push to a phone
```

It talks to Apple rather than checking the file parses, and reads the refusal
back. The device token is the hex string the app registers; it is in
`device_tokens.device_token` for a signed-in account.

Three things go wrong, and all three look identical from the app — nothing
arrives:

| Apple says | What it actually means |
|---|---|
| `BadDeviceToken` | **Usually the environment, not the token.** A Debug or TestFlight build's token is only valid against the sandbox; an App Store build's only against production. |
| `InvalidProviderToken` | The credentials, not the device. Key ID and Team ID are both ten characters — check they are not swapped, and that the key has APNs enabled. |
| `DeviceTokenNotForTopic` | The token belongs to a different app than `APNS_BUNDLE_ID`. |

A credential failure never deletes anybody's token: only `410 Gone`,
`BadDeviceToken` and `Unregistered` retire a row. A misconfigured key must not
quietly unsubscribe a whole club.
