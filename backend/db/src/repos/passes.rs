//! Passes, price types, group fees and paying for others — steps B and C of
//! docs/CLUB_PAYMENTS_V2_PLAN.md. The ledger and bills are in `club_payments`;
//! this is where bills that aren't for a session come from, and where a
//! session's bill learns who owes nothing.

use std::collections::HashMap;

use chrono::{DateTime, NaiveDate, Utc};
use fishers_domain::money::{self, LedgerShare, PassBilling, PassStanding};
use serde::Serialize;
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

use super::club_payments::{self as payments, Payer};

// MARK: price types

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct PriceType {
    pub id: Uuid,
    pub club_id: Uuid,
    pub name: String,
    pub free: bool,
    pub for_guests: bool,
    pub sort_order: i32,
    pub archived_at: Option<DateTime<Utc>>,
}

pub async fn price_types(pool: &PgPool, club_id: Uuid) -> Result<Vec<PriceType>, sqlx::Error> {
    sqlx::query_as::<_, PriceType>(
        "SELECT id, club_id, name, free, for_guests, sort_order, archived_at FROM club_price_types
         WHERE club_id = $1 ORDER BY archived_at NULLS FIRST, sort_order, lower(name)",
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

pub async fn price_type(pool: &PgPool, id: Uuid) -> Result<Option<PriceType>, sqlx::Error> {
    sqlx::query_as::<_, PriceType>(
        "SELECT id, club_id, name, free, for_guests, sort_order, archived_at FROM club_price_types WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(pool)
    .await
}

pub async fn create_price_type(
    conn: &mut PgConnection,
    club_id: Uuid,
    name: &str,
    free: bool,
    for_guests: bool,
) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar(
        "INSERT INTO club_price_types (club_id, name, free, for_guests, sort_order)
         VALUES ($1, $2, $3, $4, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM club_price_types WHERE club_id = $1))
         RETURNING id",
    )
    .bind(club_id)
    .bind(name)
    .bind(free)
    .bind(for_guests)
    .fetch_one(conn)
    .await
}

pub async fn update_price_type(
    conn: &mut PgConnection,
    id: Uuid,
    name: Option<&str>,
    free: Option<bool>,
    for_guests: Option<bool>,
    archived: Option<bool>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE club_price_types SET name = COALESCE($2, name), free = COALESCE($3, free),
             for_guests = COALESCE($4, for_guests),
             archived_at = CASE WHEN $5 IS NULL THEN archived_at WHEN $5 THEN COALESCE(archived_at, NOW()) ELSE NULL END
         WHERE id = $1",
    )
    .bind(id)
    .bind(name)
    .bind(free)
    .bind(for_guests)
    .bind(archived)
    .execute(conn)
    .await?;
    Ok(())
}

/// Each active member's price type, where they have one.
pub async fn member_price_types(pool: &PgPool, club_id: Uuid) -> Result<HashMap<Uuid, Uuid>, sqlx::Error> {
    let rows: Vec<(Uuid, Uuid)> = sqlx::query_as(
        "SELECT user_id, price_type_id FROM club_members
         WHERE club_id = $1 AND status = 'active' AND price_type_id IS NOT NULL",
    )
    .bind(club_id)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().collect())
}

pub async fn set_member_price_type(
    conn: &mut PgConnection,
    club_id: Uuid,
    user_id: Uuid,
    price_type_id: Option<Uuid>,
) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE club_members SET price_type_id = $3 WHERE club_id = $1 AND user_id = $2 AND status = 'active'",
    )
    .bind(club_id)
    .bind(user_id)
    .bind(price_type_id)
    .execute(conn)
    .await?
    .rows_affected()
        == 1)
}

/// A session's own price for each price type, where it has one.
pub async fn event_prices(pool: &PgPool, event_id: Uuid) -> Result<HashMap<Uuid, i64>, sqlx::Error> {
    let rows: Vec<(Uuid, i64)> =
        sqlx::query_as("SELECT price_type_id, amount_cents FROM event_cost_prices WHERE event_id = $1")
            .bind(event_id)
            .fetch_all(pool)
            .await?;
    Ok(rows.into_iter().collect())
}

