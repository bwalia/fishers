//! Paying the club by bank transfer: the rules, with no database in the way.
//!
//! The app never touches the money. These functions decide what each person
//! owes ([`split`]), how much of it is paid ([`settle`]), what reference they
//! put on the transfer ([`reference`]), and whether a club's bank details may
//! be shown ([`payout_states`]). Everything here is pure, so every rule that
//! decides somebody's money has a test beside it.
//!
//! Money is integer minor units (pence, paise, cents) throughout.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// The most one person can be asked for in one bill: £1,000.
pub const MAX_SHARE_CENTS: i64 = 100_000;
/// The most one bill can total: £10,000. Anything bigger is a typo.
pub const MAX_BILL_CENTS: i64 = 1_000_000;
/// A bill is for one session, not a whole league.
pub const MAX_PEOPLE: usize = 200;
/// How long a change of bank details waits before players see it.
pub const CHANGE_DELAY_HOURS: i64 = 24;
/// How long players are told the details changed.
pub const CHANGED_NOTICE_DAYS: i64 = 30;
/// The UK Faster Payments reference limit.
pub const MAX_REFERENCE_LEN: usize = 18;

// MARK: cost and split

/// How an event's cost is shared.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CostMode {
    /// A total ("£60 lane hire") divided between whoever came.
    SplitTotal,
    /// The same amount from everyone who came ("£5 match fee").
    PerPlayer,
}

impl CostMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::SplitTotal => "split_total",
            Self::PerPlayer => "per_player",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "split_total" => Some(Self::SplitTotal),
            "per_player" => Some(Self::PerPlayer),
            _ => None,
        }
    }
}

/// How a split total is rounded.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Rounding {
    /// Whole pennies; the leftover pennies go one each to the first people.
    Exact,
    /// Every share rounded up to the next 10p; the surplus is the club's.
    #[serde(rename = "up_10p")]
    Up10p,
}

impl Rounding {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Exact => "exact",
            Self::Up10p => "up_10p",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "exact" => Some(Self::Exact),
            "up_10p" => Some(Self::Up10p),
            _ => None,
        }
    }
}

/// Each person's amount, in the order the people were given.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Split {
    pub shares: Vec<i64>,
    pub total_cents: i64,
    /// What rounding up collects over the cost. Zero unless rounding up.
    pub surplus_cents: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SplitError {
    NoPeople,
    TooManyPeople,
    /// Zero, negative, or a total too small to give everyone a penny.
    BadAmount,
    ShareTooBig,
    BillTooBig,
}

impl SplitError {
    /// A stable code for clients to branch on.
    pub fn code(self) -> &'static str {
        match self {
            Self::NoPeople => "no_attendees",
            Self::TooManyPeople => "too_many_attendees",
            Self::BadAmount => "bad_amount",
            Self::ShareTooBig | Self::BillTooBig => "amount_limit",
        }
    }

    /// What to tell the person who pressed the button.
    pub fn message(self) -> String {
        match self {
            Self::NoPeople => "Nobody's ticked as coming, so there's no one to split it between.".into(),
            Self::TooManyPeople => format!("A bill can be split between at most {MAX_PEOPLE} people."),
            Self::BadAmount => "The amount has to be more than zero, and enough to give everyone at least a penny.".into(),
            Self::ShareTooBig => format!(
                "That's more than {} each. If it's right, split it over more than one bill.",
                fmt_money(MAX_SHARE_CENTS, "GBP")
            ),
            Self::BillTooBig => format!(
                "A bill can't be more than {} in total.",
                fmt_money(MAX_BILL_CENTS, "GBP")
            ),
        }
    }
}

