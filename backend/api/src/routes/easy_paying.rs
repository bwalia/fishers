//! Easy paying: pay links from WhatsApp with no sign-in, "all arrived", cash
//! at the ground, and payment screenshots. See docs/CLUB_PAYMENTS_V2_PLAN.md,
//! step A.
//!
//! **What a pay link can do, and why that is safe.** Anyone holding the link
//! can see one bill's names, each person's amount, and the club's bank
//! details — the same things clubs already post in their WhatsApp group — and
//! say "I've paid" for somebody on it. That is a *claim*: a treasurer still
//! checks the bank before anything counts as paid, so a wrong or mischievous
//! tap costs one "not received". It can never confirm a payment, change an
//! amount or see anybody's history.
//!
//! The guards: the token is unforgeable (`services::pay_links`); links close
//! after 30 days, when the bill is cancelled, or when a secretary switches
//! them off; every view and claim is audited with a hashed address; each
//! address and each link is throttled; one open claim per person per bill; and
//! a claim made by mistake can be taken back from the same link within the hour.

use std::sync::LazyLock;
use std::time::Duration as StdDuration;

use axum::body::Bytes;
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::{DateTime, Duration, Utc};
use fishers_db::repos::club_payments::{self as repo, NewPayment, PaymentRow, Payer, ShareRow};
use fishers_domain::money::{self, fmt_money, ShareState};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use super::club_payments::{
    accounts, club_bank_details, decide, event_or_404, first_name, idempotency_key, reference_for,
    require_can_bill, require_money_admin, share_view, status, BankDetails, Ledger, ShareView,
};
use crate::auth::{decode_token, AuthUser};
use crate::error::{ApiError, ApiResult};
use crate::services::pay_links::{token_fingerprint, Throttle};
use crate::state::AppState;

/// How long a pay link stays open.
const LINK_DAYS: i64 = 30;
/// Claims one link may take in an hour before it looks like abuse.
const CLAIMS_PER_LINK_HOUR: i64 = 100;
/// How long a mistaken claim can be taken back from the link.
const UNDO_MINUTES: i64 = 60;
/// A screenshot is attached within this long of the claim.
const SCREENSHOT_MINUTES: i64 = 120;
/// The request body limit is a megabyte; the apps shrink a screenshot first.
const MAX_SCREENSHOT_BYTES: usize = 1_000_000;

static VIEWS: LazyLock<Throttle> = LazyLock::new(|| Throttle::new(120, StdDuration::from_secs(60)));
static CLAIMS: LazyLock<Throttle> = LazyLock::new(|| Throttle::new(20, StdDuration::from_secs(3600)));

pub fn router() -> Router<AppState> {
    Router::new()
        // Public: what the WhatsApp link opens. No sign-in.
        .route("/pay-links/{token}", get(link_page))
        .route("/pay-links/{token}/people/{share_id}", get(link_person))
        .route("/pay-links/{token}/people/{share_id}/claim", post(link_claim))
        .route("/pay-links/{token}/claims/{pid}", axum::routing::delete(link_undo))
        .route("/pay-links/{token}/claims/{pid}/screenshot", post(link_screenshot))
        // Whoever runs the session.
        .route("/events/{id}/bill/link", post(make_link))
        .route("/events/{id}/bill/link/disable", post(disable_link))
        .route("/events/{id}/bill/cash", post(cash_at_ground))
        // Money admins.
        .route("/clubs/{id}/payments/confirm", post(confirm_many))
        .route("/payments/{pid}/screenshot", get(view_screenshot).post(upload_screenshot))
}

// MARK: opening a link

fn link_closed() -> ApiError {
    status(
        StatusCode::GONE,
        "This pay link has closed. Ask your secretary to share the latest one.",
        "link_closed",
    )
}