pub async fn set_event_prices(
    conn: &mut PgConnection,
    event_id: Uuid,
    prices: &[(Uuid, i64)],
) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM event_cost_prices WHERE event_id = $1").bind(event_id).execute(&mut *conn).await?;
    for (price_type_id, amount) in prices {
        sqlx::query("INSERT INTO event_cost_prices (event_id, price_type_id, amount_cents) VALUES ($1, $2, $3)")
            .bind(event_id)
            .bind(price_type_id)
            .bind(amount)
            .execute(&mut *conn)
            .await?;
    }
    Ok(())
}

// MARK: pass plans

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct PassPlan {
    pub id: Uuid,
    pub club_id: Uuid,
    pub name: String,
    pub price_cents: i64,
    pub currency: String,
    pub billing: String,
    pub instalments: Option<i32>,
    pub covers: Vec<String>,
    pub team_id: Option<Uuid>,
    pub valid_until: Option<NaiveDate>,
    pub sessions: Option<i32>,
    pub price_type_id: Option<Uuid>,
    pub open_to_join: bool,
    pub created_at: DateTime<Utc>,
    pub archived_at: Option<DateTime<Utc>>,
}

impl PassPlan {
    pub fn billing(&self) -> PassBilling {
        PassBilling::parse(&self.billing).unwrap_or(PassBilling::Once)
    }

    /// What each payment is: the price, or one instalment of it.
    pub fn charge_cents(&self) -> i64 {
        match (self.billing(), self.instalments) {
            (PassBilling::Instalments, Some(n)) if n > 0 => (self.price_cents + i64::from(n) - 1) / i64::from(n),
            _ => self.price_cents,
        }
    }
}

const PLAN_COLS: &str = "id, club_id, name, price_cents, currency, billing, instalments, covers, team_id, \
    valid_until, sessions, price_type_id, open_to_join, created_at, archived_at";

pub async fn plans(pool: &PgPool, club_id: Uuid, include_archived: bool) -> Result<Vec<PassPlan>, sqlx::Error> {
    sqlx::query_as::<_, PassPlan>(&format!(
        "SELECT {PLAN_COLS} FROM pass_plans WHERE club_id = $1 AND ($2 OR archived_at IS NULL)
         ORDER BY archived_at NULLS FIRST, created_at"
    ))
    .bind(club_id)
    .bind(include_archived)
    .fetch_all(pool)
    .await
}

pub async fn plan(pool: &PgPool, id: Uuid) -> Result<Option<PassPlan>, sqlx::Error> {
    sqlx::query_as::<_, PassPlan>(&format!("SELECT {PLAN_COLS} FROM pass_plans WHERE id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

pub struct NewPlan<'a> {
    pub club_id: Uuid,
    pub name: &'a str,
    pub price_cents: i64,
    pub currency: &'a str,
    pub billing: PassBilling,
    pub instalments: Option<i32>,
    pub covers: &'a [String],
    pub team_id: Option<Uuid>,
    pub valid_until: Option<NaiveDate>,
    pub sessions: Option<i32>,
    pub price_type_id: Option<Uuid>,
    pub open_to_join: bool,
    pub by: Uuid,
}

pub async fn create_plan(conn: &mut PgConnection, p: &NewPlan<'_>) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar(
        "INSERT INTO pass_plans (club_id, name, price_cents, currency, billing, instalments, covers, team_id,
             valid_until, sessions, price_type_id, open_to_join, created_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id",
    )
    .bind(p.club_id)
    .bind(p.name)
    .bind(p.price_cents)
    .bind(p.currency)
    .bind(p.billing.as_str())
    .bind(p.instalments)
    .bind(p.covers)
    .bind(p.team_id)
    .bind(p.valid_until)
    .bind(p.sessions)
    .bind(p.price_type_id)
    .bind(p.open_to_join)
    .bind(p.by)
    .fetch_one(conn)
    .await
}

/// A plan's price, name or availability. The price applies to charges made
/// from now on; nothing already charged changes.
pub async fn update_plan(
    conn: &mut PgConnection,
    id: Uuid,
    name: Option<&str>,
    price_cents: Option<i64>,
    open_to_join: Option<bool>,
    archived: Option<bool>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE pass_plans SET name = COALESCE($2, name), price_cents = COALESCE($3, price_cents),
             open_to_join = COALESCE($4, open_to_join),
             archived_at = CASE WHEN $5 IS NULL THEN archived_at WHEN $5 THEN COALESCE(archived_at, NOW()) ELSE NULL END
         WHERE id = $1",
    )
    .bind(id)
    .bind(name)
    .bind(price_cents)
    .bind(open_to_join)
    .bind(archived)
    .execute(conn)
    .await?;
    Ok(())
}