/// Share `amount_cents` between `people`.
///
/// Exact splits always add up to the cost, and no two shares differ by more
/// than a penny. Rounding up never asks anybody for less than their exact share.
pub fn split(
    mode: CostMode,
    amount_cents: i64,
    people: usize,
    rounding: Rounding,
) -> Result<Split, SplitError> {
    if people == 0 {
        return Err(SplitError::NoPeople);
    }
    if people > MAX_PEOPLE {
        return Err(SplitError::TooManyPeople);
    }
    if amount_cents <= 0 {
        return Err(SplitError::BadAmount);
    }
    let n = people as i64;
    let split = match mode {
        CostMode::PerPlayer => {
            let total = amount_cents.checked_mul(n).ok_or(SplitError::BillTooBig)?;
            Split { shares: vec![amount_cents; people], total_cents: total, surplus_cents: 0 }
        }
        CostMode::SplitTotal => match rounding {
            Rounding::Exact => {
                let base = amount_cents / n;
                if base == 0 {
                    return Err(SplitError::BadAmount);
                }
                let extra = (amount_cents % n) as usize;
                let shares = (0..people).map(|i| base + i64::from(i < extra)).collect();
                Split { shares, total_cents: amount_cents, surplus_cents: 0 }
            }
            Rounding::Up10p => {
                let exact_up = (amount_cents + n - 1) / n; // ceiling
                let each = (exact_up + 9) / 10 * 10;
                let total = each * n;
                Split { shares: vec![each; people], total_cents: total, surplus_cents: total - amount_cents }
            }
        },
    };
    if split.shares.iter().any(|s| *s > MAX_SHARE_CENTS) {
        return Err(SplitError::ShareTooBig);
    }
    if split.total_cents > MAX_BILL_CENTS {
        return Err(SplitError::BillTooBig);
    }
    Ok(split)
}

// MARK: settling — what is paid towards what

/// A share as the ledger sees it: only live shares are passed in.
#[derive(Debug, Clone)]
pub struct LedgerShare {
    pub id: Uuid,
    pub amount_cents: i64,
    /// When its bill was sent. Payments go to the oldest share first.
    pub issued_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LedgerKind {
    /// A treasurer confirmed it, or a card payment succeeded.
    Confirmed,
    /// The member says they paid; nobody has checked yet.
    Claimed,
    /// Money the club sent back. Comes out of credit.
    Refund,
}

#[derive(Debug, Clone)]
pub struct LedgerPayment {
    pub amount_cents: i64,
    pub kind: LedgerKind,
}

/// Where one share stands.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShareState {
    Owed,
    PartPaid,
    /// Covered by a payment nobody has confirmed yet.
    Waiting,
    Paid,
    Waived,
    Void,
}

impl ShareState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Owed => "owed",
            Self::PartPaid => "part_paid",
            Self::Waiting => "waiting",
            Self::Paid => "paid",
            Self::Waived => "waived",
            Self::Void => "void",
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize)]
pub struct ShareProgress {
    pub paid_cents: i64,
    pub waiting_cents: i64,
}

impl ShareProgress {
    pub fn state(self, amount_cents: i64) -> ShareState {
        if self.paid_cents >= amount_cents {
            ShareState::Paid
        } else if self.waiting_cents > 0 && self.paid_cents + self.waiting_cents >= amount_cents {
            ShareState::Waiting
        } else if self.paid_cents > 0 || self.waiting_cents > 0 {
            ShareState::PartPaid
        } else {
            ShareState::Owed
        }
    }
}

/// One member's position with one club.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Settlement {
    pub shares: HashMap<Uuid, ShareProgress>,
    /// Still to pay: not covered by anything, confirmed or claimed.
    pub owed_cents: i64,
    /// Covered by claims nobody has confirmed yet.
    pub waiting_cents: i64,
    /// Confirmed money beyond every share, held for the next one.
    pub credit_cents: i64,
}

/// Match a member's payments to their shares, oldest share first.
///
/// Confirmed money goes first, then claimed money covers what is left, so a
/// claim can never make a share look *paid*. Nothing is stored about which
/// payment went where: it is worked out here every time, so a re-split, a
/// waived share or a cancelled bill can't leave a stale allocation behind.
pub fn settle(shares: &[LedgerShare], payments: &[LedgerPayment]) -> Settlement {
    let mut ordered: Vec<&LedgerShare> = shares.iter().collect();
    ordered.sort_by(|a, b| a.issued_at.cmp(&b.issued_at).then(a.id.cmp(&b.id)));

    let sum = |kind: LedgerKind| -> i64 {
        payments.iter().filter(|p| p.kind == kind).map(|p| p.amount_cents.max(0)).sum()
    };
    let mut confirmed = (sum(LedgerKind::Confirmed) - sum(LedgerKind::Refund)).max(0);
    let mut claimed = sum(LedgerKind::Claimed);

    let mut out = Settlement::default();
    for share in &ordered {
        let paid = share.amount_cents.min(confirmed);
        confirmed -= paid;
        out.shares.insert(share.id, ShareProgress { paid_cents: paid, waiting_cents: 0 });
    }
    out.credit_cents = confirmed;
    for share in &ordered {
        let progress = out.shares.get_mut(&share.id).expect("inserted above");
        let left = share.amount_cents - progress.paid_cents;
        let waiting = left.min(claimed);
        claimed -= waiting;
        progress.waiting_cents = waiting;
        out.waiting_cents += waiting;
        out.owed_cents += left - waiting;
    }
    out
}

