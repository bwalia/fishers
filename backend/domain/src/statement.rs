//! A bank statement export, read for what came in and matched to the club's
//! members by their payment reference — so a treasurer ticks off a week of
//! transfers in one go instead of one by one.
//!
//! Nothing here guesses. A line is matched to a member only by their
//! reference written in it; with no reference, or two members it could be, or
//! an amount that isn't what they said they paid, the line is left for the
//! treasurer to look at. Money going out is ignored, and nothing is kept of
//! the statement but what the treasurer chooses to apply.

use std::collections::HashSet;

use chrono::{Datelike, NaiveDate};
use serde::Serialize;
use uuid::Uuid;

/// The most rows read from one statement.
pub const MAX_ROWS: usize = 5000;

/// Money in, on one line of the statement.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Credit {
    /// Its row in the file, from 1 (the header is row 1 when there is one).
    pub row: usize,
    pub date: NaiveDate,
    pub amount_cents: i64,
    /// What the bank says about it: description, reference, payer — joined.
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum StatementError {
    #[error("That file is empty.")]
    Empty,
    #[error("Couldn't find the {0} column. Export the statement as CSV from your bank and try again.")]
    NoColumn(&'static str),
    #[error("That statement is too long: export a shorter period (up to {MAX_ROWS} lines).")]
    TooLong,
}

impl StatementError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Empty => "empty_statement",
            Self::NoColumn(_) => "unknown_statement",
            Self::TooLong => "statement_too_long",
        }
    }
}

/// Split CSV text into rows of fields: quoted fields may hold the delimiter,
/// doubled quotes and line breaks.
fn records(text: &str, delimiter: char) -> Vec<Vec<String>> {
    let mut rows = Vec::new();
    let mut row = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if quoted {
            match c {
                '"' if chars.peek() == Some(&'"') => {
                    field.push('"');
                    chars.next();
                }
                '"' => quoted = false,
                _ => field.push(c),
            }
            continue;
        }
        match c {
            '"' if field.trim().is_empty() => {
                field.clear();
                quoted = true;
            }
            c if c == delimiter => row.push(std::mem::take(&mut field)),
            '\r' => {}
            '\n' => {
                row.push(std::mem::take(&mut field));
                rows.push(std::mem::take(&mut row));
            }
            _ => field.push(c),
        }
    }
    if !field.is_empty() || !row.is_empty() {
        row.push(field);
        rows.push(row);
    }
    rows.retain(|r| r.iter().any(|f| !f.trim().is_empty()));
    rows
}

fn delimiter_of(text: &str) -> char {
    let first = text.lines().find(|l| !l.trim().is_empty()).unwrap_or("");
    [',', ';', '\t']
        .into_iter()
        .max_by_key(|d| first.matches(*d).count())
        .unwrap_or(',')
}

/// An amount as the bank writes it — "£1,234.50", "-12.00", "(5.00)",
/// "500.00 CR", "250 DR" — in pence, without going through a float.
pub fn parse_amount(raw: &str) -> Option<i64> {
    let lower = raw.trim().to_lowercase();
    if lower.is_empty() {
        return None;
    }
    let mut negative = lower.starts_with('-') || (lower.starts_with('(') && lower.ends_with(')')) || lower.ends_with("dr");
    let kept: String = lower.chars().filter(|c| c.is_ascii_digit() || matches!(c, '.' | ',' | '-')).collect();
    if kept.contains('-') && !lower.starts_with('-') {
        negative = true;
    }
    let kept = kept.replace('-', "");
    // "1,234.50" and "1.234,50" are both £1,234.50; "6,00" is £6 and
    // "1,234" is £1,234.
    let digits = match (kept.rfind(','), kept.rfind('.')) {
        (Some(c), Some(p)) if c > p => kept.replace('.', "").replace(',', "."),
        (Some(_), Some(_)) => kept.replace(',', ""),
        (Some(c), None) if kept.matches(',').count() == 1 && kept.len() - c - 1 == 2 => kept.replace(',', "."),
        _ => kept.replace(',', ""),
    };
    let (whole, frac) = match digits.split_once('.') {
        Some((w, f)) => (w, f),
        None => (digits.as_str(), ""),
    };
    if whole.is_empty() && frac.is_empty() || frac.contains('.') || frac.len() > 2 {
        return None;
    }
    let whole: i64 = if whole.is_empty() { 0 } else { whole.parse().ok()? };
    let frac: i64 = match frac.len() {
        0 => 0,
        1 => frac.parse::<i64>().ok()? * 10,
        _ => frac.parse().ok()?,
    };
    let cents = whole.checked_mul(100)?.checked_add(frac)?;
    Some(if negative { -cents } else { cents })
}

