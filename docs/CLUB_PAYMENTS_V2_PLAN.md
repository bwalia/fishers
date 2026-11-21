# Club payments, version 2: passes, subscriptions, group fees, and paying made very easy

> **Status: plan, not built.** Written 2026-11-21. It builds on phase 1
> ([PAY_BY_BANK_TRANSFER.md](PAY_BY_BANK_TRANSFER.md)), which is merged and running on the int
> servers but not yet in the stores or production. The questions to settle are in §9.

## 1. What we are fixing

Phase 1 does one thing: a session has a cost, it is split between whoever came, and each player
pays their share by bank transfer. Real clubs need more than that, and their players need it much
simpler.

1. **Not every player pays per session.** Some buy a nets pass or pay a monthly subscription, and
   then they owe nothing for the sessions it covers. Others pay as they go.
2. **Not every charge is a session.** Season membership, league registration, the tour, a kit
   order and the annual dinner are charged to a team or a group of people, not to one evening.
3. **Not everybody pays for themselves.** A parent pays for two juniors; one friend pays for the
   four who came together.
4. **Most players are not comfortable with technology.** Many get stuck signing in. Copying a
   sort code, an account number and a "reference" into a banking app, then coming back to tap
   "I've paid", is too much to ask.

The goal: **a player should be able to pay in under a minute, from a WhatsApp message, without
signing in, and without knowing what a "reference" is.** A secretary should set the club up once,
in a few minutes, and after that mostly tap "Received".

The principle from phase 1 stays: **the app never touches the money.** No Stripe, no cut.

---

## 2. Every way a club charges, and how the app handles it

| How a club charges | Example | In the app |
|---|---|---|
| **Pay as you go** | Nets £5 a session | Session price: what phase 1 does today |
| **Split the bill** | £60 lane hire between whoever came | Session price, split. Phase 1 does this. |
| **Match fee** | £8 a game, teas included | Session price on matches |
| **Nets pass, unlimited** | Winter nets, January to March, £60 | Pass: one payment, covers nets until a date |
| **Nets pass, bundle** | 10 sessions for £40 | Pass: one payment, covers 10 sessions |
| **Monthly subscription** | £20 a month, nets whenever you like | Pass, paid monthly by **standing order** |
| **Season membership** | £120 a season, can be paid in 3 parts | Pass: membership, optionally in instalments |
| **Membership that includes nets or matches** | £150 includes all nets | Pass that covers several kinds of session |
| **Group fee** | League registration £300 for the 1st XI; tour £200 each; kit order | Collection: a charge to a team or a chosen list, split or a fixed amount each |
| **Different prices for different people** | Juniors £3, students £4, adults £5, guests £7 | Price types on a session or pass |
| **Free for some** | Coaches, captains, a trialist's first session | Free price types; first session free |
| **Family or friends paying together** | A parent pays for two juniors | A payer for other people: one person sees and pays everyone's dues |
| **Cash at the ground** | Half the team pays cash | Secretary ticks who paid cash, at the ground |
| **One-offs** | Lost ball £5; dinner ticket £25 | A collection with one person in it |

**Everything ends up as the same thing:** a line saying who owes what for what. Phase 1's ledger
already matches payments to those lines oldest first, and turns overpayments and cancellations
into credit. Version 2 adds new ways to create those lines, plus a check, when a bill is made, of
whether a pass already covers a session.

---

## 3. Passes and subscriptions

### How a secretary sets one up

Choose a template, change the numbers, done:

| Template | Price | Covers |
|---|---|---|
| Winter nets pass | £60, once | All nets until 31 March |
| 10-session nets card | £40, once | The next 10 nets sessions |
| Monthly nets | £20 a month | All nets while it's active |
| Season membership | £120, or 3 × £40 | Membership. Optionally all nets, or all matches too. |
| Junior membership | £50 | Only open to members marked as juniors |

Each pass has:
- **What it covers:** nets, training, matches, or a mix; optionally only one team.
- **How long it lasts:** until a date, a number of sessions, or while it's active (monthly).
- **Who can have it:** anyone, or only one price type (juniors, for example).

### How a player gets one

There are two ways:
- **The secretary adds them.** This is usual for people who already paid in cash or at the AGM.
- **The player chooses "Get the nets pass"** on the club page.

Either way, the player then sees one of two things:
- **A one-off pass:** "Pay £60 once, and nets are covered until 31 March." Paying works exactly
  like a session.
