# Prompt: club accounts — a treasurer keeps the club's books

Hand this to an agent working on branch `feat/a-treasurer-keeps-the-club-books`.

---

## Goal

Give every club a set of books that its **owner** and a new **Treasurer** role can
keep inside the app, and that produce, at the end of an accounting year, the three
documents a club treasurer takes to the AGM:

1. **Treasurer's annual report**: a written narrative.
2. **Income & Expenditure account**: income and spending by category, with the
   previous year beside it.
3. **Balance sheet**: balance brought forward + income − expenditure = balance
   carried forward, followed by "Represented by", which lists bank, credit held
   with suppliers, stock, debtors and creditors, and must agree with the balance
   carried forward.

The worked example at the bottom of this document is a real small cricket club's
year. Build the feature so it can reproduce that example exactly, then do better
than the spreadsheet it came from: point out where the numbers don't agree, and
build the debtors list from the fees the app already knows are unpaid.

## Who may see and change the accounts

- **Club owner** (`clubs.owner_id`) and members with the new role
  **`club_treasurer`**. Nobody else can see the accounts or change them.
- The club secretary (`club_admin`), captains, vice captains, members and
  guests get **no** access by default. A secretary is not a treasurer. Club
  money is the one area where the usual "secretary can do everything" rule does
  not hold, so say that in `docs/RBAC.md`.
- `super_admin` gets no access through the normal UI. If platform support ever
  needs to look, that is a separate, audited path that is out of scope here.
- A club may have more than one treasurer, for example an outgoing one and an
  incoming one in the same year.
- Only the owner or the club secretary can appoint or remove a treasurer, using
  the existing member-role flow (`ManageMembers`). Appointing someone does not
  let the person who appointed them see the books.

### Where this goes in the code

- `backend/domain/src/enums.rs`: add `UserRole::ClubTreasurer`, and a migration
  that runs `ALTER TYPE user_role ADD VALUE 'club_treasurer'`. Outside the
  accounts, a treasurer has the same permissions as a `Member`. Place the new
  role carefully in any ordering or "at least" comparisons in `rbac.rs` so it
  does not quietly gain captain or secretary powers.
- `backend/domain/src/rbac.rs`: add `Permission::ViewAccounts` and
  `Permission::ManageAccounts`. `UserRole::can` grants both to `ClubTreasurer`
  only. The owner gets them from an ownership check, not a role. Add
  `require_accounts_access(state, club_id, user_id, write: bool)` in
  `backend/api/src/rbac.rs`, which passes when the user is
  `clubs.owner_id` **or** an active member whose role grants the permission.
  Return a 403 that names the rule: "Only the club owner or a treasurer can open
  the accounts".
- Tests for every role, both read and write. Cover a suspended treasurer, and a
  treasurer of one club trying to reach another club's books.

## What the books hold

All money is stored as **integer minor units** (`*_cents BIGINT`) plus a currency,
matching `events.fee_amount_cents` and `events.fee_currency`. Never use floats.
Each club has a single base currency (GBP by default).

