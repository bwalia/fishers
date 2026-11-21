//! Bank statement import (step D of docs/CLUB_PAYMENTS_V2_PLAN.md): the
//! treasurer exports their bank statement as CSV, sees what each payment in
//! it matches, and ticks the lot in one go.
//!
//! Money admins only. The statement is read in memory and never stored — it
//! holds the club's other banking too. What's kept is a fingerprint of each
//! line applied, so importing the same statement twice changes nothing, and
//! the payments those lines became.

use std::collections::{HashMap, HashSet};

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use chrono::NaiveDate;
use fishers_db::repos::club_payments::{self as repo, NewPayment};
use fishers_domain::money::fmt_money;
use fishers_domain::statement::{self, CheckWhy, Credit, OpenClaim, Proposal, Reference};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use uuid::Uuid;

use super::club_payments::{accounts, decide, require_money_admin, status};
use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/clubs/{id}/statement/preview", post(preview))
        .route("/clubs/{id}/statement/apply", post(apply))
}

#[derive(Debug, Serialize)]
struct Line {
    /// Stable for this line of this statement: send it back to apply it.
    hash: String,
    row: usize,
    date: NaiveDate,
    amount_cents: i64,
    /// What the bank wrote, for the treasurer to recognise it.
    text: String,
    /// `confirm` (tick their "I've paid"), `record` (paid without saying),
    /// `check` (look at it yourself), `unknown` (nobody's reference) or
    /// `already` (applied before).
    action: &'static str,
    /// Whose reference it carries.
    user_id: Option<Uuid>,
    name: Option<String>,
    /// For `confirm`: the "I've paid"s it ticks — several when one transfer
    /// paid for several people (a parent for two juniors).
    payment_ids: Vec<Uuid>,
    /// For `check`: `different_amount` or `shared_name`.
    why: Option<CheckWhy>,
}

#[derive(Debug, Serialize, Default)]
struct Summary {
    credits: usize,
    confirm: usize,
    record: usize,
    check: usize,
    unknown: usize,
    already: usize,
}

#[derive(Debug, Serialize)]
struct Preview {
    currency: String,
    summary: Summary,
    lines: Vec<Line>,
}

/// A line's fingerprint: the club, its date, amount and words, and which
/// copy it is of identical lines in the file (two £5 transfers from one
/// person on one day are two lines).
fn fingerprint(club_id: Uuid, c: &Credit, copy: usize) -> String {
    let words = c.text.split_whitespace().collect::<Vec<_>>().join(" ").to_uppercase();
    let digest = Sha256::digest(format!("{club_id}|{}|{}|{words}|{copy}", c.date, c.amount_cents).as_bytes());
    hex::encode(&digest[..16])
}

async fn read(state: &AppState, club_id: Uuid, csv: &str) -> ApiResult<Preview> {
    let credits = statement::read_credits(csv)
        .map_err(|e| status(StatusCode::UNPROCESSABLE_ENTITY, e.to_string(), e.code()))?;
    let refs: Vec<Reference> = repo::club_references(&state.pool, club_id)
        .await?
        .into_iter()
        .map(|(code, user_id)| Reference { code, user_id })
        .collect();
    let claims: Vec<OpenClaim> = repo::open_transfer_claims(&state.pool, club_id)
        .await?
        .into_iter()
        .map(|c| OpenClaim {
            payment_id: c.id,
            user_id: c.user_id,
            amount_cents: c.amount_cents,
            on: c.on,
            payer: c.payer,
            batch: c.batch,
        })
        .collect();
    let proposals = statement::propose(&credits, &refs, &claims);

    let mut seen: HashMap<(NaiveDate, i64, String), usize> = HashMap::new();
    let hashes: Vec<String> = credits
        .iter()
        .map(|c| {
            let n = seen.entry((c.date, c.amount_cents, c.text.to_uppercase())).or_default();
            *n += 1;
            fingerprint(club_id, c, *n)
        })
        .collect();
    let applied: HashSet<String> = repo::applied_lines(&state.pool, club_id, &hashes).await?.into_iter().collect();
    let mut names: HashMap<Uuid, String> = HashMap::new();
    let mut summary = Summary { credits: credits.len(), ..Default::default() };
    let mut lines = Vec::with_capacity(credits.len());
    for ((c, p), hash) in credits.into_iter().zip(proposals).zip(hashes) {
        let (action, user_id, payment_ids, why) = if applied.contains(&hash) {
            ("already", None, Vec::new(), None)
        } else {
            match p {
                Proposal::Confirm { payment_ids, user_id } => ("confirm", Some(user_id), payment_ids, None),
                Proposal::Record { user_id } => ("record", Some(user_id), Vec::new(), None),
                Proposal::Check { user_id, why } => ("check", user_id, Vec::new(), Some(why)),
                Proposal::Unknown => ("unknown", None, Vec::new(), None),
            }
        };
        match action {
            "confirm" => summary.confirm += 1,
            "record" => summary.record += 1,
            "check" => summary.check += 1,
            "already" => summary.already += 1,
            _ => summary.unknown += 1,
        }
        let name = match user_id {
            Some(u) => match names.get(&u) {
                Some(n) => Some(n.clone()),
                None => {
                    let n = repo::user_name(&state.pool, u).await?.unwrap_or_default();
                    names.insert(u, n.clone());
                    Some(n)
                }
            },
            None => None,
        };
        let text: String = c.text.chars().take(140).collect();
        lines.push(Line { hash, row: c.row, date: c.date, amount_cents: c.amount_cents, text, action, user_id, name, payment_ids, why });
    }
    Ok(Preview { currency: repo::club_currency(&state.pool, club_id).await?, summary, lines })
}

