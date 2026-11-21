//! Paying the club by bank transfer. See docs/PAY_BY_BANK_TRANSFER.md.
//!
//! The app never touches the money. A secretary adds the club's bank details;
//! an event gets a cost; once the session is over a bill splits it between
//! whoever came; each player copies the details and a reference into their
//! banking app and taps "I've paid"; a treasurer confirms it.
//!
//! Who may do what, decided here and nowhere else:
//!
//! * **Money admins** — the club's owner, its secretaries and its treasurers —
//!   add and change bank details, confirm and reject payments, record cash,
//!   refund credit and waive shares.
//! * Only the **owner** unfreezes bank details somebody froze.
//! * Whoever may **manage the event** (a captain who scheduled the nets, or a
//!   money admin) sets its cost and sends, re-splits or cancels its bill.
//! * **Members** see their own shares, and full bank details only while they
//!   owe the club something.
//!
//! Every write is one transaction with its audit row.

use argon2::{Argon2, PasswordHash, PasswordVerifier};
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{delete, get, post, put};
use axum::{Json, Router};
use chrono::{DateTime, Duration, Utc};
use fishers_db::repos::club_payments::{
    self as repo, Attendee, BillError, BillInput, BillRow, Candidate, EventCostRow, LedgerRow,
    MoneyRole, NewPayment, NewPayoutAccount, Payer, PaymentRow, PaymentSettings, PayoutAccountRow,
    ShareRow,
};
use fishers_db::repos::events as events_repo;
use fishers_db::repos::users as users_repo;
use fishers_domain::money::{
    self, fmt_money, CostMode, PayoutState, Rounding, Settlement, ShareProgress, ShareState,
};
use fishers_domain::{Event, Permission};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use tracing::warn;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::require_permission;
use crate::services::payout_crypto::SealedDetails;
use crate::state::AppState;

/// More than this many full reveals of bank details in an hour, by one
/// person, is not somebody paying their subs.
const REVEALS_PER_HOUR: i64 = 60;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/clubs/{id}/payout-account", get(get_payout_account).post(add_payout_account))
        .route("/clubs/{id}/payout-account/{aid}/freeze", post(freeze_account))
        .route("/clubs/{id}/payout-account/{aid}/unfreeze", post(unfreeze_account))
        .route("/clubs/{id}/payout-account/{aid}/retire", post(retire_account))
        .route("/clubs/{id}/payments/settings", put(update_settings))
        .route("/clubs/{id}/money", get(money_overview))
        .route("/clubs/{id}/payments", get(list_payments).post(claim_payment))
        .route("/clubs/{id}/payments/record", post(record_payment))
        .route("/clubs/{id}/payments/refund", post(refund))
        .route("/clubs/{id}/payments/audit", get(audit_log))
        .route("/clubs/{id}/pay", get(pay_screen))
        .route("/payments/{pid}", delete(cancel_claim))
        .route("/payments/{pid}/confirm", post(confirm_payment))
        .route("/payments/{pid}/reject", post(reject_payment))
        .route("/shares/{sid}/waive", post(waive_share))
        .route("/events/{id}/cost", put(set_cost).delete(remove_cost))
        .route("/events/{id}/bill", get(get_bill).post(send_bill))
        .route("/events/{id}/bill/preview", post(preview_bill))
        .route("/events/{id}/bill/void", post(void_bill))
        .route("/me/dues", get(my_dues))
}

// MARK: access

pub(crate) fn status(code: StatusCode, message: impl Into<String>, reason: &'static str) -> ApiError {
    ApiError { status: code, message: message.into(), code: Some(reason) }
}

