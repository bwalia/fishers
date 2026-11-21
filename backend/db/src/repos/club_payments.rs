//! Paying the club by bank transfer: bank details, costs, bills, shares,
//! payments, references and their audit trail.
//!
//! The rules live in `fishers_domain::money`; this is the storage. Sending a
//! bill is here too ([`issue_bill`]) so the API and the scheduler share one
//! path: the same split, the same checks, the same rows.

use chrono::{DateTime, NaiveDate, Utc};
use fishers_domain::money::{self, CostMode, LedgerKind, LedgerPayment, LedgerShare, Rounding, SplitError};
use serde::Serialize;
use serde_json::Value;
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

// MARK: who may handle a club's money

/// What somebody is to a club, as far as its money goes.
#[derive(Debug, Clone, Copy, Default, Serialize, sqlx::FromRow)]
pub struct MoneyRole {
    pub is_owner: bool,
    pub is_treasurer: bool,
    pub is_secretary: bool,
    pub is_member: bool,
}

impl MoneyRole {
    /// Owner, treasurer or secretary: may add bank details, confirm payments,
    /// waive shares and send bills.
    pub fn is_admin(self) -> bool {
        self.is_owner || self.is_treasurer || self.is_secretary
    }
}

/// `None` when there is no such club.
pub async fn money_role(pool: &PgPool, club_id: Uuid, user_id: Uuid) -> Result<Option<MoneyRole>, sqlx::Error> {
    sqlx::query_as::<_, MoneyRole>(
        r#"
        SELECT c.owner_id = $2 AS is_owner,
               COALESCE(m.status = 'active' AND m.is_treasurer, false) AS is_treasurer,
               COALESCE(m.status = 'active' AND m.role IN ('club_admin', 'super_admin'), false) AS is_secretary,
               COALESCE(m.status = 'active', false) AS is_member
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

/// Everyone who looks after the club's money: `(user_id, is_treasurer)`.
pub async fn money_admins(pool: &PgPool, club_id: Uuid) -> Result<Vec<(Uuid, bool)>, sqlx::Error> {
    let rows: Vec<(Uuid, bool)> = sqlx::query_as(
        r#"
        SELECT owner_id, false FROM clubs WHERE id = $1
        UNION ALL
        SELECT user_id, is_treasurer FROM club_members
        WHERE club_id = $1 AND status = 'active'
          AND (is_treasurer OR role IN ('club_admin', 'super_admin'))
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await?;
    let mut out: Vec<(Uuid, bool)> = Vec::new();
    for (id, treasurer) in rows {
        match out.iter_mut().find(|(seen, _)| *seen == id) {
            Some(entry) => entry.1 |= treasurer,
            None => out.push((id, treasurer)),
        }
    }
    Ok(out)
}

/// Who should hear about a payment to check: the treasurers if the club has
/// any, otherwise the owner and secretaries.
pub fn payment_checkers(admins: &[(Uuid, bool)]) -> Vec<Uuid> {
    let treasurers: Vec<Uuid> = admins.iter().filter(|(_, t)| *t).map(|(id, _)| *id).collect();
    if treasurers.is_empty() {
        admins.iter().map(|(id, _)| *id).collect()
    } else {
        treasurers
    }
}

pub async fn club_name(pool: &PgPool, club_id: Uuid) -> Result<Option<String>, sqlx::Error> {
    sqlx::query_scalar("SELECT name FROM clubs WHERE id = $1").bind(club_id).fetch_optional(pool).await
}

pub async fn user_name(pool: &PgPool, user_id: Uuid) -> Result<Option<String>, sqlx::Error> {
    sqlx::query_scalar("SELECT name FROM users WHERE id = $1").bind(user_id).fetch_optional(pool).await
}

/// "Josh" from "Josh Patel".
pub fn first_name_of(name: &str) -> &str {
    name.split_whitespace().next().unwrap_or(name)
}

/// The currency a club works in: its open accounting year's, else the one
/// its sessions were last priced in, else pounds.
pub async fn club_currency(pool: &PgPool, club_id: Uuid) -> Result<String, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT COALESCE(
             (SELECT currency FROM club_account_periods WHERE club_id = $1 AND status = 'open' ORDER BY starts_on DESC LIMIT 1),
             (SELECT currency FROM event_costs WHERE club_id = $1 ORDER BY updated_at DESC LIMIT 1),
             'GBP')",
    )
    .bind(club_id)
    .fetch_one(pool)
    .await
}

/// Take the club row's lock, so two changes to its bank details can't
/// interleave (two "replace" requests landing together).
pub async fn lock_club(conn: &mut PgConnection, club_id: Uuid) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query("SELECT 1 FROM clubs WHERE id = $1 FOR UPDATE")
        .bind(club_id)
        .fetch_optional(conn)
        .await?
        .is_some())
}

// MARK: settings

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct PaymentSettings {
    pub payments_enabled_at: Option<DateTime<Utc>>,
    pub auto_bill: bool,
    pub auto_bill_after_hours: i32,
    pub round_shares_up: bool,
    pub fee_chase_after_hours: i32,
    pub fee_chase_max_reminders: i32,
    /// The club's usual nets price, offered on every new nets session.
    pub default_nets_mode: Option<String>,
    pub default_nets_cents: Option<i64>,
    /// The usual match fee, offered on every new match.
    pub default_match_fee_cents: Option<i64>,
}

pub async fn settings(pool: &PgPool, club_id: Uuid) -> Result<Option<PaymentSettings>, sqlx::Error> {
    sqlx::query_as::<_, PaymentSettings>(
        "SELECT payments_enabled_at, auto_bill, auto_bill_after_hours, round_shares_up,
                fee_chase_after_hours, fee_chase_max_reminders,
                default_nets_mode, default_nets_cents, default_match_fee_cents
         FROM clubs WHERE id = $1",
    )
    .bind(club_id)
    .fetch_optional(pool)
    .await
}

/// What a settings change asks for. `None` leaves a field as it is; for the
/// usual prices, `Some(None)` clears one.
#[derive(Debug, Default)]
pub struct SettingsChange {
    pub auto_bill: Option<bool>,
    pub auto_bill_after_hours: Option<i32>,
    pub round_shares_up: Option<bool>,
    pub default_nets: Option<Option<(String, i64)>>,
    pub default_match_fee_cents: Option<Option<i64>>,
}

pub async fn set_settings(conn: &mut PgConnection, club_id: Uuid, c: &SettingsChange) -> Result<(), sqlx::Error> {
    let (nets_set, nets_mode, nets_cents) = match &c.default_nets {
        None => (false, None, None),
        Some(None) => (true, None, None),
        Some(Some((mode, cents))) => (true, Some(mode.clone()), Some(*cents)),
    };
    let (fee_set, fee) = match c.default_match_fee_cents {
        None => (false, None),
        Some(v) => (true, v),
    };
    sqlx::query(
        "UPDATE clubs SET auto_bill = COALESCE($2, auto_bill),
                          auto_bill_after_hours = COALESCE($3, auto_bill_after_hours),
                          round_shares_up = COALESCE($4, round_shares_up),
                          default_nets_mode = CASE WHEN $5 THEN $6 ELSE default_nets_mode END,
                          default_nets_cents = CASE WHEN $5 THEN $7 ELSE default_nets_cents END,
                          default_match_fee_cents = CASE WHEN $8 THEN $9 ELSE default_match_fee_cents END
         WHERE id = $1",
    )
    .bind(club_id)
    .bind(c.auto_bill)
    .bind(c.auto_bill_after_hours)
    .bind(c.round_shares_up)
    .bind(nets_set)
    .bind(nets_mode)
    .bind(nets_cents)
    .bind(fee_set)
    .bind(fee)
    .execute(conn)
    .await?;
    Ok(())
}

/// From now on the club collects money in the app. Idempotent: the first time
/// is the one that counts, because nothing that ended before it is billed by
/// itself.
pub async fn enable_payments(conn: &mut PgConnection, club_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE clubs SET payments_enabled_at = COALESCE(payments_enabled_at, NOW()) WHERE id = $1")
        .bind(club_id)
        .execute(conn)
        .await?;
    Ok(())
}

