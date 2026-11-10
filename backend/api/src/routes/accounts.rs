//! Club accounts — the books a treasurer keeps and takes to the AGM.
//!
//! Every handler starts with [`require_accounts_access`]: the club's owner or
//! one of its treasurers, and nobody else. Hiding the link in a client is not
//! protection; this is.
//!
//! Every write goes through one database transaction with its audit row.
//! A closed year's figures never move: anything that would change them is
//! refused until the owner reopens the year, which is itself audited.

use axum::extract::{Path, Query, State};
use axum::routing::{get, patch, post, put};
use axum::{Json, Router};
use chrono::{NaiveDate, Utc};
use fishers_db::repos::accounts as repo;
use fishers_db::repos::accounts::TransactionFilter;
use fishers_domain::{
    build_report, fee_category_key, keys, period_label, AcceptPaymentsRequest, AccountCategory,
    AccountPeriod, AccountTransaction, AccountsReport, AuditEntry, CategoryKind,
    CreateCategoryRequest, CreateDebtRequest, CreateMoneyAccountRequest, CreatePeriodRequest,
    CreateStockItemRequest, CreateTransactionRequest, DebtPosition, DebtSettlement, EntryKind,
    MoneyAccount, MoneyAccountPosition, PaymentSuggestion, RaiseUnpaidFeesRequest,
    ReopenPeriodRequest, ReportInput, SetAccountBalanceRequest, SetStockCountRequest,
    SettleDebtRequest, StockPosition, UnpaidFee, UpdateCategoryRequest, UpdateMoneyAccountRequest,
    UpdatePeriodRequest, UpdateTransactionRequest, VoidRequest,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_accounts_access, require_secretary, AccountsAccess};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/clubs/{id}/members/{user_id}/treasurer", put(set_treasurer))
        .route("/clubs/{id}/accounts", get(overview))
        .route("/clubs/{id}/accounts/audit", get(audit_log))
        .route("/clubs/{id}/accounts/periods", post(create_period))
        .route("/clubs/{id}/accounts/periods/{pid}", patch(update_period))
        .route("/clubs/{id}/accounts/periods/{pid}/close", post(close_period))
        .route("/clubs/{id}/accounts/periods/{pid}/reopen", post(reopen_period))
        .route("/clubs/{id}/accounts/periods/{pid}/report", get(report))
        .route(
            "/clubs/{id}/accounts/periods/{pid}/transactions",
            get(list_transactions).post(create_transaction),
        )
        .route("/clubs/{id}/accounts/periods/{pid}/debts", get(list_debts))
        .route("/clubs/{id}/accounts/periods/{pid}/suggestions", get(suggestions))
        .route("/clubs/{id}/accounts/periods/{pid}/accept-payments", post(accept_payments))
        .route("/clubs/{id}/accounts/periods/{pid}/raise-unpaid-fees", post(raise_unpaid_fees))
        .route("/clubs/{id}/accounts/periods/{pid}/stock", get(list_stock))
        .route("/clubs/{id}/accounts/periods/{pid}/money", get(list_money_positions))
        .route("/clubs/{id}/accounts/transactions/{tid}", patch(update_transaction))
        .route("/clubs/{id}/accounts/transactions/{tid}/void", post(void_transaction))
        .route(
            "/clubs/{id}/accounts/categories",
            get(list_categories).post(create_category),
        )
        .route("/clubs/{id}/accounts/categories/{cid}", patch(update_category))
        .route(
            "/clubs/{id}/accounts/money-accounts",
            get(list_money_accounts).post(create_money_account),
        )
        .route("/clubs/{id}/accounts/money-accounts/{aid}", patch(update_money_account))
        .route("/clubs/{id}/accounts/money-accounts/{aid}/balance", put(set_balance))
        .route("/clubs/{id}/accounts/debts", post(create_debt))
        .route(
            "/clubs/{id}/accounts/debts/{did}/settlements",
            get(list_settlements).post(settle_debt),
        )
        .route("/clubs/{id}/accounts/debts/{did}/void", post(void_debt))
        .route("/clubs/{id}/accounts/settlements/{sid}/void", post(void_settlement))
        .route("/clubs/{id}/accounts/stock", post(create_stock_item))
        .route("/clubs/{id}/accounts/stock/{item}/count", put(set_stock_count))
}

// MARK: helpers

fn money_kind_ok(kind: &str) -> bool {
    matches!(kind, "bank" | "cash" | "supplier_credit" | "provider")
}

async fn period_or_404(state: &AppState, club_id: Uuid, pid: Uuid) -> ApiResult<AccountPeriod> {
    repo::get_period(&state.pool, club_id, pid)
        .await?
        .ok_or_else(|| ApiError::not_found("no such accounting year"))
}

/// The year a write lands in must be open, and the date must fall inside it.
async fn open_period_for(
    conn: &mut sqlx::PgConnection,
    club_id: Uuid,
    on: NaiveDate,
) -> ApiResult<AccountPeriod> {
    repo::open_period_for_date(conn, club_id, on).await?.ok_or_else(|| {
        ApiError::conflict(format!(
            "{on} is not in an open accounting year — open the year first, or reopen it"
        ))
        .with_code("period_closed")
    })
}

fn ensure_open(period: &AccountPeriod) -> ApiResult<()> {
    if period.is_open() {
        Ok(())
    } else {
        Err(ApiError::conflict(format!(
            "{} is closed. Its figures don't change unless the owner reopens it.",
            period.label
        ))
        .with_code("period_closed"))
    }
}

async fn check_category(
    state: &AppState,
    club_id: Uuid,
    id: Uuid,
    kind: EntryKind,
) -> ApiResult<AccountCategory> {
    let c = repo::get_category(&state.pool, club_id, id)
        .await?
        .ok_or_else(|| ApiError::bad_request("that category isn't one of this club's"))?;
    if c.kind != kind.as_str() {
        return Err(ApiError::bad_request(format!(
            "{} is an {} line, not {}",
            c.name,
            c.kind,
            kind.as_str()
        )));
    }
    Ok(c)
}

