# Paying the club by bank transfer

> **Status: plan, not built.** Written 2026-11-21. Decisions still open are at the end.

A secretary adds the club's bank details once. When a match or nets session has a cost,
the app works out each player's share from who actually came. It shows them the bank
details with a reference, and keeps track of who has paid. **The app never touches the
money.** It goes straight from the player's bank to the club's, so nobody takes a cut.

The trade-off: nobody tells us automatically that money arrived. A person ticks
"received". The design makes that one tap, and phase 2 lets a bank statement do it.

---

## 1. What already exists (build on it, don't duplicate it)

| Already in the code | Where | How this plan uses it |
|---|---|---|
| Per-player fee on an event | `events.fee_amount_cents`, `fee_currency` | Becomes the "fixed per player" cost. Old apps keep reading it. |
| Who owes a match fee | `outstanding_match_fees` view | Rebuilt on the new tables. Today it treats everyone who said "going" with no card payment as owing. |
| Fee reminders | `jobs::chase_match_fees`, club settings `fee_chase_after_hours`, `fee_chase_max_reminders` | Reused and rewritten to read shares. Today it hard-codes "£" and says "pay in the app". |
| Who turned up | `event_invites.attended`, set from team sheets (`repos/cricket.rs`) | A match's attendance is already known. Nets need a "who came" step. |
| Treasurer role | `club_members.is_treasurer` and `clubs.owner_id` | The same people who can open the books manage payments. |
| The books | `club_account_*` tables, [CLUB_ACCOUNTS.md](CLUB_ACCOUNTS.md) | A confirmed transfer appears as a suggestion in the books, as card payments already do. `source`/`source_ref` stop anything being counted twice. |
| Card payments | `backend/payments` (Stripe, platform as merchant) | Left as it is. It stays an option, not the default. A card payment simply counts towards a share. |

House rules this plan keeps:
- **Money is integer minor units** in the club's currency. There are INR clubs, not only GBP.
- **Nothing is deleted.** A mistake is voided, with a reason.
- **A debt is never cleared on the payer's say-so.** `event_tickets` already works this way.
- **Phones decode enums as closed lists.** New values go in new fields, or the apps
  decode them leniently. An unknown status must never break a whole screen on an
  old iPhone build.

---

## 2. The pieces

| Piece | What it is |
|---|---|
| **Payout account** | Where the money goes: the club's bank account (or the secretary's own). A club can have several, and one is the default. |
| **Cost** | Set on an event or a weekly series. Either **split a total** ("£60 lane hire between whoever comes") or **fixed per player** ("£5 match fee"). |
| **Bill** (charge) | Created once attendance is known. It fixes who pays, how much, and to which account. |
| **Share** | One person's part of a bill. |
| **Payment** | Money a player says they sent (*waiting to confirm*), which a treasurer *confirms* or *rejects*. One payment can cover several shares ("Pay all £20.01"). Cash is recorded straight away by the treasurer. |
| **Balance** | Worked out, never stored: shares minus confirmed payments. A negative balance is credit, used up by the next share automatically. |

A share's status is **derived**, so it can't drift: *owed*, *part paid*, *waiting to
confirm*, *paid*, *waived* or *cancelled*.

---

## 3. The flow, end to end

### 3.1 The secretary adds bank details (once)
**Club → Manage club → Payments → Add bank account**

- **Account holder name, exactly as on the account.** UK banks check the name a payer
  types (Confirmation of Payee). A mismatch shows the player a fraud warning and they
  stop paying, so the form says this plainly.
- **Sort code and account number.** We check the format, then run the Pay.UK modulus
  check: a published table, free to use, that catches most typos before anyone pays
  into a wrong account.
- **Nickname**, e.g. "Club account" or "Aman's account".
- **"This is a personal account"** tick box. Players see it.
- **Re-enter your password**, or an email code for people who sign in with Google or Apple.
- **Going live:**
  - A club's **first** account is live at once.
  - A **change** goes live after **24 hours**. The owner, every secretary and every
    treasurer get a push and an email: "Riverside's bank details were changed by Aman.
    Live at 14:30 tomorrow. Not right? Freeze them."
  - Players see "Bank details changed on 21 Nov" beside the details for 30 days.

### 3.2 Set the cost when scheduling
The schedule-nets and fixture forms get an optional **Cost** section:
- **Split a total** or **Fixed per player**, plus the amount.
- **Paid to**: the payout account, if the club has more than one.
- A preview: "8 coming → about £7.50 each".
- **Weekly nets:**
  - The cost is set on the series and copied to each week as it's created.
  - One week can be edited without touching the others.
  - Changing the series changes future weeks that haven't been billed yet.