// MARK: pass holders

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct Holder {
    pub id: Uuid,
    pub plan_id: Uuid,
    pub club_id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub started_on: NaiveDate,
    pub ends_on: Option<NaiveDate>,
    pub cancelled_at: Option<DateTime<Utc>>,
    pub keep_covering: bool,
    pub told_standing: String,
    pub created_at: DateTime<Utc>,
}

const HOLDER_SELECT: &str = "SELECT h.id, h.plan_id, h.club_id, h.user_id, u.name, h.started_on, h.ends_on, \
    h.cancelled_at, h.keep_covering, h.told_standing, h.created_at \
    FROM pass_holders h JOIN users u ON u.id = h.user_id";

pub async fn holder(pool: &PgPool, id: Uuid) -> Result<Option<Holder>, sqlx::Error> {
    sqlx::query_as::<_, Holder>(&format!("{HOLDER_SELECT} WHERE h.id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

pub async fn plan_holders(pool: &PgPool, plan_id: Uuid) -> Result<Vec<Holder>, sqlx::Error> {
    sqlx::query_as::<_, Holder>(&format!(
        "{HOLDER_SELECT} WHERE h.plan_id = $1 ORDER BY h.cancelled_at NULLS FIRST, lower(u.name)"
    ))
    .bind(plan_id)
    .fetch_all(pool)
    .await
}

/// Every pass a member holds or held at a club.
pub async fn member_holders(pool: &PgPool, club_id: Uuid, user_id: Uuid) -> Result<Vec<Holder>, sqlx::Error> {
    sqlx::query_as::<_, Holder>(&format!(
        "{HOLDER_SELECT} WHERE h.club_id = $1 AND h.user_id = $2 ORDER BY h.created_at DESC"
    ))
    .bind(club_id)
    .bind(user_id)
    .fetch_all(pool)
    .await
}

/// Passes still running (not cancelled, or cancelled but not yet ended),
/// across a club. The scheduler's starting point.
pub async fn running_holders(pool: &PgPool) -> Result<Vec<Holder>, sqlx::Error> {
    sqlx::query_as::<_, Holder>(&format!(
        "{HOLDER_SELECT} WHERE h.ends_on IS NULL OR h.ends_on >= CURRENT_DATE LIMIT 5000"
    ))
    .fetch_all(pool)
    .await
}

pub async fn add_holder(
    conn: &mut PgConnection,
    plan: &PassPlan,
    user_id: Uuid,
    started_on: NaiveDate,
    by: Uuid,
) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar(
        "INSERT INTO pass_holders (plan_id, club_id, user_id, started_on, created_by) VALUES ($1, $2, $3, $4, $5)
         RETURNING id",
    )
    .bind(plan.id)
    .bind(plan.club_id)
    .bind(user_id)
    .bind(started_on)
    .bind(by)
    .fetch_one(conn)
    .await
}

/// Cancelled: it covers up to and including `ends_on`, and isn't charged after.
pub async fn cancel_holder(conn: &mut PgConnection, id: Uuid, ends_on: NaiveDate) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE pass_holders SET cancelled_at = NOW(), ends_on = $2 WHERE id = $1 AND cancelled_at IS NULL",
    )
    .bind(id)
    .bind(ends_on)
    .execute(conn)
    .await?
    .rows_affected()
        == 1)
}

pub async fn set_keep_covering(conn: &mut PgConnection, id: Uuid, on: bool) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE pass_holders SET keep_covering = $2 WHERE id = $1").bind(id).bind(on).execute(conn).await?;
    Ok(())
}