/// What the statement's payments match. Changes nothing.
async fn preview(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    csv: String,
) -> ApiResult<Json<Preview>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    Ok(Json(read(&state, club_id, &csv).await?))
}

#[derive(Debug, Deserialize)]
struct ApplyBody {
    /// The same statement again: it's read afresh, so nothing the phone sends
    /// decides who gets ticked — only which of the server's matches to apply.
    csv: String,
    lines: Vec<String>,
}

#[derive(Debug, Serialize)]
struct Applied {
    confirmed: usize,
    recorded: usize,
    /// Asked for, but no longer a `confirm` or `record` (applied meanwhile,
    /// or the "I've paid" was ticked by somebody else).
    skipped: usize,
}

/// Apply the chosen lines: tick the "I've paid"s, record the rest.
async fn apply(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<ApplyBody>,
) -> ApiResult<Json<Applied>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    if body.lines.len() > statement::MAX_ROWS {
        return Err(ApiError::bad_request("Too many lines at once"));
    }
    let wanted: HashSet<&str> = body.lines.iter().map(String::as_str).collect();
    let preview = read(&state, club_id, &body.csv).await?;
    let payout = accounts(&state, club_id).await?.current().map(|a| a.id);
    let club = repo::club_name(&state.pool, club_id).await?.unwrap_or_default();
    let mut out = Applied { confirmed: 0, recorded: 0, skipped: 0 };
    for line in preview.lines.iter().filter(|l| wanted.contains(l.hash.as_str())) {
        match (line.action, line.payment_ids.first().copied(), line.user_id) {
            ("confirm", Some(first), Some(_)) => {
                // Each ticked like any other (the member hears it arrived),
                // and only then is the line marked applied: an "I've paid"
                // taken back meanwhile leaves the line for next time.
                let mut ticked = 0;
                for pid in &line.payment_ids {
                    if decide(&state, auth.user_id, *pid, true, None).await.is_ok() {
                        ticked += 1;
                    }
                }
                if ticked == 0 {
                    out.skipped += 1;
                    continue;
                }
                let mut tx = state.pool.begin().await?;
                if repo::take_line(&mut tx, club_id, &line.hash, auth.user_id).await? {
                    repo::set_line_payment(&mut tx, club_id, &line.hash, first).await?;
                }
                tx.commit().await?;
                out.confirmed += ticked;
            }
            ("record", _, Some(user)) => {
                let name = line.name.clone().unwrap_or_default();
                let note = format!("From the bank statement, {}", line.date.format("%-d %b"));
                let key = format!("statement:{}", line.hash);
                let mut tx = state.pool.begin().await?;
                if !repo::take_line(&mut tx, club_id, &line.hash, auth.user_id).await? {
                    out.skipped += 1;
                    continue;
                }
                let (row, _) = repo::insert_payment(
                    &mut tx,
                    &NewPayment {
                        club_id,
                        user_id: Some(user),
                        guest_name: None,
                        name: &name,
                        amount_cents: line.amount_cents,
                        currency: &preview.currency,
                        method: "transfer",
                        reference: None,
                        payout_account_id: payout,
                        status: "confirmed",
                        note: Some(&note),
                        idempotency_key: Some(&key),
                        created_by: Some(auth.user_id),
                        via_link: None,
                        share_id: None,
                    },
                )
                .await?;
                repo::set_line_payment(&mut tx, club_id, &line.hash, row.id).await?;
                repo::audit(&mut tx, club_id, Some(auth.user_id), "record_from_statement", "payment", Some(row.id), None,
                    Some(json!({ "user_id": user, "amount_cents": line.amount_cents, "date": line.date }))).await?;
                tx.commit().await?;
                out.recorded += 1;
                let money = fmt_money(line.amount_cents, &preview.currency);
                if user != auth.user_id {
                    state
                        .notify_text(user, "payment_confirmed", &format!("{club} got your {money}"),
                            &format!("{club} received your payment of {money}. Thanks!"),
                            json!({ "club_id": club_id, "payment_id": row.id }))
                        .await;
                }
            }
            _ => out.skipped += 1,
        }
    }
    let mut tx = state.pool.begin().await?;
    repo::audit(&mut tx, club_id, Some(auth.user_id), "apply_statement", "club", Some(club_id), None,
        Some(json!({ "confirmed": out.confirmed, "recorded": out.recorded, "skipped": out.skipped }))).await?;
    tx.commit().await?;
    Ok(Json(out))
}