async fn check_money_account(state: &AppState, club_id: Uuid, id: Uuid) -> ApiResult<MoneyAccount> {
    repo::get_money_account(&state.pool, club_id, id)
        .await?
        .ok_or_else(|| ApiError::bad_request("that money account isn't one of this club's"))
}

async fn build(state: &AppState, period: &AccountPeriod) -> ApiResult<AccountsReport> {
    let pool = &state.pool;
    let club_id = period.club_id;
    let (adjustments, extra_out, extra_in) = repo::period_extras(pool, period.id).await?;
    let input = ReportInput {
        period: period.clone(),
        categories: repo::list_categories(pool, club_id).await?,
        category_totals: repo::category_totals(pool, period.id).await?,
        adjustments_cents: adjustments,
        extraordinary_expenditure_cents: extra_out,
        extraordinary_income_cents: extra_in,
        money_accounts: repo::money_positions(pool, club_id, period.id).await?,
        stock: repo::stock_positions(pool, club_id, period.id).await?,
        debts: repo::debt_positions(pool, club_id, period.ends_on).await?,
        matches_played: repo::matches_played(pool, club_id, period.starts_on, period.ends_on)
            .await?,
    };
    Ok(build_report(&input))
}

// MARK: who keeps the books

#[derive(Deserialize)]
struct TreasurerBody {
    is_treasurer: bool,
}

/// Make somebody treasurer, or stop them being it. The owner or a secretary
/// may — and doing so gives *them* no way into the books.
async fn set_treasurer(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, user_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<TreasurerBody>,
) -> ApiResult<Json<serde_json::Value>> {
    let owner = repo::accounts_access(&state.pool, club_id, auth.user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("club not found"))?
        .0;
    if !owner {
        require_secretary(&state, club_id, auth.user_id).await?;
    }
    if !fishers_domain::can_set_treasurer(owner, true, user_id == auth.user_id, body.is_treasurer) {
        return Err(ApiError::forbidden(
            "A secretary can't make themselves treasurer. Ask the club owner.",
        )
        .with_code("treasurer_self_appointment"));
    }
    // The change and its line in the audit trail go together or not at all.
    let mut tx = state.pool.begin().await?;
    if !repo::set_treasurer(&mut tx, club_id, user_id, body.is_treasurer).await? {
        return Err(ApiError::not_found("they aren't an active member of this club"));
    }
    repo::audit(
        &mut tx,
        club_id,
        auth.user_id,
        if body.is_treasurer { "appoint_treasurer" } else { "remove_treasurer" },
        "member",
        Some(user_id),
        None,
        Some(json!({ "is_treasurer": body.is_treasurer })),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({ "user_id": user_id, "is_treasurer": body.is_treasurer })))
}

// MARK: overview

#[derive(Serialize)]
struct Overview {
    access: AccountsAccess,
    periods: Vec<AccountPeriod>,
    open_period_id: Option<Uuid>,
    categories: Vec<AccountCategory>,
    money_accounts: Vec<MoneyAccount>,
    /// The open year's headline figures, when there is one.
    open_report: Option<AccountsReport>,
    /// A suggested next year, so the first screen can offer it in one tap.
    suggested_next: SuggestedPeriod,
}

#[derive(Serialize)]
struct SuggestedPeriod {
    label: String,
    starts_on: NaiveDate,
    ends_on: NaiveDate,
}

fn suggest_next(periods: &[AccountPeriod]) -> SuggestedPeriod {
    use chrono::{Datelike, Months};
    let (starts_on, ends_on) = match periods.first() {
        Some(last) => {
            let s = last.ends_on.succ_opt().unwrap_or(last.ends_on);
            let e = s
                .checked_add_months(Months::new(12))
                .and_then(|d| d.pred_opt())
                .unwrap_or(s);
            (s, e)
        }
        None => {
            // Cricket clubs commonly run 1 October to 30 September.
            let today = Utc::now().date_naive();
            let y = if today.month() >= 10 { today.year() } else { today.year() - 1 };
            (
                NaiveDate::from_ymd_opt(y, 10, 1).expect("valid date"),
                NaiveDate::from_ymd_opt(y + 1, 9, 30).expect("valid date"),
            )
        }
    };
    SuggestedPeriod { label: period_label(starts_on, ends_on), starts_on, ends_on }
}

async fn overview(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<Overview>> {
    let access = require_accounts_access(&state, club_id, auth.user_id).await?;
    {
        let mut tx = state.pool.begin().await?;
        repo::ensure_default_categories(&mut tx, club_id).await?;
        tx.commit().await?;
    }
    let periods = repo::list_periods(&state.pool, club_id).await?;
    let open = periods.iter().find(|p| p.is_open()).cloned();
    let open_report = match &open {
        Some(p) => Some(build(&state, p).await?),
        None => None,
    };
    Ok(Json(Overview {
        access,
        suggested_next: suggest_next(&periods),
        open_period_id: open.map(|p| p.id),
        periods,
        categories: repo::list_categories(&state.pool, club_id).await?,
        money_accounts: repo::list_money_accounts(&state.pool, club_id).await?,
        open_report,
    }))
}

#[derive(Deserialize)]
struct AuditQuery {
    limit: Option<i64>,
}

async fn audit_log(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Query(q): Query<AuditQuery>,
) -> ApiResult<Json<Vec<AuditEntry>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    Ok(Json(repo::list_audit(&state.pool, club_id, q.limit.unwrap_or(100)).await?))
}

// MARK: years