/// Record what the holder has been told; `false` when somebody else already did.
pub async fn set_told_standing(pool: &PgPool, id: Uuid, from: &str, to: &str) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query("UPDATE pass_holders SET told_standing = $3 WHERE id = $1 AND told_standing = $2")
        .bind(id)
        .bind(from)
        .bind(to)
        .execute(pool)
        .await?
        .rows_affected()
        == 1)
}

/// What a bundle says when a bill brings it down to its last session or
/// uses it up; nothing otherwise.
pub fn sessions_left_notice(plan_name: &str, left: i64) -> Option<(String, &'static str)> {
    match left {
        1 => Some((format!("1 session left on your {plan_name}"), "Get another from the club's pay screen when it runs out.")),
        0 => Some((
            format!("Your {plan_name} is used up"),
            "Your next sessions are paid as usual. Get another from the club's pay screen.",
        )),
        _ => None,
    }
}

/// Passes running at a club that are a payment behind or paused, as the
/// scheduler last found them.
pub async fn passes_behind(pool: &PgPool, club_id: Uuid) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT COUNT(*) FROM pass_holders WHERE club_id = $1 AND told_standing <> 'up_to_date'
           AND (ends_on IS NULL OR ends_on >= CURRENT_DATE)",
    )
    .bind(club_id)
    .fetch_one(pool)
    .await
}

/// Monthly passes still being paid at a club: whoever has a standing order.
pub async fn standing_orders(pool: &PgPool, club_id: Uuid) -> Result<Vec<Holder>, sqlx::Error> {
    sqlx::query_as::<_, Holder>(&format!(
        "{HOLDER_SELECT} JOIN pass_plans p ON p.id = h.plan_id
         WHERE h.club_id = $1 AND h.cancelled_at IS NULL AND p.billing = 'monthly'"
    ))
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// Sessions a holder's pass has covered on bills still standing.
pub async fn sessions_used(pool: &PgPool, holder_id: Uuid, except_event: Option<Uuid>) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT COUNT(*) FROM bill_shares s JOIN event_bills b ON b.id = s.bill_id
         WHERE s.covered_by = $1 AND s.status = 'covered' AND b.status = 'issued'
           AND ($2::uuid IS NULL OR b.event_id IS DISTINCT FROM $2)",
    )
    .bind(holder_id)
    .bind(except_event)
    .fetch_one(pool)
    .await
}

// MARK: a pass holder's charges

/// The title on a pass charge: "Winter nets pass", "Monthly nets — December
/// 2026", "Season membership — part 2 of 3".
pub fn charge_title(plan: &PassPlan, period: NaiveDate, part: usize) -> String {
    match plan.billing() {
        PassBilling::Once => plan.name.clone(),
        PassBilling::Monthly => format!("{} — {}", plan.name, period.format("%B %Y")),
        PassBilling::Instalments => format!("{} — part {part} of {}", plan.name, plan.instalments.unwrap_or(1)),
    }
}

/// One charge for a pass: a bill of kind `pass` with the holder's one share.
/// Charging the same month twice does nothing (unique per holder and month).
#[allow(clippy::too_many_arguments)]
pub async fn charge_pass(
    conn: &mut PgConnection,
    plan: &PassPlan,
    holder: &Holder,
    period_start: NaiveDate,
    title: &str,
    amount_cents: i64,
    payout_account_id: Option<Uuid>,
) -> Result<Option<Uuid>, sqlx::Error> {
    let due_on = period_start + chrono::Duration::days(money::PASS_GRACE_DAYS);
    let bill: Option<Uuid> = sqlx::query_scalar(
        "INSERT INTO event_bills (event_id, club_id, title, event_start_at, mode, amount_cents, total_cents, currency,
             payout_account_id, kind, pass_holder_id, period_start, due_on, auto)
         VALUES (NULL, $1, $2, $3::date::timestamptz, 'per_player', $4, $4, $5, $6, 'pass', $7, $3, $8, TRUE)
         ON CONFLICT (pass_holder_id, period_start) WHERE kind = 'pass' AND status = 'issued' DO NOTHING
         RETURNING id",
    )
    .bind(plan.club_id)
    .bind(title)
    .bind(period_start)
    .bind(amount_cents)
    .bind(&plan.currency)
    .bind(payout_account_id)
    .bind(holder.id)
    .bind(due_on)
    .fetch_optional(&mut *conn)
    .await?;
    let Some(bill) = bill else { return Ok(None) };
    sqlx::query(
        "INSERT INTO bill_shares (bill_id, club_id, user_id, name, amount_cents) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(bill)
    .bind(plan.club_id)
    .bind(holder.user_id)
    .bind(&holder.name)
    .bind(amount_cents)
    .execute(conn)
    .await?;
    Ok(Some(bill))
}

