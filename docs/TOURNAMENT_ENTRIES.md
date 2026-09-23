# Tournament entries and ticket sales

How a club is asked into a tournament and answers for itself, and how somebody
who is not a member of the hosting club buys a ticket.

## 1. The gap, precisely

The tournament engine was already complete and tested: snake-seeded groups, the
circle-method round robin, a seeded knockout, a timetable across pitches and
time slots that never puts a side in two places at once, standings and
qualifiers (`domain/src/tournament.rs`). The ticket API was complete too —
book, cancel, pay, mark paid, capacity held under `SELECT … FOR UPDATE`.

Four things were missing, and none of them were the hard part:

| Gap | Where it showed |
|---|---|
| No way to ask a **club** into a tournament | `InviteTarget` is `Club \| Team \| Event`, and every invite addresses a *person*. Entrants were free text an organiser typed; `tournament_entrants.club_id` and `contact_email` existed and nothing ever wrote them. |
| Tickets were members-only | `book_ticket` required membership of the hosting club. A tournament's spectators are, by definition, mostly not members of it. |
| Ticketing had no door | `ticket_price_cents`, `ticket_capacity` and `guests_allowed` were on the create and update requests, and **no screen on web or iOS set any of them**. A finished feature nothing could reach. |
| Stripe was a stub | `create_payment_intent` returned `pi_stub_…` and made no HTTP call. Webhook *verification* was real and good; there was nothing on the other end to fire it. |

## 2. The core idea

**An entrant row is the invitation.** Not an invitation table plus an entrant
table that have to be kept in step — one row, with a status:

```
invited ──► accepted ──► withdrawn
   │            ▲            │
   └─► declined ┴────────────┘
```

**Accepted is not the same as entered.** Where a tournament charges, a side is
in the draw once it has accepted *and* settled the entry fee. Until then the
place is held and nothing else: the fixtures are not built around it and the
table does not count it. That rule lives in SQL — in `tournament_standings` and
in `entrants_for_generation` — because the organiser's screen and the invited
club's screen must not each decide it for themselves.

It applies to a side the organiser typed in as well. The fee belongs to the
tournament, not to how the side was asked.

`EntryStatus::can_move` in `domain/src/tournament.rs` is the whole rule, and it
is the same rule on the server, on iOS and on Android. A side that never
answered cannot be recorded as having pulled out; a side already in the draw
cannot be quietly re-invited into limbo; a side that said no can be asked again,
because that conversation happens every season.

Two kinds of side end up in a draw and the difference decides who is scheduled:

- **Entered** — a name an organiser typed in. They are in straight away. The
  organiser is entering them, not asking them.
- **Invited** — a real club, which answers for itself. Not in the draw until it
  accepts, so `entrants_for_generation` filters to `accepted` and a fixture
  nobody agreed to play is never put in the diary.

`withdrawn` is kept as a **generated column** over `status`, so the standings
view, the API, both apps and the web UI all keep reading the column they
already read, and there is still exactly one source of truth.

## 3. Answering one

The invitation arrives as a notification and lands on
`/tournaments/invite/{entrantId}`, which is the whole conversation in one
screen: what the tournament is, who is running it, the rules the club would be
agreeing to, what it costs, and Accept or Decline. Where there is a fee, paying
it is the next thing on the same screen, and the place is not confirmed until
it clears.

Two bugs made that screen necessary rather than merely nice:

- The notification pointed at `/clubs/{id}?invites=1`, a page with nothing on
  it to answer an invitation with. It arrived and led nowhere.
- `GET /fixture-blocks/{id}` required membership of the **host** club, so the
  invited club could not read the rules it was being asked to agree to.
  `may_read_block` now allows a member of the host club *or* of any club it has
  asked in.

## 4. Reaching a club that is not on Fishers

Most opposition clubs are not. They get an email with an unguessable token; the
link opens `/entry/{token}`, which asks one question and takes one answer,
signed in to nothing. The same shape as a shared scoreboard: the link is the
credential.

The endpoint deliberately returns four fields — the tournament, the host, the
side's name and its status — and nothing else about the club running it. The
token is spent on the way through, so a second visit is a 404 rather than a
chance to change a draw that has already been built.

An invite-only club **cannot be found by searching**, by design
(`search_opponents` filters on visibility). Reaching one means scanning its code
or pasting its link, which is what the opposition picker already offers.

## 5. Selling a ticket to somebody who is not a member

`events.tickets_public`, off by default, so every event that exists today keeps
behaving exactly as it does. On, any signed-in Fishers user may buy.

Opening sales must not open the guest list. A non-member gets the headcount and
their own booking; members' names, their dietary notes and the club's takings
stay inside the club. That is enforced on the server — `list_tickets` filters
the rows before they leave — and the clients hide the panels rather than relying
on the filtering alone.