/// The link a token names, open. Throttled per address before anything else.
async fn open_link(state: &AppState, token: &str, headers: &HeaderMap) -> ApiResult<repo::PayLinkRow> {
    let ip = crate::services::pay_links::client_ip(headers);
    if !VIEWS.allow(&format!("{ip}|{}", token_fingerprint(token))) || !VIEWS.allow(&ip) {
        return Err(ApiError::too_many("Too many tries. Wait a minute and open the link again.").with_code("slow_down"));
    }
    let id = state.pay_links.open(token).ok_or_else(|| {
        ApiError::not_found("This pay link isn't right. Ask your secretary to share it again.").with_code("bad_link")
    })?;
    let link = repo::pay_link(&state.pool, id).await?.ok_or_else(link_closed)?;
    if !link.is_open(Utc::now()) {
        return Err(link_closed());
    }
    Ok(link)
}

/// Who is asking, if they happen to be signed in on this phone. Never
/// required: a link works for anybody holding it.
fn signed_in(state: &AppState, headers: &HeaderMap) -> Option<Uuid> {
    let token = headers.get(header::AUTHORIZATION)?.to_str().ok()?.strip_prefix("Bearer ")?;
    let claims = decode_token(state, token).ok()?;
    (claims.typ == "access").then_some(claims.sub)
}

#[derive(Debug, Serialize)]
struct LinkPerson {
    id: Uuid,
    name: String,
}

#[derive(Debug, Serialize)]
struct LinkPage {
    club_name: String,
    title: String,
    event_start_at: DateTime<Utc>,
    currency: String,
    expires_at: DateTime<Utc>,
    /// Everybody on the bill, by name only: tap yours to see what you owe.
    people: Vec<LinkPerson>,
    /// Your share, when you are signed in on this phone and on the bill.
    me: Option<Uuid>,
    account_state: &'static str,
    account: Option<BankDetails>,
}

async fn link_page(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(token): Path<String>,
) -> ApiResult<Json<LinkPage>> {
    let link = open_link(&state, &token, &headers).await?;
    let shares = repo::bill_shares(&state.pool, link.bill_id).await?;
    let bill = repo::live_bill(&state.pool, link.event_id).await?.ok_or_else(link_closed)?;
    let club_name = repo::club_name(&state.pool, link.club_id).await?.unwrap_or_default();
    let me = signed_in(&state, &headers).and_then(|u| shares.iter().find(|s| s.user_id == Some(u)).map(|s| s.id));
    let all = accounts(&state, link.club_id).await?;
    let ip = state.pay_links.ip_hash(&headers);
    let (account_state, account) = club_bank_details(&state, link.club_id, &all, None, Some((link.id, ip))).await?;
    Ok(Json(LinkPage {
        club_name,
        title: bill.title.clone(),
        event_start_at: bill.event_start_at,
        currency: bill.currency.clone(),
        expires_at: link.expires_at,
        people: shares.iter().filter(|s| s.status == "live").map(|s| LinkPerson { id: s.id, name: s.name.clone() }).collect(),
        me,
        account_state,
        account,
    }))
}

#[derive(Debug, Serialize)]
struct PersonOnLink {
    #[serde(flatten)]
    share: ShareView,
    /// Still to pay on this bill: not covered by anything, paid or claimed.
    owed_cents: i64,
    /// What to write in the reference box.
    reference: String,
    /// A claim waiting for the treasurer, which can be taken back within the hour.
    claim: Option<LinkClaim>,
}

#[derive(Debug, Serialize)]
struct LinkClaim {
    id: Uuid,
    method: String,
    amount_cents: i64,
    created_at: DateTime<Utc>,
    can_undo: bool,
    has_screenshot: bool,
}

impl LinkClaim {
    fn of(p: &PaymentRow, link: Uuid) -> Self {
        Self {
            id: p.id,
            method: p.method.clone(),
            amount_cents: p.amount_cents,
            created_at: p.created_at,
            can_undo: p.via_link == Some(link) && Utc::now() - p.created_at < Duration::minutes(UNDO_MINUTES),
            has_screenshot: p.has_screenshot,
        }
    }
}