pub(crate) async fn role(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<MoneyRole> {
    repo::money_role(&state.pool, club_id, user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("club not found"))
}

async fn require_member(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<MoneyRole> {
    let r = role(state, club_id, user_id).await?;
    if r.is_member || r.is_owner {
        Ok(r)
    } else {
        Err(ApiError::forbidden("You're not a member of this club").with_code("not_member"))
    }
}

pub(crate) async fn require_money_admin(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<MoneyRole> {
    let r = role(state, club_id, user_id).await?;
    if r.is_admin() {
        Ok(r)
    } else {
        Err(ApiError::forbidden(
            "Only the club owner, a secretary or a treasurer can look after the club's money",
        )
        .with_code("not_money_admin"))
    }
}

pub(crate) async fn event_or_404(state: &AppState, event_id: Uuid) -> ApiResult<Event> {
    events_repo::get_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))
}

/// Whether `user_id` may set this event's cost and send its bill: a money
/// admin, or anybody who may manage the event (its captain).
async fn can_bill(state: &AppState, event: &Event, user_id: Uuid, money: MoneyRole) -> bool {
    money.is_admin()
        || require_permission(state, event.club_id, user_id, event.team_id, Permission::ManageEvents)
            .await
            .is_ok()
}

pub(crate) async fn require_can_bill(state: &AppState, event: &Event, user_id: Uuid) -> ApiResult<MoneyRole> {
    let money = role(state, event.club_id, user_id).await?;
    if can_bill(state, event, user_id, money).await {
        Ok(money)
    } else {
        Err(ApiError::forbidden(
            "Only whoever runs this session, or the club's secretary or treasurer, can do that",
        )
        .with_code("not_billing_admin"))
    }
}

/// Where there is a password, changing bank details needs it typed again: a
/// live session on a borrowed phone must not be enough to redirect the club's
/// money. Somebody who signs in only with Google or Apple has none to type;
/// for them the 24-hour wait and the warning to every admin are the guard.
async fn reauthenticate(state: &AppState, user_id: Uuid, given: Option<&str>) -> ApiResult<()> {
    let user = users_repo::find_by_id(&state.pool, user_id)
        .await?
        .ok_or_else(|| ApiError::unauthorized("not signed in"))?;
    let Some(hash) = user.password_hash.as_deref() else { return Ok(()) };
    let Some(given) = given.filter(|p| !p.is_empty()) else {
        return Err(status(
            StatusCode::PRECONDITION_REQUIRED,
            "Type your password to change the club's bank details",
            "reauth_required",
        ));
    };
    let parsed = PasswordHash::new(hash).map_err(|_| ApiError::internal("bad password hash"))?;
    Argon2::default()
        .verify_password(given.as_bytes(), &parsed)
        // 403, not 401: a 401 tells the apps the session is over and signs
        // the person out, for mistyping a password.
        .map_err(|_| ApiError::forbidden("That password doesn't match").with_code("wrong_password"))
}

pub(crate) fn idempotency_key(headers: &HeaderMap) -> ApiResult<Option<String>> {
    match headers.get("idempotency-key").and_then(|v| v.to_str().ok()) {
        None => Ok(None),
        Some(k) if !k.is_empty() && k.len() <= 100 => Ok(Some(k.to_string())),
        Some(_) => Err(ApiError::bad_request("Idempotency-Key must be 1–100 characters")),
    }
}

/// The payment a retried request already made, for an idempotency key.
async fn retried(state: &AppState, user_id: Uuid, club_id: Uuid, key: Option<&str>) -> ApiResult<Option<PaymentRow>> {
    let Some(k) = key else { return Ok(None) };
    match repo::payment_by_key(&state.pool, user_id, k).await? {
        Some(existing) if existing.club_id != club_id => {
            Err(ApiError::conflict("That Idempotency-Key was already used for another club"))
        }
        other => Ok(other),
    }
}

fn reason_required(reason: Option<&str>, what: &str) -> ApiResult<String> {
    let r = reason.map(str::trim).unwrap_or("");
    if r.is_empty() {
        return Err(ApiError::bad_request(format!("Say why {what}")).with_code("reason_required"));
    }
    if r.chars().count() > 200 {
        return Err(ApiError::bad_request("Keep the reason to 200 characters"));
    }
    Ok(r.to_string())
}

pub(crate) fn first_name(name: &str) -> &str {
    name.split_whitespace().next().unwrap_or(name)
}

// MARK: bank details

#[derive(Debug, Clone, Serialize)]
pub struct PayoutAccountView {
    pub id: Uuid,
    pub label: String,
    pub holder_name: String,
    pub is_personal: bool,
    pub sort_code: Option<String>,
    pub last4: String,
    pub state: PayoutState,
    pub live_from: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub created_by_name: Option<String>,
    pub freeze_reason: Option<String>,
    /// False when the key that sealed the number is gone: enter them again.
    pub readable: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct PayoutAccountsView {
    pub can_manage: bool,
    pub is_owner: bool,
    /// What players are shown.
    pub current: Option<PayoutAccountView>,
    /// A change waiting out its delay. Admins only.
    pub pending: Option<PayoutAccountView>,
    /// Frozen details waiting for the owner. Admins only.
    pub frozen: Option<PayoutAccountView>,
    /// When the current details replaced older ones, if that was recent.
    pub changed_at: Option<DateTime<Utc>>,
}

fn view_of(state: &AppState, row: &PayoutAccountRow, s: PayoutState) -> PayoutAccountView {
    let readable = row
        .details_ciphertext
        .as_deref()
        .is_some_and(|c| state.payout_crypto.open(row.club_id, c, &row.key_id).is_ok());
    PayoutAccountView {
        id: row.id,
        label: row.label.clone(),
        holder_name: row.holder_name.clone(),
        is_personal: row.is_personal,
        sort_code: row.sort_code.as_deref().map(money::fmt_sort_code),
        last4: row.last4.clone(),
        state: s,
        live_from: row.live_from,
        created_at: row.created_at,
        created_by_name: row.created_by_name.clone(),
        freeze_reason: row.freeze_reason.clone(),
        readable,
    }
}

/// The club's accounts and the state of each, now.
pub(crate) struct Accounts {
    pub(crate) rows: Vec<PayoutAccountRow>,
    states: Vec<PayoutState>,
}

impl Accounts {
    fn of(rows: Vec<PayoutAccountRow>) -> Self {
        let timelines: Vec<_> = rows.iter().map(PayoutAccountRow::timeline).collect();
        let states = money::payout_states(&timelines, Utc::now());
        Self { rows, states }
    }

    pub(crate) fn find(&self, wanted: PayoutState) -> Option<&PayoutAccountRow> {
        // Newest first: rows are oldest first.
        self.rows.iter().zip(&self.states).rev().find(|(_, s)| **s == wanted).map(|(r, _)| r)
    }

    pub(crate) fn current(&self) -> Option<&PayoutAccountRow> {
        self.find(PayoutState::Active)
    }

    fn state_of(&self, id: Uuid) -> Option<(&PayoutAccountRow, PayoutState)> {
        self.rows.iter().zip(&self.states).find(|(r, _)| r.id == id).map(|(r, s)| (r, *s))
    }

    /// When the current account went live, if it replaced one within the
    /// notice period: players are told the details changed.
    pub(crate) fn changed_at(&self) -> Option<DateTime<Utc>> {
        let current = self.current()?;
        current.replaces_id?;
        (Utc::now() - current.live_from < Duration::days(money::CHANGED_NOTICE_DAYS)).then_some(current.live_from)
    }

    fn view(&self, state: &AppState, role: MoneyRole) -> PayoutAccountsView {
        let v = |row: Option<&PayoutAccountRow>, s| row.map(|r| view_of(state, r, s));
        let admin = role.is_admin();
        PayoutAccountsView {
            can_manage: admin,
            is_owner: role.is_owner,
            current: v(self.current(), PayoutState::Active),
            pending: if admin { v(self.find(PayoutState::Pending), PayoutState::Pending) } else { None },
            frozen: if admin { v(self.find(PayoutState::Frozen), PayoutState::Frozen) } else { None },
            changed_at: self.changed_at(),
        }
    }
}

pub(crate) async fn accounts(state: &AppState, club_id: Uuid) -> ApiResult<Accounts> {
    Ok(Accounts::of(repo::payout_accounts(&state.pool, club_id).await?))
}

async fn get_payout_account(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<PayoutAccountsView>> {
    let r = require_member(&state, club_id, auth.user_id).await?;
    Ok(Json(accounts(&state, club_id).await?.view(&state, r)))
}

#[derive(Debug, Deserialize)]
struct AddAccountBody {
    label: Option<String>,
    holder_name: String,
    sort_code: String,
    account_number: String,
    #[serde(default)]
    is_personal: bool,
    password: Option<String>,
}

async fn add_payout_account(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<AddAccountBody>,
) -> ApiResult<Json<PayoutAccountsView>> {
    let r = require_money_admin(&state, club_id, auth.user_id).await?;
    let bad = |m: &str| ApiError::bad_request(m).with_code("invalid_bank_details");
    let holder = money::clean_holder_name(&body.holder_name).map_err(bad)?;
    let sort_code = money::normalise_sort_code(&body.sort_code).map_err(bad)?;
    let number = money::normalise_account_number(&body.account_number).map_err(bad)?;
    let label = body.label.as_deref().map(str::trim).filter(|l| !l.is_empty()).unwrap_or(
        // Not "Personal account": the apps already say that beside it.
        if body.is_personal { "Bank account" } else { "Club account" },
    );
    if label.chars().count() > 60 {
        return Err(bad("Keep the nickname to 60 characters."));
    }
    reauthenticate(&state, auth.user_id, body.password.as_deref()).await?;

    let fingerprint = state.payout_crypto.fingerprint(club_id, &sort_code, &number);
    let (ciphertext, key_id) = state
        .payout_crypto
        .seal(club_id, &SealedDetails { account_number: number.clone() });

    let mut tx = state.pool.begin().await?;
    if !repo::lock_club(&mut tx, club_id).await? {
        return Err(ApiError::not_found("club not found"));
    }
    let before = Accounts::of(repo::payout_accounts_conn(&mut tx, club_id).await?);
    let current = before.current().cloned();
    let pending = before.find(PayoutState::Pending).cloned();
    for row in [&current, &pending].into_iter().flatten() {
        if row.fingerprint == fingerprint {
            return Err(ApiError::conflict(if row.id == current.as_ref().map_or(Uuid::nil(), |c| c.id) {
                "Those are already the club's bank details."
            } else {
                "Those details are already waiting to go live."
            })
            .with_code("same_details"));
        }
    }
    // A club's first details are live at once: there is nothing to be swapped
    // out from under players yet. Every later change waits, so the people
    // told about it can stop it.
    let first = before.rows.is_empty();
    let live_from = if first { Utc::now() } else { Utc::now() + Duration::hours(money::CHANGE_DELAY_HOURS) };
    // A newer change replaces one still waiting: only one is ever pending.
    if let Some(p) = &pending {
        repo::retire_payout_account(&mut tx, p.id, Some(auth.user_id)).await?;
        repo::audit(&mut tx, club_id, Some(auth.user_id), "replace_pending", "payout_account", Some(p.id), None, None)
            .await?;
    }
    let id = repo::insert_payout_account(
        &mut tx,
        &NewPayoutAccount {
            club_id,
            label,
            holder_name: &holder,
            is_personal: body.is_personal,
            sort_code: &sort_code,
            last4: &number[number.len() - 4..],
            ciphertext: &ciphertext,
            key_id: &key_id,
            fingerprint: &fingerprint,
            live_from,
            replaces_id: current.as_ref().map(|c| c.id),
            created_by: auth.user_id,
        },
    )
    .await?;
    repo::enable_payments(&mut tx, club_id).await?;
    repo::audit(
        &mut tx,
        club_id,
        Some(auth.user_id),
        if first { "add_bank_details" } else { "change_bank_details" },
        "payout_account",
        Some(id),
        current.as_ref().map(|c| json!({ "id": c.id, "holder_name": c.holder_name, "last4": c.last4 })),
        Some(json!({ "holder_name": holder, "sort_code": sort_code, "last4": &number[number.len() - 4..],
                     "is_personal": body.is_personal, "live_from": live_from })),
    )
    .await?;
    tx.commit().await?;

    let after = accounts(&state, club_id).await?;
    tell_admins_about_bank_details(&state, club_id, auth.user_id, first, live_from, &holder).await;
    Ok(Json(after.view(&state, r)))
}

/// Every owner, secretary and treasurer hears about bank details changing,
/// by push and by email, with the time it goes live. This is what makes a
/// hijacked account obvious before anybody pays into it.
async fn tell_admins_about_bank_details(
    state: &AppState,
    club_id: Uuid,
    by: Uuid,
    first: bool,
    live_from: DateTime<Utc>,
    holder: &str,
) {
    let club = repo::club_name(&state.pool, club_id).await.ok().flatten().unwrap_or_else(|| "Your club".into());
    let who = repo::user_name(&state.pool, by).await.ok().flatten().unwrap_or_else(|| "Somebody".into());
    let (title, body) = if first {
        (
            format!("{club}: bank details added"),
            format!("{who} added bank details in the name of {holder}. Players can pay into them now. Not right? Freeze them in the app."),
        )
    } else {
        (
            format!("{club}: bank details changed"),
            format!(
                "{who} changed the bank details to an account in the name of {holder}. They go live {}. Not right? Freeze them in the app before then.",
                live_from.format("%a %-d %b at %H:%M UTC")
            ),
        )
    };
    let admins = repo::money_admins(&state.pool, club_id).await.unwrap_or_default();
    for (admin, _) in admins {
        state
            .notify_text(admin, "payout_details_changed", &title, &body, json!({ "club_id": club_id }))
            .await;
        if let Ok(Some(user)) = users_repo::find_by_id(&state.pool, admin).await {
            if let Some(address) = user.email.as_deref() {
                if let Err(error) = state.email.send(address, &title, &body).await {
                    warn!(%error, "bank details email failed");
                }
            }
        }
    }
}

#[derive(Debug, Deserialize, Default)]
struct ReasonBody {
    reason: Option<String>,
}

async fn freeze_account(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, aid)): Path<(Uuid, Uuid)>,
    body: Option<Json<ReasonBody>>,
) -> ApiResult<Json<PayoutAccountsView>> {
    let r = require_money_admin(&state, club_id, auth.user_id).await?;
    let reason = body.and_then(|Json(b)| b.reason).map(|s| s.trim().chars().take(200).collect::<String>());
    let mut tx = state.pool.begin().await?;
    repo::lock_club(&mut tx, club_id).await?;
    let all = Accounts::of(repo::payout_accounts_conn(&mut tx, club_id).await?);
    let (_, s) = all.state_of(aid).ok_or_else(|| ApiError::not_found("no such bank details"))?;
    if !matches!(s, PayoutState::Active | PayoutState::Pending) {
        return Err(ApiError::conflict("Those details aren't live or waiting, so there's nothing to freeze")
            .with_code("not_freezable"));
    }
    // A change frozen before it went live stops only the change: players
    // keep paying into the current details. Live details frozen leave them
    // nothing to pay into.
    let what_players_see = if s == PayoutState::Pending {
        "The change won't go live until the club owner has looked. Players keep paying into the current details."
    } else {
        "Players are told not to pay until the club owner has looked."
    };
    repo::freeze_payout_account(&mut tx, aid, auth.user_id, reason.as_deref()).await?;
    repo::audit(&mut tx, club_id, Some(auth.user_id), "freeze_bank_details", "payout_account", Some(aid), None,
        Some(json!({ "reason": reason }))).await?;
    tx.commit().await?;

    let club = repo::club_name(&state.pool, club_id).await?.unwrap_or_default();
    let who = repo::user_name(&state.pool, auth.user_id).await?.unwrap_or_default();
    for (admin, _) in repo::money_admins(&state.pool, club_id).await? {
        state
            .notify_text(
                admin,
                "payout_details_frozen",
                &format!("{club}: bank details frozen"),
                &format!("{who} froze the bank details. {what_players_see}"),
                json!({ "club_id": club_id }),
            )
            .await;
    }
    Ok(Json(accounts(&state, club_id).await?.view(&state, r)))
}

async fn unfreeze_account(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, aid)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<PayoutAccountsView>> {
    let r = role(&state, club_id, auth.user_id).await?;
    if !r.is_owner {
        return Err(ApiError::forbidden("Only the club owner can unfreeze bank details").with_code("owner_only"));
    }
    let mut tx = state.pool.begin().await?;
    repo::lock_club(&mut tx, club_id).await?;
    if !repo::unfreeze_payout_account(&mut tx, aid).await? {
        return Err(ApiError::conflict("Those details aren't frozen").with_code("not_frozen"));
    }
    repo::audit(&mut tx, club_id, Some(auth.user_id), "unfreeze_bank_details", "payout_account", Some(aid), None, None)
        .await?;
    tx.commit().await?;
    Ok(Json(accounts(&state, club_id).await?.view(&state, r)))
}

async fn retire_account(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, aid)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<PayoutAccountsView>> {
    let r = require_money_admin(&state, club_id, auth.user_id).await?;
    let mut tx = state.pool.begin().await?;
    repo::lock_club(&mut tx, club_id).await?;
    let all = Accounts::of(repo::payout_accounts_conn(&mut tx, club_id).await?);
    let (row, s) = all.state_of(aid).ok_or_else(|| ApiError::not_found("no such bank details"))?;
    if s == PayoutState::Frozen && !r.is_owner {
        return Err(ApiError::forbidden("Only the club owner can remove frozen details").with_code("owner_only"));
    }
    let snapshot = json!({ "holder_name": row.holder_name, "last4": row.last4, "state": s.as_str() });
    if !repo::retire_payout_account(&mut tx, aid, Some(auth.user_id)).await? {
        return Err(ApiError::conflict("Those details were already removed").with_code("already_retired"));
    }
    repo::audit(&mut tx, club_id, Some(auth.user_id), "remove_bank_details", "payout_account", Some(aid), Some(snapshot), None)
        .await?;
    tx.commit().await?;
    Ok(Json(accounts(&state, club_id).await?.view(&state, r)))
}

// MARK: settings

#[derive(Debug, Deserialize)]
struct SettingsBody {
    auto_bill: Option<bool>,
    auto_bill_after_hours: Option<i32>,
    round_shares_up: Option<bool>,
    /// The usual nets price: `{ "mode": "per_player", "amount_cents": 500 }`,
    /// or null to clear it. Absent leaves it as it is.
    #[serde(default, deserialize_with = "fishers_domain::double_option")]
    default_nets: Option<Option<DefaultPrice>>,
    #[serde(default, deserialize_with = "fishers_domain::double_option")]
    default_match_fee_cents: Option<Option<i64>>,
}

#[derive(Debug, Deserialize)]
struct DefaultPrice {
    mode: String,
    amount_cents: i64,
}

async fn update_settings(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<SettingsBody>,
) -> ApiResult<Json<PaymentSettings>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    if let Some(h) = body.auto_bill_after_hours {
        if !(1..=336).contains(&h) {
            return Err(ApiError::bad_request("Send the bill between 1 hour and 14 days after the session"));
        }
    }
    let default_nets = match &body.default_nets {
        None => None,
        Some(None) => Some(None),
        Some(Some(p)) => {
            let mode = CostMode::parse(&p.mode)
                .ok_or_else(|| ApiError::bad_request("mode is split_total or per_player"))?;
            let cap = if mode == CostMode::PerPlayer { money::MAX_SHARE_CENTS } else { money::MAX_BILL_CENTS };
            if p.amount_cents <= 0 || p.amount_cents > cap {
                return Err(ApiError::bad_request("That price is more than the app allows").with_code("amount_limit"));
            }
            Some(Some((mode.as_str().to_string(), p.amount_cents)))
        }
    };
    if let Some(Some(fee)) = body.default_match_fee_cents {
        if fee <= 0 || fee > money::MAX_SHARE_CENTS {
            return Err(ApiError::bad_request("That match fee is more than the app allows").with_code("amount_limit"));
        }
    }
    let change = repo::SettingsChange {
        auto_bill: body.auto_bill,
        auto_bill_after_hours: body.auto_bill_after_hours,
        round_shares_up: body.round_shares_up,
        default_nets,
        default_match_fee_cents: body.default_match_fee_cents,
    };
    let mut tx = state.pool.begin().await?;
    repo::set_settings(&mut tx, club_id, &change).await?;
    repo::audit(&mut tx, club_id, Some(auth.user_id), "update_settings", "club", Some(club_id), None,
        Some(json!({ "auto_bill": body.auto_bill, "auto_bill_after_hours": body.auto_bill_after_hours,
                     "round_shares_up": body.round_shares_up, "default_nets": format!("{:?}", change.default_nets),
                     "default_match_fee_cents": body.default_match_fee_cents }))).await?;
    tx.commit().await?;
    Ok(Json(repo::settings(&state.pool, club_id).await?.ok_or_else(|| ApiError::not_found("club not found"))?))
}