async fn create_period(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<CreatePeriodRequest>,
) -> ApiResult<Json<AccountPeriod>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    if body.ends_on <= body.starts_on {
        return Err(ApiError::bad_request("the year has to end after it starts"));
    }
    if (body.ends_on - body.starts_on).num_days() > 550 {
        return Err(ApiError::bad_request("an accounting year can't be longer than 18 months"));
    }
    if repo::overlaps(&state.pool, club_id, body.starts_on, body.ends_on).await? {
        return Err(ApiError::conflict("those dates overlap a year already in the books"));
    }
    if let Some(open) = repo::list_periods(&state.pool, club_id)
        .await?
        .into_iter()
        .find(|p| p.is_open())
    {
        return Err(ApiError::conflict(format!(
            "{} is still open. Close it before starting another year.",
            open.label
        ))
        .with_code("period_open"));
    }

    // Last year's c/f is this year's b/f, and so are its bank balances and
    // stock. Typed in only when there is no last year to carry from.
    let previous = repo::previous_period(&state.pool, club_id, body.starts_on).await?;
    let carried = match &previous {
        Some(p) => Some(build(&state, p).await?),
        None => None,
    };
    let opening = match &carried {
        Some(r) => r.balance_sheet.carried_forward_cents,
        None => body.opening_balance_cents.unwrap_or(0),
    };
    let currency = body
        .currency
        .as_deref()
        .map(str::to_uppercase)
        .or_else(|| previous.as_ref().map(|p| p.currency.clone()))
        .unwrap_or_else(|| "GBP".into());

    let mut tx = state.pool.begin().await?;
    repo::ensure_default_categories(&mut tx, club_id).await?;
    let period = repo::create_period(
        &mut tx,
        club_id,
        body.label.trim(),
        body.starts_on,
        body.ends_on,
        &currency,
        opening,
        auth.user_id,
    )
    .await?;
    if let (Some(prev), Some(_)) = (&previous, &carried) {
        for a in repo::money_positions(&state.pool, club_id, prev.id).await? {
            let closing = a.reconciled_cents.unwrap_or(a.computed_closing_cents);
            repo::set_account_balance(&mut tx, a.id, period.id, Some(closing), None, None).await?;
        }
        for s in repo::stock_positions(&state.pool, club_id, prev.id).await? {
            repo::set_stock_count(
                &mut tx,
                s.item_id,
                period.id,
                Some(s.closing_quantity),
                Some(s.closing_cents),
                Some(s.closing_quantity),
                Some(s.closing_cents),
                None,
            )
            .await?;
        }
    }
    repo::audit(
        &mut tx,
        club_id,
        auth.user_id,
        "create",
        "period",
        Some(period.id),
        None,
        Some(json!(period)),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(period))
}

async fn update_period(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
    Json(body): Json<UpdatePeriodRequest>,
) -> ApiResult<Json<AccountPeriod>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let before = period_or_404(&state, club_id, pid).await?;
    // The words can be finished after the books close — the report is often
    // written then. The figures can't.
    if body.opening_balance_cents.is_some() {
        ensure_open(&before)?;
        if repo::previous_period(&state.pool, club_id, before.starts_on).await?.is_some() {
            return Err(ApiError::bad_request(
                "the opening balance is last year's closing balance — correct last year, \
                 or post a prior-period adjustment",
            ));
        }
    }
    let mut tx = state.pool.begin().await?;
    let after = repo::update_period(&mut tx, club_id, pid, &body)
        .await?
        .ok_or_else(|| ApiError::not_found("no such accounting year"))?;
    repo::audit(&mut tx, club_id, auth.user_id, "update", "period", Some(pid), Some(json!(before)), Some(json!(after)))
        .await?;
    tx.commit().await?;
    Ok(Json(after))
}

async fn close_period(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<AccountsReport>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    let period = period_or_404(&state, club_id, pid).await?;
    ensure_open(&period)?;
    let mut tx = state.pool.begin().await?;
    let closed = repo::set_period_status(&mut tx, club_id, pid, false, auth.user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("no such accounting year"))?;
    repo::audit(&mut tx, club_id, auth.user_id, "close", "period", Some(pid), None, None).await?;
    tx.commit().await?;
    Ok(Json(build(&state, &closed).await?))
}

/// Reopen a closed year. The owner only, with a reason, and never while a
/// later year is open — two open years would let one change the other's b/f.
async fn reopen_period(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
    Json(body): Json<ReopenPeriodRequest>,
) -> ApiResult<Json<AccountPeriod>> {
    let access = require_accounts_access(&state, club_id, auth.user_id).await?;
    if !access.is_owner {
        return Err(ApiError::forbidden("only the club owner can reopen a closed year"));
    }
    body.validate()?;
    let period = period_or_404(&state, club_id, pid).await?;
    if period.is_open() {
        return Ok(Json(period));
    }
    let periods = repo::list_periods(&state.pool, club_id).await?;
    if let Some(open) = periods.iter().find(|p| p.is_open()) {
        return Err(ApiError::conflict(format!(
            "{} is open. Close it before reopening {} — two open years could change each \
             other's balances.",
            open.label, period.label
        )));
    }
    let mut tx = state.pool.begin().await?;
    let reopened = repo::set_period_status(&mut tx, club_id, pid, true, auth.user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("no such accounting year"))?;
    repo::audit(
        &mut tx,
        club_id,
        auth.user_id,
        "reopen",
        "period",
        Some(pid),
        None,
        Some(json!({ "reason": body.reason.trim() })),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(reopened))
}

#[derive(Serialize)]
struct ReportResponse {
    current: AccountsReport,
    /// Last year, for the second column.
    previous: Option<AccountsReport>,
    club_name: String,
}

async fn report(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<ReportResponse>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    let period = period_or_404(&state, club_id, pid).await?;
    let current = build(&state, &period).await?;
    let previous = match repo::previous_period(&state.pool, club_id, period.starts_on).await? {
        Some(p) => Some(build(&state, &p).await?),
        None => None,
    };
    let club_name: String = sqlx::query_scalar("SELECT name FROM clubs WHERE id = $1")
        .bind(club_id)
        .fetch_one(&state.pool)
        .await?;
    Ok(Json(ReportResponse { current, previous, club_name }))
}

// MARK: transactions

