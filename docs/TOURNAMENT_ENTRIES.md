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

## 3. Reaching a club that is not on Fishers

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

## 4. Selling a ticket to somebody who is not a member

`events.tickets_public`, off by default, so every event that exists today keeps
behaving exactly as it does. On, any signed-in Fishers user may buy.

Opening sales must not open the guest list. A non-member gets the headcount and
their own booking; members' names, their dietary notes and the club's takings
stay inside the club. That is enforced on the server — `list_tickets` filters
the rows before they leave — and the clients hide the panels rather than relying
on the filtering alone.

Truly public, logged-out ticket sales are **not** built. That needs guest
checkout and an anonymous buyer identity, which is a bigger step than this one.

## 5. Money

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

## 6. Schema

Migration `20260922000001_tournament_entries_and_ticket_sales.sql`.

```
tournament_entrants
  + status         invited | accepted | declined | withdrawn
  + invited_by     who asked
  + responded_at   when they answered
  + invite_token   the emailed link, spent on use
  ~ withdrawn      now GENERATED ALWAYS AS (status = 'withdrawn')

events
  + tickets_public  default false

payment_webhook_events
    event_id PRIMARY KEY, payment_id, kind, processed_at
```

`UNIQUE (block_id, name)` is gone. It meant two clubs called "Wanderers" could
not both enter, and the `ON CONFLICT` that relied on it silently overwrote the
first. In its place: a club enters once (`block_id, club_id`), and free-text
sides stay unique by name among themselves, case-insensitively.

## 7. Permissions

No new permissions. Asking a side in, and answering for a club, are both
`ManageEvents` — held by a secretary or a captain, which is who does this. The
invited club's own officers answer; the host may answer only for a side that has
no club of its own, because otherwise nobody could and an emailed invitation
would strand the entry.

## 8. What this deliberately does not do

- **Entry fees.** A tournament entry fee is a `Payment` against an entrant and
  reuses everything here. Not built, because nobody has asked for one.
- **Logged-out ticket sales.** See §4.
- **Stripe Connect.** See §5 — a commercial decision first.
- **A tournament screen on Android.** The models and API calls are ported and
  tested; the screens are not. See `flutter/PARITY.md`.
- **Overriding a fixture's `batting` side.** Unrelated, and still true: see the
  note in `domain/src/cricket/engine.rs`.

## 9. Known rough edges

- `tournament_standings.conceded` sums *all* opponents' scores per event.
  Correct for a two-side match, wrong for the `side = 'entrant'` americano
  format the schema already allows. Pre-existing; not reached by anything yet.
- The organiser's invite panel does not know the host club's id, so "you are
  running this one" is caught by the server rather than by the form. The error
  is clear; the form could be clearer.