/// One person's line on the bill, worked out from the club's whole ledger so
/// their credit and earlier payments count, as they do everywhere else.
async fn person(state: &AppState, link: &repo::PayLinkRow, share: &ShareRow) -> ApiResult<PersonOnLink> {
    let ledger = Ledger::load(state, link.club_id, share.user_id).await?;
    let view = share_view(share, ledger.progress(share));
    let owed = if share.status == "live" { (view.amount_cents - view.paid_cents - view.waiting_cents).max(0) } else { 0 };
    let reference = match share.user_id {
        Some(user) => reference_for(state, link.club_id, user).await?,
        None => money::reference_base(share.guest_name.as_deref().unwrap_or(&share.name)),
    };
    let claim = repo::open_claim_for_share(&state.pool, share.id).await?.map(|p| LinkClaim::of(&p, link.id));
    Ok(PersonOnLink { share: view, owed_cents: owed, reference, claim })
}

async fn link_person(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((token, share_id)): Path<(String, Uuid)>,
) -> ApiResult<Json<PersonOnLink>> {
    let link = open_link(&state, &token, &headers).await?;
    let share = repo::share_on_bill(&state.pool, link.bill_id, share_id)
        .await?
        .ok_or_else(|| ApiError::not_found("That name isn't on this bill any more. Open the link again."))?;
    Ok(Json(person(&state, &link, &share).await?))
}

// MARK: "I've paid", from a link

#[derive(Debug, Deserialize)]
struct LinkClaimBody {
    method: String,
    note: Option<String>,
}

async fn link_claim(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((token, share_id)): Path<(String, Uuid)>,
    Json(body): Json<LinkClaimBody>,
) -> ApiResult<Json<PersonOnLink>> {
    let link = open_link(&state, &token, &headers).await?;
    if !matches!(body.method.as_str(), "transfer" | "cash") {
        return Err(ApiError::bad_request("method is transfer or cash"));
    }
    let key = idempotency_key(&headers)?;
    let note = body.note.as_deref().map(str::trim).filter(|n| !n.is_empty()).map(|n| n.chars().take(200).collect::<String>());
    let share = repo::share_on_bill(&state.pool, link.bill_id, share_id)
        .await?
        .ok_or_else(|| ApiError::not_found("That name isn't on this bill any more. Open the link again."))?;

    // A claim already waiting for this person — a second tap, a retry on a
    // bad signal, a friend tapping too — is that claim, not another one.
    if repo::open_claim_for_share(&state.pool, share.id).await?.is_some() {
        return Ok(Json(person(&state, &link, &share).await?));
    }
    let current = person(&state, &link, &share).await?;
    if share.status != "live" || current.owed_cents <= 0 {
        return Err(ApiError::conflict(match current.share.state {
            ShareState::Waived => "You've been let off this one. There's nothing to pay.",
            ShareState::Paid => "That's already paid. Thank you!",
            _ => "There's nothing left to pay on this one.",
        })
        .with_code("nothing_owed"));
    }
    let ip = crate::services::pay_links::client_ip(&headers);
    if !CLAIMS.allow(&ip) || repo::recent_link_claims(&state.pool, link.id).await? >= CLAIMS_PER_LINK_HOUR {
        return Err(ApiError::too_many("Too many payments from here. Try again later.").with_code("slow_down"));
    }

    let payer = share.payer();
    let (user_id, guest) = match &payer {
        Payer::Member(id) => (Some(*id), None),
        Payer::Guest(_) => (None, Some(share.name.as_str())),
    };
    let reference = (body.method == "transfer").then(|| current.reference.clone());
    let payout = accounts(&state, link.club_id).await?.current().map(|a| a.id);
    let mut tx = state.pool.begin().await?;
    let (row, created) = repo::insert_payment(
        &mut tx,
        &NewPayment {
            club_id: link.club_id,
            user_id,
            guest_name: guest,
            name: &share.name,
            amount_cents: current.owed_cents,
            currency: &share.currency,
            method: &body.method,
            reference: reference.as_deref(),
            payout_account_id: payout,
            status: "claimed",
            note: note.as_deref(),
            idempotency_key: key.as_deref(),
            created_by: None,
            via_link: Some(link.id),
            share_id: Some(share.id),
        },
    )
    .await?;
    if created {
        repo::audit(&mut tx, link.club_id, None, "link_claim", "payment", Some(row.id), None,
            Some(json!({ "share_id": share.id, "amount_cents": row.amount_cents, "method": body.method,
                         "pay_link": link.id, "ip": state.pay_links.ip_hash(&headers) }))).await?;
    }
    tx.commit().await?;

    if created {
        let money = fmt_money(row.amount_cents, &row.currency);
        let how = match reference.as_deref() {
            Some(r) => format!("by bank transfer, reference {r}"),
            None => "in cash".to_string(),
        };
        let admins = repo::money_admins(&state.pool, link.club_id).await?;
        for checker in repo::payment_checkers(&admins) {
            state
                .notify_text(
                    checker,
                    "payment_claimed",
                    &format!("{} says they paid {money}", first_name(&share.name)),
                    &format!("{} says they paid {money} {how}, from the pay link. Check it arrived, then tick it.", share.name),
                    json!({ "club_id": link.club_id, "payment_id": row.id }),
                )
                .await;
        }
    }
    Ok(Json(person(&state, &link, &share).await?))
}