// MARK: the ledger, as people read it

#[derive(Debug, Clone, Serialize)]
pub struct ShareView {
    pub id: Uuid,
    pub bill_id: Uuid,
    /// The session; none for a pass charge or a group fee (see `kind`).
    pub event_id: Option<Uuid>,
    /// `event`, `pass` or `collection`.
    pub kind: String,
    /// When a pass charge or group fee is due.
    pub due_on: Option<chrono::NaiveDate>,
    pub title: String,
    pub event_start_at: DateTime<Utc>,
    pub user_id: Option<Uuid>,
    pub guest_name: Option<String>,
    pub name: String,
    pub amount_cents: i64,
    pub paid_cents: i64,
    pub waiting_cents: i64,
    pub currency: String,
    pub state: ShareState,
    pub reason: Option<String>,
}

pub(crate) fn share_view(s: &ShareRow, progress: Option<ShareProgress>) -> ShareView {
    let p = progress.unwrap_or_default();
    let state = match s.status.as_str() {
        "waived" => ShareState::Waived,
        "void" => ShareState::Void,
        "covered" => ShareState::Covered,
        _ => p.state(s.amount_cents),
    };
    ShareView {
        id: s.id,
        bill_id: s.bill_id,
        event_id: s.event_id,
        kind: s.kind.clone(),
        due_on: s.due_on,
        title: s.title.clone(),
        event_start_at: s.event_start_at,
        user_id: s.user_id,
        guest_name: s.guest_name.clone(),
        name: s.name.clone(),
        amount_cents: s.amount_cents,
        paid_cents: p.paid_cents,
        waiting_cents: p.waiting_cents,
        currency: s.currency.clone(),
        state,
        reason: s.reason.clone(),
    }
}

/// A club's money, settled per payer.
pub(crate) struct Ledger {
    pub(crate) shares: Vec<ShareRow>,
    pub(crate) by_payer: HashMap<Payer, Settlement>,
    pub(crate) names: HashMap<Payer, String>,
}

impl Ledger {
    fn build(shares: Vec<ShareRow>, payments: Vec<LedgerRow>) -> Self {
        let mut grouped: HashMap<Payer, (Vec<money::LedgerShare>, Vec<money::LedgerPayment>)> = HashMap::new();
        let mut names = HashMap::new();
        for s in &shares {
            grouped.entry(s.payer()).or_default().0.push(s.ledger());
            names.entry(s.payer()).or_insert_with(|| s.name.clone());
        }
        for p in &payments {
            grouped.entry(p.payer()).or_default().1.push(p.ledger());
            // A guest who has only ever paid (cash, no share yet) still has a name.
            if let Some(guest) = p.guest_name.as_deref() {
                names.entry(p.payer()).or_insert_with(|| guest.to_string());
            }
        }
        let by_payer = grouped.into_iter().map(|(k, (s, p))| (k, money::settle(&s, &p))).collect();
        Self { shares, by_payer, names }
    }

    pub(crate) async fn load(state: &AppState, club_id: Uuid, only: Option<Uuid>) -> ApiResult<Self> {
        let (shares, payments) = repo::ledger(&state.pool, club_id, only).await?;
        Ok(Self::build(shares, payments))
    }

    pub(crate) fn progress(&self, s: &ShareRow) -> Option<ShareProgress> {
        self.by_payer.get(&s.payer()).and_then(|st| st.shares.get(&s.id)).copied()
    }

    fn of(&self, payer: &Payer) -> Settlement {
        self.by_payer.get(payer).cloned().unwrap_or_default()
    }
}

// MARK: costs

#[derive(Debug, Deserialize)]
struct CostBody {
    mode: String,
    amount_cents: i64,
    note: Option<String>,
    /// Also every later week of the same weekly series not yet billed.
    #[serde(default)]
    apply_to_series: bool,
    /// A per-player price for some price types ("Juniors £3"). Given, it
    /// replaces the session's prices; left out, they stay as they are.
    prices: Option<Vec<PriceIn>>,
}

#[derive(Debug, Deserialize)]
struct PriceIn {
    price_type_id: Uuid,
    amount_cents: i64,
}

/// A session's price for one price type.
#[derive(Debug, Serialize)]
pub(crate) struct TypePrice {
    price_type_id: Uuid,
    name: String,
    amount_cents: i64,
}

pub(crate) async fn type_prices(state: &AppState, club_id: Uuid, event_id: Uuid) -> ApiResult<Vec<TypePrice>> {
    let prices = fishers_db::repos::passes::event_prices(&state.pool, event_id).await?;
    if prices.is_empty() {
        return Ok(Vec::new());
    }
    Ok(fishers_db::repos::passes::price_types(&state.pool, club_id)
        .await?
        .into_iter()
        .filter_map(|t| prices.get(&t.id).map(|a| TypePrice { price_type_id: t.id, name: t.name, amount_cents: *a }))
        .collect())
}

#[derive(Debug, Serialize)]
struct CostResponse {
    cost: Option<EventCostRow>,
    /// Other weeks of the series that took the same cost.
    series_updated: usize,
    prices: Vec<TypePrice>,
}