- **No bank details yet:** the cost can still be saved. The form links to "Add bank
  details", and players are told the club hasn't added them yet.

### 3.3 Confirm who came, then send the bill
- **Matches:** players on the team sheets are already marked as attended. Guests typed
  in by name become guest shares.
- **Nets:**
  - After the session, whoever scheduled it gets "Who came to Friday nets?". The
    "Going" list is already ticked.
  - They adjust it and see "£60 ÷ 9 = £6.67 each (6 pay £6.67, 3 pay £6.66)".
  - They tap **Send**. Confirming attendance also feeds the reliability score.
- **If nobody confirms within 24 hours** (a club setting): the app bills from the
  "Going" list and tells the secretary. The setting is *auto-bill* or *remind me only*.
- **Splitting:** whole pennies only.
  - **Exact** (the default): the leftover pennies go 1p each to the first people, in a
    fixed order.
  - **Round up to 10p** (a club setting): any surplus is shown as club income.
- **Sending:**
  - It fixes the bill: who pays, the amounts, and the payout account.
  - Each player gets a push: "Friday nets: your share is £6.67. Pay Riverside Strikers
    by bank transfer."
  - Credit a player already holds pays their share automatically.

### 3.4 The player pays
- **Where they see it:**
  - Home shows "You owe £6.67".
  - The event page shows their share.
  - **Profile → Payments** lists everything they owe, across all their clubs.
- **The pay screen:**
  - Amount, account holder name, sort code, account number and reference, each with
    **Copy**, plus **Copy all**.
  - Then: "Pay in your banking app, then come back and tap **I've paid**".
  - **Pay all** covers everything owed to one club in one transfer.
- **The reference:**
  - Made when they tap Pay; the same one comes back if they return.
  - Unique within the club and **at most 18 characters**, the UK Faster Payments limit.
  - No letters that are easy to confuse (0/O, 1/I). Example: `7KQ3X GILL`.
- **Claiming:**
  - **I've paid** (transfer) or **I paid cash** makes the share *waiting to confirm*.
  - The player can undo it until someone confirms.
- **Offline:**
  - The details are cached on the phone.
  - "I've paid" is queued with a one-time key and sent when the signal returns. A double
    tap can never make two claims.

### 3.5 A treasurer confirms
- **Payments to check** (with a badge) lists name, amount, reference and date. The
  treasurer checks their banking app, then either:
  - taps **✓ Received** (several at once is fine), or
  - taps **✗ Not received** with a reason. The player is told, and reminders start again.
- **Record a payment** with no claim, for cash at the ground or a player who forgot to tap.
- **Waive** a share (junior, coach, hardship) or **write off** a debt (left, never paid),
  each with a reason.
- The event's money panel shows "£46.69 of £60 collected · 2 unpaid · 1 to check".
- **Clubs that keep their books in the app:** confirmed payments appear as suggestions in
  Club accounts, once and never doubled.

### 3.6 Reminders
- The existing fee-chasing job, rewritten:
  - It reads shares.
  - The first nudge goes `fee_chase_after_hours` after the bill is sent, then every few
    days, up to `fee_chase_max_reminders`.
  - It stops as soon as a share is paid, waiting to confirm, waived or cancelled.
- A claim still unconfirmed after 48 hours nudges the treasurer.
- **Pushes never show the account number**, because they appear on lock screens.
- Every reminder records that it was sent. RSVP reminders once went out every five
  minutes because they didn't.

---

## 4. When things change: every case and what happens

