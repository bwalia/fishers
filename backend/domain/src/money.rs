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
    /// Paid after everything else: a monthly pass charge the member's
    /// standing order is about to pay. Money paid by hand goes to what's
    /// owed by hand first, so the standing order isn't left overpaying.
    pub last: bool,
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
    /// A payment made for one share (from a pay link, cash at the ground, a
    /// standing order's month) goes to that share first; the rest of it, and
    /// every other payment, oldest share first.
    pub share: Option<Uuid>,
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
    /// Covered by a pass, or a free price type: on the bill, owing nothing.
    Covered,
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
            Self::Covered => "covered",
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
    ordered.sort_by(|a, b| a.last.cmp(&b.last).then(a.issued_at.cmp(&b.issued_at)).then(a.id.cmp(&b.id)));
    let at: HashMap<Uuid, usize> = ordered.iter().enumerate().map(|(i, s)| (s.id, i)).collect();
    let mut paid = vec![0i64; ordered.len()];
    let mut waiting = vec![0i64; ordered.len()];

    // Money for one share goes to it first (up to what it owes); what's left
    // of it joins everything else, which goes oldest share first.
    let earmark = |kind: LedgerKind, room: &dyn Fn(usize) -> i64, into: &mut Vec<i64>| -> i64 {
        let mut pool = 0;
        for p in payments.iter().filter(|p| p.kind == kind) {
            let amount = p.amount_cents.max(0);
            match p.share.and_then(|s| at.get(&s)).copied() {
                Some(i) => {
                    let take = amount.min((room(i) - into[i]).max(0));
                    into[i] += take;
                    pool += amount - take;
                }
                None => pool += amount,
            }
        }
        pool
    };
    let amount_of = |i: usize| ordered[i].amount_cents;
    let refunds: i64 = payments.iter().filter(|p| p.kind == LedgerKind::Refund).map(|p| p.amount_cents.max(0)).sum();
    let mut confirmed = (earmark(LedgerKind::Confirmed, &amount_of, &mut paid) - refunds).max(0);
    for i in 0..ordered.len() {
        let take = (ordered[i].amount_cents - paid[i]).max(0).min(confirmed);
        paid[i] += take;
        confirmed -= take;
    }
    let paid_now = paid.clone();
    let room_left = |i: usize| ordered[i].amount_cents - paid_now[i];
    let mut claimed = earmark(LedgerKind::Claimed, &room_left, &mut waiting);
    for i in 0..ordered.len() {
        let take = (ordered[i].amount_cents - paid[i] - waiting[i]).max(0).min(claimed);
        waiting[i] += take;
        claimed -= take;
    }

    let mut out = Settlement { credit_cents: confirmed, ..Default::default() };
    for (i, share) in ordered.iter().enumerate() {
        out.shares.insert(share.id, ShareProgress { paid_cents: paid[i], waiting_cents: waiting[i] });
        out.waiting_cents += waiting[i];
        out.owed_cents += share.amount_cents - paid[i] - waiting[i];
    }
    out
}

/// Which shares each confirmed payment paid: shares oldest first, payments in
/// the order given (the order they were made). For saying what a payment was
/// for — the line it goes on in the club's books — never for what is owed,
/// which [`settle`] decides. Money beyond every share is left unallocated.
pub fn allocate(shares: &[LedgerShare], payments: &[(Uuid, i64)]) -> HashMap<Uuid, Vec<(Uuid, i64)>> {
    let mut ordered: Vec<&LedgerShare> = shares.iter().collect();
    ordered.sort_by(|a, b| a.last.cmp(&b.last).then(a.issued_at.cmp(&b.issued_at)).then(a.id.cmp(&b.id)));
    let mut left: Vec<i64> = ordered.iter().map(|s| s.amount_cents.max(0)).collect();
    let mut at = 0;
    let mut out: HashMap<Uuid, Vec<(Uuid, i64)>> = HashMap::new();
    for (payment, amount) in payments {
        let mut money = (*amount).max(0);
        let lines = out.entry(*payment).or_default();
        while money > 0 && at < ordered.len() {
            let take = money.min(left[at]);
            if take > 0 {
                lines.push((ordered[at].id, take));
                money -= take;
                left[at] -= take;
            }
            if left[at] == 0 {
                at += 1;
            }
        }
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

// MARK: passes

/// How a pass is paid.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PassBilling {
    /// One payment.
    Once,
    /// A payment every month, by the player's standing order, until cancelled.
    Monthly,
    /// A fixed number of monthly payments.
    Instalments,
}

impl PassBilling {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Once => "once",
            Self::Monthly => "monthly",
            Self::Instalments => "instalments",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "once" => Some(Self::Once),
            "monthly" => Some(Self::Monthly),
            "instalments" => Some(Self::Instalments),
            _ => None,
        }
    }
}

/// The session kinds a pass can cover (the `event_subtype` values).
pub const PASS_COVERABLE: [&str; 7] = ["nets", "training", "friendly", "league_match", "tournament", "social", "generic"];