// MARK: bank details

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct PayoutAccountRow {
    pub id: Uuid,
    pub club_id: Uuid,
    pub method: String,
    pub label: String,
    pub holder_name: String,
    pub is_personal: bool,
    pub sort_code: Option<String>,
    pub last4: String,
    pub details_ciphertext: Option<Vec<u8>>,
    pub key_id: String,
    pub fingerprint: String,
    pub live_from: DateTime<Utc>,
    pub replaces_id: Option<Uuid>,
    pub frozen_at: Option<DateTime<Utc>>,
    pub freeze_reason: Option<String>,
    pub retired_at: Option<DateTime<Utc>>,
    pub created_by: Option<Uuid>,
    pub created_by_name: Option<String>,
    pub created_at: DateTime<Utc>,
}

impl PayoutAccountRow {
    pub fn timeline(&self) -> money::PayoutTimeline {
        money::PayoutTimeline {
            id: self.id,
            created_at: self.created_at,
            live_from: self.live_from,
            frozen_at: self.frozen_at,
            retired_at: self.retired_at,
        }
    }
}

/// Every account the club has ever had, oldest first.
pub async fn payout_accounts(pool: &PgPool, club_id: Uuid) -> Result<Vec<PayoutAccountRow>, sqlx::Error> {
    payout_accounts_conn(&mut *pool.acquire().await?, club_id).await
}

pub async fn payout_accounts_conn(conn: &mut PgConnection, club_id: Uuid) -> Result<Vec<PayoutAccountRow>, sqlx::Error> {
    sqlx::query_as::<_, PayoutAccountRow>(
        r#"
        SELECT a.id, a.club_id, a.method, a.label, a.holder_name, a.is_personal, a.sort_code,
               a.last4, a.details_ciphertext, a.key_id, a.fingerprint, a.live_from,
               a.replaces_id, a.frozen_at, a.freeze_reason, a.retired_at, a.created_by,
               u.name AS created_by_name, a.created_at
        FROM club_payout_accounts a
        LEFT JOIN users u ON u.id = a.created_by
        WHERE a.club_id = $1
        ORDER BY a.created_at, a.id
        "#,
    )
    .bind(club_id)
    .fetch_all(conn)
    .await
}

pub struct NewPayoutAccount<'a> {
    pub club_id: Uuid,
    pub label: &'a str,
    pub holder_name: &'a str,
    pub is_personal: bool,
    pub sort_code: &'a str,
    pub last4: &'a str,
    pub ciphertext: &'a [u8],
    pub key_id: &'a str,
    pub fingerprint: &'a str,
    pub live_from: DateTime<Utc>,
    pub replaces_id: Option<Uuid>,
    pub created_by: Uuid,
}

pub async fn insert_payout_account(conn: &mut PgConnection, a: &NewPayoutAccount<'_>) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar(
        r#"
        INSERT INTO club_payout_accounts
            (club_id, label, holder_name, is_personal, sort_code, last4, details_ciphertext,
             key_id, fingerprint, live_from, replaces_id, created_by)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
        RETURNING id
        "#,
    )
    .bind(a.club_id)
    .bind(a.label)
    .bind(a.holder_name)
    .bind(a.is_personal)
    .bind(a.sort_code)
    .bind(a.last4)
    .bind(a.ciphertext)
    .bind(a.key_id)
    .bind(a.fingerprint)
    .bind(a.live_from)
    .bind(a.replaces_id)
    .bind(a.created_by)
    .fetch_one(conn)
    .await
}

pub async fn freeze_payout_account(
    conn: &mut PgConnection,
    id: Uuid,
    by: Uuid,
    reason: Option<&str>,
) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE club_payout_accounts SET frozen_at = NOW(), frozen_by = $2, freeze_reason = $3
         WHERE id = $1 AND frozen_at IS NULL AND retired_at IS NULL",
    )
    .bind(id)
    .bind(by)
    .bind(reason)
    .execute(conn)
    .await?
    .rows_affected()
        == 1)
}

/// Unfreezing never makes an account go live sooner than it would have.
pub async fn unfreeze_payout_account(conn: &mut PgConnection, id: Uuid) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE club_payout_accounts SET frozen_at = NULL, frozen_by = NULL, freeze_reason = NULL
         WHERE id = $1 AND frozen_at IS NOT NULL AND retired_at IS NULL",
    )
    .bind(id)
    .execute(conn)
    .await?
    .rows_affected()
        == 1)
}

/// Retired: the sealed number goes; the name and last four stay for history.
pub async fn retire_payout_account(conn: &mut PgConnection, id: Uuid, by: Option<Uuid>) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE club_payout_accounts SET retired_at = NOW(), retired_by = $2, details_ciphertext = NULL
         WHERE id = $1 AND retired_at IS NULL",
    )
    .bind(id)
    .bind(by)
    .execute(conn)
    .await?
    .rows_affected()
        == 1)
}

/// Clubs with more than one account still holding details — the only ones
/// where a replacement may have gone live and left an old one to retire.
pub async fn clubs_with_replaced_accounts(pool: &PgPool) -> Result<Vec<Uuid>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT club_id FROM club_payout_accounts WHERE retired_at IS NULL
         GROUP BY club_id HAVING COUNT(*) > 1 LIMIT 500",
    )
    .fetch_all(pool)
    .await
}

// MARK: audit

#[allow(clippy::too_many_arguments)]
pub async fn audit(
    conn: &mut PgConnection,
    club_id: Uuid,
    actor_id: Option<Uuid>,
    action: &str,
    entity: &str,
    entity_id: Option<Uuid>,
    before: Option<Value>,
    after: Option<Value>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO club_payment_audit (club_id, actor_id, action, entity, entity_id, before, after)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
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

/// How many times this person has been shown full bank details in the last
/// hour, anywhere. The pay screen is throttled on it.
pub async fn recent_reveals(pool: &PgPool, user_id: Uuid) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT COUNT(*) FROM club_payment_audit
         WHERE actor_id = $1 AND action = 'reveal' AND created_at > NOW() - INTERVAL '1 hour'",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
}

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct AuditRow {
    pub id: i64,
    pub actor_id: Option<Uuid>,
    pub actor_name: Option<String>,
    pub action: String,
    pub entity: String,
    pub entity_id: Option<Uuid>,
    pub after: Option<Value>,
    pub created_at: DateTime<Utc>,
}

/// The trail a club's admins can read. Reveals are left out: they are for
/// throttling and investigation, and would bury everything else.
pub async fn audit_log(pool: &PgPool, club_id: Uuid, limit: i64) -> Result<Vec<AuditRow>, sqlx::Error> {
    sqlx::query_as::<_, AuditRow>(
        "SELECT a.id, a.actor_id, u.name AS actor_name, a.action, a.entity, a.entity_id, a.after, a.created_at
         FROM club_payment_audit a LEFT JOIN users u ON u.id = a.actor_id
         WHERE a.club_id = $1 AND a.action <> 'reveal'
         ORDER BY a.created_at DESC, a.id DESC LIMIT $2",
    )
    .bind(club_id)
    .bind(limit.clamp(1, 200))
    .fetch_all(pool)
    .await
}

// MARK: costs

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct EventCostRow {
    pub event_id: Uuid,
    pub club_id: Uuid,
    pub mode: String,
    pub amount_cents: i64,
    pub currency: String,
    pub note: Option<String>,
    pub updated_at: DateTime<Utc>,
}

impl EventCostRow {
    pub fn mode(&self) -> CostMode {
        CostMode::parse(&self.mode).unwrap_or(CostMode::PerPlayer)
    }
}