async fn set_cost(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
    Json(body): Json<CostBody>,
) -> ApiResult<Json<CostResponse>> {
    let event = event_or_404(&state, event_id).await?;
    require_can_bill(&state, &event, auth.user_id).await?;
    let mode = CostMode::parse(&body.mode)
        .ok_or_else(|| ApiError::bad_request("mode is split_total or per_player"))?;
    if body.amount_cents <= 0 || body.amount_cents > money::MAX_BILL_CENTS
        || (mode == CostMode::PerPlayer && body.amount_cents > money::MAX_SHARE_CENTS)
    {
        return Err(ApiError::bad_request(format!(
            "The cost has to be more than zero and at most {} ({} a head)",
            fmt_money(money::MAX_BILL_CENTS, &event.fee_currency),
            fmt_money(money::MAX_SHARE_CENTS, &event.fee_currency)
        ))
        .with_code("amount_limit"));
    }
    let note = body.note.as_deref().map(str::trim).filter(|n| !n.is_empty());
    if note.is_some_and(|n| n.chars().count() > 200) {
        return Err(ApiError::bad_request("Keep the note to 200 characters"));
    }
    if repo::live_bill(&state.pool, event_id).await?.is_some() {
        return Err(ApiError::conflict("This one's already been billed. Re-split the bill to change it.")
            .with_code("already_billed"));
    }
    let prices: Option<Vec<(Uuid, i64)>> = match &body.prices {
        None => None,
        Some(list) => {
            if mode != CostMode::PerPlayer && !list.is_empty() {
                return Err(ApiError::bad_request("Prices by type are for a cost per player; a total is split evenly")
                    .with_code("prices_need_per_player"));
            }
            let types = fishers_db::repos::passes::price_types(&state.pool, event.club_id).await?;
            let mut out: Vec<(Uuid, i64)> = Vec::new();
            for p in list {
                if !types.iter().any(|t| t.id == p.price_type_id && t.archived_at.is_none()) {
                    return Err(ApiError::bad_request("That price type isn't one of this club's"));
                }
                if p.amount_cents < 0 || p.amount_cents > money::MAX_SHARE_CENTS {
                    return Err(ApiError::bad_request(format!(
                        "A price is between nothing and {}",
                        fmt_money(money::MAX_SHARE_CENTS, &event.fee_currency)
                    ))
                    .with_code("amount_limit"));
                }
                if !out.iter().any(|(t, _)| *t == p.price_type_id) {
                    out.push((p.price_type_id, p.amount_cents));
                }
            }
            Some(out)
        }
    };
    let mut targets = vec![event_id];
    if body.apply_to_series {
        if let Some(series) = event.metadata.get("series_id").and_then(|v| v.as_str()) {
            for id in repo::series_weeks_ahead(&state.pool, event.club_id, series, event.start_at).await? {
                if id != event_id {
                    targets.push(id);
                }
            }
        }
    }
    let mut tx = state.pool.begin().await?;
    for id in &targets {
        repo::upsert_cost(&mut tx, *id, event.club_id, mode, body.amount_cents, &event.fee_currency, note, Some(auth.user_id))
            .await?;
        match (&prices, mode) {
            (Some(p), _) => fishers_db::repos::passes::set_event_prices(&mut tx, *id, p).await?,
            // A split total has no per-type prices to keep.
            (None, CostMode::SplitTotal) => fishers_db::repos::passes::set_event_prices(&mut tx, *id, &[]).await?,
            (None, CostMode::PerPlayer) => {}
        }
    }
    repo::audit(&mut tx, event.club_id, Some(auth.user_id), "set_cost", "event", Some(event_id), None,
        Some(json!({ "mode": mode.as_str(), "amount_cents": body.amount_cents, "weeks": targets.len(), "prices": prices }))).await?;
    tx.commit().await?;
    Ok(Json(CostResponse {
        cost: repo::cost(&state.pool, event_id).await?,
        series_updated: targets.len() - 1,
        prices: type_prices(&state, event.club_id, event_id).await?,
    }))
}

async fn remove_cost(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
) -> ApiResult<StatusCode> {
    let event = event_or_404(&state, event_id).await?;
    require_can_bill(&state, &event, auth.user_id).await?;
    if repo::live_bill(&state.pool, event_id).await?.is_some() {
        return Err(ApiError::conflict("This one's already been billed. Cancel the bill first.")
            .with_code("already_billed"));
    }
    let mut tx = state.pool.begin().await?;
    repo::delete_cost(&mut tx, event_id).await?;
    repo::audit(&mut tx, event.club_id, Some(auth.user_id), "remove_cost", "event", Some(event_id), None, None).await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// MARK: bills

#[derive(Debug, Serialize)]
struct BillView {
    #[serde(flatten)]
    bill: BillRow,
    paid_cents: i64,
    waiting_cents: i64,
    owed_cents: i64,
    surplus_cents: i64,
}

#[derive(Debug, Serialize)]
struct CandidateView {
    #[serde(flatten)]
    candidate: Candidate,
    /// Ticked to start with: they turned up, or (with nothing recorded) said
    /// they were going.
    suggested: bool,
}

#[derive(Debug, Serialize)]
struct BillResponse {
    event_id: Uuid,
    club_id: Uuid,
    title: String,
    start_at: DateTime<Utc>,
    end_at: DateTime<Utc>,
    event_status: fishers_domain::EventStatus,
    cost: Option<EventCostRow>,
    /// The session's own prices for some price types.
    prices: Vec<TypePrice>,
    bill: Option<BillView>,
    can_bill: bool,
    can_manage_money: bool,
    /// Everyone's shares for those who run it; only your own otherwise.
    shares: Vec<ShareView>,
    my_share: Option<ShareView>,
    /// Who to tick on the "who came?" screen. Empty unless `can_bill`.
    candidates: Vec<CandidateView>,
    /// Guests on the current bill, to carry into a re-split.
    guests: Vec<String>,
    has_payout_account: bool,
    round_shares_up: bool,
}

async fn bill_response(state: &AppState, event: &Event, user_id: Uuid) -> ApiResult<BillResponse> {
    let money_role = role(state, event.club_id, user_id).await?;
    let billing = can_bill(state, event, user_id, money_role).await;
    let cost = repo::cost(&state.pool, event.id).await?;
    let live = repo::live_bill(&state.pool, event.id).await?;
    let settings = repo::settings(&state.pool, event.club_id).await?;

    let (mut shares, mut my_share, mut guests, mut bill) = (Vec::new(), None, Vec::new(), None);
    if let Some(b) = live {
        let ledger = Ledger::load(state, event.club_id, None).await?;
        let rows = repo::bill_shares(&state.pool, b.id).await?;
        let (mut paid, mut waiting, mut owed) = (0, 0, 0);
        for row in &rows {
            let v = share_view(row, ledger.progress(row));
            if row.status == "live" {
                paid += v.paid_cents;
                waiting += v.waiting_cents;
                owed += v.amount_cents - v.paid_cents - v.waiting_cents;
            }
            if row.user_id.is_none() {
                guests.push(row.name.clone());
            }
            if row.user_id == Some(user_id) {
                my_share = Some(v.clone());
            }
            if billing || money_role.is_admin() {
                shares.push(v);
            }
        }
        let surplus = (b.total_cents - b.amount_cents).max(0) * i64::from(b.mode == "split_total");
        bill = Some(BillView { bill: b, paid_cents: paid, waiting_cents: waiting, owed_cents: owed, surplus_cents: surplus });
    }
    if !billing && !money_role.is_admin() {
        shares = my_share.iter().cloned().collect();
    }
    let candidates = if billing {
        let any_attendance = |c: &[Candidate]| c.iter().any(|c| c.attended.is_some());
        let all = repo::candidates(&state.pool, event.id).await?;
        let recorded = any_attendance(&all);
        all.into_iter()
            .map(|c| {
                let suggested = if recorded { c.attended == Some(true) } else { c.rsvp == "going" };
                CandidateView { candidate: c, suggested }
            })
            .collect()
    } else {
        Vec::new()
    };
    Ok(BillResponse {
        event_id: event.id,
        club_id: event.club_id,
        title: event.title.clone(),
        start_at: event.start_at,
        end_at: event.end_at,
        event_status: event.status,
        cost,
        prices: type_prices(state, event.club_id, event.id).await?,
        bill,
        can_bill: billing,
        can_manage_money: money_role.is_admin(),
        shares,
        my_share,
        candidates,
        guests,
        has_payout_account: accounts(state, event.club_id).await?.current().is_some(),
        round_shares_up: settings.map(|s| s.round_shares_up).unwrap_or(false),
    })
}

async fn get_bill(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
) -> ApiResult<Json<BillResponse>> {
    let event = event_or_404(&state, event_id).await?;
    require_member(&state, event.club_id, auth.user_id).await?;
    Ok(Json(bill_response(&state, &event, auth.user_id).await?))
}

#[derive(Debug, Deserialize)]
struct BillBody {
    #[serde(default)]
    attendees: Vec<Uuid>,
    #[serde(default)]
    guests: Vec<String>,
    /// The bill's version when re-splitting; absent to send a new bill.
    version: Option<i32>,
    note: Option<String>,
}

/// The people on a bill, checked and in the order shares are handed out:
/// members by name, then guests by name. The first few get any leftover penny,
/// and the order never depends on how the request listed them.
async fn attendees_for(
    conn: &mut sqlx::PgConnection,
    club_id: Uuid,
    body: &BillBody,
) -> ApiResult<Vec<Attendee>> {
    let mut ids = body.attendees.clone();
    ids.sort();
    ids.dedup();
    let members = repo::active_members_named(conn, club_id, &ids).await?;
    if members.len() != ids.len() {
        return Err(ApiError::bad_request(
            "Somebody ticked isn't a member of the club any more. Refresh and try again.",
        )
        .with_code("not_members"));
    }
    let mut people: Vec<Attendee> =
        members.into_iter().map(|(id, name)| Attendee { user_id: Some(id), name, ..Default::default() }).collect();
    people.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()).then(a.user_id.cmp(&b.user_id)));

    let mut seen = std::collections::HashSet::new();
    let mut guests = Vec::new();
    for raw in &body.guests {
        let name = raw.split_whitespace().collect::<Vec<_>>().join(" ");
        if name.is_empty() {
            continue;
        }
        if name.chars().count() > 60 {
            return Err(ApiError::bad_request("A guest's name can be at most 60 characters"));
        }
        if seen.insert(name.to_lowercase()) {
            guests.push(Attendee { user_id: None, name, ..Default::default() });
        }
    }
    if guests.len() > 50 {
        return Err(ApiError::bad_request("That's a lot of guests: at most 50 on one bill"));
    }
    guests.sort_by_key(|g| g.name.to_lowercase());
    people.extend(guests);
    Ok(people)
}