async fn list_transactions(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
    Query(filter): Query<TransactionFilter>,
) -> ApiResult<Json<Vec<AccountTransaction>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    period_or_404(&state, club_id, pid).await?;
    Ok(Json(repo::list_transactions(&state.pool, club_id, pid, &filter).await?))
}

async fn create_transaction(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
    Json(body): Json<CreateTransactionRequest>,
) -> ApiResult<Json<AccountTransaction>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let period = period_or_404(&state, club_id, pid).await?;
    ensure_open(&period)?;
    if body.occurred_on < period.starts_on || body.occurred_on > period.ends_on {
        return Err(ApiError::bad_request(format!(
            "{} is outside {} ({} to {})",
            body.occurred_on, period.label, period.starts_on, period.ends_on
        )));
    }
    match body.kind {
        EntryKind::Income | EntryKind::Expenditure => {
            if body.amount_cents <= 0 {
                return Err(ApiError::bad_request("the amount has to be more than zero"));
            }
            let cid = body
                .category_id
                .ok_or_else(|| ApiError::bad_request("pick which line it goes on"))?;
            check_category(&state, club_id, cid, body.kind).await?;
        }
        EntryKind::Adjustment => {
            if body.amount_cents == 0 || body.category_id.is_some() {
                return Err(ApiError::bad_request(
                    "an adjustment has a signed amount and no category",
                ));
            }
            if body.extraordinary {
                return Err(ApiError::bad_request("an adjustment isn't trading, extraordinary or not"));
            }
        }
    }
    if let Some(aid) = body.money_account_id {
        check_money_account(&state, club_id, aid).await?;
    }
    let mut tx = state.pool.begin().await?;
    let id = repo::insert_transaction(&mut tx, club_id, pid, &body, None, auth.user_id).await?;
    let row = repo::get_transaction(&mut tx, club_id, id)
        .await?
        .ok_or_else(|| ApiError::internal("transaction vanished"))?;
    repo::audit(&mut tx, club_id, auth.user_id, "create", "transaction", Some(id), None, Some(json!(row)))
        .await?;
    tx.commit().await?;
    Ok(Json(row))
}

async fn update_transaction(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, tid)): Path<(Uuid, Uuid)>,
    Json(body): Json<UpdateTransactionRequest>,
) -> ApiResult<Json<AccountTransaction>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let mut tx = state.pool.begin().await?;
    let before = repo::get_transaction(&mut tx, club_id, tid)
        .await?
        .ok_or_else(|| ApiError::not_found("no such transaction"))?;
    if before.voided_at.is_some() {
        return Err(ApiError::conflict("a voided line can't be edited — add a new one"));
    }
    if before.source.is_some() {
        return Err(ApiError::conflict(
            "the app wrote this line from a payment or a debt; void it and post it again instead",
        ));
    }
    let period = period_or_404(&state, club_id, before.period_id).await?;
    ensure_open(&period)?;
    let kind = match before.kind.as_str() {
        "income" => EntryKind::Income,
        "expenditure" => EntryKind::Expenditure,
        _ => EntryKind::Adjustment,
    };
    if let Some(d) = body.occurred_on {
        if d < period.starts_on || d > period.ends_on {
            return Err(ApiError::bad_request(format!("{d} is outside {}", period.label)));
        }
    }
    if let Some(cid) = body.category_id {
        if kind == EntryKind::Adjustment {
            return Err(ApiError::bad_request("an adjustment has no category"));
        }
        check_category(&state, club_id, cid, kind).await?;
    }
    if let Some(Some(aid)) = body.money_account_id {
        check_money_account(&state, club_id, aid).await?;
    }
    if let Some(a) = body.amount_cents {
        if (kind != EntryKind::Adjustment && a <= 0) || a == 0 {
            return Err(ApiError::bad_request("that amount isn't allowed for this line"));
        }
    }
    repo::update_transaction(&mut tx, club_id, tid, &body).await?;
    let after = repo::get_transaction(&mut tx, club_id, tid)
        .await?
        .ok_or_else(|| ApiError::not_found("no such transaction"))?;
    repo::audit(&mut tx, club_id, auth.user_id, "update", "transaction", Some(tid), Some(json!(before)), Some(json!(after)))
        .await?;
    tx.commit().await?;
    Ok(Json(after))
}

async fn void_transaction(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, tid)): Path<(Uuid, Uuid)>,
    Json(body): Json<VoidRequest>,
) -> ApiResult<Json<AccountTransaction>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let mut tx = state.pool.begin().await?;
    let before = repo::get_transaction(&mut tx, club_id, tid)
        .await?
        .ok_or_else(|| ApiError::not_found("no such transaction"))?;
    let period = period_or_404(&state, club_id, before.period_id).await?;
    ensure_open(&period)?;
    if matches!(before.source.as_deref(), Some("debt_accrual" | "debt_write_off" | "debt_shortfall")) {
        return Err(ApiError::conflict(
            "this line belongs to a debt — void the debt or its settlement instead",
        ));
    }
    if !repo::void_transaction(&mut tx, club_id, tid, auth.user_id, &body.reason).await? {
        return Err(ApiError::conflict("already voided"));
    }
    let after = repo::get_transaction(&mut tx, club_id, tid)
        .await?
        .ok_or_else(|| ApiError::not_found("no such transaction"))?;
    repo::audit(&mut tx, club_id, auth.user_id, "void", "transaction", Some(tid), Some(json!(before)), Some(json!({ "reason": body.reason.trim() })))
        .await?;
    tx.commit().await?;
    Ok(Json(after))
}

// MARK: categories

async fn list_categories(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<Vec<AccountCategory>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    Ok(Json(repo::list_categories(&state.pool, club_id).await?))
}

async fn create_category(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<CreateCategoryRequest>,
) -> ApiResult<Json<AccountCategory>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let mut tx = state.pool.begin().await?;
    let c = repo::create_category(&mut tx, club_id, &body).await?;
    repo::audit(&mut tx, club_id, auth.user_id, "create", "category", Some(c.id), None, Some(json!(c)))
        .await?;
    tx.commit().await?;
    Ok(Json(c))
}