pub async fn cost(pool: &PgPool, event_id: Uuid) -> Result<Option<EventCostRow>, sqlx::Error> {
    sqlx::query_as::<_, EventCostRow>(
        "SELECT event_id, club_id, mode, amount_cents, currency, note, updated_at FROM event_costs WHERE event_id = $1",
    )
    .bind(event_id)
    .fetch_optional(pool)
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn upsert_cost(
    conn: &mut PgConnection,
    event_id: Uuid,
    club_id: Uuid,
    mode: CostMode,
    amount_cents: i64,
    currency: &str,
    note: Option<&str>,
    by: Option<Uuid>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO event_costs (event_id, club_id, mode, amount_cents, currency, note, updated_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (event_id) DO UPDATE
          SET mode = EXCLUDED.mode, amount_cents = EXCLUDED.amount_cents,
              currency = EXCLUDED.currency, note = EXCLUDED.note,
              updated_by = EXCLUDED.updated_by, updated_at = NOW(),
              -- A changed cost deserves a fresh look by the scheduler.
              auto_bill_skipped_at = NULL
        "#,
    )
    .bind(event_id)
    .bind(club_id)
    .bind(mode.as_str())
    .bind(amount_cents)
    .bind(currency)
    .bind(note)
    .bind(by)
    .execute(&mut *conn)
    .await?;
    // The old field, for apps that only know it. A split total is not a
    // per-player fee and must never appear as one.
    let fee: Option<i32> = match mode {
        CostMode::PerPlayer => i32::try_from(amount_cents).ok(),
        CostMode::SplitTotal => None,
    };
    sqlx::query("UPDATE events SET fee_amount_cents = $2, fee_currency = $3, updated_at = NOW() WHERE id = $1")
        .bind(event_id)
        .bind(fee)
        .bind(currency)
        .execute(conn)
        .await?;
    Ok(())
}

pub async fn delete_cost(conn: &mut PgConnection, event_id: Uuid) -> Result<bool, sqlx::Error> {
    let gone = sqlx::query("DELETE FROM event_costs WHERE event_id = $1")
        .bind(event_id)
        .execute(&mut *conn)
        .await?
        .rows_affected()
        == 1;
    sqlx::query("UPDATE events SET fee_amount_cents = NULL, updated_at = NOW() WHERE id = $1")
        .bind(event_id)
        .execute(conn)
        .await?;
    Ok(gone)
}

/// The other weeks of a weekly series still to come and not yet billed.
pub async fn series_weeks_ahead(
    pool: &PgPool,
    club_id: Uuid,
    series_id: &str,
    from: DateTime<Utc>,
) -> Result<Vec<Uuid>, sqlx::Error> {
    sqlx::query_scalar(
        r#"
        SELECT e.id FROM events e
        WHERE e.club_id = $1 AND e.metadata->>'series_id' = $2 AND e.start_at >= $3
          AND e.status <> 'cancelled'
          AND NOT EXISTS (SELECT 1 FROM event_bills b WHERE b.event_id = e.id AND b.status = 'issued')
        ORDER BY e.start_at
        "#,
    )
    .bind(club_id)
    .bind(series_id)
    .bind(from)
    .fetch_all(pool)
    .await
}

// MARK: who came

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct Candidate {
    pub user_id: Uuid,
    pub name: String,
    /// Their own answer: going, maybe, not_going, invited.
    pub rsvp: String,
    /// What happened, when somebody has said (team sheets say it for matches).
    pub attended: Option<bool>,
}

/// The home club's active members, with their answer and whether they
/// turned up: those who were asked first, then everyone else (a member who
/// joined after it was scheduled can still have come). The opposition's
/// players are never billed. `rsvp` is `not_invited` for the latter.
pub async fn candidates(pool: &PgPool, event_id: Uuid) -> Result<Vec<Candidate>, sqlx::Error> {
    sqlx::query_as::<_, Candidate>(
        r#"
        SELECT m.user_id, u.name, COALESCE(i.status::text, 'not_invited') AS rsvp, i.attended
        FROM events e
        JOIN club_members m ON m.club_id = e.club_id AND m.status = 'active'
        JOIN users u ON u.id = m.user_id
        LEFT JOIN event_invites i ON i.event_id = e.id AND i.user_id = m.user_id
        WHERE e.id = $1
        ORDER BY (i.user_id IS NULL), lower(u.name), u.id
        "#,
    )
    .bind(event_id)
    .fetch_all(pool)
    .await
}

/// Of `user_ids`, the ones who are active members of the club, with names.
pub async fn active_members_named(
    conn: &mut PgConnection,
    club_id: Uuid,
    user_ids: &[Uuid],
) -> Result<Vec<(Uuid, String)>, sqlx::Error> {
    sqlx::query_as(
        "SELECT m.user_id, u.name FROM club_members m JOIN users u ON u.id = m.user_id
         WHERE m.club_id = $1 AND m.status = 'active' AND m.user_id = ANY($2)",
    )
    .bind(club_id)
    .bind(user_ids)
    .fetch_all(conn)
    .await
}

/// Record who came. Those ticked attended; those who said "going" and weren't
/// ticked didn't. Feeds the reliability score as team sheets already do.
pub async fn record_attendance(conn: &mut PgConnection, event_id: Uuid, came: &[Uuid]) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE event_invites SET attended = (user_id = ANY($2))
        WHERE event_id = $1 AND (user_id = ANY($2) OR status = 'going')
        "#,
    )
    .bind(event_id)
    .bind(came)
    .execute(conn)
    .await?;
    Ok(())
}

// MARK: bills and shares

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct BillRow {
    pub id: Uuid,
    /// The session, for a session's bill; none for a pass charge or a group fee.
    pub event_id: Option<Uuid>,
    pub club_id: Uuid,
    pub title: String,
    pub event_start_at: DateTime<Utc>,
    pub mode: String,
    pub amount_cents: i64,
    pub total_cents: i64,
    pub currency: String,
    pub rounding: String,
    pub payout_account_id: Option<Uuid>,
    pub status: String,
    pub version: i32,
    pub auto: bool,
    pub note: Option<String>,
    pub issued_by: Option<Uuid>,
    pub issued_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub voided_at: Option<DateTime<Utc>>,
    pub void_reason: Option<String>,
    /// `event`, `pass` or `collection`.
    pub kind: String,
    pub pass_holder_id: Option<Uuid>,
    pub period_start: Option<chrono::NaiveDate>,
    pub due_on: Option<chrono::NaiveDate>,
}

const BILL_COLS: &str = "id, event_id, club_id, title, event_start_at, mode, amount_cents, total_cents, currency, \
    rounding, payout_account_id, status, version, auto, note, issued_by, issued_at, updated_at, voided_at, void_reason, \
    kind, pass_holder_id, period_start, due_on";