/// Taken back: tapped the wrong name, or hadn't really paid yet. Only from
/// the link it was made on, within the hour, while nobody has checked it.
async fn link_undo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((token, pid)): Path<(String, Uuid)>,
) -> ApiResult<StatusCode> {
    let link = open_link(&state, &token, &headers).await?;
    let payment = repo::payment(&state.pool, pid).await?.ok_or_else(|| ApiError::not_found("no such payment"))?;
    if payment.via_link != Some(link.id) {
        return Err(ApiError::not_found("no such payment"));
    }
    if payment.status != "claimed" {
        return Err(ApiError::conflict("The club has already checked that one.").with_code("already_decided"));
    }
    if Utc::now() - payment.created_at >= Duration::minutes(UNDO_MINUTES) {
        return Err(ApiError::conflict("It's too late to take that back here. Ask your secretary.").with_code("too_late"));
    }
    let mut tx = state.pool.begin().await?;
    let done = sqlx::query("UPDATE member_payments SET status = 'cancelled', decided_at = NOW() WHERE id = $1 AND status = 'claimed'")
        .bind(pid)
        .execute(&mut *tx)
        .await?
        .rows_affected()
        == 1;
    if !done {
        return Err(ApiError::conflict("The club has already checked that one.").with_code("already_decided"));
    }
    repo::audit(&mut tx, link.club_id, None, "link_undo", "payment", Some(pid), None,
        Some(json!({ "pay_link": link.id, "ip": state.pay_links.ip_hash(&headers) }))).await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// MARK: screenshots

/// A screenshot of the payment, checked by its own bytes — never by what the
/// caller says it is — and kept private to the club's money admins.
fn checked_image(bytes: &[u8]) -> ApiResult<&'static str> {
    if bytes.is_empty() {
        return Err(ApiError::bad_request("Choose a picture of the payment"));
    }
    if bytes.len() > MAX_SCREENSHOT_BYTES {
        return Err(ApiError::bad_request("That picture is too big. Try a screenshot instead of a photo.")
            .with_code("too_big"));
    }
    super::users::sniff_image(bytes).map(|(t, _)| t).ok_or_else(|| {
        status(StatusCode::UNSUPPORTED_MEDIA_TYPE, "That isn't a picture we can keep (JPEG, PNG or WebP).", "not_an_image")
    })
}