async fn update_category(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, cid)): Path<(Uuid, Uuid)>,
    Json(body): Json<UpdateCategoryRequest>,
) -> ApiResult<Json<AccountCategory>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let before = repo::get_category(&state.pool, club_id, cid)
        .await?
        .ok_or_else(|| ApiError::not_found("no such category"))?;
    if body.archived == Some(true) && before.system_key.is_some() {
        return Err(ApiError::conflict(format!(
            "the app posts to {} by itself, so it can't be archived — rename it instead",
            before.name
        )));
    }
    let mut tx = state.pool.begin().await?;
    let after = repo::update_category(&mut tx, club_id, cid, &body)
        .await?
        .ok_or_else(|| ApiError::not_found("no such category"))?;
    repo::audit(&mut tx, club_id, auth.user_id, "update", "category", Some(cid), Some(json!(before)), Some(json!(after)))
        .await?;
    tx.commit().await?;
    Ok(Json(after))
}

// MARK: money accounts

async fn list_money_accounts(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
) -> ApiResult<Json<Vec<MoneyAccount>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    Ok(Json(repo::list_money_accounts(&state.pool, club_id).await?))
}

async fn list_money_positions(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<Vec<MoneyAccountPosition>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    period_or_404(&state, club_id, pid).await?;
    Ok(Json(repo::money_positions(&state.pool, club_id, pid).await?))
}

async fn create_money_account(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<CreateMoneyAccountRequest>,
) -> ApiResult<Json<MoneyAccount>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    if !money_kind_ok(&body.kind) {
        return Err(ApiError::bad_request("kind is bank, cash, supplier_credit or provider"));
    }
    let open = repo::list_periods(&state.pool, club_id)
        .await?
        .into_iter()
        .find(|p| p.is_open());
    let mut tx = state.pool.begin().await?;
    let a = repo::create_money_account(&mut tx, club_id, &body.name, &body.kind).await?;
    if let Some(p) = &open {
        repo::set_account_balance(&mut tx, a.id, p.id, Some(body.opening_cents.unwrap_or(0)), None, None)
            .await?;
    }
    repo::audit(&mut tx, club_id, auth.user_id, "create", "money_account", Some(a.id), None, Some(json!({ "account": a, "opening_cents": body.opening_cents })))
        .await?;
    tx.commit().await?;
    Ok(Json(a))
}

async fn update_money_account(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, aid)): Path<(Uuid, Uuid)>,
    Json(body): Json<UpdateMoneyAccountRequest>,
) -> ApiResult<Json<MoneyAccount>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let before = check_money_account(&state, club_id, aid).await?;
    let mut tx = state.pool.begin().await?;
    let after = repo::update_money_account(&mut tx, club_id, aid, body.name.as_deref(), body.archived)
        .await?
        .ok_or_else(|| ApiError::not_found("no such money account"))?;
    repo::audit(&mut tx, club_id, auth.user_id, "update", "money_account", Some(aid), Some(json!(before)), Some(json!(after)))
        .await?;
    tx.commit().await?;
    Ok(Json(after))
}

/// Opening balance (first year only) and the statement figure for a year.
async fn set_balance(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, aid)): Path<(Uuid, Uuid)>,
    Json(body): Json<SetAccountBalanceRequest>,
) -> ApiResult<Json<Vec<MoneyAccountPosition>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    check_money_account(&state, club_id, aid).await?;
    let period = period_or_404(&state, club_id, body.period_id).await?;
    ensure_open(&period)?;
    if body.opening_cents.is_some()
        && repo::previous_period(&state.pool, club_id, period.starts_on).await?.is_some()
    {
        return Err(ApiError::bad_request(
            "the opening balance came from last year's closing figure; correct last year instead",
        ));
    }
    let mut tx = state.pool.begin().await?;
    repo::set_account_balance(
        &mut tx,
        aid,
        period.id,
        body.opening_cents,
        body.reconciled_cents,
        body.reconciled_on.or(Some(period.ends_on)),
    )
    .await?;
    repo::audit(
        &mut tx,
        club_id,
        auth.user_id,
        "set_balance",
        "money_account",
        Some(aid),
        None,
        Some(json!({
            "period_id": period.id,
            "opening_cents": body.opening_cents,
            "reconciled_cents": body.reconciled_cents,
            "reconciled_on": body.reconciled_on,
        })),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(repo::money_positions(&state.pool, club_id, period.id).await?))
}

// MARK: debts

async fn list_debts(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<Vec<DebtPosition>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    let period = period_or_404(&state, club_id, pid).await?;
    Ok(Json(repo::debt_positions(&state.pool, club_id, period.ends_on).await?))
}

/// The category the other side of a debt goes on.
fn accrual_key(direction: &str, kind: &str) -> (&'static str, &'static str) {
    let cat_kind = if direction == "debtor" { "income" } else { "expenditure" };
    let key = match kind {
        "member_fees" => keys::FEES_OWED,
        "cost_share" => keys::COST_SHARE_OWED,
        _ => keys::MISC,
    };
    (cat_kind, key)
}

