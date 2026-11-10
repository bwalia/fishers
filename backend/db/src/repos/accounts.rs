//! Club accounts — periods, categories, money accounts, transactions, debts,
//! stock, and the audit trail.
//!
//! Reads take the pool. Writes take a connection so a route can put the change
//! and its audit row in one transaction: a change to club money with no record
//! of who made it is worse than no change.
//!
//! `SUM(bigint)` is `numeric` in Postgres; every sum here is cast back.

use chrono::NaiveDate;
use fishers_domain::{
    AccountCategory, AccountPeriod, AccountTransaction, AuditEntry, CreateCategoryRequest,
    CreateDebtRequest, CreateTransactionRequest, DebtPosition, DebtSettlement, MoneyAccount,
    MoneyAccountPosition, PaymentSuggestion, StockPosition, UnpaidFee, UpdateCategoryRequest,
    UpdatePeriodRequest, UpdateTransactionRequest, DEFAULT_CATEGORIES,
};
use serde_json::Value;
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

// MARK: who may open the books

/// `(is_owner, is_active_treasurer)` for somebody in a club.
pub async fn accounts_access(
    pool: &PgPool,
    club_id: Uuid,
    user_id: Uuid,
) -> Result<Option<(bool, bool)>, sqlx::Error> {
    sqlx::query_as::<_, (bool, bool)>(
        r#"
        SELECT c.owner_id = $2 AS is_owner,
               COALESCE(m.is_treasurer AND m.status = 'active', false) AS is_treasurer
        FROM clubs c
        LEFT JOIN club_members m ON m.club_id = c.id AND m.user_id = $2
        WHERE c.id = $1
        "#,
    )
    .bind(club_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

/// Make somebody the club's treasurer, or stop them being it. Only an active
/// member can hold it. Returns `false` when they are not one.
pub async fn set_treasurer(
    conn: &mut PgConnection,
    club_id: Uuid,
    user_id: Uuid,
    is_treasurer: bool,
) -> Result<bool, sqlx::Error> {
    let done = sqlx::query(
        r#"
        UPDATE club_members SET is_treasurer = $3
        WHERE club_id = $1 AND user_id = $2 AND status = 'active'
        "#,
    )
    .bind(club_id)
    .bind(user_id)
    .bind(is_treasurer)
    .execute(conn)
    .await?;
    Ok(done.rows_affected() > 0)
}

// MARK: audit

#[allow(clippy::too_many_arguments)]
pub async fn audit(
    conn: &mut PgConnection,
    club_id: Uuid,
    actor_id: Uuid,
    action: &str,
    entity: &str,
    entity_id: Option<Uuid>,
    before: Option<Value>,
    after: Option<Value>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO club_account_audit (club_id, actor_id, action, entity, entity_id, before, after)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        "#,
    )
    .bind(club_id)
    .bind(actor_id)
    .bind(action)
    .bind(entity)
    .bind(entity_id)
    .bind(before)
    .bind(after)
    .execute(conn)
    .await?;
    Ok(())
}

pub async fn list_audit(
    pool: &PgPool,
    club_id: Uuid,
    limit: i64,
) -> Result<Vec<AuditEntry>, sqlx::Error> {
    sqlx::query_as::<_, AuditEntry>(
        r#"
        SELECT a.id, u.name AS actor_name, a.action, a.entity, a.entity_id, a.before, a.after,
               a.created_at
        FROM club_account_audit a
        LEFT JOIN users u ON u.id = a.actor_id
        WHERE a.club_id = $1
        ORDER BY a.created_at DESC, a.id DESC
        LIMIT $2
        "#,
    )
    .bind(club_id)
    .bind(limit.clamp(1, 500))
    .fetch_all(pool)
    .await
}

// MARK: categories

/// Give a club the usual categories the first time its books are opened.
/// Does nothing once it has any — a treasurer's renames and deletions stay.
pub async fn ensure_default_categories(
    conn: &mut PgConnection,
    club_id: Uuid,
) -> Result<(), sqlx::Error> {
    let has_any: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM club_account_categories WHERE club_id = $1)",
    )
    .bind(club_id)
    .fetch_one(&mut *conn)
    .await?;
    if has_any {
        return Ok(());
    }
    for (i, d) in DEFAULT_CATEGORIES.iter().enumerate() {
        sqlx::query(
            r#"
            INSERT INTO club_account_categories (club_id, kind, name, system_key, sort_order, footnote)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT DO NOTHING
            "#,
        )
        .bind(club_id)
        .bind(d.kind.as_str())
        .bind(d.name)
        .bind(d.system_key)
        .bind((i as i32 + 1) * 10)
        .bind(d.footnote)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

const CATEGORY_COLS: &str =
    "id, club_id, kind, name, system_key, sort_order, footnote, archived";

pub async fn list_categories(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<AccountCategory>, sqlx::Error> {
    sqlx::query_as::<_, AccountCategory>(&format!(
        "SELECT {CATEGORY_COLS} FROM club_account_categories WHERE club_id = $1
         ORDER BY kind DESC, sort_order, name"
    ))
    .bind(club_id)
    .fetch_all(pool)
    .await
}

pub async fn get_category(
    pool: &PgPool,
    club_id: Uuid,
    id: Uuid,
) -> Result<Option<AccountCategory>, sqlx::Error> {
    sqlx::query_as::<_, AccountCategory>(&format!(
        "SELECT {CATEGORY_COLS} FROM club_account_categories WHERE club_id = $1 AND id = $2"
    ))
    .bind(club_id)
    .bind(id)
    .fetch_optional(pool)
    .await
}

pub async fn category_by_key(
    conn: &mut PgConnection,
    club_id: Uuid,
    kind: &str,
    key: &str,
) -> Result<Option<AccountCategory>, sqlx::Error> {
    sqlx::query_as::<_, AccountCategory>(&format!(
        "SELECT {CATEGORY_COLS} FROM club_account_categories
         WHERE club_id = $1 AND kind = $2 AND system_key = $3"
    ))
    .bind(club_id)
    .bind(kind)
    .bind(key)
    .fetch_optional(conn)
    .await
}

pub async fn create_category(
    conn: &mut PgConnection,
    club_id: Uuid,
    req: &CreateCategoryRequest,
) -> Result<AccountCategory, sqlx::Error> {
    sqlx::query_as::<_, AccountCategory>(&format!(
        r#"
        INSERT INTO club_account_categories (club_id, kind, name, sort_order, footnote)
        VALUES ($1, $2, $3,
                COALESCE($4, (SELECT COALESCE(MAX(sort_order), 0) + 10
                              FROM club_account_categories WHERE club_id = $1 AND kind = $2)),
                NULLIF(TRIM($5), ''))
        RETURNING {CATEGORY_COLS}
        "#
    ))
    .bind(club_id)
    .bind(req.kind.as_str())
    .bind(req.name.trim())
    .bind(req.sort_order)
    .bind(req.footnote.as_deref())
    .fetch_one(conn)
    .await
}

pub async fn update_category(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
    req: &UpdateCategoryRequest,
) -> Result<Option<AccountCategory>, sqlx::Error> {
    let (set_footnote, footnote) = match &req.footnote {
        None => (false, None),
        Some(v) => (true, v.as_deref().map(str::trim).filter(|s| !s.is_empty())),
    };
    sqlx::query_as::<_, AccountCategory>(&format!(
        r#"
        UPDATE club_account_categories SET
            name       = COALESCE($3, name),
            sort_order = COALESCE($4, sort_order),
            footnote   = CASE WHEN $5 THEN $6 ELSE footnote END,
            archived   = COALESCE($7, archived)
        WHERE club_id = $1 AND id = $2
        RETURNING {CATEGORY_COLS}
        "#
    ))
    .bind(club_id)
    .bind(id)
    .bind(req.name.as_deref().map(str::trim))
    .bind(req.sort_order)
    .bind(set_footnote)
    .bind(footnote)
    .bind(req.archived)
    .fetch_optional(conn)
    .await
}

// MARK: periods

const PERIOD_COLS: &str = "id, club_id, label, starts_on, ends_on, status, currency, \
    opening_balance_cents, report_text, statement_text, signed_by_name, signed_on, closed_at, \
    created_at";

pub async fn list_periods(pool: &PgPool, club_id: Uuid) -> Result<Vec<AccountPeriod>, sqlx::Error> {
    sqlx::query_as::<_, AccountPeriod>(&format!(
        "SELECT {PERIOD_COLS} FROM club_account_periods WHERE club_id = $1 ORDER BY starts_on DESC"
    ))
    .bind(club_id)
    .fetch_all(pool)
    .await
}

pub async fn get_period(
    pool: &PgPool,
    club_id: Uuid,
    id: Uuid,
) -> Result<Option<AccountPeriod>, sqlx::Error> {
    sqlx::query_as::<_, AccountPeriod>(&format!(
        "SELECT {PERIOD_COLS} FROM club_account_periods WHERE club_id = $1 AND id = $2"
    ))
    .bind(club_id)
    .bind(id)
    .fetch_optional(pool)
    .await
}

/// The year that ended the day before `starts_on` began, if it is in the app.
pub async fn previous_period(
    pool: &PgPool,
    club_id: Uuid,
    starts_on: NaiveDate,
) -> Result<Option<AccountPeriod>, sqlx::Error> {
    sqlx::query_as::<_, AccountPeriod>(&format!(
        "SELECT {PERIOD_COLS} FROM club_account_periods
         WHERE club_id = $1 AND ends_on < $2 ORDER BY ends_on DESC LIMIT 1"
    ))
    .bind(club_id)
    .bind(starts_on)
    .fetch_optional(pool)
    .await
}

/// The open year whose dates contain `on`.
pub async fn open_period_for_date(
    conn: &mut PgConnection,
    club_id: Uuid,
    on: NaiveDate,
) -> Result<Option<AccountPeriod>, sqlx::Error> {
    sqlx::query_as::<_, AccountPeriod>(&format!(
        "SELECT {PERIOD_COLS} FROM club_account_periods
         WHERE club_id = $1 AND status = 'open' AND $2 BETWEEN starts_on AND ends_on"
    ))
    .bind(club_id)
    .bind(on)
    .fetch_optional(conn)
    .await
}

pub async fn overlaps(
    pool: &PgPool,
    club_id: Uuid,
    starts_on: NaiveDate,
    ends_on: NaiveDate,
) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM club_account_periods
         WHERE club_id = $1 AND starts_on <= $3 AND ends_on >= $2)",
    )
    .bind(club_id)
    .bind(starts_on)
    .bind(ends_on)
    .fetch_one(pool)
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn create_period(
    conn: &mut PgConnection,
    club_id: Uuid,
    label: &str,
    starts_on: NaiveDate,
    ends_on: NaiveDate,
    currency: &str,
    opening_balance_cents: i64,
    created_by: Uuid,
) -> Result<AccountPeriod, sqlx::Error> {
    sqlx::query_as::<_, AccountPeriod>(&format!(
        r#"
        INSERT INTO club_account_periods
            (club_id, label, starts_on, ends_on, currency, opening_balance_cents, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING {PERIOD_COLS}
        "#
    ))
    .bind(club_id)
    .bind(label)
    .bind(starts_on)
    .bind(ends_on)
    .bind(currency)
    .bind(opening_balance_cents)
    .bind(created_by)
    .fetch_one(conn)
    .await
}

pub async fn update_period(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
    req: &UpdatePeriodRequest,
) -> Result<Option<AccountPeriod>, sqlx::Error> {
    sqlx::query_as::<_, AccountPeriod>(&format!(
        r#"
        UPDATE club_account_periods SET
            label                 = COALESCE($3, label),
            opening_balance_cents = COALESCE($4, opening_balance_cents),
            report_text           = COALESCE($5, report_text),
            statement_text        = COALESCE($6, statement_text),
            signed_by_name        = COALESCE($7, signed_by_name),
            signed_on             = COALESCE($8, signed_on),
            updated_at            = NOW()
        WHERE club_id = $1 AND id = $2
        RETURNING {PERIOD_COLS}
        "#
    ))
    .bind(club_id)
    .bind(id)
    .bind(req.label.as_deref().map(str::trim))
    .bind(req.opening_balance_cents)
    .bind(req.report_text.as_deref())
    .bind(req.statement_text.as_deref())
    .bind(req.signed_by_name.as_deref().map(str::trim))
    .bind(req.signed_on)
    .fetch_optional(conn)
    .await
}

pub async fn set_period_status(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
    open: bool,
    by: Uuid,
) -> Result<Option<AccountPeriod>, sqlx::Error> {
    sqlx::query_as::<_, AccountPeriod>(&format!(
        r#"
        UPDATE club_account_periods SET
            status     = CASE WHEN $3 THEN 'open' ELSE 'closed' END,
            closed_at  = CASE WHEN $3 THEN NULL ELSE NOW() END,
            closed_by  = CASE WHEN $3 THEN NULL ELSE $4 END,
            updated_at = NOW()
        WHERE club_id = $1 AND id = $2
        RETURNING {PERIOD_COLS}
        "#
    ))
    .bind(club_id)
    .bind(id)
    .bind(open)
    .bind(by)
    .fetch_optional(conn)
    .await
}

// MARK: money accounts

const MONEY_COLS: &str = "id, club_id, name, kind, sort_order, archived";

pub async fn list_money_accounts(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<MoneyAccount>, sqlx::Error> {
    sqlx::query_as::<_, MoneyAccount>(&format!(
        "SELECT {MONEY_COLS} FROM club_money_accounts WHERE club_id = $1 ORDER BY sort_order, name"
    ))
    .bind(club_id)
    .fetch_all(pool)
    .await
}

pub async fn get_money_account(
    pool: &PgPool,
    club_id: Uuid,
    id: Uuid,
) -> Result<Option<MoneyAccount>, sqlx::Error> {
    sqlx::query_as::<_, MoneyAccount>(&format!(
        "SELECT {MONEY_COLS} FROM club_money_accounts WHERE club_id = $1 AND id = $2"
    ))
    .bind(club_id)
    .bind(id)
    .fetch_optional(pool)
    .await
}

pub async fn create_money_account(
    conn: &mut PgConnection,
    club_id: Uuid,
    name: &str,
    kind: &str,
) -> Result<MoneyAccount, sqlx::Error> {
    sqlx::query_as::<_, MoneyAccount>(&format!(
        r#"
        INSERT INTO club_money_accounts (club_id, name, kind, sort_order)
        VALUES ($1, $2, $3, (SELECT COALESCE(MAX(sort_order), 0) + 10
                             FROM club_money_accounts WHERE club_id = $1))
        RETURNING {MONEY_COLS}
        "#
    ))
    .bind(club_id)
    .bind(name.trim())
    .bind(kind)
    .fetch_one(conn)
    .await
}

pub async fn update_money_account(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
    name: Option<&str>,
    archived: Option<bool>,
) -> Result<Option<MoneyAccount>, sqlx::Error> {
    sqlx::query_as::<_, MoneyAccount>(&format!(
        r#"
        UPDATE club_money_accounts SET name = COALESCE($3, name), archived = COALESCE($4, archived)
        WHERE club_id = $1 AND id = $2
        RETURNING {MONEY_COLS}
        "#
    ))
    .bind(club_id)
    .bind(id)
    .bind(name.map(str::trim))
    .bind(archived)
    .fetch_optional(conn)
    .await
}

/// Set an account's opening figure and/or statement figure for a year.
/// `reconciled`: `None` leaves it, `Some(None)` clears it.
pub async fn set_account_balance(
    conn: &mut PgConnection,
    account_id: Uuid,
    period_id: Uuid,
    opening_cents: Option<i64>,
    reconciled: Option<Option<i64>>,
    reconciled_on: Option<NaiveDate>,
) -> Result<(), sqlx::Error> {
    let (set_reconciled, reconciled_cents) = match reconciled {
        None => (false, None),
        Some(v) => (true, v),
    };
    sqlx::query(
        r#"
        INSERT INTO club_money_account_balances
            (account_id, period_id, opening_cents, reconciled_cents, reconciled_on)
        VALUES ($1, $2, COALESCE($3, 0), $5, CASE WHEN $5 IS NULL THEN NULL ELSE $6 END)
        ON CONFLICT (account_id, period_id) DO UPDATE SET
            opening_cents    = COALESCE($3, club_money_account_balances.opening_cents),
            reconciled_cents = CASE WHEN $4 THEN $5 ELSE club_money_account_balances.reconciled_cents END,
            reconciled_on    = CASE WHEN $4 THEN (CASE WHEN $5 IS NULL THEN NULL ELSE $6 END)
                                    ELSE club_money_account_balances.reconciled_on END
        "#,
    )
    .bind(account_id)
    .bind(period_id)
    .bind(opening_cents)
    .bind(set_reconciled)
    .bind(reconciled_cents)
    .bind(reconciled_on)
    .execute(conn)
    .await?;
    Ok(())
}

/// Every money account's year: opening, what the books say it ends on, and
/// the statement figure if there is one.
pub async fn money_positions(
    pool: &PgPool,
    club_id: Uuid,
    period_id: Uuid,
) -> Result<Vec<MoneyAccountPosition>, sqlx::Error> {
    sqlx::query_as::<_, MoneyAccountPosition>(
        r#"
        SELECT a.id, a.name, a.kind,
               COALESCE(b.opening_cents, 0)::BIGINT AS opening_cents,
               (COALESCE(b.opening_cents, 0)
                + COALESCE((
                    SELECT SUM(CASE t.kind WHEN 'expenditure' THEN -t.amount_cents
                                           ELSE t.amount_cents END)
                    FROM club_account_transactions t
                    WHERE t.money_account_id = a.id AND t.period_id = $2 AND t.voided_at IS NULL
                  ), 0)
                + COALESCE((
                    SELECT SUM(CASE d.direction WHEN 'debtor' THEN s.amount_cents
                                                ELSE -s.amount_cents END)
                    FROM club_account_settlements s
                    JOIN club_account_debts d ON d.id = s.debt_id
                    WHERE s.money_account_id = a.id AND s.period_id = $2 AND s.kind = 'payment'
                      AND s.voided_at IS NULL AND d.voided_at IS NULL
                  ), 0))::BIGINT AS computed_closing_cents,
               b.reconciled_cents, b.reconciled_on
        FROM club_money_accounts a
        LEFT JOIN club_money_account_balances b ON b.account_id = a.id AND b.period_id = $2
        WHERE a.club_id = $1 AND (NOT a.archived OR b.account_id IS NOT NULL)
        ORDER BY a.sort_order, a.name
        "#,
    )
    .bind(club_id)
    .bind(period_id)
    .fetch_all(pool)
    .await
}

// MARK: transactions

const TX_SELECT: &str = r#"
    SELECT t.id, t.club_id, t.period_id, t.occurred_on, t.kind, t.category_id,
           c.name AS category_name, t.money_account_id, a.name AS money_account_name,
           t.amount_cents, t.description, t.counterparty, t.member_id, u.name AS member_name,
           t.event_id, t.note, t.receipt_url, t.extraordinary, t.authorised_on,
           t.authorisation_ref, t.source, t.voided_at, t.void_reason,
           cb.name AS created_by_name, t.created_at
    FROM club_account_transactions t
    LEFT JOIN club_account_categories c ON c.id = t.category_id
    LEFT JOIN club_money_accounts a ON a.id = t.money_account_id
    LEFT JOIN users u ON u.id = t.member_id
    LEFT JOIN users cb ON cb.id = t.created_by
"#;

#[derive(Debug, Default, Clone, serde::Deserialize)]
pub struct TransactionFilter {
    pub kind: Option<String>,
    pub category_id: Option<Uuid>,
    pub money_account_id: Option<Uuid>,
    pub q: Option<String>,
    #[serde(default)]
    pub include_voided: bool,
}

pub async fn list_transactions(
    pool: &PgPool,
    club_id: Uuid,
    period_id: Uuid,
    f: &TransactionFilter,
) -> Result<Vec<AccountTransaction>, sqlx::Error> {
    sqlx::query_as::<_, AccountTransaction>(&format!(
        r#"{TX_SELECT}
        WHERE t.club_id = $1 AND t.period_id = $2
          AND ($3::TEXT IS NULL OR t.kind = $3)
          AND ($4::UUID IS NULL OR t.category_id = $4)
          AND ($5::UUID IS NULL OR t.money_account_id = $5)
          AND ($6::TEXT IS NULL OR t.description ILIKE '%' || $6 || '%'
               OR t.counterparty ILIKE '%' || $6 || '%' OR u.name ILIKE '%' || $6 || '%')
          AND ($7 OR t.voided_at IS NULL)
        ORDER BY t.occurred_on DESC, t.created_at DESC
        "#
    ))
    .bind(club_id)
    .bind(period_id)
    .bind(f.kind.as_deref())
    .bind(f.category_id)
    .bind(f.money_account_id)
    .bind(f.q.as_deref().map(str::trim).filter(|s| !s.is_empty()))
    .bind(f.include_voided)
    .fetch_all(pool)
    .await
}

pub async fn get_transaction(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
) -> Result<Option<AccountTransaction>, sqlx::Error> {
    sqlx::query_as::<_, AccountTransaction>(&format!(
        "{TX_SELECT} WHERE t.club_id = $1 AND t.id = $2"
    ))
    .bind(club_id)
    .bind(id)
    .fetch_optional(conn)
    .await
}

/// Write a line. `source` marks lines the app wrote itself.
#[allow(clippy::too_many_arguments)]
pub async fn insert_transaction(
    conn: &mut PgConnection,
    club_id: Uuid,
    period_id: Uuid,
    req: &CreateTransactionRequest,
    source: Option<(&str, Uuid)>,
    created_by: Uuid,
) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO club_account_transactions
            (club_id, period_id, occurred_on, kind, category_id, money_account_id, amount_cents,
             description, counterparty, member_id, event_id, note, receipt_url, extraordinary,
             authorised_on, authorisation_ref, source, source_ref, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULLIF(TRIM($9), ''), $10, $11,
                NULLIF(TRIM($12), ''), NULLIF(TRIM($13), ''), $14, $15,
                NULLIF(TRIM($16), ''), $17, $18, $19)
        RETURNING id
        "#,
    )
    .bind(club_id)
    .bind(period_id)
    .bind(req.occurred_on)
    .bind(req.kind.as_str())
    .bind(req.category_id)
    .bind(req.money_account_id)
    .bind(req.amount_cents)
    .bind(req.description.trim())
    .bind(req.counterparty.as_deref())
    .bind(req.member_id)
    .bind(req.event_id)
    .bind(req.note.as_deref())
    .bind(req.receipt_url.as_deref())
    .bind(req.extraordinary)
    .bind(req.authorised_on)
    .bind(req.authorisation_ref.as_deref())
    .bind(source.map(|s| s.0))
    .bind(source.map(|s| s.1))
    .bind(created_by)
    .fetch_one(conn)
    .await
}