/// How far behind a holder is: charges for this pass unpaid past their due
/// day, matched against the member's whole ledger oldest first.
pub async fn overdue_charges(pool: &PgPool, holder: &Holder, today: NaiveDate) -> Result<usize, sqlx::Error> {
    let (shares, payments) = payments::ledger(pool, holder.club_id, Some(holder.user_id)).await?;
    let mine: Vec<LedgerShare> = shares.iter().map(|s| s.ledger()).collect();
    let paid: Vec<_> = payments.iter().filter(|p| p.payer() == Payer::Member(holder.user_id)).map(|p| p.ledger()).collect();
    let settled = money::settle(&mine, &paid);
    let holder_bills: Vec<(Uuid, Option<NaiveDate>)> = sqlx::query_as(
        "SELECT id, due_on FROM event_bills WHERE pass_holder_id = $1 AND kind = 'pass' AND status = 'issued'",
    )
    .bind(holder.id)
    .fetch_all(pool)
    .await?;
    Ok(shares
        .iter()
        .filter(|s| holder_bills.iter().any(|(b, due)| *b == s.bill_id && due.is_some_and(|d| d < today)))
        .filter(|s| settled.shares.get(&s.id).is_some_and(|p| p.paid_cents < s.amount_cents))
        .count())
}

/// Charges for this pass nobody has paid or said they've paid, due or not.
pub async fn unpaid_charges(pool: &PgPool, holder: &Holder) -> Result<usize, sqlx::Error> {
    let (shares, payments) = payments::ledger(pool, holder.club_id, Some(holder.user_id)).await?;
    let mine: Vec<LedgerShare> = shares.iter().map(|s| s.ledger()).collect();
    let paid: Vec<_> = payments.iter().filter(|p| p.payer() == Payer::Member(holder.user_id)).map(|p| p.ledger()).collect();
    let settled = money::settle(&mine, &paid);
    let bills: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM event_bills WHERE pass_holder_id = $1 AND kind = 'pass' AND status = 'issued'",
    )
    .bind(holder.id)
    .fetch_all(pool)
    .await?;
    Ok(shares
        .iter()
        .filter(|s| bills.contains(&s.bill_id))
        .filter(|s| settled.shares.get(&s.id).is_some_and(|p| p.paid_cents + p.waiting_cents < s.amount_cents))
        .count())
}

/// Where a holder stands, from the plan's billing and how far behind they are.
pub async fn standing(pool: &PgPool, plan: &PassPlan, holder: &Holder, today: NaiveDate) -> Result<PassStanding, sqlx::Error> {
    let overdue = overdue_charges(pool, holder, today).await?;
    Ok(money::pass_standing(plan.billing(), overdue, holder.keep_covering))
}

// MARK: who a session's bill covers

/// The session as coverage needs it.
pub struct SessionFacts {
    pub club_id: Uuid,
    pub event_id: Option<Uuid>,
    pub subtype: String,
    pub team_id: Option<Uuid>,
    pub day: NaiveDate,
}