pub async fn bill_by_id(pool: &PgPool, id: Uuid) -> Result<Option<BillRow>, sqlx::Error> {
    sqlx::query_as::<_, BillRow>(&format!("SELECT {BILL_COLS} FROM event_bills WHERE id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

pub async fn live_bill(pool: &PgPool, event_id: Uuid) -> Result<Option<BillRow>, sqlx::Error> {
    sqlx::query_as::<_, BillRow>(&format!(
        "SELECT {BILL_COLS} FROM event_bills WHERE event_id = $1 AND status = 'issued'"
    ))
    .bind(event_id)
    .fetch_optional(pool)
    .await
}

async fn live_bill_locked(conn: &mut PgConnection, event_id: Uuid) -> Result<Option<BillRow>, sqlx::Error> {
    sqlx::query_as::<_, BillRow>(&format!(
        "SELECT {BILL_COLS} FROM event_bills WHERE event_id = $1 AND status = 'issued' FOR UPDATE"
    ))
    .bind(event_id)
    .fetch_optional(conn)
    .await
}

pub async fn bills_for_event(pool: &PgPool, event_id: Uuid) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar("SELECT COUNT(*) FROM event_bills WHERE event_id = $1")
        .bind(event_id)
        .fetch_one(pool)
        .await
}

pub async fn recent_bills(pool: &PgPool, club_id: Uuid, limit: i64) -> Result<Vec<BillRow>, sqlx::Error> {
    sqlx::query_as::<_, BillRow>(&format!(
        "SELECT {BILL_COLS} FROM event_bills WHERE club_id = $1 AND status = 'issued'
         ORDER BY event_start_at DESC LIMIT $2"
    ))
    .bind(club_id)
    .bind(limit.clamp(1, 100))
    .fetch_all(pool)
    .await
}

/// Cancel a bill. Its shares go with it; anything already paid becomes credit.
pub async fn void_bill(
    conn: &mut PgConnection,
    event_id: Uuid,
    by: Uuid,
    reason: &str,
) -> Result<Option<BillRow>, sqlx::Error> {
    let Some(bill) = live_bill_locked(conn, event_id).await? else { return Ok(None) };
    sqlx::query(
        "UPDATE event_bills SET status = 'void', voided_at = NOW(), voided_by = $2, void_reason = $3, updated_at = NOW()
         WHERE id = $1",
    )
    .bind(bill.id)
    .bind(by)
    .bind(reason)
    .execute(&mut *conn)
    .await?;
    sqlx::query("UPDATE bill_shares SET status = 'void', reason = $2, decided_by = $3, decided_at = NOW() WHERE bill_id = $1 AND status IN ('live', 'covered')")
        .bind(bill.id)
        .bind(reason)
        .bind(by)
        .execute(conn)
        .await?;
    Ok(Some(bill))
}

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct ShareRow {
    pub id: Uuid,
    pub bill_id: Uuid,
    pub club_id: Uuid,
    pub user_id: Option<Uuid>,
    pub guest_name: Option<String>,
    pub name: String,
    pub amount_cents: i64,
    pub status: String,
    pub reason: Option<String>,
    pub reminders_sent: i32,
    pub last_reminded_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    /// The pass that covers it, when `status` is `covered` by a pass.
    pub covered_by: Option<Uuid>,
    // From the bill.
    pub event_id: Option<Uuid>,
    pub title: String,
    pub event_start_at: DateTime<Utc>,
    pub currency: String,
    pub issued_at: DateTime<Utc>,
    pub kind: String,
    pub due_on: Option<chrono::NaiveDate>,
}

const SHARE_SELECT: &str = "SELECT s.id, s.bill_id, s.club_id, s.user_id, s.guest_name, s.name, s.amount_cents, \
    s.status, s.reason, s.reminders_sent, s.last_reminded_at, s.created_at, s.covered_by, \
    b.event_id, b.title, b.event_start_at, b.currency, b.issued_at, b.kind, b.due_on \
    FROM bill_shares s JOIN event_bills b ON b.id = s.bill_id";

impl ShareRow {
    pub fn ledger(&self) -> LedgerShare {
        LedgerShare { id: self.id, amount_cents: self.amount_cents, issued_at: self.issued_at }
    }

    /// Who this share belongs to, for matching payments: a member, or a guest
    /// by name within the club.
    pub fn payer(&self) -> Payer {
        Payer::of(self.user_id, self.guest_name.as_deref())
    }
}

/// Who pays: a member by id, or a guest by (case-folded) name.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Payer {
    Member(Uuid),
    Guest(String),
}

impl Payer {
    pub fn of(user_id: Option<Uuid>, guest_name: Option<&str>) -> Self {
        match user_id {
            Some(id) => Self::Member(id),
            None => Self::Guest(guest_name.unwrap_or("").trim().to_lowercase()),
        }
    }
}

/// The shares on one bill, live and waived (voided ones are history).
pub async fn bill_shares(pool: &PgPool, bill_id: Uuid) -> Result<Vec<ShareRow>, sqlx::Error> {
    sqlx::query_as::<_, ShareRow>(&format!(
        "{SHARE_SELECT} WHERE s.bill_id = $1 AND s.status IN ('live', 'waived', 'covered') ORDER BY lower(s.name), s.id"
    ))
    .bind(bill_id)
    .fetch_all(pool)
    .await
}

pub async fn share(pool: &PgPool, share_id: Uuid) -> Result<Option<ShareRow>, sqlx::Error> {
    sqlx::query_as::<_, ShareRow>(&format!("{SHARE_SELECT} WHERE s.id = $1"))
        .bind(share_id)
        .fetch_optional(pool)
        .await
}

pub async fn waive_share(conn: &mut PgConnection, share_id: Uuid, by: Uuid, reason: &str) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE bill_shares SET status = 'waived', reason = $3, decided_by = $2, decided_at = NOW()
         WHERE id = $1 AND status = 'live'",
    )
    .bind(share_id)
    .bind(by)
    .bind(reason)
    .execute(conn)
    .await?
    .rows_affected()
        == 1)
}

/// Somebody on the bill.
#[derive(Debug, Clone, Default)]
pub struct Attendee {
    pub user_id: Option<Uuid>,
    pub name: String,
    /// Their own price, for a per-player cost where their price type has one.
    pub amount_cents: Option<i64>,
    /// Owing nothing on this bill, and why.
    pub cover: Option<Cover>,
}

/// Why somebody on a bill owes nothing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Cover {
    /// A pass covers it (the pass holder's id).
    Pass { holder_id: Uuid, plan_name: String },
    /// Their price type is free (coach, say).
    Free { price_type: String },
}

pub struct BillInput<'a> {
    pub event_id: Uuid,
    pub club_id: Uuid,
    pub title: &'a str,
    pub event_start_at: DateTime<Utc>,
    pub mode: CostMode,
    pub amount_cents: i64,
    pub currency: &'a str,
    pub rounding: Rounding,
    pub payout_account_id: Option<Uuid>,
    /// In the order shares are handed out; the first get any leftover penny.
    pub attendees: Vec<Attendee>,
    pub note: Option<&'a str>,
    pub by: Option<Uuid>,
    pub auto: bool,
    /// For a re-split: the version the person was looking at.
    pub expected_version: Option<i32>,
}

#[derive(Debug)]
pub enum BillError {
    Split(SplitError),
    /// Somebody else changed the bill since it was read.
    VersionConflict { current: i32 },
    /// A re-split was asked for but there is no bill to re-split, or the
    /// reverse: a fresh bill was asked for and one is already live.
    Mismatch { live: bool },
    Db(sqlx::Error),
}

impl From<sqlx::Error> for BillError {
    fn from(e: sqlx::Error) -> Self {
        Self::Db(e)
    }
}

#[derive(Debug, Clone)]
pub struct BillOutcome {
    pub bill: BillRow,
    pub resplit: bool,
    /// Members whose share is new or changed: they are the ones to tell.
    pub changed: Vec<(Uuid, i64)>,
    /// Members a re-split took off the bill: they are told too.
    pub removed: Vec<Uuid>,
    pub surplus_cents: i64,
}

/// A share on the version being re-split: user, guest, amount, status, reason.
type PriorShare = (Option<Uuid>, Option<String>, i64, String, Option<String>);