/// A date as UK and Indian banks write it (day first), with or without a
/// time after it.
pub fn parse_date(raw: &str) -> Option<NaiveDate> {
    let raw = raw.trim();
    const FORMATS: [&str; 12] = [
        "%d/%m/%Y", "%d/%m/%y", "%Y-%m-%d", "%d-%m-%Y", "%d-%m-%y", "%d.%m.%Y", "%d %b %Y", "%d %B %Y", "%d-%b-%Y",
        "%d-%b-%y", "%d %b %y", "%Y/%m/%d",
    ];
    let candidates = [raw, raw.split(['T', ' ']).next().unwrap_or(raw)];
    for c in candidates {
        for f in FORMATS {
            // "%Y" reads "26" as the year 26: leave that to "%y".
            if let Some(d) = NaiveDate::parse_from_str(c, f).ok().filter(|d| d.year() >= 1900) {
                return Some(d);
            }
        }
    }
    // "21 Nov 2026 10:31": the date is the first three words.
    let words: Vec<&str> = raw.split_whitespace().take(3).collect();
    if words.len() == 3 {
        let joined = words.join(" ");
        for f in ["%d %b %Y", "%d %B %Y"] {
            if let Some(d) = NaiveDate::parse_from_str(&joined, f).ok().filter(|d| d.year() >= 1900) {
                return Some(d);
            }
        }
    }
    None
}

struct Columns {
    date: usize,
    text: Vec<usize>,
    /// A paid-in column; or, with none, a signed amount column.
    credit: Option<usize>,
    amount: Option<usize>,
}

fn columns(header: &[String]) -> Option<Columns> {
    let names: Vec<String> = header.iter().map(|h| h.trim().to_lowercase()).collect();
    let find = |pred: &dyn Fn(&str) -> bool| names.iter().position(|n| pred(n));
    let date = find(&|n| n == "date")
        .or_else(|| find(&|n| n.contains("transaction date") || n.contains("txn date") || n == "posting date"))
        .or_else(|| find(&|n| n.contains("date") && !n.contains("value")))?;
    let credit = find(&|n| {
        n.contains("paid in") || n.contains("money in") || n.contains("credit amount") || n == "credit"
            || n == "credits" || n == "in" || n.contains("deposit")
    });
    let amount = find(&|n| n == "amount" || n.starts_with("amount (") || n.starts_with("amount(") || n == "value"
        || n.contains("transaction amount"));
    if credit.is_none() && amount.is_none() {
        return None;
    }
    let text: Vec<usize> = names
        .iter()
        .enumerate()
        .filter(|(_, n)| {
            !n.contains("account")
                && ["description", "narration", "details", "reference", "memo", "counter party", "counterparty",
                    "name", "payee", "particulars", "notes"]
                    .iter()
                    .any(|k| n.contains(k))
        })
        .map(|(i, _)| i)
        .collect();
    Some(Columns { date, text, credit, amount })
}