/// Everybody on a session's bill, priced by their price type and marked
/// where a pass or a free type means they owe nothing.
async fn priced(state: &AppState, event: &Event, mode: CostMode, people: Vec<Attendee>) -> ApiResult<Vec<Attendee>> {
    let subtype = serde_json::to_value(event.event_subtype)
        .ok()
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_else(|| "generic".into());
    let facts = fishers_db::repos::passes::SessionFacts {
        club_id: event.club_id,
        event_id: Some(event.id),
        subtype,
        team_id: event.team_id,
        day: event.start_at.date_naive(),
    };
    Ok(fishers_db::repos::passes::priced(&state.pool, &facts, mode, people).await?)
}

fn split_error(e: money::SplitError) -> ApiError {
    status(StatusCode::UNPROCESSABLE_ENTITY, e.message(), e.code())
}

fn rounding_for(settings: &Option<PaymentSettings>) -> Rounding {
    if settings.as_ref().is_some_and(|s| s.round_shares_up) {
        Rounding::Up10p
    } else {
        Rounding::Exact
    }
}

async fn cost_or_409(state: &AppState, event_id: Uuid) -> ApiResult<EventCostRow> {
    repo::cost(&state.pool, event_id).await?.ok_or_else(|| {
        ApiError::conflict("This session has no cost set, so there's nothing to bill. Add a cost first.")
            .with_code("no_cost")
    })
}

#[derive(Debug, Serialize)]
struct PreviewShare {
    user_id: Option<Uuid>,
    name: String,
    amount_cents: i64,
    /// Owing nothing, and why: "Covered by Winter nets pass", "Free: Coach".
    covered: Option<String>,
}

#[derive(Debug, Serialize)]
struct Preview {
    shares: Vec<PreviewShare>,
    total_cents: i64,
    surplus_cents: i64,
    currency: String,
}

async fn preview_bill(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
    Json(body): Json<BillBody>,
) -> ApiResult<Json<Preview>> {
    let event = event_or_404(&state, event_id).await?;
    require_can_bill(&state, &event, auth.user_id).await?;
    let cost = cost_or_409(&state, event_id).await?;
    let settings = repo::settings(&state.pool, event.club_id).await?;
    let people = attendees_for(&mut *state.pool.acquire().await?, event.club_id, &body).await?;
    let people = priced(&state, &event, cost.mode(), people).await?;
    let split = money::split(cost.mode(), cost.amount_cents, people.len(), rounding_for(&settings)).map_err(split_error)?;
    let shares: Vec<PreviewShare> = people
        .into_iter()
        .zip(&split.shares)
        .map(|(p, standard)| {
            let amount = match (cost.mode(), p.amount_cents) {
                (CostMode::PerPlayer, Some(own)) if own > 0 => own,
                _ => *standard,
            };
            let covered = p.cover.as_ref().map(|c| match c {
                repo::Cover::Pass { plan_name, .. } => format!("Covered by {plan_name}"),
                repo::Cover::Free { price_type } => format!("Free: {price_type}"),
            });
            PreviewShare { user_id: p.user_id, name: p.name, amount_cents: amount, covered }
        })
        .collect();
    Ok(Json(Preview {
        total_cents: shares.iter().filter(|s| s.covered.is_none()).map(|s| s.amount_cents).sum(),
        surplus_cents: split.surplus_cents,
        currency: cost.currency,
        shares,
    }))
}

async fn send_bill(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
    Json(body): Json<BillBody>,
) -> ApiResult<Json<BillResponse>> {
    let event = event_or_404(&state, event_id).await?;
    require_can_bill(&state, &event, auth.user_id).await?;
    let cost = cost_or_409(&state, event_id).await?;
    let settings = repo::settings(&state.pool, event.club_id).await?;
    let note = body.note.as_deref().map(str::trim).filter(|n| !n.is_empty() && n.chars().count() <= 200);
    let payout = accounts(&state, event.club_id).await?.current().map(|a| a.id);

    let mut tx = state.pool.begin().await?;
    let people = attendees_for(&mut tx, event.club_id, &body).await?;
    let people = priced(&state, &event, cost.mode(), people).await?;
    let came: Vec<Uuid> = people.iter().filter_map(|p| p.user_id).collect();
    let outcome = repo::issue_bill(
        &mut tx,
        &BillInput {
            event_id,
            club_id: event.club_id,
            title: &event.title,
            event_start_at: event.start_at,
            mode: cost.mode(),
            amount_cents: cost.amount_cents,
            currency: &cost.currency,
            rounding: rounding_for(&settings),
            payout_account_id: payout,
            attendees: people,
            note,
            by: Some(auth.user_id),
            auto: false,
            expected_version: body.version,
        },
    )
    .await
    .map_err(|e| match e {
        BillError::Split(s) => split_error(s),
        BillError::VersionConflict { current } => ApiError::conflict(format!(
            "Somebody changed this bill a moment ago (it's now version {current}). Reload it and try again."
        ))
        .with_code("version_conflict"),
        BillError::Mismatch { live: true } => {
            ApiError::conflict("This one has just been billed by somebody else. Reload it.").with_code("already_billed")
        }
        BillError::Mismatch { live: false } => {
            ApiError::conflict("There's no bill to re-split any more. Reload it.").with_code("version_conflict")
        }
        BillError::Db(e) => e.into(),
    })?;
    repo::record_attendance(&mut tx, event_id, &came).await?;
    repo::enable_payments(&mut tx, event.club_id).await?;
    repo::audit(
        &mut tx,
        event.club_id,
        Some(auth.user_id),
        if outcome.resplit { "resplit_bill" } else { "send_bill" },
        "bill",
        Some(outcome.bill.id),
        None,
        Some(json!({ "event_id": event_id, "people": came.len() + body.guests.len(),
                     "total_cents": outcome.bill.total_cents, "version": outcome.bill.version })),
    )
    .await?;
    tx.commit().await?;

    tell_players_about_bill(&state, &outcome.bill, &outcome.changed, outcome.resplit, Some(auth.user_id)).await;
    for user in outcome.removed.iter().filter(|u| **u != auth.user_id) {
        state
            .notify_text(
                *user,
                "bill_updated",
                &outcome.bill.title,
                "You've been taken off this bill, so you don't owe anything for it. Anything you'd paid counts as credit.",
                json!({ "event_id": event_id, "club_id": event.club_id }),
            )
            .await;
    }
    Ok(Json(bill_response(&state, &event, auth.user_id).await?))
}

/// "Friday nets: your share is £6.67." To the members whose share is new or
/// changed — never to the person who pressed the button about their own.
pub(crate) async fn tell_players_about_bill(
    state: &AppState,
    bill: &BillRow,
    changed: &[(Uuid, i64)],
    resplit: bool,
    sender: Option<Uuid>,
) {
    let club = repo::club_name(&state.pool, bill.club_id).await.ok().flatten().unwrap_or_default();
    for (user, amount) in changed {
        if Some(*user) == sender {
            continue;
        }
        let money = fmt_money(*amount, &bill.currency);
        let body = if resplit {
            format!("The bill changed: your share is now {money}. Pay {club} by bank transfer in the app.")
        } else {
            format!("Your share is {money}. Pay {club} by bank transfer in the app.")
        };
        state
            .notify_text(
                *user,
                if resplit { "bill_updated" } else { "bill_issued" },
                &bill.title,
                &body,
                json!({ "event_id": bill.event_id, "club_id": bill.club_id }),
            )
            .await;
    }
}

#[derive(Debug, Deserialize)]
struct VoidBody {
    reason: Option<String>,
}

async fn void_bill(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
    Json(body): Json<VoidBody>,
) -> ApiResult<Json<BillResponse>> {
    let event = event_or_404(&state, event_id).await?;
    require_can_bill(&state, &event, auth.user_id).await?;
    let reason = reason_required(body.reason.as_deref(), "the bill is being cancelled")?;
    // Who was on it, read before it goes: they are the ones to tell.
    let on_bill: Vec<Uuid> = match repo::live_bill(&state.pool, event_id).await? {
        Some(b) => repo::bill_shares(&state.pool, b.id)
            .await?
            .into_iter()
            .filter(|s| s.status == "live")
            .filter_map(|s| s.user_id)
            .collect(),
        None => Vec::new(),
    };
    let mut tx = state.pool.begin().await?;
    let bill = repo::void_bill(&mut tx, event_id, auth.user_id, &reason)
        .await?
        .ok_or_else(|| ApiError::conflict("There's no bill to cancel.").with_code("no_bill"))?;
    repo::audit(&mut tx, event.club_id, Some(auth.user_id), "cancel_bill", "bill", Some(bill.id), None,
        Some(json!({ "reason": reason }))).await?;
    tx.commit().await?;

    for user in on_bill.into_iter().filter(|u| *u != auth.user_id) {
        state
            .notify_text(
                user,
                "bill_cancelled",
                &bill.title,
                &format!("The bill was cancelled: {reason}. Anything you'd paid towards it counts as credit."),
                json!({ "event_id": event_id, "club_id": event.club_id }),
            )
            .await;
    }
    Ok(Json(bill_response(&state, &event, auth.user_id).await?))
}

// MARK: shares