// MARK: references

/// The longest base a reference is built from, leaving room for " 99".
const REFERENCE_BASE_LEN: usize = 14;

/// What a member writes in the reference box: their surname, in capitals,
/// A–Z only (banks drop everything else). Readable on purpose — players are
/// told "write SHARMA", not handed a code to copy — and the treasurer sees who
/// paid at a glance on the statement.
///
/// No usable surname (a name in Gurmukhi, say) falls back to the first name,
/// then to "PLAYER": a reference box must never be empty.
pub fn reference_base(name: &str) -> String {
    let letters = |word: &str| -> String {
        word.chars().filter(char::is_ascii_alphabetic).map(|c| c.to_ascii_uppercase()).collect()
    };
    let words: Vec<&str> = name.split_whitespace().collect();
    let base = words
        .iter()
        .rev()
        .map(|w| letters(w))
        .find(|w| !w.is_empty())
        .unwrap_or_else(|| "PLAYER".to_string());
    base[..base.len().min(REFERENCE_BASE_LEN)].to_string()
}

/// The `n`th reference for a base within one club: "SHARMA", then
/// "SHARMA 2", "SHARMA 3"… when two members share a surname. Always within the
/// 18-character Faster Payments limit.
pub fn reference_numbered(base: &str, n: u32) -> String {
    if n <= 1 { base.to_string() } else { format!("{base} {n}") }
}

// MARK: UK bank details

/// Six digits; spaces and dashes typed with it are fine.
pub fn normalise_sort_code(raw: &str) -> Result<String, &'static str> {
    let digits: String = raw.chars().filter(|c| !matches!(c, ' ' | '-')).collect();
    if digits.len() == 6 && digits.chars().all(|c| c.is_ascii_digit()) {
        Ok(digits)
    } else {
        Err("A sort code is six digits, like 12-34-56.")
    }
}

/// Eight digits. A seven-digit number (some older accounts) gets the leading
/// zero banks add themselves.
pub fn normalise_account_number(raw: &str) -> Result<String, &'static str> {
    let digits: String = raw.chars().filter(|c| !matches!(c, ' ' | '-')).collect();
    if !digits.chars().all(|c| c.is_ascii_digit()) {
        return Err("An account number is digits only.");
    }
    match digits.len() {
        8 => Ok(digits),
        7 => Ok(format!("0{digits}")),
        _ => Err("A UK account number is eight digits."),
    }
}

/// The name as the bank has it. Players' banks check it against the account
/// (Confirmation of Payee), so it is trimmed but otherwise kept as typed.
pub fn clean_holder_name(raw: &str) -> Result<String, &'static str> {
    let name = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    if name.is_empty() {
        return Err("Put the name exactly as it is on the account.");
    }
    if name.chars().count() > 70 {
        return Err("The account name can be at most 70 characters.");
    }
    let allowed = |c: char| c.is_alphanumeric() || " &'-.,/()".contains(c);
    if !name.chars().all(allowed) {
        return Err("The account name can have letters, numbers, spaces and & ' - . , / ( ) only.");
    }
    Ok(name)
}

/// "12-34-56".
pub fn fmt_sort_code(digits: &str) -> String {
    if digits.len() == 6 {
        format!("{}-{}-{}", &digits[0..2], &digits[2..4], &digits[4..6])
    } else {
        digits.to_string()
    }
}

// MARK: whether bank details may be shown

/// The account fields that decide its state.
#[derive(Debug, Clone)]
pub struct PayoutTimeline {
    pub id: Uuid,
    pub created_at: DateTime<Utc>,
    pub live_from: DateTime<Utc>,
    pub frozen_at: Option<DateTime<Utc>>,
    pub retired_at: Option<DateTime<Utc>>,
}