| Thing | Notes |
|---|---|
| **Accounting period** | `club_id`, `starts_on`, `ends_on`, status `open` / `closed`, `closed_at`, `closed_by`. The default year is 1 Oct to 30 Sep, and the club can change it. One open period at a time. The opening balance (b/f) is the previous period's closing balance (c/f). For a club's first period it is typed in. |
| **Categories** | Per club, each either `income` or `expenditure`, with a sort order, and archivable but never deleted. Seed them from the example: Indoor net fees, Outdoor match fees, Match/net fees owed, Miscellaneous, Sponsorship, Cost share with other teams, Cost shares owed, Interest / Indoor nets, Pitch hire, Cost share with other teams, Losses on previous year recovered debt, Unrecovered debt, Cost shares owed, Equipment purchase, Public liability insurance, Engraving & trophies, Food (home games), Website, Charitable donations, Social, Miscellaneous. A category can carry a footnote that prints on the report, like (1), (2) and (3) in the example. |
| **Money accounts** | Where money is held: bank current account, cash tin, **credit held with a supplier** (the example's "Credit with HSV"), payment provider balance. Each has an opening balance per period and a **reconciled balance**: a figure the treasurer types in from the bank statement on a date. |
| **Transactions** | Date, amount, direction, category, money account, payee or payer text, an optional link to a **member** (`user_id`), an **event**, or an **other club/team**, a note, an optional receipt (photo/PDF, reusing the existing upload path), `created_by`. A transaction is never deleted. It is **voided**, with a reason, and the void stays in the audit trail. A transaction can be marked **extraordinary** and **authorised by committee** (with the date and minute reference), which covers the example's £490 of one-off payments. |
| **Debtors** (owed to the club) | Unpaid match/net fees per member, unpaid cost shares from other teams. A debt can be **written off** (with the AGM decision recorded), and the write-off posts to "Unrecovered debt". When a debt is recovered short (for example after a provider's fee), the shortfall posts to "Losses on previous year recovered debt". |
| **Creditors** (owed by the club) | Unpaid cost shares to other teams, unpaid invoices. |
| **Stock** | Starts with **match balls**: opening quantity and value, purchases, quantity used. Balls used in the year are expensed to Equipment purchase, and unused balls carry forward at cost (footnote 3 in the example). Build stock as a general list of items so the club can track more than balls, but ship balls first. |
| **Report text** | The treasurer's narrative for each period, written in plain text or Markdown, plus a signed statement ("I have reviewed the accounts…") with name and date. |

Put all of it in **one migration** `backend/db/migrations/<date>_club_accounts.sql`,
with a repo in `backend/db/src/repos/accounts.rs` and domain types in
`backend/domain/src/accounts.rs`. Every write also adds a row to an append-only
`club_account_audit` table (who did what, when, and the before and after values).

## Connect it to what the app already knows

The app already charges match fees (`events.fee_amount_cents`), records payments
(`event_tickets.paid_at`, `paid_by`, `payment_method`: stripe / cash / transfer),
and chases late payers (`fee_reminders_sent`, the club's `fee_chase_*` settings).
Use that data, don't re-enter it:

- **Fees paid in the app** show up in the books as suggested income lines in
  "Outdoor match fees" or "Indoor net fees", depending on the event type. The
  treasurer accepts them one at a time or in bulk. Nothing posts without the
  treasurer's say-so, and nothing is counted twice.
- **Fees still unpaid** when a period closes become debtors automatically, one
  per member, each linked to the fixtures it covers. This replaces the
  hand-counted "Unpaid 2026 match/net fees" line.
- Show **paid since the books closed** against each debtor, as in the
  example's "£108.50 paid since books closed".
- A debtor's page links to the existing fee reminder, so the treasurer can chase
  from where they're working. The example's report says prompter payment
  requests reduced debt.
- Losing a fee-collection provider (the example's "With the demise of
  Teamer…") is the reason this exists. The club's own fees are already collected
  through Fishers payments, so say so on the accounts screen.

## The reports

Build these for any period, open or closed. A closed period's figures never move.

1. **Income & Expenditure**: categories in the club's order, current year and
   previous year side by side, totals, and **Excess of income over expenditure**
   (negative means a loss). Footnotes are printed below.
2. **Balance sheet**: b/f, + income, = total, − expenditure, = c/f, for both
   years. Then **Represented by**: each money account's reconciled balance,
   supplier credit, stock value, debtors and creditors (creditors are
   subtracted), and the total. Then the debtors and creditors notes, broken down
   as in the example.
3. **Reconciliation check**: if "Represented by" does not equal c/f, show the
   **difference**, highlighted, on screen and in the export. The example has
   one: c/f is £3,496.23 but "Represented by" totals £3,426.31, a gap of £69.92
   that the narrative puts down to "likely errors in the books from 2025". The
   app must never hide that number. Let the treasurer post an explicitly labelled
   **prior-period adjustment** to clear it, and the adjustment shows on the
   report.
4. **Treasurer's annual report**: the narrative, the headline figures pulled in
   live (total assets, surplus or loss, total debtors), the signed statement, then
   the two tables.
5. **Insights**: computed from the data, nothing made up. Each one is a short
   line the treasurer can paste into the narrative:
   - Net profit or loss for the year, and the same figure **excluding
     extraordinary items**. The example says "ignoring the two extraordinary
     payments, 2026 was a profitable year", and the app should show that figure
     directly.
   - Indoor nets: fees received against hire cost, giving the net result. Also
     season passes sold this year against last year.
   - Summer matches: matches completed, total fees, average fee per match, and
     ball cost per match.
   - Fixed costs (insurance, website, affiliation) this year against last year,
     with any multi-year prepayment pointed out. The example's website hosting
     was renewed for 4 years.
   - Debt at year end against last year, and how much was recovered.
6. **Exports**: PDF (A4, laid out like the example, ready to hand round at an
   AGM), CSV of transactions, and CSV of each table. The club name and period go
   in the header, and there is no Fishers or Gully Cricket branding inside the
   document.

## Clients

- **Web first** (`web/src/app/clubs/[id]/accounts/…`), because keeping books is
  desk work. Pages: Overview (the headline numbers and reconciliation status),
  Transactions (filterable, with quick add), Debtors & creditors, Stock, Report
  (narrative editor, preview, export), Settings (period dates, categories, money
  accounts, close the period).
- Add an **Accounts** entry to the club page. Render it only for the owner and
  treasurers, and have the server enforce the same rule. Hiding the link is not
  protection.
- **iOS and Android**: phase 2. Add a read-only overview, quick-add a
  transaction with a receipt photo (a treasurer at the ground with a receipt in
  hand), and mark a fee paid in cash. Show nothing to roles that cannot see the
  accounts.
- Every user-facing string goes in **English and ਪੰਜਾਬੀ**
  (`web/src/lib/i18n/{en,pa}.ts`, plus the app string JSON files for phase 2).
  Use accountancy terms that a club treasurer recognises: b/f, c/f, debtors,
  creditors.
- Brand-neutral: the feature works the same for Fishers and Gully Cricket.

## API

Under `/v1/clubs/{club_id}/accounts/…`. Every handler starts with
`require_accounts_access`. Cover periods (list, create, close, reopen; reopening
is owner only, needs a reason, and is audited), categories, money accounts
(including posting a reconciled balance), transactions (create, edit while the
period is open, void), debtors and creditors (create, settle, write off), stock,
report text, `GET …/reports/{period_id}` (I&E, balance sheet, reconciliation and
insights as JSON), and `GET …/reports/{period_id}.pdf`. Document the routes in
`backend/api/src/docs.rs` the same way the existing routes are documented.

## Acceptance test: the worked example

Seed a club with the 2024/25 and 2025/26 periods below (use fixture data, not
the real club), then assert:

- I&E 2025/26: income **4,287.37**, expenditure **4,637.73**, excess
  **−350.36**. 2024/25: income **4,711.91**, expenditure **4,114.08**, excess
  **597.83**.
- Balance sheet 2025/26: b/f **3,846.59** + 4,287.37 = **8,133.96**, − 4,637.73
  = c/f **3,496.23**. The 2024/25 c/f equals the 2025/26 b/f.
- Represented by 2025/26: bank 2,825.46 + supplier credit 0.00 + balls 70.85 +
  debtors 530.00 − creditors 0.00 = **3,426.31**, and the reconciliation check
  reports a **difference of 69.92**. 2024/25: 2,996.88 + 104.94 + 749.00 =
  **3,850.82**, which differs from 3,846.59 by **4.23**, and that must be
  reported as well.
- Debtors note: 339.00 (unpaid 2026 fees, with 108.50 paid since close) + 61.00
  (unpaid 2025 fees) + 130.00 (cost share from another team) = **530.00**.
- Excluding extraordinary items (490.00), the 2025/26 result is **+139.64**.
- Indoor nets 2025/26: 648.76 received against 1,120.00 hire, a net of
  **−471.24**. (The narrative says "£300". Season passes and fees owed explain
  part of the gap, so the insight must show its working rather than round the
  figure off.)
- Role tests as listed in the access section. Run them against both brands.

Run the API tests, the web typecheck, lint and Playwright checks, plus
`tools/brand` tests, before opening the PR.

## Worked example (source material)

A real club's treasurer's report for 01 Oct 2025 to 30 Sep 2026, reproduced for
its structure and figures. Names of individuals have been removed.

**Narrative, summarised.** Assets £3,496.23, a loss of £350.36. Debtors £530,
which includes £42 left over from 2025 and two payments owed by other teams.
Winter nets made a bigger loss than last year (about £300). Fewer season passes
were sold (4 against 8). Net hire costs keep rising. 22 summer matches were
completed with high fee income, and they covered the nets losses. Ball costs
were slightly up. Fixed costs rose because website hosting was renewed for 4
years. Insurance cost the same. Match fee debt was lower thanks to prompter
payment requests. The fee-collection provider has closed, so fee collection for
2027 needs a new answer. There were two extraordinary payments authorised by the
committee: a charitable contribution to a member's family and a commissioned
painting for a long-serving supporter, totalling £490. Excluding those, the year
was profitable. Errors in the 2025 books mean the accounts are not fully
accurate, but the bank balance, debtors and ball stock are correct.

**Income & Expenditure, 01-Oct-2025 to 30-Sep-2026** (2025/26 | 2024/25)

| Income | 2025/26 | 2024/25 |
|---|---:|---:|
| Indoor net fees | 648.76 | 974.20 |
| Outdoor match fees | 2,549.61 | 2,328.71 |
| Match/net fees owed | 339.00 | 629.00 |
| Miscellaneous | 0.00 | 0.00 |
| Sponsorship | 0.00 | 0.00 |
| Cost share with other teams | 620.00 | 660.00 |
| Cost shares owed | 130.00 | 120.00 |
| Interest | 0.00 | 0.00 |
| **Total** | **4,287.37** | **4,711.91** |
| Excess income over expenditure | −350.36 | 597.83 |

| Expenditure | 2025/26 | 2024/25 |
|---|---:|---:|
| Indoor nets | 1,120.00 | 1,139.00 |
| Pitch hire | 1,692.50 | 1,940.00 |
| Cost share with other teams | 245.00 | 238.00 |
| Losses on previous year recovered debt ⁽¹⁾ | 18.83 | 5.23 |
| Unrecovered debt ⁽²⁾ | 0.00 | 11.00 |
| Cost shares owed | 0.00 | 0.00 |
| Equipment purchase ⁽³⁾ | 377.46 | 339.82 |
| Public liability insurance | 100.80 | 100.80 |
| Engraving, trophies etc. | 60.00 | 82.08 |
| Food (home games) | 318.93 | 123.36 |
| Website | 214.21 | 134.79 |
| Charitable donations | 0.00 | 0.00 |
| Social | 0.00 | 0.00 |
| Miscellaneous | 490.00 | 0.00 |
| **Total** | **4,637.73** | **4,114.08** |

⁽¹⁾ Adjustment for income lost on the previous year's owed fees, when the
provider's admin fees meant the full amount was not recovered.
⁽²⁾ Overdue match fees from previous seasons, written off at the AGM.
⁽³⁾ Match balls used in the season count as purchases against club stock. Unused
balls bought in the period are added to stock.

**Balance sheet**

| | 2025/26 | 2024/25 |
|---|---:|---:|
| Balance b/f | 3,846.59 | 3,248.76 |
| Income received | 4,287.37 | 4,711.91 |
| Total | 8,133.96 | 7,960.67 |
| Expenditure | 4,637.73 | 4,114.08 |
| **Balance c/f** | **3,496.23** | **3,846.59** |
| *Represented by:* | | |
| Bank current a/c | 2,825.46 | 2,996.88 |
| Credit with supplier (nets venue) | 0.00 | 0.00 |
| Unused balls | 70.85 | 104.94 |
| Debtors | 530.00 | 749.00 |
| Creditors | 0.00 | 0.00 |
| **Total** | **3,426.31** | **3,850.82** |

Debtors: unpaid 2026 match/net fees 339.00 (108.50 paid since the books closed),
unpaid 2025 match fees 61.00 (should be recoverable), unpaid cost share from
another team 130.00. Total 530.00. Creditors: none.