async fn waive_share(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(share_id): Path<Uuid>,
    Json(body): Json<ReasonBody>,
) -> ApiResult<Json<ShareView>> {
    let share = repo::share(&state.pool, share_id).await?.ok_or_else(|| ApiError::not_found("no such share"))?;
    require_money_admin(&state, share.club_id, auth.user_id).await?;
    let reason = reason_required(body.reason.as_deref(), "it's being let off")?;
    let mut tx = state.pool.begin().await?;
    if !repo::waive_share(&mut tx, share_id, auth.user_id, &reason).await? {
        return Err(ApiError::conflict("That share isn't owed any more").with_code("not_live"));
    }
    repo::audit(&mut tx, share.club_id, Some(auth.user_id), "waive_share", "share", Some(share_id),
        Some(json!({ "name": share.name, "amount_cents": share.amount_cents })), Some(json!({ "reason": reason }))).await?;
    tx.commit().await?;
    let after = repo::share(&state.pool, share_id).await?.ok_or_else(|| ApiError::not_found("no such share"))?;
    Ok(Json(share_view(&after, None)))
}

// MARK: the player's side

#[derive(Debug, Serialize)]
struct ClubDues {
    club_id: Uuid,
    club_name: String,
    currency: String,
    owed_cents: i64,
    waiting_cents: i64,
    credit_cents: i64,
    /// Still to pay or waiting, then the most recent paid ones.
    shares: Vec<ShareView>,
}

#[derive(Debug, Serialize)]
struct Dues {
    clubs: Vec<ClubDues>,
    /// What the people you pay for owe (a parent's juniors), club by club.
    people: Vec<PersonDues>,
}

#[derive(Debug, Serialize)]
struct PersonDues {
    user_id: Uuid,
    name: String,
    /// No sign-in of their own: you look after their account.
    managed: bool,
    club_id: Uuid,
    dues: ClubDues,
}

fn dues_for(club_id: Uuid, club_name: String, ledger: &Ledger, payer: &Payer) -> ClubDues {
    let settled = ledger.of(payer);
    let mut open = Vec::new();
    let mut paid = Vec::new();
    for s in ledger.shares.iter().filter(|s| &s.payer() == payer) {
        let v = share_view(s, ledger.progress(s));
        if v.state == ShareState::Paid {
            paid.push(v);
        } else {
            open.push(v);
        }
    }
    open.sort_by_key(|v| v.event_start_at);
    paid.sort_by_key(|v| std::cmp::Reverse(v.event_start_at));
    paid.truncate(10);
    let currency = ledger.shares.last().map(|s| s.currency.clone()).unwrap_or_else(|| "GBP".into());
    open.extend(paid);
    ClubDues {
        club_id,
        club_name,
        currency,
        owed_cents: settled.owed_cents,
        waiting_cents: settled.waiting_cents,
        credit_cents: settled.credit_cents,
        shares: open,
    }
}

async fn my_dues(State(state): State<AppState>, auth: AuthUser) -> ApiResult<Json<Dues>> {
    let mut clubs = Vec::new();
    for (club_id, name) in repo::clubs_with_money(&state.pool, auth.user_id).await? {
        let ledger = Ledger::load(&state, club_id, Some(auth.user_id)).await?;
        clubs.push(dues_for(club_id, name, &ledger, &Payer::Member(auth.user_id)));
    }
    let mut people = Vec::new();
    for d in fishers_db::repos::passes::dependents(&state.pool, auth.user_id).await? {
        let club_name = repo::club_name(&state.pool, d.club_id).await?.unwrap_or_default();
        let ledger = Ledger::load(&state, d.club_id, Some(d.member_id)).await?;
        people.push(PersonDues {
            user_id: d.member_id,
            name: d.name,
            managed: d.managed,
            club_id: d.club_id,
            dues: dues_for(d.club_id, club_name, &ledger, &Payer::Member(d.member_id)),
        });
    }
    Ok(Json(Dues { clubs, people }))
}

/// This member's reference with this club, made the first time it is needed.
pub(crate) async fn reference_for(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<String> {
    // The same reference for good, so a player can save the club as a payee
    // once. Made the first time it is needed: their surname, or the surname
    // with a number when another member of the club already has it.
    for _ in 0..8 {
        if let Some(code) = repo::reference_code(&state.pool, club_id, user_id).await? {
            return Ok(code);
        }
        let name = repo::user_name(&state.pool, user_id).await?.unwrap_or_default();
        let base = money::reference_base(&name);
        let taken = repo::references_like(&state.pool, club_id, &base).await?;
        let code = (1..=99)
            .map(|n| money::reference_numbered(&base, n))
            .find(|c| !taken.contains(c))
            .ok_or_else(|| ApiError::internal("could not make a payment reference"))?;
        match repo::store_reference_code(&state.pool, club_id, user_id, &code).await {
            Ok(()) => continue, // read it back: a concurrent request may have won
            Err(sqlx::Error::Database(db)) if db.constraint() == Some("payment_references_club_id_code_key") => continue,
            Err(e) => return Err(e.into()),
        }
    }
    Err(ApiError::internal("could not make a payment reference"))
}

#[derive(Debug, Serialize)]
pub(crate) struct BankDetails {
    pub(crate) label: String,
    pub(crate) holder_name: String,
    pub(crate) sort_code: String,
    pub(crate) account_number: String,
    pub(crate) is_personal: bool,
    /// When these replaced older details, if recently: say so to the player.
    pub(crate) changed_at: Option<DateTime<Utc>>,
    /// Who the money goes to, in words a player understands: "Aman Gill, the
    /// club secretary". `role` is secretary, treasurer or owner — what the
    /// person who added the details is to the club — or null for a club account.
    pub(crate) payee_role: Option<&'static str>,
}

/// What the person who added these details is to the club, for "Pay Aman
/// Gill, the club secretary". Only said of a personal account: a club account
/// is the club's.
pub(crate) async fn payee_role(state: &AppState, row: &PayoutAccountRow) -> Option<&'static str> {
    if !row.is_personal {
        return None;
    }
    let by = row.created_by?;
    // Only when the account is the adder's own: a treasurer who adds the
    // secretary's account mustn't make it read "the club treasurer".
    let adder = repo::user_name(&state.pool, by).await.ok().flatten()?;
    if !money::same_person(&row.holder_name, &adder) {
        return None;
    }
    let r = repo::money_role(&state.pool, row.club_id, by).await.ok().flatten()?;
    if r.is_treasurer {
        Some("treasurer")
    } else if r.is_secretary {
        Some("secretary")
    } else if r.is_owner {
        Some("owner")
    } else {
        None
    }
}

/// The club's bank details as a player is shown them, and which of the
/// states the pay screen speaks of: `active` (details below), `none` (the club
/// hasn't added any), `frozen` (being checked: don't pay) or `unreadable` (the
/// club must enter them again). Each time a number is shown, an audit row
/// says who saw it — a member, or a pay link with the caller's hashed address.
pub(crate) async fn club_bank_details(
    state: &AppState,
    club_id: Uuid,
    all: &Accounts,
    viewer: Option<Uuid>,
    via_link: Option<(Uuid, String)>,
) -> ApiResult<(&'static str, Option<BankDetails>)> {
    let Some(row) = all.current() else {
        return Ok(if all.find(PayoutState::Frozen).is_some() { ("frozen", None) } else { ("none", None) });
    };
    match row.details_ciphertext.as_deref().map(|c| state.payout_crypto.open(club_id, c, &row.key_id)) {
        Some(Ok(details)) => {
            let mut conn = state.pool.acquire().await?;
            let after = via_link.as_ref().map(|(link, ip)| json!({ "pay_link": link, "ip": ip }));
            repo::audit(&mut conn, club_id, viewer, "reveal", "payout_account", Some(row.id), None, after).await?;
            Ok((
                "active",
                Some(BankDetails {
                    label: row.label.clone(),
                    holder_name: row.holder_name.clone(),
                    sort_code: row.sort_code.as_deref().map(money::fmt_sort_code).unwrap_or_default(),
                    account_number: details.account_number,
                    is_personal: row.is_personal,
                    changed_at: all.changed_at(),
                    payee_role: payee_role(state, row).await,
                }),
            ))
        }
        _ => {
            warn!(%club_id, "bank details could not be opened — key missing or data damaged");
            Ok(("unreadable", None))
        }
    }
}

#[derive(Debug, Serialize)]
struct PayScreen {
    club_id: Uuid,
    club_name: String,
    currency: String,
    owed_cents: i64,
    waiting_cents: i64,
    credit_cents: i64,
    shares: Vec<ShareView>,
    /// `active` (details below), `none` (the club hasn't added any),
    /// `frozen` (being checked: don't pay), `unreadable` (the club must enter
    /// them again) or `nothing_owed`.
    account_state: &'static str,
    account: Option<BankDetails>,
    reference: String,
    /// Your claims nobody has confirmed yet.
    claims: Vec<PaymentRow>,
}