impl PayoutTimeline {
    /// Whether it ever went live: its time came while it was neither frozen
    /// nor removed. Once true, it has replaced everything older for good —
    /// freezing or removing it later never brings the old details back.
    fn took_over(&self, now: DateTime<Utc>) -> bool {
        self.live_from <= now
            && self.frozen_at.is_none_or(|f| f > self.live_from)
            && self.retired_at.is_none_or(|r| r > self.live_from)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PayoutState {
    /// What players are shown.
    Active,
    /// Added, waiting out its delay. Nobody pays into it yet.
    Pending,
    /// Somebody said "that wasn't me". Nobody sees it until the owner looks.
    Frozen,
    /// A newer account went live and took over.
    Superseded,
    Retired,
}

impl PayoutState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Pending => "pending",
            Self::Frozen => "frozen",
            Self::Superseded => "superseded",
            Self::Retired => "retired",
        }
    }
}

/// Each account's state at `now`, in the order given.
///
/// At most one account comes out `Active`: the newest one that is live and
/// neither frozen nor retired, provided nothing newer has taken over. A
/// change frozen *before* its time never takes over, so the old details stay
/// in place; a change frozen *after* it went live leaves nothing to pay into
/// rather than quietly bringing back details the club had replaced.
pub fn payout_states(accounts: &[PayoutTimeline], now: DateTime<Utc>) -> Vec<PayoutState> {
    let mut order: Vec<usize> = (0..accounts.len()).collect();
    order.sort_by(|&a, &b| {
        accounts[b].created_at.cmp(&accounts[a].created_at).then(accounts[b].id.cmp(&accounts[a].id))
    });
    let mut states = vec![PayoutState::Retired; accounts.len()];
    // Newest first: once something newer has taken over, older live
    // accounts are superseded whatever happened to the newer one since.
    let mut taken_over = false;
    for i in order {
        let a = &accounts[i];
        states[i] = if a.retired_at.is_some() {
            PayoutState::Retired
        } else if a.frozen_at.is_some() {
            PayoutState::Frozen
        } else if a.live_from > now {
            PayoutState::Pending
        } else if taken_over {
            PayoutState::Superseded
        } else {
            PayoutState::Active
        };
        taken_over |= a.took_over(now);
    }
    states
}

// MARK: money as people read it