/// For each of `users`, the pass that covers this session, if any: running on
/// the day, covering this kind of session (and team, where the plan names
/// one), with sessions left on a bundle, and not suspended for being behind.
/// When a member holds two that would, the first one made is used.
pub async fn coverage(
    pool: &PgPool,
    session: &SessionFacts,
    users: &[Uuid],
) -> Result<HashMap<Uuid, (Uuid, String)>, sqlx::Error> {
    if users.is_empty() {
        return Ok(HashMap::new());
    }
    let rows: Vec<(Uuid, Uuid)> = sqlx::query_as(
        "SELECT h.id, h.user_id FROM pass_holders h JOIN pass_plans p ON p.id = h.plan_id
         WHERE h.club_id = $1 AND h.user_id = ANY($2)
           AND $3 = ANY(p.covers)
           AND (p.team_id IS NULL OR p.team_id IS NOT DISTINCT FROM $4)
           AND h.started_on <= $5
           AND (h.ends_on IS NULL OR h.ends_on >= $5)
           AND (p.valid_until IS NULL OR p.valid_until >= $5)
         ORDER BY h.created_at",
    )
    .bind(session.club_id)
    .bind(users)
    .bind(&session.subtype)
    .bind(session.team_id)
    .bind(session.day)
    .fetch_all(pool)
    .await?;
    let mut out: HashMap<Uuid, (Uuid, String)> = HashMap::new();
    for (holder_id, user) in rows {
        if out.contains_key(&user) {
            continue;
        }
        let Some(h) = holder(pool, holder_id).await? else { continue };
        let Some(plan) = plan(pool, h.plan_id).await? else { continue };
        if let Some(limit) = plan.sessions {
            if sessions_used(pool, h.id, session.event_id).await? >= i64::from(limit) {
                continue;
            }
        }
        if standing(pool, &plan, &h, session.day).await? == PassStanding::Suspended {
            continue;
        }
        out.insert(user, (h.id, plan.name.clone()));
    }
    Ok(out)
}

// MARK: group fees

/// Members for a group fee: the whole club, one team, one price type, or a
/// list — active members only, with their names.
pub async fn members_for(
    pool: &PgPool,
    club_id: Uuid,
    team_id: Option<Uuid>,
    price_type_id: Option<Uuid>,
    user_ids: Option<&[Uuid]>,
) -> Result<Vec<(Uuid, String)>, sqlx::Error> {
    sqlx::query_as(
        "SELECT m.user_id, u.name FROM club_members m JOIN users u ON u.id = m.user_id
         WHERE m.club_id = $1 AND m.status = 'active'
           AND ($2::uuid IS NULL OR EXISTS (SELECT 1 FROM team_members t WHERE t.team_id = $2 AND t.user_id = m.user_id))
           AND ($3::uuid IS NULL OR m.price_type_id = $3)
           AND ($4::uuid[] IS NULL OR m.user_id = ANY($4))
         ORDER BY lower(u.name), m.user_id",
    )
    .bind(club_id)
    .bind(team_id)
    .bind(price_type_id)
    .bind(user_ids)
    .fetch_all(pool)
    .await
}

/// Group fees, newest first.
pub async fn collections(pool: &PgPool, club_id: Uuid, limit: i64) -> Result<Vec<payments::BillRow>, sqlx::Error> {
    let ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM event_bills WHERE club_id = $1 AND kind = 'collection' ORDER BY issued_at DESC LIMIT $2",
    )
    .bind(club_id)
    .bind(limit.clamp(1, 200))
    .fetch_all(pool)
    .await?;
    let mut out = Vec::new();
    for id in ids {
        if let Some(b) = payments::bill_by_id(pool, id).await? {
            out.push(b);
        }
    }
    Ok(out)
}

pub struct NewCollection<'a> {
    pub club_id: Uuid,
    pub title: &'a str,
    pub mode: money::CostMode,
    pub amount_cents: i64,
    pub currency: &'a str,
    pub due_on: Option<NaiveDate>,
    pub note: Option<&'a str>,
    pub people: Vec<payments::Attendee>,
    pub payout_account_id: Option<Uuid>,
    pub by: Uuid,
}

#[derive(Debug)]
pub enum CollectionError {
    Split(money::SplitError),
    Db(sqlx::Error),
}