async fn pay_screen(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<PayScreen>> {
    let r = role(&state, club_id, auth.user_id).await?;
    let ledger = Ledger::load(&state, club_id, Some(auth.user_id)).await?;
    let payer = Payer::Member(auth.user_id);
    let settled = ledger.of(&payer);
    let owes = settled.owed_cents > 0 || settled.waiting_cents > 0;
    // A former member who still owes can still see what to pay.
    if !(r.is_member || r.is_owner || owes) {
        return Err(ApiError::forbidden("You're not a member of this club").with_code("not_member"));
    }
    let club_name = repo::club_name(&state.pool, club_id).await?.unwrap_or_default();
    let dues = dues_for(club_id, club_name.clone(), &ledger, &payer);
    let all = accounts(&state, club_id).await?;

    let (account_state, account) = if !owes && !r.is_admin() {
        ("nothing_owed", None)
    } else {
        if repo::recent_reveals(&state.pool, auth.user_id).await? >= REVEALS_PER_HOUR {
            return Err(ApiError::too_many("That's a lot of looks at bank details. Try again in an hour.")
                .with_code("too_many_reveals"));
        }
        club_bank_details(&state, club_id, &all, Some(auth.user_id), None).await?
    };

    let claims = repo::user_payments(&state.pool, club_id, auth.user_id, 20)
        .await?
        .into_iter()
        .filter(|p| p.status == "claimed")
        .collect();
    Ok(Json(PayScreen {
        club_id,
        club_name,
        currency: dues.currency.clone(),
        owed_cents: dues.owed_cents,
        waiting_cents: dues.waiting_cents,
        credit_cents: dues.credit_cents,
        shares: dues.shares.into_iter().filter(|s| s.state != ShareState::Paid).collect(),
        account_state,
        account,
        reference: reference_for(&state, club_id, auth.user_id).await?,
        claims,
    }))
}

#[derive(Debug, Deserialize)]
struct ClaimBody {
    amount_cents: Option<i64>,
    method: String,
    note: Option<String>,
}

fn clean_note(note: Option<&str>) -> ApiResult<Option<String>> {
    let n = note.map(str::trim).filter(|n| !n.is_empty());
    if n.is_some_and(|n| n.chars().count() > 200) {
        return Err(ApiError::bad_request("Keep the note to 200 characters"));
    }
    Ok(n.map(str::to_string))
}

async fn claim_payment(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(club_id): Path<Uuid>,
    Json(body): Json<ClaimBody>,
) -> ApiResult<Json<PaymentRow>> {
    let r = role(&state, club_id, auth.user_id).await?;
    if !matches!(body.method.as_str(), "transfer" | "cash") {
        return Err(ApiError::bad_request("method is transfer or cash"));
    }
    let key = idempotency_key(&headers)?;
    // A retry of a claim already made (a bad signal, a double tap) answers
    // with that claim, before anything is checked against the balance — which
    // the first attempt has just changed.
    if let Some(k) = key.as_deref() {
        if let Some(existing) = repo::payment_by_key(&state.pool, auth.user_id, k).await? {
            if existing.club_id != club_id {
                return Err(ApiError::conflict("That Idempotency-Key was already used for another club"));
            }
            return Ok(Json(existing));
        }
    }
    let note = clean_note(body.note.as_deref())?;
    let ledger = Ledger::load(&state, club_id, Some(auth.user_id)).await?;
    let currency = ledger.shares.last().map(|s| s.currency.clone()).unwrap_or_else(|| "GBP".into());
    let settled = ledger.of(&Payer::Member(auth.user_id));
    if !(r.is_member || r.is_owner || settled.owed_cents > 0) {
        return Err(ApiError::forbidden("You're not a member of this club").with_code("not_member"));
    }
    if settled.owed_cents <= 0 {
        return Err(ApiError::conflict(if settled.waiting_cents > 0 {
            "You've already said you paid. The club just needs to confirm it."
        } else {
            "You don't owe the club anything."
        })
        .with_code("nothing_owed"));
    }
    let amount = body.amount_cents.unwrap_or(settled.owed_cents);
    if amount <= 0 || amount > money::MAX_SHARE_CENTS {
        return Err(ApiError::bad_request(format!(
            "The amount has to be more than zero and at most {}",
            fmt_money(money::MAX_SHARE_CENTS, &currency)
        ))
        .with_code("bad_amount"));
    }
    let name = repo::user_name(&state.pool, auth.user_id).await?.unwrap_or_default();
    let (reference, payout) = if body.method == "transfer" {
        (Some(reference_for(&state, club_id, auth.user_id).await?), accounts(&state, club_id).await?.current().map(|a| a.id))
    } else {
        (None, None)
    };

    let mut tx = state.pool.begin().await?;
    let (row, created) = repo::insert_payment(
        &mut tx,
        &NewPayment {
            club_id,
            user_id: Some(auth.user_id),
            guest_name: None,
            name: &name,
            amount_cents: amount,
            currency: &currency,
            method: &body.method,
            reference: reference.as_deref(),
            payout_account_id: payout,
            status: "claimed",
            note: note.as_deref(),
            idempotency_key: key.as_deref(),
            created_by: Some(auth.user_id),
            via_link: None,
            share_id: None,
        },
    )
    .await?;
    if row.club_id != club_id {
        return Err(ApiError::conflict("That Idempotency-Key was already used for another club"));
    }
    if created {
        repo::audit(&mut tx, club_id, Some(auth.user_id), "claim_payment", "payment", Some(row.id), None,
            Some(json!({ "amount_cents": amount, "method": body.method, "reference": reference }))).await?;
    }
    tx.commit().await?;

    if created {
        let money = fmt_money(amount, &currency);
        let how = match reference.as_deref() {
            Some(r) => format!("by bank transfer, reference {r}"),
            None => "in cash".to_string(),
        };
        let admins = repo::money_admins(&state.pool, club_id).await?;
        for checker in repo::payment_checkers(&admins) {
            if checker == auth.user_id {
                continue;
            }
            state
                .notify_text(
                    checker,
                    "payment_claimed",
                    &format!("{} says they paid {money}", first_name(&name)),
                    &format!("{name} says they paid {money} {how}. Check it arrived, then confirm it in the app."),
                    json!({ "club_id": club_id, "payment_id": row.id }),
                )
                .await;
        }
    }
    Ok(Json(row))
}

async fn cancel_claim(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(pid): Path<Uuid>,
) -> ApiResult<StatusCode> {
    let payment = repo::payment(&state.pool, pid).await?.ok_or_else(|| ApiError::not_found("no such payment"))?;
    if payment.user_id != Some(auth.user_id) {
        return Err(ApiError::not_found("no such payment"));
    }
    let mut tx = state.pool.begin().await?;
    if !repo::cancel_claim(&mut tx, pid, auth.user_id).await? {
        return Err(ApiError::conflict("The club has already dealt with that payment").with_code("already_decided"));
    }
    repo::audit(&mut tx, payment.club_id, Some(auth.user_id), "cancel_claim", "payment", Some(pid), None, None).await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// MARK: the treasurer's side

#[derive(Debug, Deserialize)]
struct ListQuery {
    status: Option<String>,
    limit: Option<i64>,
}

async fn list_payments(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Query(q): Query<ListQuery>,
) -> ApiResult<Json<Vec<PaymentRow>>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    let status = q.status.as_deref().filter(|s| *s != "all");
    if let Some(s) = status {
        if !matches!(s, "claimed" | "confirmed" | "rejected" | "cancelled") {
            return Err(ApiError::bad_request("status is claimed, confirmed, rejected, cancelled or all"));
        }
    }
    Ok(Json(repo::club_payments(&state.pool, club_id, status, q.limit.unwrap_or(100)).await?))
}

pub(crate) async fn decide(
    state: &AppState,
    by: Uuid,
    pid: Uuid,
    confirm: bool,
    reason: Option<String>,
) -> ApiResult<PaymentRow> {
    let payment = repo::payment(&state.pool, pid).await?.ok_or_else(|| ApiError::not_found("no such payment"))?;
    require_money_admin(state, payment.club_id, by).await?;
    let reason = if confirm { None } else { Some(reason_required(reason.as_deref(), "it's being turned down")?) };
    let mut tx = state.pool.begin().await?;
    let new_status = if confirm { "confirmed" } else { "rejected" };
    if !repo::decide_payment(&mut tx, pid, new_status, by, reason.as_deref()).await? {
        return Err(ApiError::conflict(format!("That payment was already {}", payment.status))
            .with_code("already_decided"));
    }
    repo::audit(&mut tx, payment.club_id, Some(by), if confirm { "confirm_payment" } else { "reject_payment" },
        "payment", Some(pid), Some(json!({ "status": payment.status })), Some(json!({ "status": new_status, "reason": reason })))
        .await?;
    tx.commit().await?;

    if let Some(payer) = payment.user_id {
        let club = repo::club_name(&state.pool, payment.club_id).await?.unwrap_or_default();
        let money = fmt_money(payment.amount_cents, &payment.currency);
        let (kind, title, body) = if confirm {
            ("payment_confirmed", format!("{club} got your {money}"), format!("{club} confirmed your payment of {money}. Thanks!"))
        } else {
            (
                "payment_rejected",
                format!("{club} couldn't find your {money}"),
                format!(
                    "{club} couldn't find your payment of {money}: {}. Check your banking app, then pay or tell them.",
                    reason.as_deref().unwrap_or("")
                ),
            )
        };
        if payer != by {
            state.notify_text(payer, kind, &title, &body, json!({ "club_id": payment.club_id, "payment_id": pid })).await;
        }
    }
    repo::payment(&state.pool, pid).await?.ok_or_else(|| ApiError::not_found("no such payment"))
}

async fn confirm_payment(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(pid): Path<Uuid>,
) -> ApiResult<Json<PaymentRow>> {
    Ok(Json(decide(&state, auth.user_id, pid, true, None).await?))
}

async fn reject_payment(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(pid): Path<Uuid>,
    Json(body): Json<ReasonBody>,
) -> ApiResult<Json<PaymentRow>> {
    Ok(Json(decide(&state, auth.user_id, pid, false, body.reason).await?))
}

#[derive(Debug, Deserialize)]
struct RecordBody {
    user_id: Option<Uuid>,
    guest_name: Option<String>,
    amount_cents: i64,
    method: Option<String>,
    note: Option<String>,
}

/// Who a treasurer is recording money for, and their name.
async fn payer_for(state: &AppState, club_id: Uuid, body: &RecordBody, ledger: &Ledger) -> ApiResult<(Payer, String)> {
    match (body.user_id, body.guest_name.as_deref().map(str::trim).filter(|g| !g.is_empty())) {
        (Some(user), None) => {
            let payer = Payer::Member(user);
            let member = role(state, club_id, user).await?.is_member;
            if !member && !ledger.by_payer.contains_key(&payer) {
                return Err(ApiError::bad_request("They aren't a member and have never been billed by this club"));
            }
            let name = repo::user_name(&state.pool, user).await?.unwrap_or_default();
            Ok((payer, name))
        }
        (None, Some(guest)) => {
            let payer = Payer::of(None, Some(guest));
            let name = ledger.names.get(&payer).cloned().unwrap_or_else(|| guest.to_string());
            Ok((payer, name))
        }
        _ => Err(ApiError::bad_request("Say who paid: a member (user_id) or a guest (guest_name), not both")),
    }
}

async fn record_payment(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(club_id): Path<Uuid>,
    Json(body): Json<RecordBody>,
) -> ApiResult<Json<PaymentRow>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    let method = body.method.as_deref().unwrap_or("cash");
    if !matches!(method, "cash" | "transfer") {
        return Err(ApiError::bad_request("method is cash or transfer"));
    }
    let key = idempotency_key(&headers)?;
    if let Some(existing) = retried(&state, auth.user_id, club_id, key.as_deref()).await? {
        return Ok(Json(existing));
    }
    let note = clean_note(body.note.as_deref())?;
    let ledger = Ledger::load(&state, club_id, None).await?;
    let currency = ledger.shares.last().map(|s| s.currency.clone()).unwrap_or_else(|| "GBP".into());
    if body.amount_cents <= 0 || body.amount_cents > money::MAX_SHARE_CENTS {
        return Err(ApiError::bad_request(format!(
            "The amount has to be more than zero and at most {}",
            fmt_money(money::MAX_SHARE_CENTS, &currency)
        ))
        .with_code("bad_amount"));
    }
    let (payer, name) = payer_for(&state, club_id, &body, &ledger).await?;
    let (user_id, guest) = match &payer {
        Payer::Member(id) => (Some(*id), None),
        Payer::Guest(_) => (None, Some(name.as_str())),
    };
    let mut tx = state.pool.begin().await?;
    let (row, created) = repo::insert_payment(
        &mut tx,
        &NewPayment {
            club_id,
            user_id,
            guest_name: guest,
            name: &name,
            amount_cents: body.amount_cents,
            currency: &currency,
            method,
            reference: None,
            payout_account_id: None,
            status: "confirmed",
            note: note.as_deref(),
            idempotency_key: key.as_deref(),
            created_by: Some(auth.user_id),
            via_link: None,
            share_id: None,
        },
    )
    .await?;
    if created {
        repo::audit(&mut tx, club_id, Some(auth.user_id), "record_payment", "payment", Some(row.id), None,
            Some(json!({ "name": name, "amount_cents": body.amount_cents, "method": method }))).await?;
    }
    tx.commit().await?;
    if let (true, Some(user)) = (created, user_id) {
        if user != auth.user_id {
            let club = repo::club_name(&state.pool, club_id).await?.unwrap_or_default();
            let money = fmt_money(body.amount_cents, &currency);
            state
                .notify_text(user, "payment_confirmed", &format!("{club} got your {money}"),
                    &format!("{club} recorded your payment of {money}. Thanks!"),
                    json!({ "club_id": club_id, "payment_id": row.id }))
                .await;
        }
    }
    Ok(Json(row))
}