/// "£6.67", "₹600.00", "€12.50", or "CHF 12.50" for anything else.
pub fn fmt_money(cents: i64, currency: &str) -> String {
    let sign = if cents < 0 { "-" } else { "" };
    let (major, minor) = (cents.abs() / 100, cents.abs() % 100);
    let symbol = match currency.to_ascii_uppercase().as_str() {
        "GBP" => "£".to_string(),
        "INR" => "₹".to_string(),
        "EUR" => "€".to_string(),
        "USD" | "AUD" | "NZD" | "CAD" => "$".to_string(),
        other => format!("{other} "),
    };
    let digits = major.to_string();
    let mut grouped = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            grouped.push(',');
        }
        grouped.push(c);
    }
    format!("{sign}{symbol}{grouped}.{minor:02}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;

    fn t(minutes: i64) -> DateTime<Utc> {
        DateTime::from_timestamp(1_763_000_000, 0).unwrap() + Duration::minutes(minutes)
    }

    // ── split ──────────────────────────────────────────────────────────

    #[test]
    fn sixty_pounds_between_nine_adds_up_to_sixty() {
        let s = split(CostMode::SplitTotal, 6_000, 9, Rounding::Exact).unwrap();
        assert_eq!(s.total_cents, 6_000);
        assert_eq!(s.shares.iter().sum::<i64>(), 6_000);
        assert_eq!(s.shares.iter().filter(|&&x| x == 667).count(), 6);
        assert_eq!(s.shares.iter().filter(|&&x| x == 666).count(), 3);
        assert_eq!(s.surplus_cents, 0);
    }

    /// The property that matters, over a spread of amounts and head counts:
    /// an exact split always adds up, and nobody pays more than a penny over
    /// anybody else.
    #[test]
    fn exact_splits_always_add_up_and_are_fair() {
        for amount in [1_i64, 7, 99, 100, 101, 999, 6_000, 6_001, 12_345, 99_999, 1_000_000] {
            for people in 1..=60 {
                match split(CostMode::SplitTotal, amount, people, Rounding::Exact) {
                    Ok(s) => {
                        assert_eq!(s.shares.iter().sum::<i64>(), amount, "{amount} / {people}");
                        let (lo, hi) = (s.shares.iter().min().unwrap(), s.shares.iter().max().unwrap());
                        assert!(hi - lo <= 1, "{amount} / {people}: {lo}..{hi}");
                        assert!(*lo > 0);
                    }
                    Err(SplitError::BadAmount) => assert!(amount < people as i64),
                    Err(SplitError::ShareTooBig) => {
                        let n = people as i64;
                        assert!((amount + n - 1) / n > MAX_SHARE_CENTS)
                    }
                    Err(e) => panic!("{amount} / {people}: {e:?}"),
                }
            }
        }
    }

    #[test]
    fn rounding_up_never_asks_for_less_than_the_exact_share() {
        for amount in [1_i64, 99, 6_000, 6_001, 12_345] {
            for people in 1..=30 {
                let s = split(CostMode::SplitTotal, amount, people, Rounding::Up10p).unwrap();
                assert!(s.shares.iter().all(|x| x % 10 == 0));
                assert!(s.total_cents >= amount);
                assert_eq!(s.total_cents - amount, s.surplus_cents);
                assert!(s.surplus_cents < 10 * people as i64);
            }
        }
        let s = split(CostMode::SplitTotal, 6_000, 9, Rounding::Up10p).unwrap();
        assert_eq!(s.shares[0], 670);
        assert_eq!(s.surplus_cents, 30);
    }

    #[test]
    fn a_per_player_fee_is_the_same_for_everyone_and_ignores_rounding() {
        let s = split(CostMode::PerPlayer, 500, 11, Rounding::Up10p).unwrap();
        assert_eq!(s.shares, vec![500; 11]);
        assert_eq!(s.total_cents, 5_500);
    }

    #[test]
    fn nobody_coming_is_refused_not_divided_by_zero() {
        assert_eq!(split(CostMode::SplitTotal, 6_000, 0, Rounding::Exact), Err(SplitError::NoPeople));
        assert_eq!(split(CostMode::PerPlayer, 500, 0, Rounding::Exact), Err(SplitError::NoPeople));
    }

    #[test]
    fn zero_negative_and_too_small_amounts_are_refused() {
        assert_eq!(split(CostMode::SplitTotal, 0, 3, Rounding::Exact), Err(SplitError::BadAmount));
        assert_eq!(split(CostMode::PerPlayer, -5, 3, Rounding::Exact), Err(SplitError::BadAmount));
        assert_eq!(split(CostMode::SplitTotal, 2, 3, Rounding::Exact), Err(SplitError::BadAmount));
    }

    #[test]
    fn typos_are_caught_by_the_limits() {
        assert_eq!(split(CostMode::PerPlayer, 100_001, 1, Rounding::Exact), Err(SplitError::ShareTooBig));
        assert_eq!(split(CostMode::PerPlayer, 60_000, 20, Rounding::Exact), Err(SplitError::BillTooBig));
        assert_eq!(split(CostMode::PerPlayer, 500, 201, Rounding::Exact), Err(SplitError::TooManyPeople));
        assert!(split(CostMode::PerPlayer, i64::MAX / 2, 3, Rounding::Exact).is_err());
    }

    // ── settle ─────────────────────────────────────────────────────────

    fn share(id: u128, amount: i64, at: i64) -> LedgerShare {
        LedgerShare { id: Uuid::from_u128(id), amount_cents: amount, issued_at: t(at) }
    }
    fn pay(amount: i64, kind: LedgerKind) -> LedgerPayment {
        LedgerPayment { amount_cents: amount, kind }
    }

    #[test]
    fn nothing_paid_is_all_owed() {
        let s = settle(&[share(1, 667, 0)], &[]);
        assert_eq!(s.owed_cents, 667);
        assert_eq!(s.shares[&Uuid::from_u128(1)].state(667), ShareState::Owed);
    }

    #[test]
    fn a_claim_makes_it_waiting_never_paid() {
        let s = settle(&[share(1, 667, 0)], &[pay(667, LedgerKind::Claimed)]);
        assert_eq!(s.owed_cents, 0);
        assert_eq!(s.waiting_cents, 667);
        assert_eq!(s.shares[&Uuid::from_u128(1)].state(667), ShareState::Waiting);
    }

    #[test]
    fn confirmed_money_pays_the_oldest_share_first() {
        let shares = [share(2, 500, 60), share(1, 667, 0)];
        let s = settle(&shares, &[pay(800, LedgerKind::Confirmed)]);
        assert_eq!(s.shares[&Uuid::from_u128(1)].state(667), ShareState::Paid);
        assert_eq!(s.shares[&Uuid::from_u128(2)].paid_cents, 133);
        assert_eq!(s.shares[&Uuid::from_u128(2)].state(500), ShareState::PartPaid);
        assert_eq!(s.owed_cents, 367);
        assert_eq!(s.credit_cents, 0);
    }

    #[test]
    fn paying_too_much_is_credit_and_it_pays_the_next_share() {
        let s = settle(&[share(1, 667, 0)], &[pay(1_000, LedgerKind::Confirmed)]);
        assert_eq!(s.credit_cents, 333);
        let s = settle(&[share(1, 667, 0), share(2, 333, 10)], &[pay(1_000, LedgerKind::Confirmed)]);
        assert_eq!(s.credit_cents, 0);
        assert_eq!(s.owed_cents, 0);
    }

    #[test]
    fn a_refund_comes_out_of_credit() {
        let s = settle(
            &[share(1, 667, 0)],
            &[pay(1_000, LedgerKind::Confirmed), pay(333, LedgerKind::Refund)],
        );
        assert_eq!(s.credit_cents, 0);
        assert_eq!(s.owed_cents, 0);
    }

    /// A share waived or a bill cancelled is simply not passed in, and what
    /// was paid towards it becomes credit with nothing to unpick.
    #[test]
    fn money_paid_towards_a_cancelled_bill_becomes_credit() {
        let s = settle(&[], &[pay(667, LedgerKind::Confirmed)]);
        assert_eq!(s.credit_cents, 667);
        assert_eq!(s.owed_cents, 0);
    }

    #[test]
    fn part_confirmed_and_part_claimed_reads_as_waiting() {
        let s = settle(
            &[share(1, 667, 0)],
            &[pay(300, LedgerKind::Confirmed), pay(367, LedgerKind::Claimed)],
        );
        let p = s.shares[&Uuid::from_u128(1)];
        assert_eq!((p.paid_cents, p.waiting_cents), (300, 367));
        assert_eq!(p.state(667), ShareState::Waiting);
    }

    #[test]
    fn a_refund_bigger_than_credit_never_goes_negative() {
        let s = settle(&[share(1, 500, 0)], &[pay(100, LedgerKind::Refund)]);
        assert_eq!(s.owed_cents, 500);
        assert_eq!(s.credit_cents, 0);
    }

    // ── references ─────────────────────────────────────────────────────

    #[test]
    fn a_reference_is_the_surname_people_can_read() {
        assert_eq!(reference_base("Aman Gill"), "GILL");
        assert_eq!(reference_base("Zoë O'Brien"), "OBRIEN");
        assert_eq!(reference_base("Jaspreet Singh-Sandhu-Wolfeschlegel"), "SINGHSANDHUWOL");
        assert_eq!(reference_base("Ravi"), "RAVI");
        // A surname with no Latin letters falls back to the first name...
        assert_eq!(reference_base("Ravi ਸ਼ਰਮਾ"), "RAVI");
        // ...and a name with none at all still gives something to write.
        assert_eq!(reference_base("ਹਰਚਰਨ ਸਿੰਘ"), "PLAYER");
        assert_eq!(reference_base("   "), "PLAYER");
    }

    #[test]
    fn two_members_with_one_surname_get_a_number_and_stay_within_eighteen() {
        assert_eq!(reference_numbered("SHARMA", 1), "SHARMA");
        assert_eq!(reference_numbered("SHARMA", 2), "SHARMA 2");
        let longest = reference_numbered(&reference_base("Aleksandrovichovski"), 99);
        assert!(longest.len() <= MAX_REFERENCE_LEN, "{longest}");
    }

    // ── bank details ───────────────────────────────────────────────────

    #[test]
    fn sort_codes_accept_how_people_type_them() {
        assert_eq!(normalise_sort_code("12-34-56").unwrap(), "123456");
        assert_eq!(normalise_sort_code("12 34 56").unwrap(), "123456");
        assert!(normalise_sort_code("12-34-5").is_err());
        assert!(normalise_sort_code("ab-cd-ef").is_err());
        assert_eq!(fmt_sort_code("123456"), "12-34-56");
    }

    #[test]
    fn account_numbers_are_eight_digits_with_seven_padded() {
        assert_eq!(normalise_account_number("12345678").unwrap(), "12345678");
        assert_eq!(normalise_account_number("1234 5678").unwrap(), "12345678");
        assert_eq!(normalise_account_number("1234567").unwrap(), "01234567");
        assert!(normalise_account_number("123456").is_err());
        assert!(normalise_account_number("123456789").is_err());
        assert!(normalise_account_number("1234567a").is_err());
    }

    #[test]
    fn holder_names_are_kept_as_typed_but_tidied() {
        assert_eq!(clean_holder_name("  Riverside   Strikers CC ").unwrap(), "Riverside Strikers CC");
        assert_eq!(clean_holder_name("A & B O'Neil-Smith").unwrap(), "A & B O'Neil-Smith");
        assert!(clean_holder_name("   ").is_err());
        assert!(clean_holder_name("Robert'); DROP TABLE--").is_err());
        assert!(clean_holder_name(&"x".repeat(71)).is_err());
    }

    // ── payout states ──────────────────────────────────────────────────

    fn acct(id: u128, created: i64, live: i64, frozen: Option<i64>, retired: Option<i64>) -> PayoutTimeline {
        PayoutTimeline {
            id: Uuid::from_u128(id),
            created_at: t(created),
            live_from: t(live),
            frozen_at: frozen.map(t),
            retired_at: retired.map(t),
        }
    }

    #[test]
    fn a_first_account_is_active_at_once() {
        assert_eq!(payout_states(&[acct(1, 0, 0, None, None)], t(1)), vec![PayoutState::Active]);
    }

    #[test]
    fn a_change_waits_and_the_old_details_stay_until_then() {
        let accounts = [acct(1, 0, 0, None, None), acct(2, 10, 10 + 24 * 60, None, None)];
        assert_eq!(payout_states(&accounts, t(60)), vec![PayoutState::Active, PayoutState::Pending]);
        assert_eq!(
            payout_states(&accounts, t(10 + 24 * 60)),
            vec![PayoutState::Superseded, PayoutState::Active]
        );
    }

    /// The whole point of the freeze: a suspicious change never takes over.
    #[test]
    fn a_change_frozen_before_its_time_never_takes_over() {
        let accounts = [acct(1, 0, 0, None, None), acct(2, 10, 20, Some(15), None)];
        assert_eq!(payout_states(&accounts, t(10_000)), vec![PayoutState::Active, PayoutState::Frozen]);
    }

    /// Frozen after it went live: the club had replaced the old details, so
    /// they don't come back. Players are told not to pay until it's sorted.
    #[test]
    fn freezing_live_details_does_not_bring_back_the_old_ones() {
        let accounts = [acct(1, 0, 0, None, None), acct(2, 10, 20, Some(500), None)];
        let states = payout_states(&accounts, t(10_000));
        assert_eq!(states, vec![PayoutState::Superseded, PayoutState::Frozen]);
        assert!(!states.contains(&PayoutState::Active));
    }

    #[test]
    fn removing_live_details_does_not_bring_back_the_old_ones() {
        let accounts = [acct(1, 0, 0, None, None), acct(2, 10, 20, None, Some(500))];
        assert_eq!(payout_states(&accounts, t(10_000)), vec![PayoutState::Superseded, PayoutState::Retired]);
    }

    #[test]
    fn cancelling_a_change_before_its_time_keeps_the_old_details() {
        let accounts = [acct(1, 0, 0, None, None), acct(2, 10, 20, None, Some(15))];
        assert_eq!(payout_states(&accounts, t(10_000)), vec![PayoutState::Active, PayoutState::Retired]);
    }

    #[test]
    fn freezing_the_only_account_leaves_nothing_to_pay_into() {
        let states = payout_states(&[acct(1, 0, 0, Some(1), None)], t(5));
        assert!(!states.contains(&PayoutState::Active));
    }

    #[test]
    fn retired_accounts_are_never_shown() {
        assert_eq!(payout_states(&[acct(1, 0, 0, None, Some(1))], t(5)), vec![PayoutState::Retired]);
    }

    // ── money ──────────────────────────────────────────────────────────

    #[test]
    fn money_reads_in_its_own_currency() {
        assert_eq!(fmt_money(667, "GBP"), "£6.67");
        assert_eq!(fmt_money(60_000, "inr"), "₹600.00");
        assert_eq!(fmt_money(5, "EUR"), "€0.05");
        assert_eq!(fmt_money(-1_250, "GBP"), "-£12.50");
        assert_eq!(fmt_money(1_250, "CHF"), "CHF 12.50");
        assert_eq!(fmt_money(100_000, "GBP"), "£1,000.00");
        assert_eq!(fmt_money(123_456_789, "GBP"), "£1,234,567.89");
    }
}