pub async fn update_transaction(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
    req: &UpdateTransactionRequest,
) -> Result<bool, sqlx::Error> {
    fn split<T: Clone>(v: &Option<Option<T>>) -> (bool, Option<T>) {
        match v {
            None => (false, None),
            Some(x) => (true, x.clone()),
        }
    }
    let (set_acct, acct) = split(&req.money_account_id);
    let (set_cp, cp) = split(&req.counterparty);
    let (set_note, note) = split(&req.note);
    let (set_receipt, receipt) = split(&req.receipt_url);
    let (set_auth_on, auth_on) = split(&req.authorised_on);
    let (set_auth_ref, auth_ref) = split(&req.authorisation_ref);
    let done = sqlx::query(
        r#"
        UPDATE club_account_transactions SET
            occurred_on       = COALESCE($3, occurred_on),
            category_id       = COALESCE($4, category_id),
            money_account_id  = CASE WHEN $5 THEN $6 ELSE money_account_id END,
            amount_cents      = COALESCE($7, amount_cents),
            description       = COALESCE(NULLIF(TRIM($8), ''), description),
            counterparty      = CASE WHEN $9 THEN NULLIF(TRIM($10), '') ELSE counterparty END,
            note              = CASE WHEN $11 THEN NULLIF(TRIM($12), '') ELSE note END,
            receipt_url       = CASE WHEN $13 THEN NULLIF(TRIM($14), '') ELSE receipt_url END,
            extraordinary     = COALESCE($15, extraordinary),
            authorised_on     = CASE WHEN $16 THEN $17 ELSE authorised_on END,
            authorisation_ref = CASE WHEN $18 THEN NULLIF(TRIM($19), '') ELSE authorisation_ref END,
            updated_at        = NOW()
        WHERE club_id = $1 AND id = $2 AND voided_at IS NULL
        "#,
    )
    .bind(club_id)
    .bind(id)
    .bind(req.occurred_on)
    .bind(req.category_id)
    .bind(set_acct)
    .bind(acct)
    .bind(req.amount_cents)
    .bind(req.description.as_deref())
    .bind(set_cp)
    .bind(cp)
    .bind(set_note)
    .bind(note)
    .bind(set_receipt)
    .bind(receipt)
    .bind(req.extraordinary)
    .bind(set_auth_on)
    .bind(auth_on)
    .bind(set_auth_ref)
    .bind(auth_ref)
    .execute(conn)
    .await?;
    Ok(done.rows_affected() > 0)
}