- **A monthly pass:** "Set up a standing order in your banking app. It pays itself every month."
  The app shows exactly what to type in the banking app: who, the amount, "every month", the start
  date and what to write in the reference box. It also has a picture guide, and a **Send to
  someone who pays for me** button.

### How a pass changes bills

When a bill is made, each person is checked against their passes.
- **Covered:** they see "Friday nets: covered by your nets pass ✓". There's nothing to pay and
  nothing to tap.
- **Not covered:** they're billed as usual, at their price type.
- **Bundle passes** count down. When one session is left, the player is told: "1 nets session
  left on your card".
- **When a pass holder comes to a split-total session,** everyone's share is still worked out
  over everyone who came, so nobody pays more because others hold passes. The pass holders' part
  is covered by the club out of pass money (decision 1 in §9).

### Monthly passes without card payments

There is no Stripe, so nothing is taken from anyone automatically. The player's own **standing
order** does the paying. The app only keeps track:
- **Each month,** a charge appears for every monthly pass.
- **When the money arrives,** the treasurer sees "12 standing orders due this week" and taps
  **All arrived**. Later, the bank-statement import ticks them off by itself.
- **A late payment** gets a grace period (7 days suggested). The pass keeps covering sessions,
  and the player and secretary are told.
- **Two missed months suspends the pass.** Sessions are billed as pay-as-you-go until it's paid
  up. The secretary can override this.
- **Cancelling** ends the pass at the end of the paid month. The app reminds the player to cancel
  the standing order in their bank too.
- **A price change** applies from the next month. Everyone on the pass is told to update their
  standing order, with the new amount shown.
- **Joining part way through a month:** the months run from the day they joined, so there's no
  part-month maths.

---

## 4. Group fees and paying for others

### Collections: a charge not tied to a session

The secretary chooses **New collection** and picks:
- **Who:** a team (1st XI), everyone in the club, juniors only, or ticked names.
- **How much:** a total to split ("£300 league registration between the squad") or the same from
  each ("£25 dinner ticket").
- **A due date.**

Everyone in it sees "You owe £25: annual dinner, by 30 November", and pays the same way as for a
session. It covers league fees, tours, kit orders, fines and anything else.

### Paying for other people

- **Family:** a parent is linked as the payer for their juniors. Children often have no app
  account, so the secretary can add a junior by name only. The parent's "You owe" shows each child
  as its own line, with one total and one payment for all of it.
- **Friends:** at the pay screen, "I'm paying for others too" lets one person tick who else
  they're covering. Their one payment covers everyone ticked.
- **Guests** (no account): the secretary shares a pay link with them on WhatsApp, or ticks cash.

---

## 5. Making it very, very easy

This matters more than all the features above.

### 5.1 Pay from WhatsApp, without signing in

Players live in the club's WhatsApp group, not in our app. So:

- **Every bill gets a link.** After nets, the secretary taps **Share to WhatsApp** and the app
  writes the message:
  > 🏏 Friday nets — £5 each.
  > Tap to pay: gullycricket.app/p/7KQ3X
  > Covered by a pass: Ravi, Tom ✓
- **The link opens a simple web page.** No app, no sign-in, no password. The player taps their own
  name, sees their amount, copies the details, and taps **I've paid** or **I paid cash**. If the
  player is signed in on that phone, the page already knows who they are.
- **Reminders work the same way.** **Remind the group** writes "Still to pay for Friday nets:
  Josh, Imran. Tap to pay: …" for the secretary to post. This works today, even though Android push
  and email aren't set up yet.
- **The link has limits.** It lasts 30 days. It shows a name and amount, but never who has or
  hasn't paid beyond what the secretary chose to post. Anyone with the link can see the club's bank
  details, which is how clubs share them in WhatsApp today anyway (decision 3 in §9).

### 5.2 The pay screen, rewritten for someone who doesn't use banking apps much

One screen, top to bottom, plain words:

1. **"You owe £5 for Friday nets."** Big.
2. **"Pay Aman Gill, the club secretary."** The person's name and role, so they know who the money
   goes to. Underneath: "This is Aman's own bank account. The club uses it to collect money."
3. **Four big rows, each with a Copy button:** Name, Sort code, Account number, **What to write in
   the reference box:** "SHARMA". The reference becomes the player's surname, plus a number only
   where two players share a surname, not a code like "8VF52".