/// The money that came in, from a statement exported as CSV.
pub fn read_credits(csv: &str) -> Result<Vec<Credit>, StatementError> {
    let csv = csv.trim_start_matches('\u{feff}');
    if csv.trim().is_empty() {
        return Err(StatementError::Empty);
    }
    let rows = records(csv, delimiter_of(csv));
    if rows.len() > MAX_ROWS + 10 {
        return Err(StatementError::TooLong);
    }
    // The header is the first of the opening rows that names the columns we
    // need: some banks put the account's details above it.
    let (header_at, cols) = rows
        .iter()
        .take(10)
        .enumerate()
        .find_map(|(i, r)| columns(r).map(|c| (i, c)))
        .ok_or(StatementError::NoColumn("date and amount"))?;
    if cols.text.is_empty() {
        return Err(StatementError::NoColumn("description"));
    }
    let mut out = Vec::new();
    for (i, r) in rows.iter().enumerate().skip(header_at + 1) {
        let get = |c: usize| r.get(c).map(String::as_str).unwrap_or("");
        let Some(date) = parse_date(get(cols.date)) else { continue };
        let amount = match (cols.credit, cols.amount) {
            (Some(c), _) => parse_amount(get(c)),
            (None, Some(a)) => parse_amount(get(a)),
            (None, None) => None,
        };
        let Some(amount) = amount.filter(|a| *a > 0) else { continue };
        let text = cols
            .text
            .iter()
            .map(|c| get(*c).trim())
            .filter(|t| !t.is_empty())
            .collect::<Vec<_>>()
            .join(" ");
        out.push(Credit { row: i + 1, date, amount_cents: amount, text });
    }
    Ok(out)
}

/// Upper case, letters and digits only, single spaces, padded — so a
/// reference matches as whole words.
fn words(text: &str) -> String {
    let cleaned: String = text
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_uppercase() } else { ' ' })
        .collect();
    format!(" {} ", cleaned.split_whitespace().collect::<Vec<_>>().join(" "))
}

/// A member's reference with the club.
#[derive(Debug, Clone)]
pub struct Reference {
    pub code: String,
    pub user_id: Uuid,
}

/// "I've paid" by bank transfer, not yet ticked.
#[derive(Debug, Clone)]
pub struct OpenClaim {
    pub payment_id: Uuid,
    pub user_id: Uuid,
    pub amount_cents: i64,
    pub on: NaiveDate,
    /// Whose reference the money comes with: the member's own, or — when
    /// somebody paid for them — the payer's.
    pub payer: Uuid,
    /// Claims made in one go (a parent paying for two juniors) share this:
    /// the bank shows them as one transfer, of their total.
    pub batch: String,
}

/// What to do with one line.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum Proposal {
    /// It's the money somebody said they'd sent: tick their "I've paid" —
    /// several when one transfer paid for several people.
    Confirm { payment_ids: Vec<Uuid>, user_id: Uuid },
    /// Their reference, and they hadn't said: record it as paid.
    Record { user_id: Uuid },
    /// Their reference, but something doesn't add up: a person should look.
    Check { user_id: Option<Uuid>, why: CheckWhy },
    /// No member's reference in it.
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CheckWhy {
    /// They said they paid a different amount.
    DifferentAmount,
    /// Two members share the surname, and the number was left off.
    SharedName,
}

/// How far a bank line's date may be from the "I've paid" it matches.
const CLAIM_DAYS: i64 = 21;

/// The reference written in a line, longest first, so "SHARMA 2" wins over
/// "SHARMA".
fn reference_in<'a>(text: &str, refs: &'a [Reference]) -> Option<&'a Reference> {
    let text = words(text);
    let mut sorted: Vec<&Reference> = refs.iter().collect();
    sorted.sort_by_key(|r| std::cmp::Reverse(r.code.len()));
    sorted.into_iter().find(|r| text.contains(&words(&r.code)))
}