async fn link_screenshot(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((token, pid)): Path<(String, Uuid)>,
    body: Bytes,
) -> ApiResult<StatusCode> {
    let link = open_link(&state, &token, &headers).await?;
    let payment = repo::payment(&state.pool, pid).await?.ok_or_else(|| ApiError::not_found("no such payment"))?;
    if payment.via_link != Some(link.id) || payment.status != "claimed"
        || Utc::now() - payment.created_at >= Duration::minutes(SCREENSHOT_MINUTES)
    {
        return Err(ApiError::conflict("You can only add a picture to a payment you've just made here.")
            .with_code("too_late"));
    }
    let content_type = checked_image(&body)?;
    let mut tx = state.pool.begin().await?;
    repo::put_attachment(&mut tx, pid, content_type, &body).await?;
    repo::audit(&mut tx, link.club_id, None, "attach_screenshot", "payment", Some(pid), None,
        Some(json!({ "bytes": body.len(), "pay_link": link.id }))).await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// The payer adds a screenshot to their own claim, signed in.
async fn upload_screenshot(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(pid): Path<Uuid>,
    body: Bytes,
) -> ApiResult<StatusCode> {
    let payment = repo::payment(&state.pool, pid).await?.ok_or_else(|| ApiError::not_found("no such payment"))?;
    if payment.user_id != Some(auth.user_id) && payment.created_by != Some(auth.user_id) {
        return Err(ApiError::not_found("no such payment"));
    }
    if payment.status != "claimed" {
        return Err(ApiError::conflict("The club has already checked that one.").with_code("already_decided"));
    }
    let content_type = checked_image(&body)?;
    let mut tx = state.pool.begin().await?;
    repo::put_attachment(&mut tx, pid, content_type, &body).await?;
    repo::audit(&mut tx, payment.club_id, Some(auth.user_id), "attach_screenshot", "payment", Some(pid), None,
        Some(json!({ "bytes": body.len() }))).await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Only the club's money admins see a screenshot. Served so a browser can
/// never treat it as anything but the image it was checked to be.
async fn view_screenshot(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(pid): Path<Uuid>,
) -> ApiResult<Response> {
    let payment = repo::payment(&state.pool, pid).await?.ok_or_else(|| ApiError::not_found("no such payment"))?;
    require_money_admin(&state, payment.club_id, auth.user_id).await?;
    let (content_type, bytes) =
        repo::attachment(&state.pool, pid).await?.ok_or_else(|| ApiError::not_found("No picture with this payment"))?;
    let mut response = bytes.into_response();
    let h = response.headers_mut();
    h.insert(header::CONTENT_TYPE, HeaderValue::from_str(&content_type).map_err(|_| ApiError::internal("bad type"))?);
    h.insert(header::CACHE_CONTROL, HeaderValue::from_static("private, no-store"));
    h.insert("x-content-type-options", HeaderValue::from_static("nosniff"));
    h.insert(header::CONTENT_DISPOSITION, HeaderValue::from_static("inline"));
    Ok(response)
}

// MARK: sharing to WhatsApp

#[derive(Debug, Serialize)]
struct LinkResponse {
    url: String,
    expires_at: DateTime<Utc>,
    /// "🏏 Friday nets, Fri 20 Nov: £5.00 each. Tap to pay: …"
    bill_message: String,
    /// "Still to pay for Friday nets: Josh and Imran. Tap to pay: …"
    reminder_message: String,
    /// Who still owes, for the app to show before sharing.
    still_to_pay: Vec<String>,
}

/// First names, unless two people share one: then their full names.
fn short_names(names: &[String]) -> Vec<String> {
    names
        .iter()
        .map(|n| {
            let first = first_name(n);
            if names.iter().filter(|m| first_name(m) == first).count() > 1 { n.clone() } else { first.to_string() }
        })
        .collect()
}

fn and_list(names: &[String]) -> String {
    match names {
        [] => String::new(),
        [one] => one.clone(),
        [rest @ .., last] => format!("{} and {last}", rest.join(", ")),
    }
}

async fn make_link(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
) -> ApiResult<Json<LinkResponse>> {
    let event = event_or_404(&state, event_id).await?;
    require_can_bill(&state, &event, auth.user_id).await?;
    let bill = repo::live_bill(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::conflict("Send the bill first, then share it.").with_code("no_bill"))?;
    let link = match repo::open_link_for_bill(&state.pool, bill.id).await? {
        Some(link) => link,
        None => {
            let mut tx = state.pool.begin().await?;
            let id = repo::create_pay_link(&mut tx, bill.club_id, bill.id, auth.user_id, Utc::now() + Duration::days(LINK_DAYS)).await?;
            repo::audit(&mut tx, bill.club_id, Some(auth.user_id), "make_pay_link", "bill", Some(bill.id), None,
                Some(json!({ "pay_link": id }))).await?;
            tx.commit().await?;
            repo::pay_link(&state.pool, id).await?.ok_or_else(|| ApiError::internal("pay link vanished"))?
        }
    };
    let url = format!("{}/p/{}", super::scoreboard_share::public_web_base(), state.pay_links.mint(link.id));

    let ledger = Ledger::load(&state, bill.club_id, None).await?;
    let shares = repo::bill_shares(&state.pool, bill.id).await?;
    let live: Vec<&ShareRow> = shares.iter().filter(|s| s.status == "live").collect();
    let owing: Vec<String> = live
        .iter()
        .filter(|s| {
            let p = ledger.progress(s).unwrap_or_default();
            s.amount_cents - p.paid_cents - p.waiting_cents > 0
        })
        .map(|s| s.name.clone())
        .collect();
    let when = bill.event_start_at.format("%a %-d %b");
    let amounts: std::collections::BTreeSet<i64> = live.iter().map(|s| s.amount_cents).collect();
    let price = match (amounts.len(), amounts.iter().next()) {
        (1, Some(each)) => format!("{} each", fmt_money(*each, &bill.currency)),
        _ => format!("{} between {}", fmt_money(bill.total_cents, &bill.currency), live.len()),
    };
    let bill_message = format!("🏏 {}, {when}: {price}.\nTap to pay: {url}", bill.title);
    let reminder_message = if owing.is_empty() {
        format!("Everyone has paid for {}, {when}. Thank you!", bill.title)
    } else {
        format!("Still to pay for {}, {when}: {}.\nTap to pay: {url}", bill.title, and_list(&short_names(&owing)))
    };
    Ok(Json(LinkResponse { url, expires_at: link.expires_at, bill_message, reminder_message, still_to_pay: owing }))
}

async fn disable_link(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let event = event_or_404(&state, event_id).await?;
    require_can_bill(&state, &event, auth.user_id).await?;
    let bill = repo::live_bill(&state.pool, event_id).await?.ok_or_else(|| ApiError::conflict("There's no bill.").with_code("no_bill"))?;
    let mut tx = state.pool.begin().await?;
    let n = repo::disable_links_for_bill(&mut tx, bill.id, auth.user_id).await?;
    repo::audit(&mut tx, bill.club_id, Some(auth.user_id), "disable_pay_links", "bill", Some(bill.id), None,
        Some(json!({ "links": n }))).await?;
    tx.commit().await?;
    Ok(Json(json!({ "disabled": n })))
}

// MARK: all arrived, and cash at the ground

#[derive(Debug, Deserialize)]
struct ConfirmMany {
    ids: Vec<Uuid>,
}

/// "All arrived": confirm several claims in one go. One already checked by
/// somebody else is skipped, not an error.
async fn confirm_many(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<ConfirmMany>,
) -> ApiResult<Json<serde_json::Value>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    if body.ids.len() > 200 {
        return Err(ApiError::bad_request("At most 200 at a time"));
    }
    let (mut confirmed, mut skipped) = (0, 0);
    for id in body.ids {
        match repo::payment(&state.pool, id).await? {
            Some(p) if p.club_id == club_id && p.status == "claimed" => {
                match decide(&state, auth.user_id, id, true, None).await {
                    Ok(_) => confirmed += 1,
                    Err(_) => skipped += 1,
                }
            }
            _ => skipped += 1,
        }
    }
    Ok(Json(json!({ "confirmed": confirmed, "skipped": skipped })))
}

#[derive(Debug, Deserialize)]
struct CashBody {
    share_ids: Vec<Uuid>,
}

/// Cash at the ground: tick who handed over money. A treasurer, secretary or
/// owner ticking it means received; a captain ticking it means "collected by
/// the captain", waiting for the treasurer to have the cash in hand.
async fn cash_at_ground(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
    Json(body): Json<CashBody>,
) -> ApiResult<Json<serde_json::Value>> {
    let event = event_or_404(&state, event_id).await?;
    let money = require_can_bill(&state, &event, auth.user_id).await?;
    let admin = money.is_admin();
    let bill = repo::live_bill(&state.pool, event_id).await?.ok_or_else(|| ApiError::conflict("There's no bill.").with_code("no_bill"))?;
    if body.share_ids.len() > 200 {
        return Err(ApiError::bad_request("At most 200 at a time"));
    }
    let collector = repo::user_name(&state.pool, auth.user_id).await?.unwrap_or_default();
    let ledger = Ledger::load(&state, bill.club_id, None).await?;
    let shares = repo::bill_shares(&state.pool, bill.id).await?;
    let (mut recorded, mut total) = (0, 0i64);
    let mut tx = state.pool.begin().await?;
    for sid in body.share_ids {
        let Some(share) = shares.iter().find(|s| s.id == sid && s.status == "live") else { continue };
        let p = ledger.progress(share).unwrap_or_default();
        let owed = share.amount_cents - p.paid_cents - p.waiting_cents;
        if owed <= 0 {
            continue;
        }
        let (user_id, guest) = match share.payer() {
            Payer::Member(id) => (Some(id), None),
            Payer::Guest(_) => (None, Some(share.name.as_str())),
        };
        let note = (!admin).then(|| format!("Collected in cash by {collector}"));
        let (row, created) = repo::insert_payment(
            &mut tx,
            &NewPayment {
                club_id: bill.club_id,
                user_id,
                guest_name: guest,
                name: &share.name,
                amount_cents: owed,
                currency: &share.currency,
                method: "cash",
                reference: None,
                payout_account_id: None,
                status: if admin { "confirmed" } else { "claimed" },
                note: note.as_deref(),
                idempotency_key: None,
                created_by: Some(auth.user_id),
                via_link: None,
                share_id: Some(share.id),
            },
        )
        .await?;
        if created {
            recorded += 1;
            total += owed;
            repo::audit(&mut tx, bill.club_id, Some(auth.user_id), "cash_at_ground", "payment", Some(row.id), None,
                Some(json!({ "share_id": share.id, "amount_cents": owed, "received": admin }))).await?;
        }
    }
    tx.commit().await?;
    if recorded > 0 && !admin {
        let admins = repo::money_admins(&state.pool, bill.club_id).await?;
        let money = fmt_money(total, &bill.currency);
        for checker in repo::payment_checkers(&admins) {
            state
                .notify_text(checker, "payment_claimed",
                    &format!("{} collected {money} in cash", first_name(&collector)),
                    &format!("{collector} collected {money} in cash from {recorded} at {}. Tick it once you have the cash.", bill.title),
                    json!({ "club_id": bill.club_id }))
                .await;
        }
    }
    Ok(Json(json!({ "recorded": recorded, "total_cents": total, "received": admin })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_in_a_message_are_first_names_unless_two_share_one() {
        let names = vec!["Ravi Sharma".to_string(), "Tom Bennett".to_string(), "Ravi Patel".to_string()];
        assert_eq!(short_names(&names), vec!["Ravi Sharma", "Tom", "Ravi Patel"]);
        assert_eq!(and_list(&["Josh".into(), "Imran".into()]), "Josh and Imran");
        assert_eq!(and_list(&["A".into(), "B".into(), "C".into()]), "A, B and C");
        assert_eq!(and_list(&["Josh".into()]), "Josh");
    }

    #[test]
    fn a_screenshot_is_judged_by_its_bytes() {
        assert!(checked_image(b"").is_err());
        assert!(checked_image(b"<html>not a picture</html>").is_err());
        assert_eq!(checked_image(&[0xFF, 0xD8, 0xFF, 0xE0, 0, 0]).unwrap(), "image/jpeg");
        assert!(checked_image(&vec![0xFF; MAX_SCREENSHOT_BYTES + 1]).is_err());
    }
}