/// How many days a charge may be unpaid before it counts against a pass.
pub const PASS_GRACE_DAYS: i64 = 7;

/// `months` months after `start`, on the same day where the month has it and
/// on its last day where it doesn't: a pass started on 31 January is next due
/// on 28 (or 29) February, then 31 March.
pub fn add_months(start: chrono::NaiveDate, months: u32) -> chrono::NaiveDate {
    start.checked_add_months(chrono::Months::new(months)).unwrap_or(start)
}

/// The days a pass's monthly charges fall on, from `started_on` up to and
/// including `today`, and no later than `ends_on`. Months run from the day it
/// started, so nobody pays for part of a month.
pub fn monthly_periods(
    started_on: chrono::NaiveDate,
    today: chrono::NaiveDate,
    ends_on: Option<chrono::NaiveDate>,
) -> Vec<chrono::NaiveDate> {
    let mut out = Vec::new();
    for k in 0..240u32 {
        let day = add_months(started_on, k);
        if day > today || ends_on.is_some_and(|end| day > end) {
            break;
        }
        out.push(day);
    }
    out
}

/// The days instalments fall on: `n` of them, a month apart, from the start.
pub fn instalment_days(started_on: chrono::NaiveDate, n: u32) -> Vec<chrono::NaiveDate> {
    (0..n).map(|k| add_months(started_on, k)).collect()
}

/// Whether a pass holder is up to date with its charges.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PassStanding {
    /// Paid up, or not yet past the grace period.
    UpToDate,
    /// One charge overdue: still covering, and told so.
    Behind,
    /// Too far behind: sessions are billed as usual until it's paid up.
    Suspended,
}