4. **"First time? Here's how"** opens a three-picture guide: open your banking app, add a new
   payee, paste. After the first time it says "Pay Aman as usual".
5. **Two big buttons:** **I've paid** and **I paid cash**.
6. **Optional:** attach a screenshot of the payment. People send these to the secretary on
   WhatsApp already; now it goes with the payment.
7. **Send these details to someone** (a son or daughter who does the banking).

Words we stop using: "claim", "share", "waived", "reference code", "allocation", "payout
account". We use "you owe", "paid", "waiting for Aman to check", "let off", "the club's bank
details".

For Indian clubs (rupees), the main thing on the pay screen is a **UPI QR code**. Any UPI app scans
it with the amount already filled in. That is simpler than any bank transfer, and free.

### 5.3 The secretary's side

- **A five-minute setup wizard** the first time:
  1. Where players send money: bank details or UPI, with a preview of exactly what players will
     see.
  2. What you charge: tick the templates and change the numbers.
  3. Who's on a pass: tick names.
- **After every session,** one card: "Send the bill for Friday nets to 8 people (2 covered by a
  pass)? **Send**". Then **Share to WhatsApp**.
- **Checking payments:** a list with **Received** on each, and **All arrived** for the lot. A
  screenshot, if attached, shows beside each one.
- **Cash at the ground:** a tick-list of who's paying today.
- **One overview:** "November: £320 collected · £45 still owed · 12 passes active", with who owes
  what underneath.

### 5.4 Signing in, the other reason people get stuck

This is outside payments, but it's the biggest obstacle for these players:
- **Sign in with your mobile number and a WhatsApp code.** The server can already send WhatsApp
  codes; it needs the WhatsApp Business account switched on.
- **Magic links:** an email or WhatsApp link that signs you in with one tap.
- **No sign-in at all for paying** (5.1).

---

## 6. What changes in the system (high level)

| Piece | New or changed |
|---|---|
| **Price types** | New: adult, junior, student, guest, free, as a club sets them. Each member has one. |
| **Session cost** | Changed: a price per price type, or a split total. Phase 1's two modes stay. |
| **Passes** | New: plan (name, price, once / monthly / instalments, what it covers, how long, who may have it) and each holder (since when, status, sessions left, who pays). |
| **Bills** | Changed: each attendee is priced at their price type, then checked for a covering pass. A covered line is kept at £0 with "covered by …", so the record is complete. |
| **Collections** | New: phase 1's bill without an event, for a team, a group or a list. |
| **Payers** | New: "Neha pays for Arjun and Kiran". A payment covers several people's lines. |
| **The ledger** | Unchanged: phase 1's oldest-first matching and credit. It already handles all of the above. |
| **Pay links** | New: a token per bill or collection, a public pay page on the web, and "I've paid" without signing in. |
| **The scheduler** | New: monthly pass charges, grace and suspension, "1 session left", and WhatsApp reminder text ready for the secretary to post. |
| **References** | Changed: readable (surname), unique within the club. |
| **UPI** | New: a payment method for rupee clubs, with a QR code. Phase 1 kept room for it. |

All of it extends what phase 1 built. Nothing built so far is thrown away.

---

## 7. What can go wrong, and what happens

| Situation | What happens |
|---|---|
| Pass holder comes to a match their pass doesn't cover | Billed the match fee as usual. "Your nets pass doesn't cover matches." |
| Bundle runs out mid-season | The next session is pay as you go. Told at 1 left and at 0. |
| Standing order stops (bank, or the player cancelled it) | Grace, then suspended after two missed months. The secretary sees "3 passes behind". |
| Standing order for the wrong amount | Part-paid: the rest is owed, or the extra becomes credit, as in phase 1. |
| Player joins a pass after already being billed this month | From the next bill. The secretary can re-split the bill to cover them now. |
| Secretary changes the pass price | New price from the next period. Holders are told to change their standing order. |
| Junior turns adult | The secretary changes the price type. Their pass runs to its end. |
| Parent stops paying for a junior | The link is removed. Dues move to the junior, or the secretary lets them off. |
| Someone taps another person's name on a pay link | It's only "says they've paid"; the treasurer still checks the bank. Every link tap is recorded. |
| Pay link forwarded outside the club | It shows the club's bank details and amounts, nothing more; it expires. The secretary can turn a link off. |
| Two people both pay for the same junior | The second becomes credit, or the treasurer refunds it. |
| Group fee where some people leave the team | The collection can be re-split, as a phase 1 bill can. |
| Club changes bank details while standing orders are running | Phase 1's 24-hour wait and warning, plus a message to every pass holder: "Update your standing order". |
| Session cancelled for rain | Pass holders: nothing changes, and bundles aren't counted down. Pay-as-you-go players: as in phase 1. |