pub async fn void_transaction(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
    by: Uuid,
    reason: &str,
) -> Result<bool, sqlx::Error> {
    let done = sqlx::query(
        r#"
        UPDATE club_account_transactions
        SET voided_at = NOW(), voided_by = $3, void_reason = $4, updated_at = NOW()
        WHERE club_id = $1 AND id = $2 AND voided_at IS NULL
        "#,
    )
    .bind(club_id)
    .bind(id)
    .bind(by)
    .bind(reason.trim())
    .execute(conn)
    .await?;
    Ok(done.rows_affected() > 0)
}

// MARK: totals for the report

pub async fn category_totals(
    pool: &PgPool,
    period_id: Uuid,
) -> Result<Vec<(Uuid, i64)>, sqlx::Error> {
    sqlx::query_as::<_, (Uuid, i64)>(
        r#"
        SELECT category_id, SUM(amount_cents)::BIGINT
        FROM club_account_transactions
        WHERE period_id = $1 AND voided_at IS NULL AND kind IN ('income', 'expenditure')
        GROUP BY category_id
        "#,
    )
    .bind(period_id)
    .fetch_all(pool)
    .await
}

/// `(adjustments, extraordinary expenditure, extraordinary income)`.
pub async fn period_extras(
    pool: &PgPool,
    period_id: Uuid,
) -> Result<(i64, i64, i64), sqlx::Error> {
    sqlx::query_as::<_, (i64, i64, i64)>(
        r#"
        SELECT
          COALESCE(SUM(amount_cents) FILTER (WHERE kind = 'adjustment'), 0)::BIGINT,
          COALESCE(SUM(amount_cents) FILTER (WHERE kind = 'expenditure' AND extraordinary), 0)::BIGINT,
          COALESCE(SUM(amount_cents) FILTER (WHERE kind = 'income' AND extraordinary), 0)::BIGINT
        FROM club_account_transactions
        WHERE period_id = $1 AND voided_at IS NULL
        "#,
    )
    .bind(period_id)
    .fetch_one(pool)
    .await
}

