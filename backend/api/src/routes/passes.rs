//! Passes, price types, group fees and paying for others — steps B and C of
//! docs/CLUB_PAYMENTS_V2_PLAN.md.
//!
//! Who may do what: money admins (owner, secretaries, treasurers) set price
//! types and passes, add people to passes, raise group fees and say who pays
//! for whom. A member may join a pass that is open to join, cancel their own
//! (or one they pay for), and pay for the people they pay for. Everything a
//! pass or a group fee charges is a share on a bill, matched to payments by
//! phase 1's ledger like any other.

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{get, patch, post, put};
use axum::{Json, Router};
use chrono::{NaiveDate, Utc};
use fishers_db::repos::club_payments::{self as repo, Attendee, NewPayment, PaymentRow, Payer};
use fishers_db::repos::passes::{self as passes_repo, CollectionError, Holder, PassPlan, PriceType};
use fishers_domain::money::{self, fmt_money, CostMode, PassBilling, PassStanding, PASS_COVERABLE};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use super::club_payments::{
    accounts, first_name, idempotency_key, reference_for, require_money_admin, role, share_view, status, Ledger,
    ShareView,
};
use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/clubs/{id}/price-types", get(list_price_types).post(create_price_type))
        .route("/price-types/{id}", patch(update_price_type))
        .route("/clubs/{id}/members/{user_id}/price-type", put(set_member_price_type))
        .route("/clubs/{id}/passes", get(list_passes).post(create_pass))
        .route("/passes/{id}", patch(update_pass))
        .route("/passes/{id}/holders", get(list_holders).post(add_holder))
        .route("/passes/{id}/join", post(join_pass))
        .route("/pass-holders/{id}/cancel", post(cancel_holder))
        .route("/pass-holders/{id}/keep-covering", put(keep_covering))
        .route("/me/passes", get(my_passes))
        .route("/clubs/{id}/collections", get(list_collections).post(create_collection))
        .route("/collections/{bill_id}", get(get_collection))
        .route("/collections/{bill_id}/void", post(void_collection))
        .route("/clubs/{id}/members/{member_id}/payer", put(set_payer))
        .route("/clubs/{id}/members/managed", post(add_managed_member))
        .route("/clubs/{id}/payments/for-others", post(pay_for_others))
        .route("/clubs/{id}/payments/defaults", get(usual_prices))
        .route("/clubs/{id}/payments/members", get(money_members))
}

#[derive(Debug, Serialize, sqlx::FromRow)]
struct MoneyMember {
    user_id: Uuid,
    name: String,
    price_type_id: Option<Uuid>,
    payer_id: Option<Uuid>,
    payer_name: Option<String>,
    /// No sign-in of their own: added by name, looked after by their payer.
    managed: bool,
}

/// Every active member with their price group and who pays for them, for the
/// secretary's "Prices and who pays".
async fn money_members(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<Vec<MoneyMember>>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    Ok(Json(
        sqlx::query_as::<_, MoneyMember>(
            "SELECT m.user_id, u.name, m.price_type_id, p.payer_id, pu.name AS payer_name,
                    (u.managed_by IS NOT NULL) AS managed
             FROM club_members m JOIN users u ON u.id = m.user_id
             LEFT JOIN club_payers p ON p.club_id = m.club_id AND p.member_id = m.user_id
             LEFT JOIN users pu ON pu.id = p.payer_id
             WHERE m.club_id = $1 AND m.status = 'active'
             ORDER BY lower(u.name)",
        )
        .bind(club_id)
        .fetch_all(&state.pool)
        .await?,
    ))
}

/// A price group's name must be new to the club, whatever its capitals.
async fn name_free(state: &AppState, club_id: Uuid, name: &str, except: Option<Uuid>) -> ApiResult<()> {
    let taken = passes_repo::price_types(&state.pool, club_id)
        .await?
        .iter()
        .any(|t| Some(t.id) != except && t.archived_at.is_none() && t.name.to_lowercase() == name.to_lowercase());
    if taken {
        return Err(ApiError::conflict("There's already a price type with that name").with_code("name_taken"));
    }
    Ok(())
}

#[derive(Debug, Serialize)]
struct UsualPrices {
    default_nets_mode: Option<String>,
    default_nets_cents: Option<i64>,
    default_match_fee_cents: Option<i64>,
    currency: String,
}