---

## 8. Order of work

| Step | What | Why first |
|---|---|---|
| **A. Easy paying** | Pay links and the no-sign-in pay page, Share to WhatsApp and Remind the group, the rewritten pay screen with readable references and a first-time guide, I paid cash, All arrived, screenshots, the secretary setup wizard | Makes what's already built usable by the players we have, before adding more |
| **B. Passes** | Price types; passes (once, bundle, monthly by standing order, membership with instalments); covered sessions; the monthly scheduler, grace and suspension | What you asked for: subscribers don't pay per session |
| **C. Group fees and payers** | Collections; family and friends paying together; guests on pay links | League fees, tours and families |
| **D. Less admin** | Bank-statement import that ticks payments off; UPI QR for rupee clubs; payments into the club's books | Treasurers stop ticking by hand |
| **Separately** | Sign in with a WhatsApp code; Android push notifications | Unblocks players everywhere, not just for paying |

Each step ships to the int server, is tested on real phones as phase 1 was, then goes to the
stores.

---

## 9. Questions for you

| # | Question | My recommendation |
|---|---|---|
| 1 | When pass holders come to a split-total session, who pays their part of the bill? | **The club**, from pass money. Everyone else's share is the same as if the pass holders had paid, so nobody pays more because others hold passes. |
| 2 | Monthly pass not paid: how long before it stops covering sessions? | **7 days' grace; suspended after 2 missed months.** The secretary can override. |
| 3 | Pay links without sign-in: is it OK that anyone with the link sees the club's bank details? | **Yes.** Clubs already post them in WhatsApp groups. Links expire after 30 days and can be turned off. |
| 4 | References: the player's surname, or a code? | **Surname**, with a number only where two players share one. |
| 5 | By "group fee", do you mean a charge to a team or group (league fees, tour, kit), or a family or friends paying together? | **Both** are in this plan; tell me if you meant something else. |
| 6 | Should phase 1 go to the stores and production now, or wait for step A? | **Wait for step A.** The first version players see should be the easy one. |
| 7 | Should sign-in with a WhatsApp code be part of this work? | **Yes, alongside step A.** It needs the WhatsApp Business account set up, which you'll have to do. |

---

## 10. Step A: the contract the apps use (built)

The source of truth is `backend/api/src/routes/easy_paying.rs` and `club_payments.rs`.
Real responses are in `.dev/payments/examples/stepA_*.json` after
`python3 .dev/payments/seed_demo.py`. Errors are `{error, code}`: show `error`, and branch on
`code`.

### For whoever runs the session (`can_bill`)

| Call | Returns |
|---|---|
| `GET /events/{id}/bill/link` | The open link as below, or `null`. Never makes one: use it to show the share buttons when somebody opens the session. |
| `POST /events/{id}/bill/link` | `{url, expires_at, bill_message, reminder_message, still_to_pay: [name]}`. It reuses the open link, and makes one only when there isn't one: call it when somebody taps Share. `no_bill` (409) until the bill is sent. Links are `/pay/<token>`. |
| `POST /events/{id}/bill/link/disable` | `{disabled}`. Every open link for the bill closes. |
| `POST /events/{id}/bill/cash {share_ids}` | `{recorded, already_paid, total_cents, received}`. A money admin's tick counts as received; anyone else's waits for the treasurer. `already_paid` counts ticked people who owe nothing now: after a retry, the ones the first tap recorded. |

### For money admins

| Call | Returns |
|---|---|
| `POST /clubs/{id}/payments/confirm {ids}` | `{confirmed, already_confirmed, skipped}`, for the **All arrived** button. |
| `GET /payments/{pid}/screenshot` | Image bytes, when `has_screenshot` is true on the payment. |
| `PUT /clubs/{id}/payments/settings` | Also takes `default_nets: {mode, amount_cents} \| null` and `default_match_fee_cents: int \| null`. These are read back as `default_nets_mode`, `default_nets_cents` and `default_match_fee_cents` in `settings`. |