/// From how many charges are unpaid past the grace period. A one-off pass
/// stops covering as soon as its one payment is overdue; a monthly or
/// instalment pass after two missed months. A secretary can keep it covering.
pub fn pass_standing(billing: PassBilling, overdue: usize, keep_covering: bool) -> PassStanding {
    let limit = match billing {
        PassBilling::Once => 1,
        PassBilling::Monthly | PassBilling::Instalments => 2,
    };
    if overdue == 0 {
        PassStanding::UpToDate
    } else if overdue < limit || keep_covering {
        PassStanding::Behind
    } else {
        PassStanding::Suspended
    }
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

/// Whether the name on a bank account is plausibly this person's: the same
/// surname and the same first initial, titles ignored. "MR A GILL" is Aman
/// Gill; "Neha Gill" isn't. Used to say "Aman Gill, the club treasurer" only
/// when the account really is the treasurer's own.
pub fn same_person(holder_name: &str, name: &str) -> bool {
    fn words(s: &str) -> Vec<String> {
        s.split(|c: char| !c.is_alphabetic())
            .filter(|w| !w.is_empty())
            .map(str::to_lowercase)
            .filter(|w| !matches!(w.as_str(), "mr" | "mrs" | "ms" | "miss" | "mx" | "dr"))
            .collect()
    }
    let (a, b) = (words(holder_name), words(name));
    match (a.first(), a.last(), b.first(), b.last()) {
        (Some(af), Some(al), Some(bf), Some(bl)) if a.len() > 1 && b.len() > 1 => {
            al == bl && af.chars().next() == bf.chars().next()
        }
        _ => false,
    }
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
        LedgerShare { id: Uuid::from_u128(id), amount_cents: amount, issued_at: t(at), last: false }
    }
    fn pay(amount: i64, kind: LedgerKind) -> LedgerPayment {
        LedgerPayment { amount_cents: amount, kind, share: None }
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

    // ── passes ─────────────────────────────────────────────────────────

    fn d(y: i32, m: u32, day: u32) -> chrono::NaiveDate {
        chrono::NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    #[test]
    fn monthly_charges_run_from_the_day_it_started() {
        let p = monthly_periods(d(2026, 11, 14), d(2027, 2, 14), None);
        assert_eq!(p, vec![d(2026, 11, 14), d(2026, 12, 14), d(2027, 1, 14), d(2027, 2, 14)]);
        assert_eq!(monthly_periods(d(2026, 11, 14), d(2026, 12, 13), None), vec![d(2026, 11, 14)]);
    }

    /// Started on the 31st: the last day of short months, then the 31st again.
    #[test]
    fn a_pass_started_on_the_31st_is_due_on_the_last_day_of_short_months() {
        let p = monthly_periods(d(2027, 1, 31), d(2027, 4, 30), None);
        assert_eq!(p, vec![d(2027, 1, 31), d(2027, 2, 28), d(2027, 3, 31), d(2027, 4, 30)]);
    }

    #[test]
    fn a_cancelled_pass_is_not_charged_after_it_ends() {
        let p = monthly_periods(d(2026, 11, 14), d(2027, 6, 1), Some(d(2027, 1, 13)));
        assert_eq!(p, vec![d(2026, 11, 14), d(2026, 12, 14)]);
    }

    #[test]
    fn instalments_are_a_month_apart() {
        assert_eq!(instalment_days(d(2026, 4, 1), 3), vec![d(2026, 4, 1), d(2026, 5, 1), d(2026, 6, 1)]);
    }

    #[test]
    fn a_one_off_pass_stops_at_its_first_overdue_payment() {
        assert_eq!(pass_standing(PassBilling::Once, 0, false), PassStanding::UpToDate);
        assert_eq!(pass_standing(PassBilling::Once, 1, false), PassStanding::Suspended);
        assert_eq!(pass_standing(PassBilling::Once, 1, true), PassStanding::Behind);
    }

    #[test]
    fn a_monthly_pass_stops_after_two_missed_months() {
        assert_eq!(pass_standing(PassBilling::Monthly, 1, false), PassStanding::Behind);
        assert_eq!(pass_standing(PassBilling::Monthly, 2, false), PassStanding::Suspended);
        assert_eq!(pass_standing(PassBilling::Instalments, 3, true), PassStanding::Behind, "the secretary's override");
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
    #[test]
    fn same_person_matches_bank_style_names() {
        assert!(same_person("MR A GILL", "Aman Gill"));
        assert!(same_person("Aman Singh Gill", "Aman Gill"));
        assert!(same_person("aman gill", "Aman Gill"));
        assert!(!same_person("Neha Gill", "Aman Gill"));
        assert!(!same_person("Riverside CC", "Aman Gill"));
        assert!(!same_person("Gill", "Aman Gill"));
        assert!(!same_person("", "Aman Gill"));
    }
    #[test]
    fn allocate_pays_oldest_shares_first_in_payment_order() {
        let t = |h: i64| Utc::now() - chrono::Duration::hours(h);
        let (a, b, c) = (Uuid::from_bytes([1; 16]), Uuid::from_bytes([2; 16]), Uuid::from_bytes([3; 16]));
        let shares = vec![
            LedgerShare { id: b, amount_cents: 600, issued_at: t(1), last: false },
            LedgerShare { id: a, amount_cents: 500, issued_at: t(5), last: false },
        ];
        let (p1, p2, p3) = (Uuid::from_bytes([11; 16]), Uuid::from_bytes([12; 16]), Uuid::from_bytes([13; 16]));
        let got = allocate(&shares, &[(p1, 700), (p2, 300), (p3, 900)]);
        assert_eq!(got[&p1], vec![(a, 500), (b, 200)]);
        assert_eq!(got[&p2], vec![(b, 300)]);
        assert_eq!(got[&p3], vec![(b, 100)], "the rest is credit, unallocated");
        let _ = c;
    }
    #[test]
    fn a_standing_orders_month_is_paid_last_and_its_own_money_goes_to_it() {
        // November's pass charge (the standing order's), issued first; then a
        // match and a group fee, owed by hand.
        let pass = LedgerShare { id: Uuid::from_u128(1), amount_cents: 2000, issued_at: t(30), last: true };
        let shares = vec![pass.clone(), share(2, 2500, 20), share(3, 562, 10)];
        // He pays what he owes by hand: it all goes to the match and the fee.
        let by_hand = settle(&shares, &[pay(3062, LedgerKind::Confirmed)]);
        assert_eq!(by_hand.shares[&Uuid::from_u128(1)].paid_cents, 0);
        assert_eq!(by_hand.owed_cents, 2000, "only the standing order's month is left");
        // The standing order's money, earmarked for the month, pays it — even
        // arriving before he's paid the rest.
        let so = LedgerPayment { amount_cents: 2000, kind: LedgerKind::Confirmed, share: Some(Uuid::from_u128(1)) };
        let first = settle(&shares, std::slice::from_ref(&so));
        assert_eq!(first.shares[&Uuid::from_u128(1)].paid_cents, 2000);
        assert_eq!(first.owed_cents, 3062);
        let both = settle(&shares, &[so, pay(3062, LedgerKind::Confirmed)]);
        assert_eq!((both.owed_cents, both.credit_cents), (0, 0));
    }

    #[test]
    fn an_earmarked_claim_waits_on_its_own_share() {
        let shares = vec![share(1, 500, 30), share(2, 500, 10)];
        let claim = LedgerPayment { amount_cents: 500, kind: LedgerKind::Claimed, share: Some(Uuid::from_u128(2)) };
        let s = settle(&shares, &[claim]);
        assert_eq!(s.shares[&Uuid::from_u128(2)].waiting_cents, 500);
        assert_eq!(s.shares[&Uuid::from_u128(1)].waiting_cents, 0);
        // More than the share owes: the rest goes oldest first.
        let big = LedgerPayment { amount_cents: 800, kind: LedgerKind::Confirmed, share: Some(Uuid::from_u128(2)) };
        let s = settle(&shares, &[big]);
        assert_eq!((s.shares[&Uuid::from_u128(2)].paid_cents, s.shares[&Uuid::from_u128(1)].paid_cents), (500, 300));
    }
}