/// A group fee: a bill of kind `collection` and a share for each person.
pub async fn create_collection(
    conn: &mut PgConnection,
    c: &NewCollection<'_>,
) -> Result<(payments::BillRow, Vec<(Uuid, i64)>), CollectionError> {
    let split =
        money::split(c.mode, c.amount_cents, c.people.len(), money::Rounding::Exact).map_err(CollectionError::Split)?;
    let result: Result<_, sqlx::Error> = async {
        let id: Uuid = sqlx::query_scalar(
            "INSERT INTO event_bills (event_id, club_id, title, event_start_at, mode, amount_cents, total_cents, currency,
                 payout_account_id, kind, due_on, note, issued_by)
             VALUES (NULL, $1, $2, NOW(), $3, $4, $5, $6, $7, 'collection', $8, $9, $10) RETURNING id",
        )
        .bind(c.club_id)
        .bind(c.title)
        .bind(c.mode.as_str())
        .bind(c.amount_cents)
        .bind(split.total_cents)
        .bind(c.currency)
        .bind(c.payout_account_id)
        .bind(c.due_on)
        .bind(c.note)
        .bind(c.by)
        .fetch_one(&mut *conn)
        .await?;
        let mut told = Vec::new();
        for (person, amount) in c.people.iter().zip(&split.shares) {
            sqlx::query(
                "INSERT INTO bill_shares (bill_id, club_id, user_id, guest_name, name, amount_cents)
                 VALUES ($1, $2, $3, $4, $5, $6)",
            )
            .bind(id)
            .bind(c.club_id)
            .bind(person.user_id)
            .bind(person.user_id.is_none().then_some(person.name.as_str()))
            .bind(&person.name)
            .bind(amount)
            .execute(&mut *conn)
            .await?;
            if let Some(u) = person.user_id {
                told.push((u, *amount));
            }
        }
        let bill = sqlx::query_as::<_, payments::BillRow>(&format!(
            "SELECT {} FROM event_bills WHERE id = $1",
            "id, event_id, club_id, title, event_start_at, mode, amount_cents, total_cents, currency, \
             rounding, payout_account_id, status, version, auto, note, issued_by, issued_at, updated_at, voided_at, \
             void_reason, kind, pass_holder_id, period_start, due_on"
        ))
        .bind(id)
        .fetch_one(&mut *conn)
        .await?;
        Ok((bill, told))
    }
    .await;
    result.map_err(CollectionError::Db)
}

/// Cancel any bill by id (a group fee, a pass charge). Its shares go with it;
/// anything paid becomes credit.
pub async fn void_bill_by_id(conn: &mut PgConnection, bill_id: Uuid, by: Uuid, reason: &str) -> Result<bool, sqlx::Error> {
    let done = sqlx::query(
        "UPDATE event_bills SET status = 'void', voided_at = NOW(), voided_by = $2, void_reason = $3, updated_at = NOW()
         WHERE id = $1 AND status = 'issued'",
    )
    .bind(bill_id)
    .bind(by)
    .bind(reason)
    .execute(&mut *conn)
    .await?
    .rows_affected()
        == 1;
    if done {
        sqlx::query(
            "UPDATE bill_shares SET status = 'void', reason = $2, decided_by = $3, decided_at = NOW()
             WHERE bill_id = $1 AND status IN ('live', 'covered')",
        )
        .bind(bill_id)
        .bind(reason)
        .bind(by)
        .execute(conn)
        .await?;
    }
    Ok(done)
}

// MARK: paying for others

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct Dependent {
    pub club_id: Uuid,
    pub member_id: Uuid,
    pub name: String,
    pub managed: bool,
}

/// The members this person pays for, in every club.
pub async fn dependents(pool: &PgPool, payer_id: Uuid) -> Result<Vec<Dependent>, sqlx::Error> {
    sqlx::query_as::<_, Dependent>(
        "SELECT p.club_id, p.member_id, u.name, (u.managed_by IS NOT NULL) AS managed
         FROM club_payers p JOIN users u ON u.id = p.member_id
         -- Both still in the club: leaving it ends paying for (and seeing) anyone.
         JOIN club_members pm ON pm.club_id = p.club_id AND pm.user_id = p.payer_id AND pm.status = 'active'
         JOIN club_members mm ON mm.club_id = p.club_id AND mm.user_id = p.member_id AND mm.status = 'active'
         WHERE p.payer_id = $1 AND u.deleted_at IS NULL ORDER BY lower(u.name)",
    )
    .bind(payer_id)
    .fetch_all(pool)
    .await
}

pub async fn payer_of(pool: &PgPool, club_id: Uuid, member_id: Uuid) -> Result<Option<Uuid>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT p.payer_id FROM club_payers p
         JOIN club_members pm ON pm.club_id = p.club_id AND pm.user_id = p.payer_id AND pm.status = 'active'
         WHERE p.club_id = $1 AND p.member_id = $2",
    )
        .bind(club_id)
        .bind(member_id)
        .fetch_optional(pool)
        .await
}