/// What to do with each line, in order. Each "I've paid" (or batch of them,
/// made in one go) is matched to one line at most: the nearest in date whose
/// total is the line's amount.
pub fn propose(credits: &[Credit], refs: &[Reference], claims: &[OpenClaim]) -> Vec<Proposal> {
    let mut used: HashSet<Uuid> = HashSet::new();
    credits
        .iter()
        .map(|c| {
            let Some(r) = reference_in(&c.text, refs) else { return Proposal::Unknown };
            // "SHARMA" written where there's also a "SHARMA 2": whoever of
            // them said they sent exactly this, or a person decides.
            let siblings: Vec<&Reference> = refs
                .iter()
                .filter(|o| o.user_id != r.user_id && o.code.starts_with(&format!("{} ", r.code)))
                .collect();
            let candidates: Vec<Uuid> = std::iter::once(r.user_id).chain(siblings.iter().map(|s| s.user_id)).collect();
            // A payer's unticked batches whose total is this line's amount,
            // nearest in date first.
            let exact = |payer: Uuid, used: &HashSet<Uuid>| -> Option<Vec<Uuid>> {
                let mut batches: Vec<(&str, i64, i64, Vec<Uuid>)> = Vec::new();
                for k in claims.iter().filter(|k| k.payer == payer && !used.contains(&k.payment_id)) {
                    let gap = (k.on - c.date).num_days().abs();
                    match batches.iter_mut().find(|b| b.0 == k.batch) {
                        Some(b) => {
                            b.1 += k.amount_cents;
                            b.2 = b.2.min(gap);
                            b.3.push(k.payment_id);
                        }
                        None => batches.push((k.batch.as_str(), k.amount_cents, gap, vec![k.payment_id])),
                    }
                }
                batches
                    .into_iter()
                    .filter(|b| b.1 == c.amount_cents && b.2 <= CLAIM_DAYS)
                    .min_by_key(|b| b.2)
                    .map(|b| b.3)
            };
            if !siblings.is_empty() {
                let hits: Vec<(Uuid, Vec<Uuid>)> =
                    candidates.iter().filter_map(|u| exact(*u, &used).map(|p| (*u, p))).collect();
                return match hits.as_slice() {
                    [(user_id, ids)] => {
                        used.extend(ids.iter().copied());
                        Proposal::Confirm { payment_ids: ids.clone(), user_id: *user_id }
                    }
                    _ => Proposal::Check { user_id: None, why: CheckWhy::SharedName },
                };
            }
            if let Some(ids) = exact(r.user_id, &used) {
                used.extend(ids.iter().copied());
                return Proposal::Confirm { payment_ids: ids, user_id: r.user_id };
            }
            let waiting = claims.iter().any(|k| k.payer == r.user_id && !used.contains(&k.payment_id));
            if waiting {
                Proposal::Check { user_id: Some(r.user_id), why: CheckWhy::DifferentAmount }
            } else {
                Proposal::Record { user_id: r.user_id }
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(s: &str) -> NaiveDate {
        NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap()
    }

    #[test]
    fn amounts_as_banks_write_them() {
        assert_eq!(parse_amount("£1,234.50"), Some(123_450));
        assert_eq!(parse_amount("15"), Some(1500));
        assert_eq!(parse_amount("15.5"), Some(1550));
        assert_eq!(parse_amount("-12.00"), Some(-1200));
        assert_eq!(parse_amount("(5.00)"), Some(-500));
        assert_eq!(parse_amount("500.00 CR"), Some(50_000));
        assert_eq!(parse_amount("250.00 Dr"), Some(-25_000));
        assert_eq!(parse_amount("₹ 1,500.00"), Some(150_000));
        assert_eq!(parse_amount(""), None);
        assert_eq!(parse_amount("1.2.3"), None);
        assert_eq!(parse_amount("1.234"), None);
        assert_eq!(parse_amount("6,00"), Some(600));
        assert_eq!(parse_amount("1.234,50"), Some(123_450));
        assert_eq!(parse_amount("1,234"), Some(123_400));
    }

    #[test]
    fn dates_day_first() {
        assert_eq!(parse_date("21/11/2026"), Some(d("2026-11-21")));
        assert_eq!(parse_date("21/11/26"), Some(d("2026-11-21")));
        assert_eq!(parse_date("2026-11-21"), Some(d("2026-11-21")));
        assert_eq!(parse_date("2026-11-21T10:31:00Z"), Some(d("2026-11-21")));
        assert_eq!(parse_date("21 Nov 2026"), Some(d("2026-11-21")));
        assert_eq!(parse_date("21-Nov-26"), Some(d("2026-11-21")));
        assert_eq!(parse_date("21 Nov 2026 10:31"), Some(d("2026-11-21")));
        assert_eq!(parse_date("Balance"), None);
    }

    #[test]
    fn lloyds_style_with_separate_columns() {
        let csv = "Transaction Date,Transaction Type,Sort Code,Account Number,Transaction Description,Debit Amount,Credit Amount,Balance\n\
                   21/11/2026,FPI,'30-00-00,12345678,R SHARMA SHARMA,,15.00,215.00\n\
                   20/11/2026,DEB,'30-00-00,12345678,NETS HIRE LTD,60.00,,200.00\n";
        let c = read_credits(csv).unwrap();
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].amount_cents, 1500);
        assert_eq!(c[0].text, "R SHARMA SHARMA");
        assert_eq!(c[0].date, d("2026-11-21"));
    }

    #[test]
    fn starling_style_signed_amount_and_quotes() {
        let csv = "Date,Counter Party,Reference,Type,Amount (GBP),Balance (GBP)\n\
                   21/11/2026,\"Gill, Neha\",GILL,FASTER PAYMENT,9.00,100.00\n\
                   21/11/2026,Kit Shop,\"Order 1\",CARD,-40.00,91.00\n";
        let c = read_credits(csv).unwrap();
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].text, "Gill, Neha GILL");
        assert_eq!(c[0].amount_cents, 900);
    }

    #[test]
    fn monzo_prefers_money_in_and_skips_account_columns() {
        let csv = "Transaction ID,Date,Time,Type,Name,Amount,Currency,Notes and #tags,Description,Money Out,Money In,Account Name\n\
                   tx_1,21/11/2026,10:00,Faster payment,Josh Turner,5.00,GBP,,TURNER,,5.00,GILL CLUB\n";
        let c = read_credits(csv).unwrap();
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].text, "Josh Turner TURNER");
    }

    #[test]
    fn header_below_account_details_semicolons_and_bom() {
        let csv = "\u{feff}Account;12345678\n\nDate;Description;Paid in;Paid out\n21/11/2026;BENNETT;6,00;\n";
        let c = read_credits(csv).unwrap();
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].text, "BENNETT");
        assert_eq!(c[0].amount_cents, 600, "a decimal comma");
    }

    #[test]
    fn no_columns_says_so() {
        assert_eq!(read_credits(""), Err(StatementError::Empty));
        assert!(matches!(read_credits("a,b,c\n1,2,3\n"), Err(StatementError::NoColumn(_))));
    }

    fn uid(n: u8) -> Uuid {
        Uuid::from_bytes([n; 16])
    }

    fn claim(id: u8, user: Uuid, cents: i64, on: &str) -> OpenClaim {
        OpenClaim { payment_id: uid(id), user_id: user, amount_cents: cents, on: d(on), payer: user, batch: format!("b{id}") }
    }

    #[test]
    fn a_parent_paying_for_two_is_one_transfer_under_their_reference() {
        let (neha, jas, arjun) = (uid(1), uid(2), uid(3));
        let refs = vec![
            Reference { code: "GILL".into(), user_id: neha },
            Reference { code: "GILL 2".into(), user_id: jas },
        ];
        let batch = |id: u8, user: Uuid, cents: i64| OpenClaim {
            payment_id: uid(id),
            user_id: user,
            amount_cents: cents,
            on: d("2026-11-21"),
            payer: neha,
            batch: "neha-once".into(),
        };
        let claims = vec![batch(21, jas, 900), batch(22, arjun, 600)];
        // "GILL" with a "GILL 2" about: the one batch that adds up decides it.
        let p = propose(&[credit("N GILL GILL", 1500)], &refs, &claims);
        assert_eq!(p[0], Proposal::Confirm { payment_ids: vec![uid(21), uid(22)], user_id: neha });
        // Part of it isn't a match: somebody looks.
        let p = propose(&[credit("N GILL GILL", 900)], &refs, &claims);
        assert_eq!(p[0], Proposal::Check { user_id: None, why: CheckWhy::SharedName });
    }

    fn credit(text: &str, cents: i64) -> Credit {
        Credit { row: 2, date: d("2026-11-21"), amount_cents: cents, text: text.into() }
    }

    #[test]
    fn matching_by_reference() {
        let (ravi, rohit, josh, tom) = (uid(1), uid(2), uid(3), uid(4));
        let refs = vec![
            Reference { code: "SHARMA".into(), user_id: ravi },
            Reference { code: "SHARMA 2".into(), user_id: rohit },
            Reference { code: "TURNER".into(), user_id: josh },
            Reference { code: "BENNETT".into(), user_id: tom },
        ];
        let claims = vec![
            claim(11, rohit, 1500, "2026-11-20"),
            claim(13, josh, 500, "2026-11-21"),
            claim(14, tom, 600, "2026-11-21"),
        ];
        let lines = vec![
            credit("ROHIT SHARMA SHARMA 2", 1500),   // the numbered one wins
            credit("J TURNER turner", 500),          // his "I've paid"
            credit("J TURNER turner", 500),          // the same again: no claim left → recorded
            credit("BENNETT", 900),                  // said £6, sent £9
            credit("SHARMA", 1000),                  // two Sharmas, no number, no matching claim
            credit("INTEREST", 12),                  // nobody's
        ];
        let p = propose(&lines, &refs, &claims);
        assert_eq!(p[0], Proposal::Confirm { payment_ids: vec![uid(11)], user_id: rohit });
        assert_eq!(p[1], Proposal::Confirm { payment_ids: vec![uid(13)], user_id: josh });
        assert_eq!(p[2], Proposal::Record { user_id: josh });
        assert_eq!(p[3], Proposal::Check { user_id: Some(tom), why: CheckWhy::DifferentAmount });
        assert_eq!(p[4], Proposal::Check { user_id: None, why: CheckWhy::SharedName });
        assert_eq!(p[5], Proposal::Unknown);
    }

    #[test]
    fn shared_name_settled_by_one_exact_claim() {
        let (ravi, rohit) = (uid(1), uid(2));
        let refs = vec![
            Reference { code: "SHARMA".into(), user_id: ravi },
            Reference { code: "SHARMA 2".into(), user_id: rohit },
        ];
        let claims = vec![claim(11, rohit, 1500, "2026-11-20")];
        let p = propose(&[credit("SHARMA", 1500)], &refs, &claims);
        assert_eq!(p[0], Proposal::Confirm { payment_ids: vec![uid(11)], user_id: rohit });
    }

    #[test]
    fn a_claim_too_far_away_in_time_is_not_matched() {
        let josh = uid(3);
        let refs = vec![Reference { code: "TURNER".into(), user_id: josh }];
        let claims = vec![claim(13, josh, 500, "2026-09-01")];
        let p = propose(&[credit("TURNER", 500)], &refs, &claims);
        assert_eq!(p[0], Proposal::Check { user_id: Some(josh), why: CheckWhy::DifferentAmount });
    }

    #[test]
    fn a_surname_inside_another_word_does_not_match() {
        let refs = vec![Reference { code: "GILL".into(), user_id: uid(1) }];
        let p = propose(&[credit("GILLINGHAM FC", 500)], &refs, &[]);
        assert_eq!(p[0], Proposal::Unknown);
    }
}