### For a player, signed in

- **`GET /clubs/{id}/payments/defaults`:** `{default_nets_mode, default_nets_cents,
  default_match_fee_cents, currency}` for any member, so a captain's schedule form starts from the
  usual price too.
- **`GET /clubs/{id}/pay`:** `account` gains `payee_role` (`secretary`, `treasurer`, `owner` or
  null), for "Pay Aman Gill, the club secretary". It's only set when the name on the account
  matches the person who added it: a treasurer adding the secretary's account gets null. `reference` is now readable, for example
  "SHARMA".
- **`POST /payments/{pid}/screenshot`:** raw image bytes (JPEG, PNG or WebP, at most 1 MB), for
  the payer's own claim. Shrink it on the phone first: at most 1600 px, JPEG quality 0.7.
- **Payments** gain `share_id`, `via_link` and `has_screenshot`.

### The pay link: public, no sign-in (send `Authorization` if signed in, to get `me`)

| Call | Returns |
|---|---|
| `GET /pay-links/{token}` | `{club_name, title, event_start_at, currency, expires_at, people: [{id, name}], me, account_state, account}` |
| `GET /pay-links/{token}/people/{share_id}` | The share, plus `owed_cents`, `reference` and `claim: {id, method, amount_cents, created_at, can_undo, has_screenshot} \| null` |
| `POST /pay-links/{token}/people/{share_id}/claim {method: transfer\|cash, note?}` + `Idempotency-Key` | The same person, now waiting. `nothing_owed` (409). |
| `DELETE /pay-links/{token}/claims/{pid}` | 204 when taken back. `too_late` or `already_decided` (409). |
| `POST /pay-links/{token}/claims/{pid}/screenshot` | Raw bytes as above. 204. `not_an_image` (415), `too_big` (400), `too_late` (409). |

Link errors: `bad_link` (404, "ask your secretary to share it again"), `link_closed` (410,
"ask for the latest one"), `slow_down` (429). `not_on_bill` (404) means one name has gone from a
re-split bill: go back to the names, not to the wrong-link page.

### Signing in with WhatsApp

| Call | Returns |
|---|---|
| `GET /auth/whatsapp` | `{enabled}`. Show the option only when it's true. |
| `POST /auth/whatsapp/start {phone}` | `{sent, expires_in, resend_after}`, always the same, so it never reveals whether a number has an account. Errors: `bad_phone`, `whatsapp_off` (503), `slow_down`, `not_sent` (502). |
| `POST /auth/whatsapp/verify {phone, code}` | The same tokens as `/auth/login`. `wrong_code` (400), `slow_down` (429). |

### What each app builds for step A

1. **Share to WhatsApp.**
   - **Where:** on a billed event's money section, for whoever can bill.
   - **Two buttons:** **Share the bill** (`bill_message`) and **Remind who hasn't paid**
     (`reminder_message`).
   - **Copy link.**
   - **Switch the link off,** tucked away and with a confirmation.
   - **How it shares:** through the phone's share sheet (WhatsApp first where possible) or
     `https://wa.me/?text=`.
2. **The pay screen, rewritten (§5.2).**
   1. "You owe £5 for Friday nets".
   2. "Pay Aman Gill, the club secretary", plus the own-account sentence when `is_personal`.
   3. Four big rows, each with Copy: name, sort code, account number, and "What to write in the
      reference box".
   4. **First time? Here's how:** three steps.
   5. **I've paid** (big) and **I paid cash**.
   6. After claiming: **Add a screenshot** (optional), and **Undo**.
   7. **Send these details to someone.**

   Words not to use: claim, share, waived, reference code, payout.
3. **For the treasurer:**
   - **All arrived** above the payments to check, with a confirmation ("Mark all 3 as arrived?");
   - a screenshot opens when there is one;
   - **Who paid cash?** on a billed event: tick, then save.
4. **Setup wizard,** shown to a money admin when the club has no bank details and no usual
   prices:
   1. bank details, with a preview of what players will see;
   2. usual nets price and match fee;
   3. done: "after each session, share the bill to WhatsApp".
5. **The schedule form starts from the usual price:** nets from `default_nets_*`, a match from
   `default_match_fee_cents`.
6. **WhatsApp sign-in** on the sign-in screen, when it's enabled: mobile number, then the
   six-digit code.