/// Send a bill, or re-split the live one.
///
/// One transaction, with the event's live bill locked. With no live bill a
/// new one is sent (`expected_version` must be `None`); with one, it is
/// re-split, and `expected_version` must match its version or nothing changes.
/// The old shares are voided and new ones written: nothing is edited in place,
/// and what members already paid is matched to the new shares when read.
pub async fn issue_bill(conn: &mut PgConnection, input: &BillInput<'_>) -> Result<BillOutcome, BillError> {
    let split = money::split(input.mode, input.amount_cents, input.attendees.len(), input.rounding)
        .map_err(BillError::Split)?;
    // A per-player price type overrides the standard price; a split total is
    // split evenly. What everyone covered "would have paid" stays on their line
    // for the record; the club covers it, so nobody else pays more.
    let amounts: Vec<i64> = input
        .attendees
        .iter()
        .zip(&split.shares)
        .map(|(a, standard)| match (input.mode, a.amount_cents) {
            (CostMode::PerPlayer, Some(own)) if own > 0 => own,
            _ => *standard,
        })
        .collect();
    // What the bill collects: everybody's line but those a pass or a free
    // price type covers.
    let total_cents: i64 =
        input.attendees.iter().zip(&amounts).filter(|(a, _)| a.cover.is_none()).map(|(_, amount)| amount).sum();
    let live = live_bill_locked(conn, input.event_id).await?;
    // Keyed by payer — a member by id, a guest by name — so a guest who was
    // let off stays let off too.
    let mut waived: std::collections::HashMap<Payer, Option<String>> = std::collections::HashMap::new();

    let (bill, resplit, before) = match (live, input.expected_version) {
        (None, None) => {
            let bill = sqlx::query_as::<_, BillRow>(&format!(
                r#"
                INSERT INTO event_bills (event_id, club_id, title, event_start_at, mode, amount_cents,
                    total_cents, currency, rounding, payout_account_id, auto, note, issued_by)
                VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
                RETURNING {BILL_COLS}
                "#
            ))
            .bind(input.event_id)
            .bind(input.club_id)
            .bind(input.title)
            .bind(input.event_start_at)
            .bind(input.mode.as_str())
            .bind(input.amount_cents)
            .bind(total_cents)
            .bind(input.currency)
            .bind(input.rounding.as_str())
            .bind(input.payout_account_id)
            .bind(input.auto)
            .bind(input.note)
            .bind(input.by)
            .fetch_one(&mut *conn)
            .await?;
            (bill, false, Vec::new())
        }
        (Some(live), Some(expected)) => {
            if live.version != expected {
                return Err(BillError::VersionConflict { current: live.version });
            }
            let rows: Vec<PriorShare> = sqlx::query_as(
                "SELECT user_id, guest_name, amount_cents, status, reason FROM bill_shares
                 WHERE bill_id = $1 AND status IN ('live', 'waived', 'covered')",
            )
            .bind(live.id)
            .fetch_all(&mut *conn)
            .await?;
            // Somebody let off stays let off: their new share is waived too.
            for (user, guest, _, status, reason) in &rows {
                if status == "waived" {
                    waived.insert(Payer::of(*user, guest.as_deref()), reason.clone());
                }
            }
            let before: Vec<(Option<Uuid>, i64, String, Option<String>)> =
                rows.into_iter().map(|(u, _, a, st, r)| (u, a, st, r)).collect();
            sqlx::query(
                "UPDATE bill_shares SET status = 'void', reason = 're-split', decided_by = $2, decided_at = NOW()
                 WHERE bill_id = $1 AND status IN ('live', 'waived', 'covered')",
            )
            .bind(live.id)
            .bind(input.by)
            .execute(&mut *conn)
            .await?;
            let bill = sqlx::query_as::<_, BillRow>(&format!(
                r#"
                UPDATE event_bills SET mode = $2, amount_cents = $3, total_cents = $4, rounding = $5,
                    note = COALESCE($6, note), version = version + 1, updated_at = NOW()
                WHERE id = $1
                RETURNING {BILL_COLS}
                "#
            ))
            .bind(live.id)
            .bind(input.mode.as_str())
            .bind(input.amount_cents)
            .bind(total_cents)
            .bind(input.rounding.as_str())
            .bind(input.note)
            .fetch_one(&mut *conn)
            .await?;
            (bill, true, before)
        }
        (live, _) => return Err(BillError::Mismatch { live: live.is_some() }),
    };

    let mut changed = Vec::new();
    for (attendee, amount) in input.attendees.iter().zip(&amounts) {
        let waiver = waived.get(&Payer::of(attendee.user_id, Some(attendee.name.as_str())));
        let (status, reason, covered_by) = match (&attendee.cover, waiver) {
            (Some(Cover::Pass { holder_id, plan_name }), _) => ("covered", Some(format!("Covered by {plan_name}")), Some(*holder_id)),
            (Some(Cover::Free { price_type }), _) => ("covered", Some(format!("Free: {price_type}")), None),
            (None, Some(reason)) => ("waived", reason.clone(), None),
            (None, None) => ("live", None, None),
        };
        sqlx::query(
            "INSERT INTO bill_shares (bill_id, club_id, user_id, guest_name, name, amount_cents, status, reason,
                                      decided_by, decided_at, covered_by)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CASE WHEN $7 = 'waived' THEN $9 END,
                     CASE WHEN $7 = 'waived' THEN NOW() END, $10)",
        )
        .bind(bill.id)
        .bind(input.club_id)
        .bind(attendee.user_id)
        .bind(attendee.user_id.is_none().then_some(attendee.name.as_str()))
        .bind(&attendee.name)
        .bind(amount)
        .bind(status)
        .bind(reason)
        .bind(input.by)
        .bind(covered_by)
        .execute(&mut *conn)
        .await?;
        if let (Some(user), "live") = (attendee.user_id, status) {
            let was = before.iter().find(|(u, _, s, _)| *u == Some(user) && s == "live").map(|(_, a, _, _)| *a);
            if was != Some(*amount) {
                changed.push((user, *amount));
            }
        }
    }
    let removed = before
        .iter()
        .filter(|(_, _, status, _)| status == "live")
        .filter_map(|(u, _, _, _)| *u)
        .filter(|u| !input.attendees.iter().any(|a| a.user_id == Some(*u)))
        .collect();
    Ok(BillOutcome { bill, resplit, changed, removed, surplus_cents: split.surplus_cents })
}

// MARK: payments

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct PaymentRow {
    pub id: Uuid,
    pub club_id: Uuid,
    pub user_id: Option<Uuid>,
    pub guest_name: Option<String>,
    pub name: String,
    pub amount_cents: i64,
    pub currency: String,
    pub method: String,
    pub reference: Option<String>,
    pub payout_account_id: Option<Uuid>,
    pub status: String,
    pub note: Option<String>,
    pub created_by: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub decided_by: Option<Uuid>,
    pub decided_by_name: Option<String>,
    pub decided_at: Option<DateTime<Utc>>,
    pub decision_reason: Option<String>,
    /// The share a pay-link claim was for, and the link it came through.
    pub share_id: Option<Uuid>,
    pub via_link: Option<Uuid>,
    /// Whether the payer attached a screenshot of the payment.
    pub has_screenshot: bool,
}

const PAYMENT_SELECT: &str = "SELECT p.id, p.club_id, p.user_id, p.guest_name, p.name, p.amount_cents, p.currency, \
    p.method, p.reference, p.payout_account_id, p.status, p.note, p.created_by, p.created_at, \
    p.decided_by, d.name AS decided_by_name, p.decided_at, p.decision_reason, p.share_id, p.via_link, \
    EXISTS (SELECT 1 FROM payment_attachments a WHERE a.payment_id = p.id) AS has_screenshot \
    FROM member_payments p LEFT JOIN users d ON d.id = p.decided_by";

impl PaymentRow {
    pub fn payer(&self) -> Payer {
        Payer::of(self.user_id, self.guest_name.as_deref())
    }
}

pub struct NewPayment<'a> {
    pub club_id: Uuid,
    pub user_id: Option<Uuid>,
    pub guest_name: Option<&'a str>,
    pub name: &'a str,
    pub amount_cents: i64,
    pub currency: &'a str,
    pub method: &'a str,
    pub reference: Option<&'a str>,
    pub payout_account_id: Option<Uuid>,
    pub status: &'a str,
    pub note: Option<&'a str>,
    pub idempotency_key: Option<&'a str>,
    /// Who recorded it; `None` for a claim made through a pay link.
    pub created_by: Option<Uuid>,
    pub via_link: Option<Uuid>,
    pub share_id: Option<Uuid>,
}