| Situation | What happens |
|---|---|
| Rained off before the bill is sent | Nothing is billed. The cost is dropped for that week. |
| Rained off after billing, venue refunds | The secretary cancels the bill. Unpaid shares are cancelled; money already paid becomes credit, or the treasurer records a refund. |
| Rained off, venue still charges | Bill as normal. The note says why. |
| Someone added or removed after billing | **Re-split.** If nobody has paid, the shares are simply replaced. If someone has, what they paid moves to their new share and any excess becomes credit. The history is kept. |
| The venue's bill was different (£70, not £60) | Same as a re-split. |
| Player paid too little | Part paid; the rest is still owed. |
| Player paid too much | Credit, used up by the next share, or refunded. |
| Payment arrived with no or the wrong reference | The treasurer records it against the person by hand. |
| Player tapped "I've paid", but no money came | The treasurer rejects it with a reason. The player is told, and reminders resume. |
| Player paid into the old account after a change | The claim records which account was shown. The treasurer confirms it if the money arrived. |
| Bank details frozen ("Not right?") | Pay screens say "Payment details are being checked: don't pay yet". Only the owner can unfreeze them. |
| Club has no bank details | Shares are still made. The pay screen says so, and the treasurer can record cash. |
| Two secretaries change the same bill at once | The second gets "Aman changed this a moment ago. Reload." This is checked with a version number, so nothing is lost silently. |
| The same tap sent twice on bad signal | A one-time key means one claim. |
| Nobody ticked as coming | The bill can't be sent: "Nobody's ticked as coming". |
| An amount looks like a typo | Hard limit per person and per bill. Above £100 a head, the app asks for confirmation. |
| Member leaves the club still owing | They still owe it, and can still see and pay it. The treasurer can write it off. |
| Guest with no account | A share under their name. The treasurer records cash. In phase 2, a pay link they can open without signing in. |
| Someone deletes an event that has a bill | Refused, with Cancel offered instead. Money records never cascade away; `events` cascades to many tables, so the new ones use `RESTRICT`. |
| A player deletes their account | Their money records stay, shown as "Former member". |
| An old app version | Every field is additive. The feature is switched on per club, and apps that don't know it simply don't show it. |
| A club outside the UK | The amount and its formatting use the club's currency. UK bank details only in phase 1; other methods in phase 3. |

---

## 5. Security and the law

**The main risk is someone swapping the bank details for their own**, through a hacked
secretary account or a rogue admin. In order of how much each defence matters:
1. A change waits **24 hours**. Every owner, secretary and treasurer is told and can
   **Freeze** it.
2. Changing details needs the password typed again.
3. Players see the account holder's name and "changed on…". Their own bank's name check
   warns them on a mismatch.
4. A full **audit trail** records who added, changed, froze, showed, confirmed, waived or
   cancelled what, with before and after. It never contains the account number.

**Storage:**
- The account number is **encrypted in the database** with AES-256-GCM. The key comes
  from a Kubernetes secret, and a key version is stored so the key can be rotated.
- Sort code, last four digits and holder name are kept readable, for display.
- A keyed hash spots duplicates without decrypting anything.
- **Who gets the full details:**
  - only the club's admins, and anyone who currently owes that club;
  - never list endpoints, logs, error messages, pushes or analytics;
  - the endpoint that shows them is rate-limited.
- On phones, the details live in app-private storage and are cleared on sign-out.

**The law and the stores:**
- We never hold or move money, so this isn't a payment service and needs no FCA
  authorisation. **Keep it that way:** this feature must never collect into a platform
  account.
- **App Store and Google Play:** paying for real-world services, like nets hire and match
  fees, outside in-app purchase is allowed. Apple's rule 3.1.3(e) and Play's payments
  policy both cover it.
- **GDPR:** a secretary's personal account is personal data. Its only purpose is
  collecting club costs. When the account is retired, only the name and last four digits
  are kept for history, and it is included in that person's data export.

---

## 6. Data (new tables, all additive)

| Table | Holds |
|---|---|
| `club_payout_accounts` | club, method (`uk_bank` now; `iban`, `upi`, `link` later), nickname, holder name, personal?, sort code, last 4, encrypted details + key version, fingerprint, status (`pending`, `active`, `frozen`, `retired`), live from, created by. One default per club (partial unique index). |
| `event_costs` | event or series, mode (`split_total`, `per_player`), amount, currency, payout account, rounding, auto-bill setting. For `per_player` it keeps `events.fee_amount_cents` in step. |
| `event_bills` | event (`RESTRICT`), club, title snapshot, total, currency, payout-account snapshot, status (`issued`, `void`), **version** (for conflicts), who sent it and when, void reason. One live bill per event (partial unique). |
| `bill_shares` | bill, member *or* guest name, amount, status (`live`, `waived`, `void`), reason. Unique per member per bill. Shares are never edited: a re-split cancels them and makes new ones. |
| `member_payments` | club, member or guest, amount, currency, method (`transfer`, `cash`, `card`, `credit`, `refund`), reference (unique per club), payout account shown, status (`claimed`, `confirmed`, `rejected`, `cancelled`), who decided and why, idempotency key (unique per member), card `payments.id` if paid by card. |
| `payment_allocations` | payment → share, amount. The same transaction checks that a share is never over-paid and a payment never over-spent. Anything left over is credit. |
| `club_payment_audit` | Same shape as `club_account_audit`. |