7. **Web only: `/pay/[token]`** (and `/p/[token]` for links made before it moved), the public pay page. No sign-in, mobile first, very large buttons.
   - Opens on: a list of names; when signed in, it opens on your own name.
   - Then: your amount and the bank details.
   - Then: **I've paid** or **I paid cash**, then waiting, with **Undo** and **Add a screenshot**.
   - Friendly pages for a closed or wrong link, and each `account_state`.

---

## 11. Steps B and C: the contract the apps use (built)

The source of truth is `backend/api/src/routes/passes.rs` (with the pricing in
`backend/db/src/repos/passes.rs`). Real responses are in `.dev/payments/examples/stepBC_*.json`.
Errors are `{error, code}` as before.

**Words.** "Pass", "group fee", "covered by your pass", "pays for". Never "subscription",
"collection", "holder", "dependent" or "price type" in front of a player. A secretary sees
"Prices for juniors, students…" rather than "price types".

### What changed in things the apps already read

- **A share can be `covered`:** a pass or a free price covers it. Show it like paid, with its
  `reason` ("Covered by Monthly nets", "Free: Coach"). It owes nothing and isn't counted.
- **Shares and bills carry `kind`:** `event` (a session), `pass` (a pass charge) or `collection`
  (a group fee). `event_id` is null for the last two; `due_on` is set on pass charges and on group
  fees given a date.
- **`GET /events/{id}/bill` gains `prices`:** `[{price_type_id, name, amount_cents}]`, the
  session's own prices by type. The bill preview's shares gain `covered` (the reason, or null).
- **`PUT /events/{id}/cost` takes `prices`:** `[{price_type_id, amount_cents}]` (per-player
  costs only: `prices_need_per_player`). Given, it replaces the session's prices; left out, they
  stay as they are. A price of 0 makes that type free for the session.
- **`GET /me/dues` `shares` include the 5 most recent covered lines** among the history, so a
  player sees "Tuesday nets: covered by your pass ✓".
- **`GET /me/dues` gains `people`:** `[{user_id, name, managed, club_id, dues}]`, where `dues`
  has the same shape as a club in `clubs`. Each is somebody you pay for. `managed` means they have
  no sign-in of their own.

### Prices for juniors, students, guests (money admins write; members read)

| Call | Returns |
|---|---|
| `GET /clubs/{id}/price-types` | `[{id, name, free, for_guests, sort_order, archived_at}]` |
| `POST /clubs/{id}/price-types {name, free?, for_guests?}` | The type. `name_taken` and `guest_type_taken` (409): one guest type per club. |
| `PATCH /price-types/{id} {name?, free?, for_guests?, archived?}` | The type. |
| `PUT /clubs/{id}/members/{user_id}/price-type {price_type_id \| null}` | 204. Null means the standard price. |

### Passes

| Call | Who | Returns |
|---|---|---|
| `GET /clubs/{id}/passes` | members | `[plan + {charge_cents, holders, mine}]`. `mine` is your own running pass on it, or null. `?all=true` includes archived ones (admins only). |
| `POST /clubs/{id}/passes` | admins | `{name, price_cents, billing: once\|monthly\|instalments, instalments? (2–12), covers: [nets, training, friendly, league_match, tournament, social], team_id?, valid_until?, sessions?, price_type_id?, open_to_join?}`. A monthly pass has no end date or session count. |
| `PATCH /passes/{id}` | admins | `{name?, price_cents?, open_to_join?, archived?}`. A new price applies to later charges only, and everybody on a monthly pass is told to change their standing order. |
| `GET /passes/{id}/holders` | admins | `[holder]` |
| `POST /passes/{id}/holders {user_id, started_on?}` | admins | `holder`. The first payment is charged at once. `already_on_pass` (409). |
| `POST /passes/{id}/join {for_user_id?}` | members | `holder`. Pass `for_user_id` for somebody you pay for. Errors: `not_open`, `not_eligible` (wrong price type), `not_their_payer`, `already_on_pass`. |
| `POST /pass-holders/{id}/cancel` | the holder, their payer, admins | `holder`. A monthly pass covers to the end of the month already charged (`ends_on`); anything else stops today. `already_cancelled` (409). |
| `PUT /pass-holders/{id}/keep-covering {on}` | admins | `holder`. Covers however far behind. |
| `GET /me/passes` | anyone | `[holder + {club_id, club_name, charge_cents, currency, standing_order}]`, yours and those of people you pay for. |