pub async fn set_payer(
    conn: &mut PgConnection,
    club_id: Uuid,
    member_id: Uuid,
    payer_id: Option<Uuid>,
    by: Uuid,
) -> Result<(), sqlx::Error> {
    match payer_id {
        Some(payer) => {
            sqlx::query(
                "INSERT INTO club_payers (club_id, member_id, payer_id, created_by) VALUES ($1, $2, $3, $4)
                 ON CONFLICT (club_id, member_id) DO UPDATE SET payer_id = EXCLUDED.payer_id,
                     created_by = EXCLUDED.created_by, created_at = NOW()",
            )
            .bind(club_id)
            .bind(member_id)
            .bind(payer)
            .bind(by)
            .execute(conn)
            .await?;
        }
        None => {
            sqlx::query("DELETE FROM club_payers WHERE club_id = $1 AND member_id = $2")
                .bind(club_id)
                .bind(member_id)
                .execute(conn)
                .await?;
        }
    }
    Ok(())
}

/// A member with no sign-in of their own — a young junior — added by name,
/// looked after by `managed_by`, who pays for them. They have no email, phone
/// or password, so nobody can sign in as them.
pub async fn add_managed_member(
    conn: &mut PgConnection,
    club_id: Uuid,
    name: &str,
    managed_by: Uuid,
    by: Uuid,
) -> Result<Uuid, sqlx::Error> {
    let user: Uuid = sqlx::query_scalar("INSERT INTO users (name, managed_by) VALUES ($1, $2) RETURNING id")
        .bind(name)
        .bind(managed_by)
        .fetch_one(&mut *conn)
        .await?;
    sqlx::query("INSERT INTO club_members (club_id, user_id, role, status) VALUES ($1, $2, 'member', 'active')")
        .bind(club_id)
        .bind(user)
        .execute(&mut *conn)
        .await?;
    set_payer(conn, club_id, user, Some(managed_by), by).await?;
    Ok(user)
}

// MARK: pricing a bill

/// Price everybody on a session's bill and mark who owes nothing: a pass
/// that covers it first, then a free price type, then — for a per-player
/// cost — the session's own price for their price type. People with no account
/// are priced as the club's guest type, where it has one. The one place this
/// is decided, for a bill sent by hand and by the scheduler alike.
pub async fn priced(
    pool: &PgPool,
    session: &SessionFacts,
    mode: money::CostMode,
    people: Vec<payments::Attendee>,
) -> Result<Vec<payments::Attendee>, sqlx::Error> {
    let types: HashMap<Uuid, PriceType> =
        price_types(pool, session.club_id).await?.into_iter().map(|t| (t.id, t)).collect();
    let member_types = member_price_types(pool, session.club_id).await?;
    let prices = match session.event_id {
        Some(e) => event_prices(pool, e).await?,
        None => HashMap::new(),
    };
    let guest_type = types.values().find(|t| t.for_guests && t.archived_at.is_none()).map(|t| t.id);
    let users: Vec<Uuid> = people.iter().filter_map(|p| p.user_id).collect();
    let passes = coverage(pool, session, &users).await?;
    Ok(people
        .into_iter()
        .map(|mut p| {
            let type_id = match p.user_id {
                Some(u) => member_types.get(&u).copied(),
                None => guest_type,
            };
            let ptype = type_id.and_then(|id| types.get(&id));
            if let Some((holder_id, plan_name)) = p.user_id.and_then(|u| passes.get(&u)) {
                p.cover = Some(payments::Cover::Pass { holder_id: *holder_id, plan_name: plan_name.clone() });
            } else if let Some(t) = ptype.filter(|t| t.free) {
                p.cover = Some(payments::Cover::Free { price_type: t.name.clone() });
            } else if mode == money::CostMode::PerPlayer {
                if let Some((t, price)) = ptype.and_then(|t| prices.get(&t.id).map(|price| (t, *price))) {
                    if price == 0 {
                        p.cover = Some(payments::Cover::Free { price_type: t.name.clone() });
                    } else {
                        p.amount_cents = Some(price);
                    }
                }
            }
            p
        })
        .collect())
}