/// Record a payment. With an idempotency key, the same request sent twice
/// (a retry on a bad signal) returns the first one and records nothing new:
/// `(row, created)`.
pub async fn insert_payment(conn: &mut PgConnection, p: &NewPayment<'_>) -> Result<(PaymentRow, bool), sqlx::Error> {
    let id: Option<Uuid> = sqlx::query_scalar(
        r#"
        INSERT INTO member_payments (club_id, user_id, guest_name, name, amount_cents, currency, method,
            reference, payout_account_id, status, note, idempotency_key, created_by,
            decided_by, decided_at, via_link, share_id)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,
                CASE WHEN $10 = 'confirmed' THEN $13 END,
                CASE WHEN $10 = 'confirmed' THEN NOW() END, $14, $15)
        -- Either idempotency index: per person when signed in, per link when not.
        ON CONFLICT DO NOTHING
        RETURNING id
        "#,
    )
    .bind(p.club_id)
    .bind(p.user_id)
    .bind(p.guest_name)
    .bind(p.name)
    .bind(p.amount_cents)
    .bind(p.currency)
    .bind(p.method)
    .bind(p.reference)
    .bind(p.payout_account_id)
    .bind(p.status)
    .bind(p.note)
    .bind(p.idempotency_key)
    .bind(p.created_by)
    .bind(p.via_link)
    .bind(p.share_id)
    .fetch_optional(&mut *conn)
    .await?;
    let (id, created) = match id {
        Some(id) => (id, true),
        None => {
            let existing: Uuid = sqlx::query_scalar(
                "SELECT id FROM member_payments
                 WHERE idempotency_key = $3
                   AND ((via_link IS NOT NULL AND via_link = $2) OR (via_link IS NULL AND created_by = $1))",
            )
            .bind(p.created_by)
            .bind(p.via_link)
            .bind(p.idempotency_key)
            .fetch_one(&mut *conn)
            .await?;
            (existing, false)
        }
    };
    let row = sqlx::query_as::<_, PaymentRow>(&format!("{PAYMENT_SELECT} WHERE p.id = $1"))
        .bind(id)
        .fetch_one(conn)
        .await?;
    Ok((row, created))
}

/// The payment this person already made with this idempotency key, if any.
pub async fn payment_by_key(pool: &PgPool, created_by: Uuid, key: &str) -> Result<Option<PaymentRow>, sqlx::Error> {
    sqlx::query_as::<_, PaymentRow>(&format!("{PAYMENT_SELECT} WHERE p.created_by = $1 AND p.idempotency_key = $2"))
        .bind(created_by)
        .bind(key)
        .fetch_optional(pool)
        .await
}

pub async fn payment(pool: &PgPool, id: Uuid) -> Result<Option<PaymentRow>, sqlx::Error> {
    sqlx::query_as::<_, PaymentRow>(&format!("{PAYMENT_SELECT} WHERE p.id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

/// Confirm or reject a claim. Only a claim still waiting can be decided, so a
/// second treasurer tapping the same row a moment later changes nothing.
pub async fn decide_payment(
    conn: &mut PgConnection,
    id: Uuid,
    status: &str,
    by: Uuid,
    reason: Option<&str>,
) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE member_payments SET status = $2, decided_by = $3, decided_at = NOW(), decision_reason = $4
         WHERE id = $1 AND status = 'claimed'",
    )
    .bind(id)
    .bind(status)
    .bind(by)
    .bind(reason)
    .execute(conn)
    .await?
    .rows_affected()
        == 1)
}

/// The payer takes back a claim nobody has decided yet.
pub async fn cancel_claim(conn: &mut PgConnection, id: Uuid, user_id: Uuid) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE member_payments SET status = 'cancelled', decided_by = $2, decided_at = NOW()
         WHERE id = $1 AND (user_id = $2 OR created_by = $2) AND status = 'claimed'",
    )
    .bind(id)
    .bind(user_id)
    .execute(conn)
    .await?
    .rows_affected()
        == 1)
}

pub async fn club_payments(
    pool: &PgPool,
    club_id: Uuid,
    status: Option<&str>,
    limit: i64,
) -> Result<Vec<PaymentRow>, sqlx::Error> {
    sqlx::query_as::<_, PaymentRow>(&format!(
        "{PAYMENT_SELECT} WHERE p.club_id = $1 AND ($2::text IS NULL OR p.status = $2)
         ORDER BY p.created_at DESC LIMIT $3"
    ))
    .bind(club_id)
    .bind(status)
    .bind(limit.clamp(1, 500))
    .fetch_all(pool)
    .await
}

/// A member's payments at a club, and those they made for somebody else.
pub async fn user_payments(pool: &PgPool, club_id: Uuid, user_id: Uuid, limit: i64) -> Result<Vec<PaymentRow>, sqlx::Error> {
    sqlx::query_as::<_, PaymentRow>(&format!(
        "{PAYMENT_SELECT} WHERE p.club_id = $1 AND (p.user_id = $2 OR p.created_by = $2) ORDER BY p.created_at DESC LIMIT $3"
    ))
    .bind(club_id)
    .bind(user_id)
    .bind(limit.clamp(1, 100))
    .fetch_all(pool)
    .await
}

// MARK: the ledger — what is owed and paid

/// A payment as the ledger sees it.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct LedgerRow {
    pub user_id: Option<Uuid>,
    pub guest_name: Option<String>,
    pub amount_cents: i64,
    /// transfer, cash, refund or card
    pub method: String,
    /// claimed or confirmed
    pub status: String,
}

impl LedgerRow {
    pub fn payer(&self) -> Payer {
        Payer::of(self.user_id, self.guest_name.as_deref())
    }

    pub fn ledger(&self) -> LedgerPayment {
        let kind = match (self.method.as_str(), self.status.as_str()) {
            ("refund", _) => LedgerKind::Refund,
            (_, "confirmed") => LedgerKind::Confirmed,
            _ => LedgerKind::Claimed,
        };
        LedgerPayment { amount_cents: self.amount_cents, kind }
    }
}

/// Everything that counts for a club's money: live shares on live bills, and
/// payments that are claimed or confirmed — including card payments that
/// succeeded for a fixture the member was billed for.
///
/// `only` narrows it to one member. A club's whole ledger is small (a season
/// of sessions); it is read in one go and grouped in code.
pub async fn ledger(
    pool: &PgPool,
    club_id: Uuid,
    only: Option<Uuid>,
) -> Result<(Vec<ShareRow>, Vec<LedgerRow>), sqlx::Error> {
    let shares = sqlx::query_as::<_, ShareRow>(&format!(
        "{SHARE_SELECT} WHERE s.club_id = $1 AND s.status = 'live' AND b.status = 'issued'
           AND ($2::uuid IS NULL OR s.user_id = $2)
         ORDER BY b.issued_at, s.id"
    ))
    .bind(club_id)
    .bind(only)
    .fetch_all(pool)
    .await?;
    let payments = sqlx::query_as::<_, LedgerRow>(
        r#"
        SELECT user_id, guest_name, amount_cents, method, status
        FROM member_payments
        WHERE club_id = $1 AND status IN ('claimed', 'confirmed') AND ($2::uuid IS NULL OR user_id = $2)
        UNION ALL
        SELECT p.user_id, NULL, p.amount_cents::bigint, 'card', 'confirmed'
        FROM payments p
        WHERE p.status = 'succeeded' AND p.order_id IS NULL AND ($2::uuid IS NULL OR p.user_id = $2)
          AND EXISTS (
              SELECT 1 FROM event_bills b JOIN bill_shares s ON s.bill_id = b.id
              WHERE b.club_id = $1 AND b.event_id = p.event_id AND s.user_id = p.user_id
          )
        "#,
    )
    .bind(club_id)
    .bind(only)
    .fetch_all(pool)
    .await?;
    Ok((shares, payments))
}