/// Fixtures with a fee that were played in the year — what "fees per match"
/// divides by.
pub async fn matches_played(
    pool: &PgPool,
    club_id: Uuid,
    starts_on: NaiveDate,
    ends_on: NaiveDate,
) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM events
        WHERE club_id = $1 AND status <> 'cancelled'
          AND COALESCE(fee_amount_cents, 0) > 0
          AND event_subtype NOT IN ('nets', 'training', 'social')
          AND start_at::DATE BETWEEN $2 AND $3 AND start_at < NOW()
        "#,
    )
    .bind(club_id)
    .bind(starts_on)
    .bind(ends_on)
    .fetch_one(pool)
    .await
}

// MARK: debts

/// Every debt raised on or before `as_of`, and where it stood on that day.
pub async fn debt_positions(
    pool: &PgPool,
    club_id: Uuid,
    as_of: NaiveDate,
) -> Result<Vec<DebtPosition>, sqlx::Error> {
    sqlx::query_as::<_, DebtPosition>(
        r#"
        SELECT d.id, d.period_id, p.label AS period_label, d.direction, d.kind, d.description,
               d.counterparty, d.member_id, u.name AS member_name, d.event_id, d.raised_on,
               d.amount_cents,
               (d.amount_cents
                 - COALESCE(SUM(s.amount_cents) FILTER (WHERE s.settled_on <= $2), 0))::BIGINT
                 AS outstanding_at_close_cents,
               COALESCE(SUM(s.amount_cents)
                 FILTER (WHERE s.settled_on > $2 AND s.kind = 'payment'), 0)::BIGINT
                 AS paid_since_close_cents,
               (d.amount_cents - COALESCE(SUM(s.amount_cents), 0))::BIGINT AS outstanding_now_cents,
               d.note
        FROM club_account_debts d
        JOIN club_account_periods p ON p.id = d.period_id
        LEFT JOIN users u ON u.id = d.member_id
        LEFT JOIN club_account_settlements s ON s.debt_id = d.id AND s.voided_at IS NULL
        WHERE d.club_id = $1 AND d.voided_at IS NULL AND d.raised_on <= $2
        GROUP BY d.id, p.label, u.name
        ORDER BY d.direction, d.raised_on, d.description
        "#,
    )
    .bind(club_id)
    .bind(as_of)
    .fetch_all(pool)
    .await
}