/// The club's usual prices, for anybody who schedules sessions (a captain
/// included) — the full settings are for money admins only.
async fn usual_prices(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<UsualPrices>> {
    require_member(&state, club_id, auth.user_id).await?;
    let s = repo::settings(&state.pool, club_id).await?;
    Ok(Json(UsualPrices {
        default_nets_mode: s.as_ref().and_then(|s| s.default_nets_mode.clone()),
        default_nets_cents: s.as_ref().and_then(|s| s.default_nets_cents),
        default_match_fee_cents: s.as_ref().and_then(|s| s.default_match_fee_cents),
        currency: repo::club_currency(&state.pool, club_id).await?,
    }))
}

fn today() -> NaiveDate {
    Utc::now().date_naive()
}

async fn require_member(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<()> {
    let r = role(state, club_id, user_id).await?;
    if r.is_member || r.is_owner {
        Ok(())
    } else {
        Err(ApiError::forbidden("You're not a member of this club").with_code("not_member"))
    }
}

fn clean_name(raw: &str, max: usize, what: &str) -> ApiResult<String> {
    let name = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    if name.is_empty() || name.chars().count() > max {
        return Err(ApiError::bad_request(format!("Give the {what} a name of up to {max} characters")));
    }
    Ok(name)
}

// MARK: price types

async fn list_price_types(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<Vec<PriceType>>> {
    require_member(&state, club_id, auth.user_id).await?;
    Ok(Json(passes_repo::price_types(&state.pool, club_id).await?))
}

#[derive(Debug, Deserialize)]
struct PriceTypeBody {
    name: Option<String>,
    free: Option<bool>,
    for_guests: Option<bool>,
    archived: Option<bool>,
}

async fn create_price_type(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<PriceTypeBody>,
) -> ApiResult<Json<PriceType>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    let name = clean_name(body.name.as_deref().unwrap_or(""), 30, "price type")?;
    name_free(&state, club_id, &name, None).await?;
    let mut tx = state.pool.begin().await?;
    let id = passes_repo::create_price_type(&mut tx, club_id, &name, body.free.unwrap_or(false), body.for_guests.unwrap_or(false))
        .await
        .map_err(|e| match e {
            sqlx::Error::Database(db) if db.constraint() == Some("club_price_types_club_id_name_key") => {
                ApiError::conflict("There's already a price type with that name").with_code("name_taken")
            }
            sqlx::Error::Database(db) if db.constraint() == Some("idx_price_types_one_guest") => {
                ApiError::conflict("The club already has a price for guests").with_code("guest_type_taken")
            }
            other => other.into(),
        })?;
    repo::audit(&mut tx, club_id, Some(auth.user_id), "create_price_type", "price_type", Some(id), None,
        Some(json!({ "name": name, "free": body.free, "for_guests": body.for_guests }))).await?;
    tx.commit().await?;
    Ok(Json(passes_repo::price_type(&state.pool, id).await?.ok_or_else(|| ApiError::internal("vanished"))?))
}

async fn update_price_type(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<PriceTypeBody>,
) -> ApiResult<Json<PriceType>> {
    let t = passes_repo::price_type(&state.pool, id).await?.ok_or_else(|| ApiError::not_found("no such price type"))?;
    require_money_admin(&state, t.club_id, auth.user_id).await?;
    let name = body.name.as_deref().map(|n| clean_name(n, 30, "price type")).transpose()?;
    if let Some(n) = &name {
        name_free(&state, t.club_id, n, Some(id)).await?;
    }
    let mut tx = state.pool.begin().await?;
    passes_repo::update_price_type(&mut tx, id, name.as_deref(), body.free, body.for_guests, body.archived).await?;
    repo::audit(&mut tx, t.club_id, Some(auth.user_id), "update_price_type", "price_type", Some(id),
        Some(json!(t)), Some(json!({ "name": name, "free": body.free, "for_guests": body.for_guests, "archived": body.archived }))).await?;
    tx.commit().await?;
    Ok(Json(passes_repo::price_type(&state.pool, id).await?.ok_or_else(|| ApiError::internal("vanished"))?))
}

#[derive(Debug, Deserialize)]
struct MemberPriceTypeBody {
    price_type_id: Option<Uuid>,
}

async fn set_member_price_type(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, user_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<MemberPriceTypeBody>,
) -> ApiResult<StatusCode> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    if let Some(t) = body.price_type_id {
        let pt = passes_repo::price_type(&state.pool, t).await?.filter(|p| p.club_id == club_id && p.archived_at.is_none());
        if pt.is_none() {
            return Err(ApiError::bad_request("That price type isn't one of this club's"));
        }
    }
    let mut tx = state.pool.begin().await?;
    if !passes_repo::set_member_price_type(&mut tx, club_id, user_id, body.price_type_id).await? {
        return Err(ApiError::not_found("They aren't an active member of this club"));
    }
    repo::audit(&mut tx, club_id, Some(auth.user_id), "set_price_type", "member", Some(user_id), None,
        Some(json!({ "price_type_id": body.price_type_id }))).await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// MARK: passes

#[derive(Debug, Serialize)]
struct PlanView {
    #[serde(flatten)]
    plan: PassPlan,
    /// One payment: the price, or one instalment of it.
    charge_cents: i64,
    holders: i64,
    /// Your own pass on this plan, if you hold one.
    mine: Option<HolderView>,
}

#[derive(Debug, Serialize)]
struct HolderView {
    #[serde(flatten)]
    holder: Holder,
    plan_name: String,
    billing: String,
    /// `up_to_date`, `behind` or `suspended`.
    standing: PassStanding,
    /// A bundle's sessions left, where the plan has a number.
    sessions_left: Option<i64>,
    /// Whether it covers sessions today.
    running: bool,
    /// When the next monthly charge or instalment falls, if there is one.
    next_charge_on: Option<NaiveDate>,
}

async fn holder_view(state: &AppState, plan: &PassPlan, h: Holder) -> ApiResult<HolderView> {
    let day = today();
    let standing = passes_repo::standing(&state.pool, plan, &h, day).await?;
    let sessions_left = match plan.sessions {
        Some(limit) => Some((i64::from(limit) - passes_repo::sessions_used(&state.pool, h.id, None).await?).max(0)),
        None => None,
    };
    let running = h.started_on <= day
        && h.ends_on.is_none_or(|e| e >= day)
        && plan.valid_until.is_none_or(|v| v >= day)
        && sessions_left.is_none_or(|n| n > 0)
        && standing != PassStanding::Suspended;
    let next_charge_on = match plan.billing() {
        PassBilling::Once => None,
        PassBilling::Monthly => (1..240u32)
            .map(|k| money::add_months(h.started_on, k))
            .find(|d| *d > day)
            .filter(|d| h.ends_on.is_none_or(|e| *d <= e)),
        PassBilling::Instalments => money::instalment_days(h.started_on, plan.instalments.unwrap_or(1) as u32)
            .into_iter()
            .find(|d| *d > day)
            .filter(|_| h.cancelled_at.is_none()),
    };
    Ok(HolderView {
        plan_name: plan.name.clone(),
        billing: plan.billing.clone(),
        standing,
        sessions_left,
        running,
        next_charge_on,
        holder: h,
    })
}

#[derive(Debug, Deserialize)]
struct ListQuery {
    all: Option<bool>,
}

async fn list_passes(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Query(q): Query<ListQuery>,
) -> ApiResult<Json<Vec<PlanView>>> {
    require_member(&state, club_id, auth.user_id).await?;
    let admin = role(&state, club_id, auth.user_id).await?.is_admin();
    let mut out = Vec::new();
    for plan in passes_repo::plans(&state.pool, club_id, admin && q.all.unwrap_or(false)).await? {
        let holders = passes_repo::plan_holders(&state.pool, plan.id).await?;
        let count = holders.iter().filter(|h| h.cancelled_at.is_none()).count() as i64;
        let mine = match holders.into_iter().find(|h| h.user_id == auth.user_id && h.ends_on.is_none_or(|e| e >= today())) {
            Some(h) => Some(holder_view(&state, &plan, h).await?),
            None => None,
        };
        out.push(PlanView { charge_cents: plan.charge_cents(), holders: count, mine, plan });
    }
    Ok(Json(out))
}

#[derive(Debug, Deserialize)]
struct PlanBody {
    name: Option<String>,
    price_cents: Option<i64>,
    billing: Option<String>,
    instalments: Option<i32>,
    #[serde(default)]
    covers: Vec<String>,
    team_id: Option<Uuid>,
    valid_until: Option<NaiveDate>,
    sessions: Option<i32>,
    price_type_id: Option<Uuid>,
    open_to_join: Option<bool>,
    archived: Option<bool>,
}

async fn create_pass(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<PlanBody>,
) -> ApiResult<Json<PlanView>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    let name = clean_name(body.name.as_deref().unwrap_or(""), 60, "pass")?;
    let billing = PassBilling::parse(body.billing.as_deref().unwrap_or(""))
        .ok_or_else(|| ApiError::bad_request("billing is once, monthly or instalments"))?;
    let price = body.price_cents.unwrap_or(0);
    if price <= 0 || price > money::MAX_BILL_CENTS {
        return Err(ApiError::bad_request("The price has to be more than zero").with_code("amount_limit"));
    }
    if billing == PassBilling::Instalments && !body.instalments.is_some_and(|n| (2..=12).contains(&n)) {
        return Err(ApiError::bad_request("Split it into 2 to 12 instalments"));
    }
    if body.covers.iter().any(|c| !PASS_COVERABLE.contains(&c.as_str())) {
        return Err(ApiError::bad_request("covers lists session kinds: nets, training, friendly, league_match, tournament, social"));
    }
    if body.sessions.is_some_and(|n| !(1..=500).contains(&n)) {
        return Err(ApiError::bad_request("A bundle is 1 to 500 sessions"));
    }
    if billing == PassBilling::Monthly && (body.sessions.is_some() || body.valid_until.is_some()) {
        return Err(ApiError::bad_request("A monthly pass runs until it's cancelled: no end date or session count"));
    }
    if let Some(t) = body.price_type_id {
        if !passes_repo::price_type(&state.pool, t).await?.is_some_and(|p| p.club_id == club_id) {
            return Err(ApiError::bad_request("That price type isn't one of this club's"));
        }
    }
    let currency = repo::club_currency(&state.pool, club_id).await?;
    let mut tx = state.pool.begin().await?;
    let id = passes_repo::create_plan(
        &mut tx,
        &passes_repo::NewPlan {
            club_id,
            name: &name,
            price_cents: price,
            currency: &currency,
            billing,
            instalments: body.instalments.filter(|_| billing == PassBilling::Instalments),
            covers: &body.covers,
            team_id: body.team_id,
            valid_until: body.valid_until,
            sessions: body.sessions,
            price_type_id: body.price_type_id,
            open_to_join: body.open_to_join.unwrap_or(true),
            by: auth.user_id,
        },
    )
    .await?;
    repo::enable_payments(&mut tx, club_id).await?;
    repo::audit(&mut tx, club_id, Some(auth.user_id), "create_pass", "pass", Some(id), None,
        Some(json!({ "name": name, "price_cents": price, "billing": billing.as_str(), "covers": body.covers }))).await?;
    tx.commit().await?;
    let plan = passes_repo::plan(&state.pool, id).await?.ok_or_else(|| ApiError::internal("vanished"))?;
    Ok(Json(PlanView { charge_cents: plan.charge_cents(), holders: 0, mine: None, plan }))
}

async fn update_pass(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<PlanBody>,
) -> ApiResult<Json<PlanView>> {
    let plan = passes_repo::plan(&state.pool, id).await?.ok_or_else(|| ApiError::not_found("no such pass"))?;
    require_money_admin(&state, plan.club_id, auth.user_id).await?;
    let name = body.name.as_deref().map(|n| clean_name(n, 60, "pass")).transpose()?;
    if body.price_cents.is_some_and(|p| p <= 0 || p > money::MAX_BILL_CENTS) {
        return Err(ApiError::bad_request("The price has to be more than zero").with_code("amount_limit"));
    }
    let mut tx = state.pool.begin().await?;
    passes_repo::update_plan(&mut tx, id, name.as_deref(), body.price_cents, body.open_to_join, body.archived).await?;
    repo::audit(&mut tx, plan.club_id, Some(auth.user_id), "update_pass", "pass", Some(id), Some(json!(plan)),
        Some(json!({ "name": name, "price_cents": body.price_cents, "open_to_join": body.open_to_join, "archived": body.archived }))).await?;
    tx.commit().await?;
    let after = passes_repo::plan(&state.pool, id).await?.ok_or_else(|| ApiError::internal("vanished"))?;

    // A monthly price change: everybody on it has to change their standing order.
    if plan.billing() == PassBilling::Monthly && after.price_cents != plan.price_cents {
        let club = repo::club_name(&state.pool, plan.club_id).await?.unwrap_or_default();
        let next = fmt_money(after.price_cents, &after.currency);
        for h in passes_repo::plan_holders(&state.pool, id).await?.into_iter().filter(|h| h.cancelled_at.is_none()) {
            let body = format!("{} is now {next} a month from your next payment. Change your standing order to {club} to {next}.", after.name);
            notify_holder(&state, &h, "pass_price_changed", &format!("{}: new price", after.name), &body).await;
        }
    }
    let holders = passes_repo::plan_holders(&state.pool, id).await?.iter().filter(|h| h.cancelled_at.is_none()).count() as i64;
    Ok(Json(PlanView { charge_cents: after.charge_cents(), holders, mine: None, plan: after }))
}

/// A holder hears about their pass, and so does whoever pays for them.
async fn notify_holder(state: &AppState, h: &Holder, kind: &str, title: &str, body: &str) {
    let payload = json!({ "club_id": h.club_id, "pass_holder_id": h.id });
    state.notify_text(h.user_id, kind, title, body, payload.clone()).await;
    if let Ok(Some(payer)) = passes_repo::payer_of(&state.pool, h.club_id, h.user_id).await {
        state.notify_text(payer, kind, title, &format!("For {}: {body}", h.name), payload).await;
    }
}

async fn list_holders(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<HolderView>>> {
    let plan = passes_repo::plan(&state.pool, id).await?.ok_or_else(|| ApiError::not_found("no such pass"))?;
    require_money_admin(&state, plan.club_id, auth.user_id).await?;
    let mut out = Vec::new();
    for h in passes_repo::plan_holders(&state.pool, id).await? {
        out.push(holder_view(&state, &plan, h).await?);
    }
    Ok(Json(out))
}

/// Put somebody on a pass and charge the first payment.
async fn start_holder(
    state: &AppState,
    plan: &PassPlan,
    user_id: Uuid,
    started_on: NaiveDate,
    by: Uuid,
    audit_action: &str,
) -> ApiResult<HolderView> {
    if plan.archived_at.is_some() {
        return Err(ApiError::conflict("That pass isn't offered any more").with_code("pass_archived"));
    }
    let mut tx = state.pool.begin().await?;
    let id = passes_repo::add_holder(&mut tx, plan, user_id, started_on, by).await.map_err(|e| match e {
        sqlx::Error::Database(db) if db.constraint() == Some("idx_pass_holders_one_open") => {
            ApiError::conflict("They're already on this pass").with_code("already_on_pass")
        }
        other => other.into(),
    })?;
    tx.commit().await?;
    let h = passes_repo::holder(&state.pool, id).await?.ok_or_else(|| ApiError::internal("vanished"))?;
    let payout = accounts(state, plan.club_id).await?.current().map(|a| a.id);
    let mut tx = state.pool.begin().await?;
    passes_repo::charge_pass(&mut tx, plan, &h, started_on, &passes_repo::charge_title(plan, started_on, 1), plan.charge_cents(), payout)
        .await?;
    repo::enable_payments(&mut tx, plan.club_id).await?;
    repo::audit(&mut tx, plan.club_id, Some(by), audit_action, "pass_holder", Some(id), None,
        Some(json!({ "plan": plan.id, "user_id": user_id, "started_on": started_on }))).await?;
    tx.commit().await?;

    let club = repo::club_name(&state.pool, plan.club_id).await?.unwrap_or_default();
    let money = fmt_money(plan.charge_cents(), &plan.currency);
    let how = match plan.billing() {
        PassBilling::Monthly => format!("{money} a month. Set up a standing order to {club} in your banking app, and it pays itself."),
        PassBilling::Instalments => format!("{money} now, then each month until it's paid."),
        PassBilling::Once => format!("Pay {money} to {club}, and you're covered."),
    };
    notify_holder(state, &h, "pass_started", &format!("You're on {}", plan.name), &how).await;
    holder_view(state, plan, h).await
}

#[derive(Debug, Deserialize)]
struct AddHolderBody {
    user_id: Uuid,
    started_on: Option<NaiveDate>,
}

async fn add_holder(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AddHolderBody>,
) -> ApiResult<Json<HolderView>> {
    let plan = passes_repo::plan(&state.pool, id).await?.ok_or_else(|| ApiError::not_found("no such pass"))?;
    require_money_admin(&state, plan.club_id, auth.user_id).await?;
    if !role(&state, plan.club_id, body.user_id).await?.is_member {
        return Err(ApiError::bad_request("They aren't an active member of this club"));
    }
    let started_on = body.started_on.unwrap_or_else(today);
    if (started_on - today()).num_days().abs() > 366 {
        return Err(ApiError::bad_request("Start it within a year of today"));
    }
    Ok(Json(start_holder(&state, &plan, body.user_id, started_on, auth.user_id, "add_to_pass").await?))
}

#[derive(Debug, Deserialize, Default)]
struct JoinBody {
    /// Join on behalf of somebody you pay for (a junior).
    for_user_id: Option<Uuid>,
}

async fn join_pass(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    body: Option<Json<JoinBody>>,
) -> ApiResult<Json<HolderView>> {
    let plan = passes_repo::plan(&state.pool, id).await?.ok_or_else(|| ApiError::not_found("no such pass"))?;
    let who = body.and_then(|Json(b)| b.for_user_id).unwrap_or(auth.user_id);
    if who != auth.user_id && passes_repo::payer_of(&state.pool, plan.club_id, who).await? != Some(auth.user_id) {
        return Err(ApiError::forbidden("You can only join somebody you pay for").with_code("not_their_payer"));
    }
    if !role(&state, plan.club_id, who).await?.is_member {
        return Err(ApiError::forbidden("Only members of the club can join its passes").with_code("not_member"));
    }
    if !plan.open_to_join {
        return Err(ApiError::forbidden("Ask the club's secretary to put you on this pass").with_code("not_open"));
    }
    if let Some(only) = plan.price_type_id {
        let types = passes_repo::member_price_types(&state.pool, plan.club_id).await?;
        if types.get(&who) != Some(&only) {
            let name = passes_repo::price_type(&state.pool, only).await?.map(|t| t.name).unwrap_or_default();
            return Err(ApiError::forbidden(format!("This pass is for {name} members")).with_code("not_eligible"));
        }
    }
    Ok(Json(start_holder(&state, &plan, who, today(), auth.user_id, "join_pass").await?))
}

/// Cancelled: a monthly pass runs to the end of the month already charged;
/// any other stops today. Nothing already charged changes.
async fn cancel_holder(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<HolderView>> {
    let h = passes_repo::holder(&state.pool, id).await?.ok_or_else(|| ApiError::not_found("no such pass"))?;
    let plan = passes_repo::plan(&state.pool, h.plan_id).await?.ok_or_else(|| ApiError::not_found("no such pass"))?;
    let admin = role(&state, h.club_id, auth.user_id).await?.is_admin();
    let payer = passes_repo::payer_of(&state.pool, h.club_id, h.user_id).await? == Some(auth.user_id);
    if !(admin || payer || h.user_id == auth.user_id) {
        return Err(ApiError::not_found("no such pass"));
    }
    let day = today();
    let ends_on = match plan.billing() {
        PassBilling::Monthly => {
            let next = (1..240u32).map(|k| money::add_months(h.started_on, k)).find(|d| *d > day).unwrap_or(day);
            next.pred_opt().unwrap_or(day)
        }
        _ => day,
    };
    let mut tx = state.pool.begin().await?;
    if !passes_repo::cancel_holder(&mut tx, id, ends_on).await? {
        return Err(ApiError::conflict("That pass is already cancelled").with_code("already_cancelled"));
    }
    repo::audit(&mut tx, h.club_id, Some(auth.user_id), "cancel_pass", "pass_holder", Some(id), None,
        Some(json!({ "ends_on": ends_on }))).await?;
    tx.commit().await?;
    if plan.billing() == PassBilling::Monthly {
        let club = repo::club_name(&state.pool, h.club_id).await?.unwrap_or_default();
        notify_holder(&state, &h, "pass_cancelled", &format!("{} cancelled", plan.name),
            &format!("It covers you until {}. Cancel your standing order to {club} in your banking app too.", ends_on.format("%-d %B"))).await;
    }
    let h = passes_repo::holder(&state.pool, id).await?.ok_or_else(|| ApiError::internal("vanished"))?;
    Ok(Json(holder_view(&state, &plan, h).await?))
}

#[derive(Debug, Deserialize)]
struct KeepCoveringBody {
    on: bool,
}

async fn keep_covering(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<KeepCoveringBody>,
) -> ApiResult<Json<HolderView>> {
    let h = passes_repo::holder(&state.pool, id).await?.ok_or_else(|| ApiError::not_found("no such pass"))?;
    require_money_admin(&state, h.club_id, auth.user_id).await?;
    let plan = passes_repo::plan(&state.pool, h.plan_id).await?.ok_or_else(|| ApiError::not_found("no such pass"))?;
    let mut tx = state.pool.begin().await?;
    passes_repo::set_keep_covering(&mut tx, id, body.on).await?;
    repo::audit(&mut tx, h.club_id, Some(auth.user_id), "keep_covering", "pass_holder", Some(id), None,
        Some(json!({ "on": body.on }))).await?;
    tx.commit().await?;
    let h = passes_repo::holder(&state.pool, id).await?.ok_or_else(|| ApiError::internal("vanished"))?;
    Ok(Json(holder_view(&state, &plan, h).await?))
}

#[derive(Debug, Serialize)]
struct MyPass {
    club_id: Uuid,
    club_name: String,
    #[serde(flatten)]
    view: HolderView,
    charge_cents: i64,
    currency: String,
    /// For a monthly pass: what to set up in the banking app.
    standing_order: Option<StandingOrder>,
    /// What it covers and for how long, so the app needn't load the plan.
    covers: Vec<String>,
    valid_until: Option<NaiveDate>,
    sessions: Option<i32>,
}

#[derive(Debug, Serialize)]
struct StandingOrder {
    amount_cents: i64,
    /// Always "month" for now.
    every: &'static str,
    first_payment_on: NaiveDate,
    reference: String,
}

/// My passes, and those of anybody I pay for.
async fn my_passes(State(state): State<AppState>, auth: AuthUser) -> ApiResult<Json<Vec<MyPass>>> {
    // Yours in every club; somebody you pay for, only in the club you pay for them.
    let mut people: Vec<(Uuid, Option<Uuid>)> = vec![(auth.user_id, None)];
    let deps = passes_repo::dependents(&state.pool, auth.user_id).await?;
    people.extend(deps.iter().map(|d| (d.member_id, Some(d.club_id))));
    let mut out = Vec::new();
    for (person, club) in people {
        let ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT id FROM pass_holders WHERE user_id = $1 AND ($2::uuid IS NULL OR club_id = $2)
               AND (ends_on IS NULL OR ends_on >= CURRENT_DATE)
             ORDER BY created_at DESC",
        )
        .bind(person)
        .bind(club)
        .fetch_all(&state.pool)
        .await?;
        for id in ids {
            let Some(h) = passes_repo::holder(&state.pool, id).await? else { continue };
            let Some(plan) = passes_repo::plan(&state.pool, h.plan_id).await? else { continue };
            let club_name = repo::club_name(&state.pool, h.club_id).await?.unwrap_or_default();
            let standing_order = if plan.billing() == PassBilling::Monthly && h.cancelled_at.is_none() {
                // The standing order pays every month's charge, this one too:
                // with a charge still unpaid it starts tomorrow (banks can't
                // start one today), otherwise on the next charge. Nobody pays
                // a month twice, by hand and by standing order.
                let tomorrow = today().succ_opt().unwrap_or_else(today);
                let first = if passes_repo::unpaid_charges(&state.pool, &h).await? > 0 {
                    tomorrow
                } else {
                    (1..240u32).map(|k| money::add_months(h.started_on, k)).find(|d| *d > today()).unwrap_or(tomorrow)
                };
                Some(StandingOrder {
                    amount_cents: plan.charge_cents(),
                    every: "month",
                    first_payment_on: first,
                    // The holder's own reference, even when somebody else pays:
                    // it's what puts the money against their pass.
                    reference: reference_for(&state, h.club_id, h.user_id).await?,
                })
            } else {
                None
            };
            let club_id = h.club_id;
            out.push(MyPass {
                club_id,
                club_name,
                charge_cents: plan.charge_cents(),
                currency: plan.currency.clone(),
                standing_order,
                covers: plan.covers.clone(),
                valid_until: plan.valid_until,
                sessions: plan.sessions,
                view: holder_view(&state, &plan, h).await?,
            });
        }
    }
    Ok(Json(out))
}

/// After a session is billed: a bundle down to its last session, or used
/// up, says so — once, on the bill that did it.
pub(crate) async fn bundle_notices(state: &AppState, holder_ids: &[Uuid]) {
    for id in holder_ids {
        let Ok(Some(h)) = passes_repo::holder(&state.pool, *id).await else { continue };
        let Ok(Some(plan)) = passes_repo::plan(&state.pool, h.plan_id).await else { continue };
        let Some(limit) = plan.sessions else { continue };
        let Ok(used) = passes_repo::sessions_used(&state.pool, h.id, None).await else { continue };
        let Some((title, body)) = passes_repo::sessions_left_notice(&plan.name, i64::from(limit) - used) else { continue };
        notify_holder(state, &h, "pass_sessions_left", &title, body).await;
    }
}

// MARK: group fees

#[derive(Debug, Deserialize)]
struct CollectionBody {
    title: String,
    mode: String,
    amount_cents: i64,
    /// Who: everyone, a team, a price type, or a list.
    #[serde(default)]
    everyone: bool,
    team_id: Option<Uuid>,
    price_type_id: Option<Uuid>,
    user_ids: Option<Vec<Uuid>>,
    #[serde(default)]
    guests: Vec<String>,
    due_on: Option<NaiveDate>,
    note: Option<String>,
}

#[derive(Debug, Serialize)]
struct CollectionView {
    #[serde(flatten)]
    bill: repo::BillRow,
    paid_cents: i64,
    waiting_cents: i64,
    owed_cents: i64,
    people: usize,
    /// Everyone's lines for an admin; only your own otherwise.
    shares: Vec<ShareView>,
}

async fn collection_view(state: &AppState, bill: repo::BillRow, viewer: Option<Uuid>) -> ApiResult<CollectionView> {
    let ledger = Ledger::load(state, bill.club_id, None).await?;
    let rows = repo::bill_shares(&state.pool, bill.id).await?;
    let (mut paid, mut waiting, mut owed) = (0, 0, 0);
    let mut shares = Vec::new();
    for row in &rows {
        let v = share_view(row, ledger.progress(row));
        if row.status == "live" {
            paid += v.paid_cents;
            waiting += v.waiting_cents;
            owed += (v.amount_cents - v.paid_cents - v.waiting_cents).max(0);
        }
        if viewer.is_none() || row.user_id == viewer {
            shares.push(v);
        }
    }
    Ok(CollectionView { people: rows.len(), paid_cents: paid, waiting_cents: waiting, owed_cents: owed, shares, bill })
}

async fn create_collection(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(club_id): Path<Uuid>,
    Json(body): Json<CollectionBody>,
) -> ApiResult<Json<CollectionView>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    // A retry after a lost reply (same Idempotency-Key) gets the group fee the
    // first try made, not a second one.
    let key = idempotency_key(&headers)?;
    if let Some(k) = key.as_deref() {
        let made: Option<Uuid> = sqlx::query_scalar(
            "SELECT entity_id FROM club_payment_audit WHERE club_id = $1 AND actor_id = $2
               AND action = 'create_collection' AND after->>'key' = $3 LIMIT 1",
        )
        .bind(club_id)
        .bind(auth.user_id)
        .bind(k)
        .fetch_optional(&state.pool)
        .await?
        .flatten();
        if let Some(id) = made {
            if let Some(bill) = repo::bill_by_id(&state.pool, id).await? {
                return Ok(Json(collection_view(&state, bill, None).await?));
            }
        }
    }
    let title = clean_name(&body.title, 80, "group fee")?;
    let mode = CostMode::parse(&body.mode).ok_or_else(|| ApiError::bad_request("mode is split_total or per_player"))?;
    let choices = [body.everyone, body.team_id.is_some(), body.price_type_id.is_some(), body.user_ids.is_some()];
    if choices.iter().filter(|c| **c).count() != 1 && body.guests.is_empty() {
        return Err(ApiError::bad_request("Say who: everyone, a team, a price type, or a list of people"));
    }
    let mut people: Vec<Attendee> = if choices.iter().any(|c| *c) {
        passes_repo::members_for(&state.pool, club_id, body.team_id, body.price_type_id, body.user_ids.as_deref())
            .await?
            .into_iter()
            .map(|(id, name)| Attendee { user_id: Some(id), name, ..Default::default() })
            .collect()
    } else {
        Vec::new()
    };
    let mut seen = std::collections::HashSet::new();
    for g in &body.guests {
        let name = g.split_whitespace().collect::<Vec<_>>().join(" ");
        if !name.is_empty() && name.chars().count() <= 60 && seen.insert(name.to_lowercase()) {
            people.push(Attendee { user_id: None, name, ..Default::default() });
        }
    }
    let note = body.note.as_deref().map(str::trim).filter(|n| !n.is_empty() && n.chars().count() <= 200);
    let currency = repo::club_currency(&state.pool, club_id).await?;
    let payout = accounts(&state, club_id).await?.current().map(|a| a.id);
    let mut tx = state.pool.begin().await?;
    // Two sends with the same key at once: one makes it, the other finds it.
    if let Some(k) = key.as_deref() {
        if !repo::try_lock_key(&mut tx, &format!("collection|{club_id}|{k}")).await? {
            return Err(super::club_payments::busy());
        }
        let made: Option<Uuid> = sqlx::query_scalar(
            "SELECT entity_id FROM club_payment_audit WHERE club_id = $1 AND actor_id = $2
               AND action = 'create_collection' AND after->>'key' = $3 LIMIT 1",
        )
        .bind(club_id)
        .bind(auth.user_id)
        .bind(k)
        .fetch_optional(&mut *tx)
        .await?
        .flatten();
        if let Some(id) = made {
            drop(tx);
            if let Some(bill) = repo::bill_by_id(&state.pool, id).await? {
                return Ok(Json(collection_view(&state, bill, None).await?));
            }
            return Err(super::club_payments::busy());
        }
    }
    let (bill, told) = passes_repo::create_collection(
        &mut tx,
        &passes_repo::NewCollection {
            club_id,
            title: &title,
            mode,
            amount_cents: body.amount_cents,
            currency: &currency,
            due_on: body.due_on,
            note,
            people,
            payout_account_id: payout,
            by: auth.user_id,
        },
    )
    .await
    .map_err(|e| match e {
        CollectionError::Split(s) => status(StatusCode::UNPROCESSABLE_ENTITY, s.message(), s.code()),
        CollectionError::Db(d) => d.into(),
    })?;
    repo::enable_payments(&mut tx, club_id).await?;
    repo::audit(&mut tx, club_id, Some(auth.user_id), "create_collection", "bill", Some(bill.id), None,
        Some(json!({ "title": title, "total_cents": bill.total_cents, "people": told.len(), "key": key }))).await?;
    tx.commit().await?;

    let club = repo::club_name(&state.pool, club_id).await?.unwrap_or_default();
    let due = body.due_on.map(|d| format!(", by {}", d.format("%-d %B"))).unwrap_or_default();
    for (user, amount) in &told {
        if *user == auth.user_id {
            continue;
        }
        state
            .notify_text(*user, "collection_issued", &title,
                &format!("You owe {} for {title}{due}. Pay {club} by bank transfer in the app.", fmt_money(*amount, &bill.currency)),
                json!({ "club_id": club_id, "bill_id": bill.id }))
            .await;
    }
    Ok(Json(collection_view(&state, bill, None).await?))
}

async fn list_collections(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<Vec<CollectionView>>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    let mut out = Vec::new();
    for b in passes_repo::collections(&state.pool, club_id, 50).await? {
        let mut v = collection_view(&state, b, None).await?;
        v.shares.clear(); // the list shows totals; open one to see the people
        out.push(v);
    }
    Ok(Json(out))
}

async fn get_collection(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(bill_id): Path<Uuid>,
) -> ApiResult<Json<CollectionView>> {
    let bill = repo::bill_by_id(&state.pool, bill_id)
        .await?
        .filter(|b| b.kind == "collection")
        .ok_or_else(|| ApiError::not_found("no such group fee"))?;
    let r = role(&state, bill.club_id, auth.user_id).await?;
    if r.is_admin() {
        return Ok(Json(collection_view(&state, bill, None).await?));
    }
    require_member(&state, bill.club_id, auth.user_id).await?;
    Ok(Json(collection_view(&state, bill, Some(auth.user_id)).await?))
}

#[derive(Debug, Deserialize)]
struct VoidBody {
    reason: Option<String>,
}

async fn void_collection(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(bill_id): Path<Uuid>,
    Json(body): Json<VoidBody>,
) -> ApiResult<Json<CollectionView>> {
    let bill = repo::bill_by_id(&state.pool, bill_id)
        .await?
        .filter(|b| b.kind == "collection")
        .ok_or_else(|| ApiError::not_found("no such group fee"))?;
    require_money_admin(&state, bill.club_id, auth.user_id).await?;
    let reason = body.reason.as_deref().map(str::trim).filter(|r| !r.is_empty()).map(str::to_string)
        .ok_or_else(|| ApiError::bad_request("Say why it's being cancelled").with_code("reason_required"))?;
    let mut tx = state.pool.begin().await?;
    if !passes_repo::void_bill_by_id(&mut tx, bill_id, auth.user_id, &reason).await? {
        return Err(ApiError::conflict("It's already cancelled").with_code("no_bill"));
    }
    repo::audit(&mut tx, bill.club_id, Some(auth.user_id), "cancel_collection", "bill", Some(bill_id), None,
        Some(json!({ "reason": reason }))).await?;
    tx.commit().await?;
    let after = repo::bill_by_id(&state.pool, bill_id).await?.ok_or_else(|| ApiError::internal("vanished"))?;
    Ok(Json(collection_view(&state, after, None).await?))
}

// MARK: paying for others

#[derive(Debug, Deserialize)]
struct PayerBody {
    payer_id: Option<Uuid>,
}

async fn set_payer(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, member_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<PayerBody>,
) -> ApiResult<StatusCode> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    if !role(&state, club_id, member_id).await?.is_member {
        return Err(ApiError::bad_request("They aren't an active member of this club"));
    }
    if let Some(p) = body.payer_id {
        if p == member_id {
            return Err(ApiError::bad_request("Somebody pays for themselves already"));
        }
        if !role(&state, club_id, p).await?.is_member {
            return Err(ApiError::bad_request("The payer has to be a member of the club"));
        }
    }
    let mut tx = state.pool.begin().await?;
    passes_repo::set_payer(&mut tx, club_id, member_id, body.payer_id, auth.user_id).await?;
    repo::audit(&mut tx, club_id, Some(auth.user_id), "set_payer", "member", Some(member_id), None,
        Some(json!({ "payer_id": body.payer_id }))).await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
struct ManagedBody {
    name: String,
    payer_id: Uuid,
}

/// A junior with no sign-in of their own, added by name and looked after by
/// the member who pays for them.
async fn add_managed_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<ManagedBody>,
) -> ApiResult<Json<serde_json::Value>> {
    require_money_admin(&state, club_id, auth.user_id).await?;
    let name = clean_name(&body.name, 70, "member")?;
    if !role(&state, club_id, body.payer_id).await?.is_member {
        return Err(ApiError::bad_request("The person who pays has to be a member of the club"));
    }
    let mut tx = state.pool.begin().await?;
    let id = passes_repo::add_managed_member(&mut tx, club_id, &name, body.payer_id, auth.user_id).await?;
    repo::audit(&mut tx, club_id, Some(auth.user_id), "add_managed_member", "member", Some(id), None,
        Some(json!({ "name": name, "payer_id": body.payer_id }))).await?;
    tx.commit().await?;
    Ok(Json(json!({ "user_id": id, "name": name, "payer_id": body.payer_id })))
}