async fn raise_debt(
    state: &AppState,
    tx: &mut sqlx::PgConnection,
    club_id: Uuid,
    req: &CreateDebtRequest,
    by: Uuid,
) -> ApiResult<Uuid> {
    let period = open_period_for(tx, club_id, req.raised_on).await?;
    let mut transaction_id = None;
    if req.accrue {
        let (cat_kind, key) = accrual_key(&req.direction, &req.kind);
        let category = repo::category_by_key(tx, club_id, cat_kind, key)
            .await?
            .ok_or_else(|| ApiError::conflict(format!("the club has no {cat_kind} line for {key}")))?;
        let line = CreateTransactionRequest {
            occurred_on: req.raised_on,
            kind: if cat_kind == "income" { EntryKind::Income } else { EntryKind::Expenditure },
            category_id: Some(category.id),
            money_account_id: None,
            amount_cents: req.amount_cents,
            description: req.description.clone(),
            counterparty: req.counterparty.clone(),
            member_id: req.member_id,
            event_id: req.event_id,
            note: None,
            receipt_url: None,
            extraordinary: false,
            authorised_on: None,
            authorisation_ref: None,
        };
        // The source ref is filled in once the debt has an id.
        transaction_id =
            Some(repo::insert_transaction(tx, club_id, period.id, &line, None, by).await?);
    }
    let id = repo::insert_debt(tx, club_id, period.id, req, transaction_id, by).await?;
    if let Some(t) = transaction_id {
        sqlx::query(
            "UPDATE club_account_transactions SET source = 'debt_accrual', source_ref = $2 WHERE id = $1",
        )
        .bind(t)
        .bind(id)
        .execute(&mut *tx)
        .await?;
    }
    let _ = state;
    Ok(id)
}

fn validate_debt(req: &CreateDebtRequest) -> ApiResult<()> {
    req.validate()?;
    if !matches!(req.direction.as_str(), "debtor" | "creditor") {
        return Err(ApiError::bad_request("direction is debtor or creditor"));
    }
    if !matches!(req.kind.as_str(), "member_fees" | "cost_share" | "other") {
        return Err(ApiError::bad_request("kind is member_fees, cost_share or other"));
    }
    if req.amount_cents <= 0 {
        return Err(ApiError::bad_request("the amount has to be more than zero"));
    }
    Ok(())
}

async fn create_debt(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<CreateDebtRequest>,
) -> ApiResult<Json<DebtPosition>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    validate_debt(&body)?;
    let mut tx = state.pool.begin().await?;
    let id = raise_debt(&state, &mut tx, club_id, &body, auth.user_id).await?;
    let debt = repo::debt_now(&mut tx, club_id, id)
        .await?
        .ok_or_else(|| ApiError::internal("debt vanished"))?;
    repo::audit(&mut tx, club_id, auth.user_id, "create", "debt", Some(id), None, Some(json!(debt)))
        .await?;
    tx.commit().await?;
    Ok(Json(debt))
}

async fn list_settlements(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, did)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<Vec<DebtSettlement>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    let mut conn = state.pool.acquire().await?;
    repo::debt_now(&mut conn, club_id, did)
        .await?
        .ok_or_else(|| ApiError::not_found("no such debt"))?;
    Ok(Json(repo::list_settlements(&state.pool, did).await?))
}

/// Pay, part-pay, write off, or record a debt that came in short.
///
/// A write-off posts to "Unrecovered debt"; a shortfall posts to "Losses on
/// previous year recovered debt". A payment moves money into (or, for a
/// creditor, out of) an account and is not income — the income was counted
/// when the debt was raised.
async fn settle(
    tx: &mut sqlx::PgConnection,
    club_id: Uuid,
    debt: &DebtPosition,
    req: &SettleDebtRequest,
    payment_id: Option<Uuid>,
    by: Uuid,
) -> ApiResult<Uuid> {
    if req.amount_cents <= 0 {
        return Err(ApiError::bad_request("the amount has to be more than zero"));
    }
    if req.amount_cents > debt.outstanding_now_cents {
        return Err(ApiError::bad_request(format!(
            "only {} is still owed",
            fmt_money(debt.outstanding_now_cents)
        )));
    }
    let period = open_period_for(tx, club_id, req.settled_on).await?;
    let mut transaction_id = None;
    match req.kind.as_str() {
        "payment" => {
            if req.money_account_id.is_none() {
                return Err(ApiError::bad_request("say which account it was paid into"));
            }
        }
        "write_off" | "shortfall" => {
            if debt.direction != "debtor" {
                return Err(ApiError::bad_request("only money owed to the club is written off"));
            }
            let key = if req.kind == "write_off" {
                keys::UNRECOVERED_DEBT
            } else {
                keys::RECOVERED_DEBT_LOSS
            };
            let category = repo::category_by_key(tx, club_id, "expenditure", key)
                .await?
                .ok_or_else(|| ApiError::conflict(format!("the club has no expenditure line for {key}")))?;
            let line = CreateTransactionRequest {
                occurred_on: req.settled_on,
                kind: EntryKind::Expenditure,
                category_id: Some(category.id),
                money_account_id: None,
                amount_cents: req.amount_cents,
                description: format!(
                    "{}: {}",
                    if req.kind == "write_off" { "Written off" } else { "Recovered short" },
                    debt.description
                ),
                counterparty: debt.counterparty.clone().or(debt.member_name.clone()),
                member_id: debt.member_id,
                event_id: debt.event_id,
                note: req.note.clone(),
                receipt_url: None,
                extraordinary: false,
                authorised_on: None,
                authorisation_ref: None,
            };
            transaction_id = Some(repo::insert_transaction(tx, club_id, period.id, &line, None, by).await?);
        }
        _ => return Err(ApiError::bad_request("kind is payment, write_off or shortfall")),
    }
    let id = repo::insert_settlement(
        tx,
        debt.id,
        period.id,
        req.settled_on,
        &req.kind,
        req.amount_cents,
        if req.kind == "payment" { req.money_account_id } else { None },
        payment_id,
        req.note.as_deref(),
        transaction_id,
        by,
    )
    .await?;
    if let Some(t) = transaction_id {
        let source = if req.kind == "write_off" { "debt_write_off" } else { "debt_shortfall" };
        sqlx::query("UPDATE club_account_transactions SET source = $3, source_ref = $2 WHERE id = $1")
            .bind(t)
            .bind(id)
            .bind(source)
            .execute(&mut *tx)
            .await?;
    }
    Ok(id)
}

fn fmt_money(cents: i64) -> String {
    format!("{}{}.{:02}", if cents < 0 { "-" } else { "" }, cents.abs() / 100, cents.abs() % 100)
}

