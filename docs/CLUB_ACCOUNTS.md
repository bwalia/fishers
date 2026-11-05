# Club accounts

The books a club treasurer keeps, and the three documents they take to the AGM:
the treasurer's report, the Income & Expenditure account and the balance sheet,
each with last year beside it.

Who can open them: the club **owner** and its **treasurers**, nobody else. See
[RBAC.md](RBAC.md#club-accounts--the-owner-and-treasurers-only).

## How the books are kept

| | |
|---|---|
| **Year** | `club_account_periods`. One open at a time. Closing it freezes its figures; only the owner can reopen it, with a reason, and never while a later year is open. A new year's b/f, bank opening balances and opening stock are carried from the last year's closing figures; they are typed in only for a club's first year in the app. |
| **Lines** | `club_account_categories`. A club gets the usual cricket-club lines the first time its books are opened, and can rename, reorder, footnote and archive them. Lines the app posts to by itself (fees, fees owed, write-offs, equipment…) carry a `system_key` and can't be archived. |
| **Money accounts** | Bank, cash, credit held with a supplier, a payment provider. Each has an opening figure and, once entered, the figure off the statement. |
| **Transactions** | Income and expenditure carry a positive amount and a line. A **prior-period adjustment** is signed, has no line, and prints on the balance sheet on its own — it is never trading. Nothing is deleted: a mistake is voided, with a reason. Extraordinary items can be marked with the committee's authorisation. |
| **Debtors and creditors** | Raised with the other side posted to "Match/net fees owed" or "Cost shares owed" (switch `accrue` off for one carried from before the club used the app). A payment moves money into an account and is not income again. A write-off posts to "Unrecovered debt"; a debt recovered short posts the shortfall to "Losses on previous year recovered debt". |
| **Stock** | Match balls first. The change in stock value over the year moves the equipment line: balls bought and not used are an asset, balls used off last year's shelf are a cost. |
| **Audit** | `club_account_audit` — every change, who made it, before and after. |

Money is integer pence throughout.

## What the app already knew

- **Fees paid in the app** show up as suggestions. The treasurer accepts them
  into a money account; a payment for a fee already raised as a debtor settles
  that debt instead of counting the fee twice.
- **Fees still unpaid** for the year's fixtures can be raised as debtors in one
  go — one per member per fixture, and running it again doubles nothing.

## The report

`GET /clubs/{id}/accounts/periods/{pid}/report` returns this year and last.
The arithmetic is in `backend/domain/src/accounts.rs` (`build_report`), with
tests that reproduce a real club's AGM figures to the penny.

The balance sheet's **difference** — "Represented by" minus c/f — is always
returned and never rounded away. The real club's spreadsheet was £69.92 short
in 2025/26 and £4.23 over in 2024/25; the app says so, and a prior-period
adjustment is how a treasurer clears it on the record.

## Testing

```sh
cargo test -p fishers-domain accounts           # the arithmetic
./scripts/smoke-accounts.sh http://127.0.0.1:8080   # access rules and the AGM figures, end to end
```

## Not yet

- Transfers between money accounts (bank → credit with the nets venue). For
  now, enter the statement figure on each account.
- The phone apps: read-only overview, quick-add with a receipt photo, marking a
  fee paid in cash.
- A server-rendered PDF. The web report page is laid out for printing and saves
  to PDF from the browser.
