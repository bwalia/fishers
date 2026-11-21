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