async fn settle_debt(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, did)): Path<(Uuid, Uuid)>,
    Json(body): Json<SettleDebtRequest>,
) -> ApiResult<Json<DebtPosition>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    if let Some(aid) = body.money_account_id {
        check_money_account(&state, club_id, aid).await?;
    }
    let mut tx = state.pool.begin().await?;
    let debt = repo::debt_now(&mut tx, club_id, did)
        .await?
        .ok_or_else(|| ApiError::not_found("no such debt"))?;
    let sid = settle(&mut tx, club_id, &debt, &body, None, auth.user_id).await?;
    let after = repo::debt_now(&mut tx, club_id, did)
        .await?
        .ok_or_else(|| ApiError::not_found("no such debt"))?;
    repo::audit(&mut tx, club_id, auth.user_id, "settle", "debt", Some(did), Some(json!(debt)), Some(json!({ "settlement_id": sid, "kind": body.kind, "amount_cents": body.amount_cents, "settled_on": body.settled_on })))
        .await?;
    tx.commit().await?;
    Ok(Json(after))
}

async fn void_debt(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, did)): Path<(Uuid, Uuid)>,
    Json(body): Json<VoidRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let mut tx = state.pool.begin().await?;
    let debt = repo::debt_now(&mut tx, club_id, did)
        .await?
        .ok_or_else(|| ApiError::not_found("no such debt"))?;
    ensure_open(&period_or_404(&state, club_id, debt.period_id).await?)?;
    if !repo::void_debt(&mut tx, club_id, did, auth.user_id, &body.reason).await? {
        return Err(ApiError::conflict(
            "something has been paid or written off against this debt — void that first",
        ));
    }
    repo::audit(&mut tx, club_id, auth.user_id, "void", "debt", Some(did), Some(json!(debt)), Some(json!({ "reason": body.reason.trim() })))
        .await?;
    tx.commit().await?;
    Ok(Json(json!({ "voided": did })))
}

async fn void_settlement(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, sid)): Path<(Uuid, Uuid)>,
    Json(body): Json<VoidRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let (_, status) = repo::settlement_period(&state.pool, club_id, sid)
        .await?
        .ok_or_else(|| ApiError::not_found("no such settlement"))?;
    if status != "open" {
        return Err(ApiError::conflict("that settlement is in a closed year").with_code("period_closed"));
    }
    let mut tx = state.pool.begin().await?;
    if !repo::void_settlement(&mut tx, club_id, sid, auth.user_id, &body.reason).await? {
        return Err(ApiError::conflict("already voided"));
    }
    repo::audit(&mut tx, club_id, auth.user_id, "void", "settlement", Some(sid), None, Some(json!({ "reason": body.reason.trim() })))
        .await?;
    tx.commit().await?;
    Ok(Json(json!({ "voided": sid })))
}

// MARK: what the app already knows

#[derive(Serialize)]
struct Suggestions {
    /// Fees paid in the app, not yet in the books.
    payments: Vec<PaymentSuggestion>,
    /// Fees still unpaid for fixtures played in the year.
    unpaid_fees: Vec<UnpaidFee>,
}

async fn suggestions(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<Suggestions>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    let p = period_or_404(&state, club_id, pid).await?;
    Ok(Json(Suggestions {
        payments: repo::payment_suggestions(&state.pool, club_id, p.starts_on, p.ends_on).await?,
        unpaid_fees: repo::unpaid_fees(&state.pool, club_id, p.starts_on, p.ends_on).await?,
    }))
}

#[derive(Serialize)]
struct AcceptOutcome {
    /// Became income on the fees line.
    posted: usize,
    /// Paid off a fee already owed at a year end — not income twice.
    settled: usize,
    skipped: Vec<Uuid>,
}

/// Take fees paid in the app into the books. Nothing posts without this.
async fn accept_payments(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
    Json(body): Json<AcceptPaymentsRequest>,
) -> ApiResult<Json<AcceptOutcome>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    let period = period_or_404(&state, club_id, pid).await?;
    ensure_open(&period)?;
    check_money_account(&state, club_id, body.money_account_id).await?;
    let mut out = AcceptOutcome { posted: 0, settled: 0, skipped: vec![] };
    let mut tx = state.pool.begin().await?;
    for payment_id in body.payment_ids.iter().copied() {
        let Some(s) = repo::payment_suggestion(&mut tx, club_id, payment_id).await? else {
            out.skipped.push(payment_id);
            continue;
        };
        if s.paid_on < period.starts_on || s.paid_on > period.ends_on {
            out.skipped.push(payment_id);
            continue;
        }
        if let Some(debt_id) = s.settles_debt_id {
            let debt = repo::debt_now(&mut tx, club_id, debt_id).await?;
            if let Some(debt) = debt.filter(|d| d.outstanding_now_cents > 0) {
                let req = SettleDebtRequest {
                    kind: "payment".into(),
                    amount_cents: s.amount_cents.min(debt.outstanding_now_cents),
                    settled_on: s.paid_on,
                    money_account_id: Some(body.money_account_id),
                    note: Some("Paid in the app".into()),
                };
                settle(&mut tx, club_id, &debt, &req, Some(payment_id), auth.user_id).await?;
                out.settled += 1;
                continue;
            }
        }
        let key = fee_category_key(&s.event_subtype);
        let category = repo::category_by_key(&mut tx, club_id, CategoryKind::Income.as_str(), key)
            .await?
            .ok_or_else(|| ApiError::conflict(format!("the club has no income line for {key}")))?;
        let line = CreateTransactionRequest {
            occurred_on: s.paid_on,
            kind: EntryKind::Income,
            category_id: Some(category.id),
            money_account_id: Some(body.money_account_id),
            amount_cents: s.amount_cents,
            description: s.event_title.clone(),
            counterparty: Some(s.member_name.clone()),
            member_id: Some(s.member_id),
            event_id: Some(s.event_id),
            note: Some("Paid in the app".into()),
            receipt_url: None,
            extraordinary: false,
            authorised_on: None,
            authorisation_ref: None,
        };
        repo::insert_transaction(&mut tx, club_id, pid, &line, Some(("payment", payment_id)), auth.user_id)
            .await?;
        out.posted += 1;
    }
    repo::audit(&mut tx, club_id, auth.user_id, "accept_payments", "period", Some(pid), None, Some(json!({ "payment_ids": body.payment_ids, "posted": out.posted, "settled": out.settled })))
        .await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Raise every fee still unpaid for the year's fixtures as a debtor, one per