/// One debt as it stands today.
pub async fn debt_now(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
) -> Result<Option<DebtPosition>, sqlx::Error> {
    sqlx::query_as::<_, DebtPosition>(
        r#"
        SELECT d.id, d.period_id, p.label AS period_label, d.direction, d.kind, d.description,
               d.counterparty, d.member_id, u.name AS member_name, d.event_id, d.raised_on,
               d.amount_cents,
               (d.amount_cents - COALESCE(SUM(s.amount_cents), 0))::BIGINT AS outstanding_at_close_cents,
               0::BIGINT AS paid_since_close_cents,
               (d.amount_cents - COALESCE(SUM(s.amount_cents), 0))::BIGINT AS outstanding_now_cents,
               d.note
        FROM club_account_debts d
        JOIN club_account_periods p ON p.id = d.period_id
        LEFT JOIN users u ON u.id = d.member_id
        LEFT JOIN club_account_settlements s ON s.debt_id = d.id AND s.voided_at IS NULL
        WHERE d.club_id = $1 AND d.id = $2 AND d.voided_at IS NULL
        GROUP BY d.id, p.label, u.name
        "#,
    )
    .bind(club_id)
    .bind(id)
    .fetch_optional(conn)
    .await
}

pub async fn insert_debt(
    conn: &mut PgConnection,
    club_id: Uuid,
    period_id: Uuid,
    req: &CreateDebtRequest,
    transaction_id: Option<Uuid>,
    created_by: Uuid,
) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO club_account_debts
            (club_id, period_id, direction, kind, description, counterparty, member_id, event_id,
             amount_cents, raised_on, note, transaction_id, created_by)
        VALUES ($1, $2, $3, $4, $5, NULLIF(TRIM($6), ''), $7, $8, $9, $10,
                NULLIF(TRIM($11), ''), $12, $13)
        RETURNING id
        "#,
    )
    .bind(club_id)
    .bind(period_id)
    .bind(&req.direction)
    .bind(&req.kind)
    .bind(req.description.trim())
    .bind(req.counterparty.as_deref())
    .bind(req.member_id)
    .bind(req.event_id)
    .bind(req.amount_cents)
    .bind(req.raised_on)
    .bind(req.note.as_deref())
    .bind(transaction_id)
    .bind(created_by)
    .fetch_one(conn)
    .await
}