Truly public, logged-out ticket sales are **not** built. That needs guest
checkout and an anonymous buyer identity, which is a bigger step than this one.

## 6. What a tournament settles up front

`fixture_blocks` could say its format and its points, and nothing else. Not how
many sides fit, not when entries close, not how many overs, not what colour the
ball is, and not whether a side may borrow a player from another club.
Organisers kept all of it in the covering email, and argued about it on the day.

| | |
|---|---|
| **Entry** | `max_entrants`, `entry_deadline`, `entry_fee_cents`, `venue_id` |
| **Who may play** | `players_per_side`, `guest_players_allowed`, `age_group`, `gender` |
| **Playing conditions** | `conditions` — a whole `MatchConditions` |
| **Everything else** | `description`, `rules_notes` |

`guest_players_allowed = 0` is the usual rule and the one clubs argue about:
every player must be a member of the entering club.

**The conditions are not a new shape.** They are `MatchConditions` — the same
terms two captains agree before a one-off match, already in the domain, already
ported to Swift and Dart, already carrying ball, ground, powerplay and fielding
restrictions. A tournament sets them once, and `conditions_for_event` hands them
to every match started from one of its fixtures. A scorer who opens the app with
20 overs remembered gets the tournament's six, and nobody types the ball colour
twice.

A fixture that belongs to no tournament is untouched: its two captains agree
their own terms, exactly as before.

`TournamentSettings::problem()` answers in a sentence — "a side is between 2 and
15 players", "a bowler cannot be allowed more overs than the innings has" —
because the database's own constraints answer with `23514`.

### The entry limit is held under the same lock as the entry

`max_entrants` and `entry_deadline` are checked inside `invite_entrant`'s
`SELECT … FOR UPDATE` on the block, so two organisers filling the last place at
once cannot both succeed. Re-asking a side that declined or withdrew does not
count against the limit — they are a place that is about to come back, not a new
one.

The cap applies to the organiser too. Typing eleven names into an eight-side
tournament used to work while inviting a ninth club was refused, which made the
limit meaningless and the draw wrong. A batch that would not fit is refused
whole rather than entering some and dropping the rest: "only room for 1 more —
you gave 2".

## 7. Money

Cards work. `POST /tickets/{id}/pay` and `POST /entrants/{id}/pay-entry` open a
Stripe PaymentIntent; the browser confirms it with Stripe's `PaymentElement`,
and the webhook settles the ticket or the entry. Verified against real Stripe
in test mode, including a replayed `payment_intent.succeeded`, which changes
nothing.

Three things had to be true at once, and each failed differently:

| Missing | What happened |
|---|---|
| Secret key | Nothing is charged; a stub intent is issued and logged |
| Publishable key | The browser cannot draw a card form, so the button is hidden |
| Webhook secret | Money is taken and nothing is ever marked paid |

`GET /payments/config` reports whether all of it is in place, so a button that
cannot work is never drawn.

### The webhook is the only thing that says a payment happened

Nothing marks a ticket or an entry paid except a delivery to
`POST /api/v1/payments/webhook`. Not the browser coming back from Stripe, not
what `confirmCheckout` returned — those are hints, and a payer can close the
tab before either. The webhook is the record.

So it has to be reachable, per ring:

| | |
|---|---|
| Local | `stripe listen --forward-to localhost:7312/api/v1/payments/webhook` |
| int / test / acc / prod | An endpoint in the Stripe dashboard at `https://<ring>.fishers.cloud/api/v1/payments/webhook`, and its signing secret in `kv/fishers/<ring>/config` as `STRIPE_WEBHOOK_SECRET` |

Events worth sending: `checkout.session.completed`,
`checkout.session.async_payment_succeeded`, `checkout.session.expired`,
`payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.succeeded`
and `charge.refunded`. Anything else is acknowledged and ignored.

**Without the webhook secret, the endpoint refuses every delivery** — on
purpose. An unsigned webhook is how somebody marks their own ticket paid.

### What is recorded

Settlement comes off the session or the intent; the detail comes off the
charge, which is a different event and can arrive first. So they are written
separately, and `COALESCE` throughout means whichever lands second does not
wipe what the first already knew.

```
payments
  status, settled_at          did the money arrive, and when
  receipt_url                 Stripe's own receipt, to forward
  payer_email                 who paid — often not the account holder
  card_brand, card_last4      enough to match a bank statement
  failure_reason              Stripe's words for a refusal
  stripe_payment_intent_id    the cross-reference into Stripe's dashboard
```

### Coming back from Stripe

`success_url` is built from the origin the payer is actually on, sent by the
client and **checked against the origins this deployment serves**. Two reasons,
and both have bitten:

- `localStorage` is per origin. Somebody signed in at `localhost:7311` and
  returned to `192.168.1.70:7311` arrives with no session — a login page, and a
  payment they cannot see.