async fn refund(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(club_id): Path<Uuid>,
    Json(body): Json<RecordBody>,
) -> ApiResult<Json<PaymentRow>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    let key = idempotency_key(&headers)?;
    if let Some(existing) = retried(&state, auth.user_id, club_id, key.as_deref()).await? {
        return Ok(Json(existing));
    }
    let note = clean_note(body.note.as_deref())?;
    let ledger = Ledger::load(&state, club_id, None).await?;
    let (payer, name) = payer_for(&state, club_id, &body, &ledger).await?;
    let currency = ledger.shares.last().map(|s| s.currency.clone()).unwrap_or_else(|| "GBP".into());
    let credit = ledger.of(&payer).credit_cents;
    if body.amount_cents <= 0 || body.amount_cents > credit {
        return Err(ApiError::bad_request(format!(
            "{} has {} of credit, so you can refund up to that",
            first_name(&name),
            fmt_money(credit, &currency)
        ))
        .with_code("more_than_credit"));
    }
    let (user_id, guest) = match &payer {
        Payer::Member(id) => (Some(*id), None),
        Payer::Guest(_) => (None, Some(name.as_str())),
    };
    let mut tx = state.pool.begin().await?;
    let (row, created) = repo::insert_payment(
        &mut tx,
        &NewPayment {
            club_id,
            user_id,
            guest_name: guest,
            name: &name,
            amount_cents: body.amount_cents,
            currency: &currency,
            method: "refund",
            reference: None,
            payout_account_id: None,
            status: "confirmed",
            note: note.as_deref(),
            idempotency_key: key.as_deref(),
            created_by: Some(auth.user_id),
            via_link: None,
            share_id: None,
        },
    )
    .await?;
    if created {
        repo::audit(&mut tx, club_id, Some(auth.user_id), "refund", "payment", Some(row.id), None,
            Some(json!({ "name": name, "amount_cents": body.amount_cents }))).await?;
    }
    tx.commit().await?;
    Ok(Json(row))
}

async fn audit_log(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<Vec<repo::AuditRow>>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    Ok(Json(repo::audit_log(&state.pool, club_id, 100).await?))
}

// MARK: the overview a treasurer opens

#[derive(Debug, Serialize)]
struct MemberBalance {
    user_id: Option<Uuid>,
    guest_name: Option<String>,
    name: String,
    owed_cents: i64,
    waiting_cents: i64,
    credit_cents: i64,
}

#[derive(Debug, Serialize, Default)]
struct Totals {
    owed_cents: i64,
    waiting_cents: i64,
    credit_cents: i64,
}

#[derive(Debug, Serialize)]
struct BillSummary {
    bill_id: Uuid,
    event_id: Option<Uuid>,
    title: String,
    event_start_at: DateTime<Utc>,
    currency: String,
    total_cents: i64,
    paid_cents: i64,
    waiting_cents: i64,
    owed_cents: i64,
    people: usize,
    unpaid: usize,
    waiting: usize,
}

#[derive(Debug, Serialize)]
struct MoneyOverview {
    currency: String,
    settings: PaymentSettings,
    account: PayoutAccountsView,
    to_check: Vec<PaymentRow>,
    members: Vec<MemberBalance>,
    totals: Totals,
    bills: Vec<BillSummary>,
}

async fn money_overview(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<MoneyOverview>> {
    let r = require_money_admin(&state, club_id, auth.user_id).await?;
    let settings = repo::settings(&state.pool, club_id).await?.ok_or_else(|| ApiError::not_found("club not found"))?;
    let ledger = Ledger::load(&state, club_id, None).await?;
    let mut members: Vec<MemberBalance> = ledger
        .by_payer
        .iter()
        .filter(|(_, s)| s.owed_cents > 0 || s.waiting_cents > 0 || s.credit_cents > 0)
        .map(|(payer, s)| {
            let name = ledger.names.get(payer).cloned().unwrap_or_default();
            let (user_id, guest_name) = match payer {
                Payer::Member(id) => (Some(*id), None),
                Payer::Guest(_) => (None, Some(name.clone())),
            };
            MemberBalance { user_id, guest_name, name, owed_cents: s.owed_cents, waiting_cents: s.waiting_cents, credit_cents: s.credit_cents }
        })
        .collect();
    // Names for members who have only ever paid (credit with no shares).
    for m in members.iter_mut().filter(|m| m.name.is_empty()) {
        if let Some(id) = m.user_id {
            m.name = repo::user_name(&state.pool, id).await?.unwrap_or_default();
        }
    }
    members.sort_by(|a, b| b.owed_cents.cmp(&a.owed_cents).then(a.name.to_lowercase().cmp(&b.name.to_lowercase())));
    let totals = members.iter().fold(Totals::default(), |mut t, m| {
        t.owed_cents += m.owed_cents;
        t.waiting_cents += m.waiting_cents;
        t.credit_cents += m.credit_cents;
        t
    });

    let mut bills = Vec::new();
    for b in repo::recent_bills(&state.pool, club_id, 30).await? {
        let mut sum = BillSummary {
            bill_id: b.id,
            event_id: b.event_id,
            title: b.title.clone(),
            event_start_at: b.event_start_at,
            currency: b.currency.clone(),
            total_cents: b.total_cents,
            paid_cents: 0,
            waiting_cents: 0,
            owed_cents: 0,
            people: 0,
            unpaid: 0,
            waiting: 0,
        };
        for s in ledger.shares.iter().filter(|s| s.bill_id == b.id) {
            let p = ledger.progress(s).unwrap_or_default();
            sum.people += 1;
            sum.paid_cents += p.paid_cents;
            sum.waiting_cents += p.waiting_cents;
            sum.owed_cents += s.amount_cents - p.paid_cents - p.waiting_cents;
            match p.state(s.amount_cents) {
                ShareState::Waiting => sum.waiting += 1,
                ShareState::Paid => {}
                _ => sum.unpaid += 1,
            }
        }
        bills.push(sum);
    }
    let currency = bills.first().map(|b| b.currency.clone()).unwrap_or_else(|| "GBP".into());
    let mut to_check = repo::club_payments(&state.pool, club_id, Some("claimed"), 200).await?;
    to_check.reverse(); // oldest first: the longest-waiting at the top
    Ok(Json(MoneyOverview {
        currency,
        settings,
        account: accounts(&state, club_id).await?.view(&state, r),
        to_check,
        members,
        totals,
        bills,
    }))
}

// MARK: outstanding fees, for the selection screens and the chase button

/// Billed shares still owed, as the old outstanding-fees rows, so the existing
/// "Match fees" list and "chase" button keep working on the new bills.
pub(crate) async fn billed_outstanding(
    state: &AppState,
    club_id: Uuid,
) -> ApiResult<Vec<(ShareRow, i64)>> {
    let ledger = Ledger::load(state, club_id, None).await?;
    let mut out = Vec::new();
    for s in &ledger.shares {
        if s.user_id.is_none() {
            continue;
        }
        let p = ledger.progress(s).unwrap_or_default();
        let owed = s.amount_cents - p.paid_cents - p.waiting_cents;
        if owed > 0 {
            out.push((s.clone(), owed));
        }
    }
    out.sort_by(|a, b| b.0.event_start_at.cmp(&a.0.event_start_at).then(a.0.name.cmp(&b.0.name)));
    Ok(out)
}