/// Void a debt and the accrual line that raised it. Refused when anything
/// has been paid against it — void the settlement first.
pub async fn void_debt(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
    by: Uuid,
    reason: &str,
) -> Result<bool, sqlx::Error> {
    let tx_id: Option<Option<Uuid>> = sqlx::query_scalar(
        r#"
        UPDATE club_account_debts SET voided_at = NOW()
        WHERE club_id = $1 AND id = $2 AND voided_at IS NULL
          AND NOT EXISTS (SELECT 1 FROM club_account_settlements s
                          WHERE s.debt_id = $2 AND s.voided_at IS NULL)
        RETURNING transaction_id
        "#,
    )
    .bind(club_id)
    .bind(id)
    .fetch_optional(&mut *conn)
    .await?;
    let Some(tx_id) = tx_id else { return Ok(false) };
    if let Some(tx_id) = tx_id {
        void_transaction(conn, club_id, tx_id, by, reason).await?;
    }
    Ok(true)
}

#[allow(clippy::too_many_arguments)]
pub async fn insert_settlement(
    conn: &mut PgConnection,
    debt_id: Uuid,
    period_id: Uuid,
    settled_on: NaiveDate,
    kind: &str,
    amount_cents: i64,
    money_account_id: Option<Uuid>,
    payment_id: Option<Uuid>,
    note: Option<&str>,
    transaction_id: Option<Uuid>,
    created_by: Uuid,
) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO club_account_settlements
            (debt_id, period_id, settled_on, kind, amount_cents, money_account_id, payment_id,
             note, transaction_id, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7, NULLIF(TRIM($8), ''), $9, $10)
        RETURNING id
        "#,
    )
    .bind(debt_id)
    .bind(period_id)
    .bind(settled_on)
    .bind(kind)
    .bind(amount_cents)
    .bind(money_account_id)
    .bind(payment_id)
    .bind(note)
    .bind(transaction_id)
    .bind(created_by)
    .fetch_one(conn)
    .await
}