/// Clubs where this member has ever been billed or paid.
pub async fn clubs_with_money(pool: &PgPool, user_id: Uuid) -> Result<Vec<(Uuid, String)>, sqlx::Error> {
    sqlx::query_as(
        r#"
        SELECT c.id, c.name FROM clubs c
        WHERE c.id IN (SELECT club_id FROM bill_shares WHERE user_id = $1
                       UNION SELECT club_id FROM member_payments WHERE user_id = $1)
        ORDER BY c.name
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
}

// MARK: references

pub async fn reference_code(pool: &PgPool, club_id: Uuid, user_id: Uuid) -> Result<Option<String>, sqlx::Error> {
    sqlx::query_scalar("SELECT code FROM payment_references WHERE club_id = $1 AND user_id = $2")
        .bind(club_id)
        .bind(user_id)
        .fetch_optional(pool)
        .await
}

/// References already taken in this club that start from `base`.
pub async fn references_like(pool: &PgPool, club_id: Uuid, base: &str) -> Result<Vec<String>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT code FROM payment_references WHERE club_id = $1 AND (code = $2 OR code LIKE $2 || ' %')",
    )
    .bind(club_id)
    .bind(base)
    .fetch_all(pool)
    .await
}

/// Keep `code` as this member's reference, unless they already have one.
/// A code another member already has is a unique violation: the caller tries
/// another.
pub async fn store_reference_code(pool: &PgPool, club_id: Uuid, user_id: Uuid, code: &str) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO payment_references (club_id, user_id, code) VALUES ($1, $2, $3)
         ON CONFLICT (club_id, user_id) DO NOTHING",
    )
    .bind(club_id)
    .bind(user_id)
    .bind(code)
    .execute(pool)
    .await?;
    Ok(())
}

// MARK: for the scheduler

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct FinishedEvent {
    pub event_id: Uuid,
    pub club_id: Uuid,
    pub title: String,
    pub start_at: DateTime<Utc>,
    pub subtype: String,
    pub team_id: Option<Uuid>,
    pub created_by: Uuid,
    pub mode: String,
    pub amount_cents: i64,
    pub currency: String,
    pub round_shares_up: bool,
}

const FINISHED_SELECT: &str = r#"
    SELECT e.id AS event_id, e.club_id, e.title, e.start_at, e.event_subtype::text AS subtype, e.team_id, e.created_by,
           ec.mode, ec.amount_cents, ec.currency, c.round_shares_up
    FROM event_costs ec
    JOIN events e ON e.id = ec.event_id
    JOIN clubs c ON c.id = e.club_id
    WHERE e.status <> 'cancelled'
      AND c.payments_enabled_at IS NOT NULL
      AND e.end_at >= c.payments_enabled_at
      AND e.end_at < NOW()
      AND NOT EXISTS (SELECT 1 FROM event_bills b WHERE b.event_id = e.id)
"#;

/// Sessions with a cost that have just finished and haven't been billed:
/// whoever scheduled them is asked who came. Once each, within a week.
pub async fn events_to_prompt(pool: &PgPool) -> Result<Vec<FinishedEvent>, sqlx::Error> {
    sqlx::query_as::<_, FinishedEvent>(&format!(
        "{FINISHED_SELECT} AND ec.attendance_prompted_at IS NULL AND e.end_at > NOW() - INTERVAL '7 days'
         ORDER BY e.end_at LIMIT 200"
    ))
    .fetch_all(pool)
    .await
}

pub async fn mark_prompted(pool: &PgPool, event_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE event_costs SET attendance_prompted_at = NOW() WHERE event_id = $1")
        .bind(event_id)
        .execute(pool)
        .await?;
    Ok(())
}

/// Sessions nobody billed by hand within the club's window, for clubs that
/// bill automatically. Within a fortnight, so switching auto-billing on never
/// bills last season.
pub async fn events_to_auto_bill(pool: &PgPool) -> Result<Vec<FinishedEvent>, sqlx::Error> {
    sqlx::query_as::<_, FinishedEvent>(&format!(
        "{FINISHED_SELECT} AND c.auto_bill AND ec.auto_bill_skipped_at IS NULL
           AND e.end_at < NOW() - make_interval(hours => c.auto_bill_after_hours)
           AND e.end_at > NOW() - INTERVAL '14 days'
         ORDER BY e.end_at LIMIT 100"
    ))
    .fetch_all(pool)
    .await
}

pub async fn mark_auto_bill_skipped(pool: &PgPool, event_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE event_costs SET auto_bill_skipped_at = NOW() WHERE event_id = $1")
        .bind(event_id)
        .execute(pool)
        .await?;
    Ok(())
}

/// A member's most recent lines a pass or free price covered, newest first:
/// "Tuesday nets — covered by your pass", in their history.
pub async fn recent_covered_shares(pool: &PgPool, club_id: Uuid, user_id: Uuid, limit: i64) -> Result<Vec<ShareRow>, sqlx::Error> {
    sqlx::query_as::<_, ShareRow>(&format!(
        "{SHARE_SELECT} WHERE s.club_id = $1 AND s.user_id = $2 AND s.status = 'covered' AND b.status = 'issued'
         ORDER BY b.event_start_at DESC LIMIT $3"
    ))
    .bind(club_id)
    .bind(user_id)
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Live shares old enough to chase and not chased too often, for members.
/// Whether anything is still owed is decided by the caller with the ledger.
pub async fn shares_due_a_reminder(pool: &PgPool) -> Result<Vec<ShareRow>, sqlx::Error> {
    sqlx::query_as::<_, ShareRow>(&format!(
        r#"
        {SHARE_SELECT}
        JOIN clubs c ON c.id = s.club_id
        WHERE s.status = 'live' AND b.status = 'issued' AND s.user_id IS NOT NULL
          AND b.issued_at < NOW() - make_interval(hours => c.fee_chase_after_hours)
          AND (b.due_on IS NULL OR b.due_on < CURRENT_DATE)
          AND s.reminders_sent < c.fee_chase_max_reminders
          AND (s.last_reminded_at IS NULL OR s.last_reminded_at < NOW() - INTERVAL '72 hours')
        ORDER BY s.club_id, s.user_id
        LIMIT 1000
        "#
    ))
    .fetch_all(pool)
    .await
}

pub async fn mark_shares_reminded(pool: &PgPool, share_ids: &[Uuid]) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE bill_shares SET reminders_sent = reminders_sent + 1, last_reminded_at = NOW() WHERE id = ANY($1)",
    )
    .bind(share_ids)
    .execute(pool)
    .await?;
    Ok(())
}

/// Claims nobody has checked for two days: `(club_id, payment ids)`.
pub async fn stale_claims(pool: &PgPool) -> Result<Vec<(Uuid, Vec<Uuid>)>, sqlx::Error> {
    sqlx::query_as(
        "SELECT club_id, array_agg(id) FROM member_payments
         WHERE status = 'claimed' AND check_reminded_at IS NULL AND created_at < NOW() - INTERVAL '48 hours'
         GROUP BY club_id LIMIT 500",
    )
    .fetch_all(pool)
    .await
}

pub async fn mark_claims_nudged(pool: &PgPool, ids: &[Uuid]) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE member_payments SET check_reminded_at = NOW() WHERE id = ANY($1)")
        .bind(ids)
        .execute(pool)
        .await?;
    Ok(())
}

// MARK: pay links

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct PayLinkRow {
    pub id: Uuid,
    pub club_id: Uuid,
    pub bill_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub disabled_at: Option<DateTime<Utc>>,
    /// The bill it is for: still the live one?
    pub bill_status: String,
    pub event_id: Option<Uuid>,
}

const PAY_LINK_SELECT: &str = "SELECT l.id, l.club_id, l.bill_id, l.created_at, l.expires_at, l.disabled_at, \
    b.status AS bill_status, b.event_id FROM pay_links l JOIN event_bills b ON b.id = l.bill_id";

impl PayLinkRow {
    /// Open: not switched off, not expired, and its bill not cancelled.
    pub fn is_open(&self, now: DateTime<Utc>) -> bool {
        self.disabled_at.is_none() && self.expires_at > now && self.bill_status == "issued"
    }
}