A **holder** is `{id, plan_id, club_id, user_id, name, started_on, ends_on, cancelled_at,
keep_covering, plan_name, billing, standing, sessions_left, running, next_charge_on}`.
- **`standing`** is `up_to_date`, `behind` (a payment late but still covering: say so) or
  `suspended` (not covering until paid up).
- **`running`** means it covers sessions today.
- **`standing_order`** is `{amount_cents, every: "month", first_payment_on, reference}`: exactly
  what to type into the banking app for a monthly pass. It's null for other passes and once
  cancelled.

The scheduler charges each month (or instalment) on the day it falls. The holder (and whoever
pays for them) is told once when a pass falls behind and again if it's suspended; the club is told
at suspension. A bundle says so at one session left and when it's used up. When the club's bank
details change, everybody paying a monthly pass by standing order is told to change it (no
account numbers in the notice). `GET /clubs/{id}/money` gains `passes_behind`, for "3 passes
behind" on the treasurer's screen.

### Group fees (money admins)

| Call | Returns |
|---|---|
| `POST /clubs/{id}/collections` | `{title, mode: split_total\|per_player, amount_cents, due_on?, note?}` plus who: one of `everyone: true`, `team_id`, `price_type_id` or `user_ids`, and optionally `guests: [name]`. Returns the group fee: the bill fields plus `{paid_cents, waiting_cents, owed_cents, people, shares}`. Everybody in it is told. |
| `GET /clubs/{id}/collections` | The 50 newest, totals only (`shares` empty). |
| `GET /collections/{bill_id}` | Everyone's lines for an admin; only your own for a member. |
| `POST /collections/{bill_id}/void {reason}` | Cancelled: anything paid becomes credit, and its pay link closes. `reason_required`. |
| `POST /bills/{bill_id}/link`, `…/link/disable` | A group fee's WhatsApp link and messages, the same shape as a session's. |

### Paying for others

| Call | Who | Returns |
|---|---|---|
| `PUT /clubs/{id}/members/{member_id}/payer {payer_id \| null}` | admins | 204 |
| `POST /clubs/{id}/members/managed {name, payer_id}` | admins | `{user_id, name, payer_id}`: a junior with no sign-in of their own. |
| `POST /clubs/{id}/payments/for-others {method: transfer\|cash, people: [user_id], include_me?, note?}` + `Idempotency-Key` | members | `{payments, total_cents, reference}`. One line each for what they owe, all under your reference, marked paid by you. You may pay for people you pay for, or for friends on a bill you're on (`not_their_payer` otherwise). `nothing_owed` (409) when nobody picked owes anything. |

### What each app builds for steps B and C

1. **For a player: "Passes" on the club's pay screen.**
   - Each offered pass in one line, for example "Monthly nets: £20 a month, covers nets and
     training", with **Get this pass**.
   - Your own pass: "Covered until …" or "3 sessions left", and the standing as words ("A payment
     is late: pay it to stay covered").
   - For a monthly pass, a **Set up your standing order** card: who, the amount, "every month",
     the start date and the reference, each with Copy. It also offers "Send to someone who pays
     for me" and **Cancel my pass** (with a confirmation, and the reminder to cancel the standing
     order in the bank too).
2. **Covered lines** read "Covered by your pass ✓" and need no tap. Pass charges and group fees sit
   in "You owe" like any session: "Monthly nets — December 2026", or "Match balls, by 6 Dec".
3. **For a parent:** "You owe" shows each person they pay for as their own block, with one
   **Pay for everyone** button: one payment, one reference, through `for-others`. The pay screen
   also has "I'm paying for friends too": tick names from the same session.
4. **For money admins:**
   - **Passes.** Make one from a template (Winter nets pass, 10-session card, Monthly nets,
     Season membership in 3 parts, Junior membership). See who's on it and how they stand. Add
     somebody, cancel, and keep covering.
   - **Prices for juniors and others.** Name the groups, mark one free or for guests, and set
     each member's group from the member list. The session cost form gets "Different price for
     juniors?".
   - **Group fees.** New group fee: who (everyone, a team, juniors, ticked names, plus guests),
     how much (split a total, or the same from each), and a due date. Then the list, one
     opened, Share to WhatsApp, and cancel.
   - **Who pays for whom** on a member's page, and **Add a junior by name**.