The balance and share status are a SQL view, not stored columns.

**Integrity:**
- Every change runs in one transaction, with the audit row inside it.
- The bill row is locked while shares change.
- The client sends the bill's version; a stale version gets `409`.

---

## 7. API (sketch)

| | |
|---|---|
| Bank details | `GET/POST /clubs/{id}/payout-accounts`, `POST …/{acc}/freeze`, `…/unfreeze` (owner), `…/retire` |
| Cost | `PUT /events/{id}/cost` (and on a series) |
| Bill | `GET /events/{id}/bill`, `POST /events/{id}/bill` `{attendees, version}` (send or re-split), `POST /events/{id}/bill/void` |
| Player | `GET /me/dues`, `POST /clubs/{id}/payments` `{shares or "all", method}` + `Idempotency-Key` → reference and details, `DELETE /payments/{id}` (undo a claim) |
| Treasurer | `GET /clubs/{id}/payments?status=claimed`, `POST /payments/{id}/confirm`, `…/reject`, `POST /clubs/{id}/payments/record`, `POST /shares/{id}/waive` |

Errors have a stable code and a sentence the apps can show:
- `version_conflict` (409), `already_billed` (409), `no_attendees` (422);
- `details_frozen` (423), `reauth_required` (428), `not_treasurer` (403);
- `amount_limit` (422), `no_payout_account` (409).

---

## 8. Code shape: built to grow without rewrites

- **`PayoutMethod`**, one trait in `domain`, with `validate`, `display_fields`,
  `instructions(amount, reference)` and an optional `deep_link`.
  - UK bank is the only one in phase 1.
  - UPI later: a `upi://pay?pa=…&am=…&tn=…` link opens GPay or PhonePe with the amount
    filled in.
  - IBAN and Monzo or Revolut links later too.
  - Each is one new implementation, with nothing else touched.
- **`split(total, people, rounding)`**, one pure function covering both modes.
  - Property-tested: the shares always add up to the bill, and in exact mode no two
    differ by more than 1p.
  - Later modes, like half price for juniors, are one more arm.
- **Share status and balance** are pure functions with their own tests. The SQL view
  matches them.
- **Jobs** are safe to run twice (a sent marker on every reminder) and batched per club.
- **Scale:** a club is tens of people, so per-club queries stay small.
  - Indexes on `(club_id, status)` and `(user_id)` keep "what do I owe" one indexed query.
  - Notifications go through the existing push and email services.

---

## 9. Phases

**Phase 1: usable end to end**
1. UK bank details, with the security in §5.
2. Cost on events and series; the "who came" step; the split; sending the bill.
3. The player's dues, pay screen and "I've paid"; the treasurer's confirm, reject,
   record-cash and waive.
4. Cancelling a bill, re-splitting, credit, and the rewritten reminders.
5. Android, iOS and web together, switched on per club.

**Phase 2: less admin**
- Upload a bank statement CSV, and transfers are matched by reference and amount.
  Free, and most of the ticking disappears.
- Pay links for guests.
- Confirmed payments posted into Club accounts.
- CSV export.

**Phase 3: wider**
- UPI, IBAN and payment-link methods.
- Automatic confirmation from a read-only Open Banking feed (cost to be checked first).
- Splitting a pitch with the opposition.
- Season subscriptions.

**Testing and release:**
- **Unit tests:** split, sort-code and modulus checks, reference format, status and
  balance.
- **API tests:** every error code, plus two people sending the same bill at once (one wins).
- **Playwright end to end:** add details → schedule nets with a cost → replies → send →
  claim → confirm → balance zero.
- **Android:** add the new endpoints to `FakeFishersApi`. Release builds skip test
  compilation, so missing ones only fail later.
- Rings int → test → acc → prod. Additive migrations only.

---

## 10. Decisions still open

| | Recommendation |
|---|---|
| Who can add or change bank details? | Owner, secretaries and treasurers, with every change announced to all of them and a 24-hour wait. |
| Who confirms payments? | The same people. |
| When is a nets bill sent? | After the session, once someone confirms who came. If they forget, automatically from "Going" after 24 hours. |
| Rounding | Exact pennies by default; "round up to 10p" as a club setting. |
| Can players see who else has paid? | No. Only admins see the list. |
| UK only first, or UPI too? | UK first, unless Indian clubs are a priority now. |
| Card payments (Stripe) | Keep them as an optional extra, off unless a club asks; bank transfer is the default. |