/// member per fixture. Run it again and nothing doubles.
async fn raise_unpaid_fees(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
    Json(body): Json<RaiseUnpaidFeesRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    let period = period_or_404(&state, club_id, pid).await?;
    ensure_open(&period)?;
    let fees = repo::unpaid_fees(&state.pool, club_id, period.starts_on, period.ends_on).await?;
    let mut tx = state.pool.begin().await?;
    let mut raised = 0usize;
    for f in fees
        .iter()
        .filter(|f| !f.already_raised)
        .filter(|f| body.event_ids.is_empty() || body.event_ids.contains(&f.event_id))
    {
        let req = CreateDebtRequest {
            direction: "debtor".into(),
            kind: "member_fees".into(),
            description: format!("{} — {}", f.event_title, f.played_on.format("%-d %b %Y")),
            counterparty: Some(f.member_name.clone()),
            member_id: Some(f.member_id),
            event_id: Some(f.event_id),
            amount_cents: f.amount_cents,
            // Owed at the year end, whatever day it was played.
            raised_on: period.ends_on.min(Utc::now().date_naive()).max(f.played_on),
            note: None,
            accrue: true,
        };
        raise_debt(&state, &mut tx, club_id, &req, auth.user_id).await?;
        raised += 1;
    }
    repo::audit(&mut tx, club_id, auth.user_id, "raise_unpaid_fees", "period", Some(pid), None, Some(json!({ "raised": raised })))
        .await?;
    tx.commit().await?;
    Ok(Json(json!({ "raised": raised })))
}

// MARK: stock

async fn list_stock(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, pid)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<Vec<StockPosition>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    period_or_404(&state, club_id, pid).await?;
    Ok(Json(repo::stock_positions(&state.pool, club_id, pid).await?))
}

async fn create_stock_item(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(club_id): Path<Uuid>,
    Json(body): Json<CreateStockItemRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    body.validate()?;
    let mut tx = state.pool.begin().await?;
    let id = repo::create_stock_item(&mut tx, club_id, &body.name).await?;
    repo::audit(&mut tx, club_id, auth.user_id, "create", "stock_item", Some(id), None, Some(json!({ "name": body.name.trim() })))
        .await?;
    tx.commit().await?;
    Ok(Json(json!({ "id": id, "name": body.name.trim() })))
}

async fn set_stock_count(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, item)): Path<(Uuid, Uuid)>,
    Json(body): Json<SetStockCountRequest>,
) -> ApiResult<Json<Vec<StockPosition>>> {
    require_accounts_access(&state, club_id, auth.user_id).await?;
    if !repo::stock_item_belongs(&state.pool, club_id, item).await? {
        return Err(ApiError::not_found("no such stock item"));
    }
    let period = period_or_404(&state, club_id, body.period_id).await?;
    ensure_open(&period)?;
    let negative = [body.opening_cents, body.closing_cents].iter().flatten().any(|v| *v < 0)
        || [body.opening_quantity, body.closing_quantity].iter().flatten().any(|v| *v < 0);
    if negative {
        return Err(ApiError::bad_request("stock can't be negative"));
    }
    if (body.opening_cents.is_some() || body.opening_quantity.is_some())
        && repo::previous_period(&state.pool, club_id, period.starts_on).await?.is_some()
    {
        return Err(ApiError::bad_request(
            "opening stock is last year's closing count; correct last year instead",
        ));
    }
    let mut tx = state.pool.begin().await?;
    repo::set_stock_count(
        &mut tx,
        item,
        period.id,
        body.opening_quantity,
        body.opening_cents,
        body.closing_quantity,
        body.closing_cents,
        body.counted_on,
    )
    .await?;
    repo::audit(&mut tx, club_id, auth.user_id, "count", "stock_item", Some(item), None, Some(json!({
        "period_id": period.id,
        "opening_quantity": body.opening_quantity,
        "opening_cents": body.opening_cents,
        "closing_quantity": body.closing_quantity,
        "closing_cents": body.closing_cents,
    })))
    .await?;
    tx.commit().await?;
    Ok(Json(repo::stock_positions(&state.pool, club_id, period.id).await?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_next_year_follows_the_last() {
        let d = |y, m, day| NaiveDate::from_ymd_opt(y, m, day).unwrap();
        let last = AccountPeriod {
            id: Uuid::nil(),
            club_id: Uuid::nil(),
            label: "2025/26".into(),
            starts_on: d(2025, 10, 1),
            ends_on: d(2026, 9, 30),
            status: "closed".into(),
            currency: "GBP".into(),
            opening_balance_cents: 0,
            report_text: None,
            statement_text: None,
            signed_by_name: None,
            signed_on: None,
            closed_at: None,
            created_at: Utc::now(),
        };
        let next = suggest_next(&[last]);
        assert_eq!(next.starts_on, d(2026, 10, 1));
        assert_eq!(next.ends_on, d(2027, 9, 30));
        assert_eq!(next.label, "2026/27");
    }

    #[test]
    fn debts_accrue_to_the_right_line() {
        assert_eq!(accrual_key("debtor", "member_fees"), ("income", keys::FEES_OWED));
        assert_eq!(accrual_key("debtor", "cost_share"), ("income", keys::COST_SHARE_OWED));
        assert_eq!(accrual_key("creditor", "cost_share"), ("expenditure", keys::COST_SHARE_OWED));
        assert_eq!(fmt_money(10_850), "108.50");
        assert_eq!(fmt_money(-6_992), "-69.92");
    }
}