pub async fn pay_link(pool: &PgPool, id: Uuid) -> Result<Option<PayLinkRow>, sqlx::Error> {
    sqlx::query_as::<_, PayLinkRow>(&format!("{PAY_LINK_SELECT} WHERE l.id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

/// The newest link for a bill that is still open, if any.
pub async fn open_link_for_bill(pool: &PgPool, bill_id: Uuid) -> Result<Option<PayLinkRow>, sqlx::Error> {
    sqlx::query_as::<_, PayLinkRow>(&format!(
        "{PAY_LINK_SELECT} WHERE l.bill_id = $1 AND l.disabled_at IS NULL AND l.expires_at > NOW()
         ORDER BY l.created_at DESC LIMIT 1"
    ))
    .bind(bill_id)
    .fetch_optional(pool)
    .await
}

pub async fn create_pay_link(
    conn: &mut PgConnection,
    club_id: Uuid,
    bill_id: Uuid,
    by: Uuid,
    expires_at: DateTime<Utc>,
) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar(
        "INSERT INTO pay_links (club_id, bill_id, created_by, expires_at) VALUES ($1, $2, $3, $4) RETURNING id",
    )
    .bind(club_id)
    .bind(bill_id)
    .bind(by)
    .bind(expires_at)
    .fetch_one(conn)
    .await
}

/// Switch off every open link for a bill.
pub async fn disable_links_for_bill(conn: &mut PgConnection, bill_id: Uuid, by: Uuid) -> Result<u64, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE pay_links SET disabled_at = NOW(), disabled_by = $2 WHERE bill_id = $1 AND disabled_at IS NULL",
    )
    .bind(bill_id)
    .bind(by)
    .execute(conn)
    .await?
    .rows_affected())
}

/// A share on this bill (live or let off), as the link shows it.
pub async fn share_on_bill(pool: &PgPool, bill_id: Uuid, share_id: Uuid) -> Result<Option<ShareRow>, sqlx::Error> {
    sqlx::query_as::<_, ShareRow>(&format!(
        "{SHARE_SELECT} WHERE s.bill_id = $1 AND s.id = $2 AND s.status IN ('live', 'waived', 'covered')"
    ))
    .bind(bill_id)
    .bind(share_id)
    .fetch_optional(pool)
    .await
}

/// The claim a link request with this Idempotency-Key made, if any: a retry
/// by the same phone.
pub async fn link_claim_by_key(pool: &PgPool, link_id: Uuid, key: &str) -> Result<Option<PaymentRow>, sqlx::Error> {
    sqlx::query_as::<_, PaymentRow>(&format!("{PAYMENT_SELECT} WHERE p.via_link = $1 AND p.idempotency_key = $2"))
        .bind(link_id)
        .bind(key)
        .fetch_optional(pool)
        .await
}

/// A claim still waiting for the treasurer, for one share — so a second tap
/// on the link shows that claim instead of making another.
pub async fn open_claim_for_share(pool: &PgPool, share_id: Uuid) -> Result<Option<PaymentRow>, sqlx::Error> {
    sqlx::query_as::<_, PaymentRow>(&format!(
        "{PAYMENT_SELECT} WHERE p.share_id = $1 AND p.status = 'claimed' ORDER BY p.created_at DESC LIMIT 1"
    ))
    .bind(share_id)
    .fetch_optional(pool)
    .await
}

/// Claims made through one link in the last hour: a link that suddenly makes
/// dozens is being abused, whatever replica the requests landed on.
pub async fn recent_link_claims(pool: &PgPool, link_id: Uuid) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT COUNT(*) FROM member_payments WHERE via_link = $1 AND created_at > NOW() - INTERVAL '1 hour'",
    )
    .bind(link_id)
    .fetch_one(pool)
    .await
}

// MARK: screenshots

pub async fn put_attachment(
    conn: &mut PgConnection,
    payment_id: Uuid,
    content_type: &str,
    bytes: &[u8],
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO payment_attachments (payment_id, content_type, bytes) VALUES ($1, $2, $3)
         ON CONFLICT (payment_id) DO UPDATE SET content_type = EXCLUDED.content_type, bytes = EXCLUDED.bytes,
             created_at = NOW()",
    )
    .bind(payment_id)
    .bind(content_type)
    .bind(bytes)
    .execute(conn)
    .await?;
    Ok(())
}

pub async fn attachment(pool: &PgPool, payment_id: Uuid) -> Result<Option<(String, Vec<u8>)>, sqlx::Error> {
    sqlx::query_as("SELECT content_type, bytes FROM payment_attachments WHERE payment_id = $1")
        .bind(payment_id)
        .fetch_optional(pool)
        .await
}

// MARK: bank statement import

/// Every member's reference with the club: `(code, user_id)`.
pub async fn club_references(pool: &PgPool, club_id: Uuid) -> Result<Vec<(String, Uuid)>, sqlx::Error> {
    sqlx::query_as("SELECT code, user_id FROM payment_references WHERE club_id = $1").bind(club_id).fetch_all(pool).await
}

/// A bank transfer somebody said they made, not yet ticked.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OpenTransfer {
    pub id: Uuid,
    pub user_id: Uuid,
    pub amount_cents: i64,
    pub on: NaiveDate,
    /// Whose reference it came with: whoever paid for them, else their own.
    pub payer: Uuid,
    /// The same for claims made in one go (one transfer on the statement).
    pub batch: String,
}

pub async fn open_transfer_claims(pool: &PgPool, club_id: Uuid) -> Result<Vec<OpenTransfer>, sqlx::Error> {
    sqlx::query_as(
        "SELECT id, user_id, amount_cents, created_at::date AS \"on\", COALESCE(paid_by, user_id) AS payer,
                COALESCE(created_by::text || '|' || created_at::text, id::text) AS batch
         FROM member_payments
         WHERE club_id = $1 AND status = 'claimed' AND method = 'transfer' AND user_id IS NOT NULL",
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// Which of these statement lines were applied already.
pub async fn applied_lines(pool: &PgPool, club_id: Uuid, hashes: &[String]) -> Result<Vec<String>, sqlx::Error> {
    sqlx::query_scalar("SELECT line_hash FROM statement_lines WHERE club_id = $1 AND line_hash = ANY($2)")
        .bind(club_id)
        .bind(hashes)
        .fetch_all(pool)
        .await
}

/// Take a statement line for applying; `false` when it was applied already.
pub async fn take_line(conn: &mut PgConnection, club_id: Uuid, hash: &str, by: Uuid) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "INSERT INTO statement_lines (club_id, line_hash, applied_by) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
    )
    .bind(club_id)
    .bind(hash)
    .bind(by)
    .execute(conn)
    .await?
    .rows_affected()
        == 1)
}

pub async fn set_line_payment(conn: &mut PgConnection, club_id: Uuid, hash: &str, payment_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE statement_lines SET payment_id = $3 WHERE club_id = $1 AND line_hash = $2")
        .bind(club_id)
        .bind(hash)
        .bind(payment_id)
        .execute(conn)
        .await?;
    Ok(())
}

/// The bills a member is on at a club (issued, any status of their line).
pub async fn bills_with(pool: &PgPool, club_id: Uuid, user_id: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT DISTINCT s.bill_id FROM bill_shares s JOIN event_bills b ON b.id = s.bill_id
         WHERE b.club_id = $1 AND b.status = 'issued' AND s.user_id = $2",
    )
    .bind(club_id)
    .bind(user_id)
    .fetch_all(pool)
    .await
}

/// Take the payer's lock for this transaction, without waiting: `false` when
/// another request is saving a payment for them right now. Two taps at once
/// (or a burst from a pay link) can't both read "£10 owed" and both record
/// it. Not waiting matters: a waiter would hold a pooled connection that the
/// request holding the lock may need.
pub async fn try_lock_payer(conn: &mut PgConnection, club_id: Uuid, payer: &Payer) -> Result<bool, sqlx::Error> {
    let key = match payer {
        Payer::Member(u) => format!("pay|{club_id}|m|{u}"),
        Payer::Guest(n) => format!("pay|{club_id}|g|{n}"),
    };
    try_lock_key(conn, &key).await
}

/// Any transaction-long lock by name, without waiting: `false` when another
/// request holds it.
pub async fn try_lock_key(conn: &mut PgConnection, key: &str) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar("SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))").bind(key).fetch_one(conn).await
}