pub async fn list_settlements(
    pool: &PgPool,
    debt_id: Uuid,
) -> Result<Vec<DebtSettlement>, sqlx::Error> {
    sqlx::query_as::<_, DebtSettlement>(
        r#"
        SELECT id, debt_id, settled_on, kind, amount_cents, money_account_id, note, voided_at
        FROM club_account_settlements WHERE debt_id = $1 ORDER BY settled_on, created_at
        "#,
    )
    .bind(debt_id)
    .fetch_all(pool)
    .await
}

/// Void a settlement and any write-off line it posted. Only in an open year.
pub async fn void_settlement(
    conn: &mut PgConnection,
    club_id: Uuid,
    id: Uuid,
    by: Uuid,
    reason: &str,
) -> Result<bool, sqlx::Error> {
    let row: Option<Option<Uuid>> = sqlx::query_scalar(
        r#"
        UPDATE club_account_settlements s SET voided_at = NOW()
        FROM club_account_debts d, club_account_periods p
        WHERE s.id = $2 AND d.id = s.debt_id AND d.club_id = $1 AND p.id = s.period_id
          AND p.status = 'open' AND s.voided_at IS NULL
        RETURNING s.transaction_id
        "#,
    )
    .bind(club_id)
    .bind(id)
    .fetch_optional(&mut *conn)
    .await?;
    let Some(tx_id) = row else { return Ok(false) };
    if let Some(tx_id) = tx_id {
        void_transaction(conn, club_id, tx_id, by, reason).await?;
    }
    Ok(true)
}

/// Which year a settlement belongs to.
pub async fn settlement_period(
    pool: &PgPool,
    club_id: Uuid,
    id: Uuid,
) -> Result<Option<(Uuid, String)>, sqlx::Error> {
    sqlx::query_as::<_, (Uuid, String)>(
        r#"
        SELECT p.id, p.status FROM club_account_settlements s
        JOIN club_account_debts d ON d.id = s.debt_id
        JOIN club_account_periods p ON p.id = s.period_id
        WHERE s.id = $2 AND d.club_id = $1
        "#,
    )
    .bind(club_id)
    .bind(id)
    .fetch_optional(pool)
    .await
}

// MARK: what the app already knows

/// Fees paid in the app for this club's fixtures that the books have not yet
/// taken in, up to `until`.
pub async fn payment_suggestions(
    pool: &PgPool,
    club_id: Uuid,
    from: NaiveDate,
    until: NaiveDate,
) -> Result<Vec<PaymentSuggestion>, sqlx::Error> {
    sqlx::query_as::<_, PaymentSuggestion>(
        r#"
        SELECT p.id AS payment_id, p.updated_at::DATE AS paid_on, p.amount_cents::BIGINT AS amount_cents,
               p.currency, p.user_id AS member_id, u.name AS member_name, e.id AS event_id,
               e.title AS event_title, e.event_subtype::TEXT AS event_subtype,
               (SELECT d.id FROM club_account_debts d
                 WHERE d.club_id = e.club_id AND d.member_id = p.user_id AND d.event_id = e.id
                   AND d.direction = 'debtor' AND d.voided_at IS NULL
                 LIMIT 1) AS settles_debt_id
        FROM payments p
        JOIN events e ON e.id = p.event_id
        JOIN users u ON u.id = p.user_id
        WHERE e.club_id = $1 AND p.status = 'succeeded' AND p.order_id IS NULL
          AND p.amount_cents > 0
          AND p.updated_at::DATE BETWEEN $2 AND $3
          AND NOT EXISTS (SELECT 1 FROM club_account_transactions t
                          WHERE t.club_id = e.club_id AND t.source = 'payment'
                            AND t.source_ref = p.id AND t.voided_at IS NULL)
          AND NOT EXISTS (SELECT 1 FROM club_account_settlements s
                          WHERE s.payment_id = p.id AND s.voided_at IS NULL)
        ORDER BY p.updated_at DESC
        "#,
    )
    .bind(club_id)
    .bind(from)
    .bind(until)
    .fetch_all(pool)
    .await
}