- An unvalidated return URL is an open redirect, and this one is handed to
  Stripe, who will send a paying customer to it.

One trap worth recording: `next.config.js` sent
`Permissions-Policy: payment=()`. An empty allowlist disables the capability for
the document *and everything it embeds*, so Stripe's form sat on its loading
skeleton for ever and logged only a console warning. It is now delegated
narrowly — `payment=(self "https://js.stripe.com")`.


`create_payment_intent` now calls Stripe when `STRIPE_SECRET_KEY` is set, and
falls back to the stub when it is not — which is how local development and CI
run, and the only reason the stub still exists.

Two bugs were fixed on the way through, both of which would have cost real money:

- **The client secret was stored as the intent id.** `pi_x_secret_y` is not
  `pi_x`, so a webhook naming only the intent could never find its payment. The
  metadata path happened to work, which is why nothing had noticed.
- **Nothing was idempotent.** Tapping Pay twice opened two payments; Stripe
  retries a webhook until it gets a 2xx, and a retried
  `payment_intent.succeeded` settled the same ticket again. Now the payment id
  is the Stripe idempotency key, a pending payment is reused while the amount
  still matches, and `payment_webhook_events` claims each delivery by primary
  key — so the second delivery loses the race in the database rather than in
  application code.

**The platform account is the merchant of record.** Money lands in the Fishers
Stripe account, not the club's. That is a commercial and regulatory decision, not
a technical one, and it is the same question `docs/VENUE_HIRE.md` §10 asks.
Paying it on to clubs is Stripe Connect: `destination` / `on_behalf_of` on the
intent, a `connected_account_id` on the club, an application fee, and an FCA
position worth confirming. The call is deliberately one function so that change
lands in one place.

## 8. Schema

Migration `20260922000001_tournament_entries_and_ticket_sales.sql`.

```
fixture_blocks
  + description, venue_id
  + max_entrants, entry_deadline, entry_fee_cents
  + players_per_side, guest_players_allowed, age_group, gender
  + conditions JSONB     a MatchConditions, inherited by every fixture
  + rules_notes

tournament_entrants
  + status           invited | accepted | declined | withdrawn
  + invited_by       who asked
  + responded_at     when they answered
  + invite_token     the emailed link, spent on use
  + entry_paid_at    when the entry fee settled — until then, not in the draw
  + entry_payment_method   card | cash | transfer | cheque
  ~ withdrawn        now GENERATED ALWAYS AS (status = 'withdrawn')

payments
  + entrant_id     so one payment shape serves a ticket, an order and an entry

events
  + tickets_public  default false

payment_webhook_events
    event_id PRIMARY KEY, payment_id, kind, processed_at
```

`UNIQUE (block_id, name)` is gone. It meant two clubs called "Wanderers" could
not both enter, and the `ON CONFLICT` that relied on it silently overwrote the
first. In its place: a club enters once (`block_id, club_id`), and free-text
sides stay unique by name among themselves, case-insensitively.

## 9. Permissions

No new permissions. Asking a side in, and answering for a club, are both
`ManageEvents` — held by a secretary or a captain, which is who does this. The
invited club's own officers answer; the host may answer only for a side that has
no club of its own, because otherwise nobody could and an emailed invitation
would strand the entry.

## 10. What this deliberately does not do

- **Refunding an entry fee.** A side that withdraws after paying keeps its
  `entry_paid_at`; getting the money back is a conversation with the organiser,
  not a button.
- **Enforcing the squad rules.** `players_per_side` and `guest_players_allowed`
  are published and read; selection does not yet refuse an XI that breaks them.
  That belongs with the selection board, not here.
- **Logged-out ticket sales.** See §5.
- **Stripe Connect.** See §7 — a commercial decision first.
- **A tournament screen on Android.** The models and API calls are ported and
  tested; the screens are not. See `flutter/PARITY.md`.
- **Overriding a fixture's `batting` side.** Unrelated, and still true: see the
  note in `domain/src/cricket/engine.rs`.

## 11. Known rough edges

- `tournament_standings.conceded` sums *all* opponents' scores per event.
  Correct for a two-side match, wrong for the `side = 'entrant'` americano
  format the schema already allows. Pre-existing; not reached by anything yet.
- The organiser's invite panel does not know the host club's id, so "you are
  running this one" is caught by the server rather than by the form. The error
  is clear; the form could be clearer.
- **A club set to "invite only" cannot be found by searching**, by design
  (`search_opponents` filters on visibility, and the club-creation form says so:
  "Kept out of search"). Since that is also the *default* for a new club, the
  first thing most organisers see is a search that finds nothing. The picker now
  says why and points at the club code; whether the default should change is a
  product decision, not a bug.