#[derive(Debug, Deserialize)]
struct ForOthersBody {
    method: String,
    /// The members being paid for: people you pay for, or friends on the
    /// same bills. Each gets their own line, for what they owe.
    people: Vec<Uuid>,
    /// Your own dues too, in the same payment.
    #[serde(default)]
    include_me: bool,
    note: Option<String>,
}

#[derive(Debug, Serialize)]
struct ForOthers {
    payments: Vec<PaymentRow>,
    total_cents: i64,
    reference: Option<String>,
}

async fn may_pay_for(state: &AppState, club_id: Uuid, me: Uuid, them: Uuid) -> ApiResult<bool> {
    if passes_repo::payer_of(&state.pool, club_id, them).await? == Some(me) {
        return Ok(true);
    }
    Ok(sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM bill_shares mine
             JOIN bill_shares theirs ON theirs.bill_id = mine.bill_id
             JOIN event_bills b ON b.id = mine.bill_id
             WHERE b.club_id = $1 AND b.status = 'issued' AND mine.user_id = $2
               AND theirs.user_id = $3 AND theirs.status = 'live')",
    )
    .bind(club_id)
    .bind(me)
    .bind(them)
    .fetch_one(&state.pool)
    .await?)
}

/// One payment covering several people: a parent paying for their juniors,
/// one friend for the group. It records a claim for each person for what
/// they owe — still checked by the treasurer — with who paid.
async fn pay_for_others(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(club_id): Path<Uuid>,
    Json(body): Json<ForOthersBody>,
) -> ApiResult<Json<ForOthers>> {
    require_member(&state, club_id, auth.user_id).await?;
    if !matches!(body.method.as_str(), "transfer" | "cash") {
        return Err(ApiError::bad_request("method is transfer or cash"));
    }
    if body.people.len() > 30 {
        return Err(ApiError::bad_request("At most 30 people in one payment"));
    }
    let key = idempotency_key(&headers)?;
    let note = body.note.as_deref().map(str::trim).filter(|n| !n.is_empty()).map(|n| n.chars().take(200).collect::<String>());
    let mut people = Vec::new();
    if body.include_me {
        people.push(auth.user_id);
    }
    for p in &body.people {
        if !people.contains(p) {
            people.push(*p);
        }
    }
    // You can pay for people you pay for, or friends on a bill you're on too —
    // not just anybody in the club.
    for p in people.iter().filter(|p| **p != auth.user_id) {
        if !may_pay_for(&state, club_id, auth.user_id, *p).await? {
            return Err(ApiError::forbidden("You can pay for the people you pay for, or friends on the same bill")
                .with_code("not_their_payer"));
        }
    }
    // Everybody in it is locked first, then what they owe is read.
    let _slot = super::club_payments::save_slot().await?;
    let mut tx = state.pool.begin().await?;
    let mut locked: Vec<Payer> = people.iter().map(|p| Payer::Member(*p)).collect();
    locked.sort();
    for p in &locked {
        super::club_payments::lock_payer(&mut tx, club_id, p).await?;
    }
    let ledger = Ledger::load(&state, club_id, None).await?;
    // A friend pays only what somebody owes on the bills they share — never
    // that person's other dues, which aren't theirs to see or settle.
    let shared = super::club_payments::owed_on_shared_bills(&state, club_id, auth.user_id, &ledger).await?;
    let payer_name = repo::user_name(&state.pool, auth.user_id).await?.unwrap_or_default();
    let reference = if body.method == "transfer" { Some(reference_for(&state, club_id, auth.user_id).await?) } else { None };
    let payout = accounts(&state, club_id).await?.current().map(|a| a.id);
    let mut out = Vec::new();
    for person in people {
        let person_key = key.as_deref().map(|k| format!("{k}:{person}"));
        // The same tap again: what it recorded the first time.
        if let Some(k) = person_key.as_deref() {
            if let Some(done) = repo::payment_by_key(&state.pool, auth.user_id, k).await? {
                out.push(done);
                continue;
            }
        }
        let total = ledger.by_payer.get(&Payer::Member(person)).map(|s| s.owed_cents).unwrap_or(0);
        let theirs = person == auth.user_id || passes_repo::payer_of(&state.pool, club_id, person).await? == Some(auth.user_id);
        let owed = if theirs { total } else { total.min(shared.get(&person).map(|(_, o)| *o).unwrap_or(0)) };
        if owed <= 0 {
            continue;
        }
        let name = repo::user_name(&state.pool, person).await?.unwrap_or_default();
        let (mut row, created) = repo::insert_payment(
            &mut tx,
            &NewPayment {
                club_id,
                user_id: Some(person),
                guest_name: None,
                name: &name,
                amount_cents: owed,
                currency: &ledger.shares.last().map(|s| s.currency.clone()).unwrap_or_else(|| "GBP".into()),
                method: &body.method,
                reference: reference.as_deref(),
                payout_account_id: payout,
                status: "claimed",
                note: note.as_deref(),
                idempotency_key: person_key.as_deref(),
                created_by: Some(auth.user_id),
                via_link: None,
                share_id: None,
            },
        )
        .await?;
        if created {
            sqlx::query("UPDATE member_payments SET paid_by = $2 WHERE id = $1 AND $2 <> user_id")
                .bind(row.id)
                .bind(auth.user_id)
                .execute(&mut *tx)
                .await?;
            row.note = row.note.or_else(|| (person != auth.user_id).then(|| format!("Paid by {payer_name}")));
            repo::audit(&mut tx, club_id, Some(auth.user_id), "claim_for_others", "payment", Some(row.id), None,
                Some(json!({ "for": person, "amount_cents": owed }))).await?;
        }
        out.push(row);
    }
    if out.is_empty() {
        return Err(ApiError::conflict("Nobody you picked owes anything").with_code("nothing_owed"));
    }
    tx.commit().await?;
    let total: i64 = out.iter().map(|p| p.amount_cents).sum();
    let currency = out[0].currency.clone();
    // Whoever was paid for hears it: it's their line that now says "waiting".
    for p in out.iter().filter(|p| p.user_id.is_some_and(|u| u != auth.user_id)) {
        let Some(u) = p.user_id else { continue };
        state
            .notify_text(u, "paid_for_you",
                &format!("{} paid {} for you", first_name(&payer_name), fmt_money(p.amount_cents, &p.currency)),
                &format!("{payer_name} says they paid {} for you. The club will check it arrived.", fmt_money(p.amount_cents, &p.currency)),
                json!({ "club_id": club_id, "payment_id": p.id }))
            .await;
    }
    let admins = repo::money_admins(&state.pool, club_id).await?;
    let names: Vec<String> = out.iter().map(|p| first_name(&p.name).to_string()).collect();
    for checker in repo::payment_checkers(&admins) {
        if checker == auth.user_id {
            continue;
        }
        state
            .notify_text(checker, "payment_claimed",
                &format!("{} says they paid {}", first_name(&payer_name), fmt_money(total, &currency)),
                &format!("{payer_name} says they paid {} for {}. Check it arrived, then tick it.", fmt_money(total, &currency), names.join(", ")),
                json!({ "club_id": club_id }))
            .await;
    }
    Ok(Json(ForOthers { payments: out, total_cents: total, reference }))
}