pub async fn payment_suggestion(
    conn: &mut PgConnection,
    club_id: Uuid,
    payment_id: Uuid,
) -> Result<Option<PaymentSuggestion>, sqlx::Error> {
    sqlx::query_as::<_, PaymentSuggestion>(
        r#"
        SELECT p.id AS payment_id, p.updated_at::DATE AS paid_on, p.amount_cents::BIGINT AS amount_cents,
               p.currency, p.user_id AS member_id, u.name AS member_name, e.id AS event_id,
               e.title AS event_title, e.event_subtype::TEXT AS event_subtype,
               (SELECT d.id FROM club_account_debts d
                 WHERE d.club_id = e.club_id AND d.member_id = p.user_id AND d.event_id = e.id
                   AND d.direction = 'debtor' AND d.voided_at IS NULL
                 LIMIT 1) AS settles_debt_id
        FROM payments p
        JOIN events e ON e.id = p.event_id
        JOIN users u ON u.id = p.user_id
        WHERE e.club_id = $1 AND p.id = $2 AND p.status = 'succeeded' AND p.order_id IS NULL
          AND p.amount_cents > 0
        "#,
    )
    .bind(club_id)
    .bind(payment_id)
    .fetch_optional(conn)
    .await
}

/// Match fees still unpaid for fixtures played in the year.
pub async fn unpaid_fees(
    pool: &PgPool,
    club_id: Uuid,
    starts_on: NaiveDate,
    ends_on: NaiveDate,
) -> Result<Vec<UnpaidFee>, sqlx::Error> {
    sqlx::query_as::<_, UnpaidFee>(
        r#"
        SELECT f.event_id, f.title AS event_title, f.start_at::DATE AS played_on,
               f.user_id AS member_id, f.name AS member_name,
               f.fee_amount_cents::BIGINT AS amount_cents,
               EXISTS (SELECT 1 FROM club_account_debts d
                       WHERE d.club_id = f.club_id AND d.member_id = f.user_id
                         AND d.event_id = f.event_id AND d.voided_at IS NULL) AS already_raised
        FROM outstanding_match_fees f
        WHERE f.club_id = $1 AND f.start_at::DATE BETWEEN $2 AND $3 AND f.start_at < NOW()
        ORDER BY f.start_at, f.name
        "#,
    )
    .bind(club_id)
    .bind(starts_on)
    .bind(ends_on)
    .fetch_all(pool)
    .await
}

// MARK: stock

pub async fn list_stock_items(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<(Uuid, String, bool)>, sqlx::Error> {
    sqlx::query_as::<_, (Uuid, String, bool)>(
        "SELECT id, name, archived FROM club_stock_items WHERE club_id = $1 ORDER BY name",
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

pub async fn create_stock_item(
    conn: &mut PgConnection,
    club_id: Uuid,
    name: &str,
) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO club_stock_items (club_id, name) VALUES ($1, $2) RETURNING id",
    )
    .bind(club_id)
    .bind(name.trim())
    .fetch_one(conn)
    .await
}

pub async fn stock_item_belongs(
    pool: &PgPool,
    club_id: Uuid,
    item_id: Uuid,
) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM club_stock_items WHERE club_id = $1 AND id = $2)",
    )
    .bind(club_id)
    .bind(item_id)
    .fetch_one(pool)
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn set_stock_count(
    conn: &mut PgConnection,
    item_id: Uuid,
    period_id: Uuid,
    opening_quantity: Option<i32>,
    opening_cents: Option<i64>,
    closing_quantity: Option<i32>,
    closing_cents: Option<i64>,
    counted_on: Option<NaiveDate>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO club_stock_counts
            (item_id, period_id, opening_quantity, opening_cents, closing_quantity, closing_cents,
             counted_on)
        VALUES ($1, $2, COALESCE($3, 0), COALESCE($4, 0), COALESCE($5, 0), COALESCE($6, 0), $7)
        ON CONFLICT (item_id, period_id) DO UPDATE SET
            opening_quantity = COALESCE($3, club_stock_counts.opening_quantity),
            opening_cents    = COALESCE($4, club_stock_counts.opening_cents),
            closing_quantity = COALESCE($5, club_stock_counts.closing_quantity),
            closing_cents    = COALESCE($6, club_stock_counts.closing_cents),
            counted_on       = COALESCE($7, club_stock_counts.counted_on)
        "#,
    )
    .bind(item_id)
    .bind(period_id)
    .bind(opening_quantity)
    .bind(opening_cents)
    .bind(closing_quantity)
    .bind(closing_cents)
    .bind(counted_on)
    .execute(conn)
    .await?;
    Ok(())
}

pub async fn stock_positions(
    pool: &PgPool,
    club_id: Uuid,
    period_id: Uuid,
) -> Result<Vec<StockPosition>, sqlx::Error> {
    sqlx::query_as::<_, StockPosition>(
        r#"
        SELECT i.id AS item_id, i.name,
               COALESCE(c.opening_quantity, 0) AS opening_quantity,
               COALESCE(c.opening_cents, 0)::BIGINT AS opening_cents,
               COALESCE(c.closing_quantity, 0) AS closing_quantity,
               COALESCE(c.closing_cents, 0)::BIGINT AS closing_cents,
               c.counted_on
        FROM club_stock_items i
        LEFT JOIN club_stock_counts c ON c.item_id = i.id AND c.period_id = $2
        WHERE i.club_id = $1 AND (NOT i.archived OR c.item_id IS NOT NULL)
        ORDER BY i.name
        "#,
    )
    .bind(club_id)
    .bind(period_id)
    .fetch_all(pool)
    .await
}
