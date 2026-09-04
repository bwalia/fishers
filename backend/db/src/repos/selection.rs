use chrono::{DateTime, Duration, Utc};
use fishers_domain::{
    AvailabilityStatus, Candidate, EventStatus, SelectionState, SquadRequirements,
};
use sqlx::PgPool;
use uuid::Uuid;

/// Per-club policy: how long before a fixture players are asked to reconfirm,
/// when the unconfirmed are dropped, and how much the assistant may do alone.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct SelectionPolicy {
    pub selection_autonomy: String,
    pub confirm_lead_hours: i32,
    pub drop_lead_hours: i32,
    pub fee_chase_after_hours: i32,
    pub fee_chase_max_reminders: i32,
}

pub async fn policy_for_club(pool: &PgPool, club_id: Uuid) -> Result<SelectionPolicy, sqlx::Error> {
    sqlx::query_as::<_, SelectionPolicy>(
        "SELECT selection_autonomy, confirm_lead_hours, drop_lead_hours,
                fee_chase_after_hours, fee_chase_max_reminders
         FROM clubs WHERE id = $1",
    )
    .bind(club_id)
    .fetch_one(pool)
    .await
}

#[derive(Debug, Clone, sqlx::FromRow)]
struct CandidateRow {
    user_id: Uuid,
    name: String,
    position_role: Option<String>,
    skill_level: Option<String>,
    availability: Option<String>,
    selection_state: Option<String>,
    is_confirmed: Option<bool>,
    invites_received: i64,
    responded: i64,
    said_going: i64,
    turned_up: i64,
    late_cancellations: i64,
    fees_due: i64,
    fees_paid: i64,
    games_missed_out: i64,
}

/// Everyone eligible for a fixture, with the signals selection weighs.
pub async fn candidates(pool: &PgPool, event_id: Uuid) -> Result<Vec<Candidate>, sqlx::Error> {
    let rows = sqlx::query_as::<_, CandidateRow>(
        "SELECT user_id, name, position_role, skill_level, availability, selection_state,
                is_confirmed, invites_received, responded, said_going, turned_up,
                late_cancellations, fees_due, fees_paid, games_missed_out
         FROM selection_candidates WHERE event_id = $1 ORDER BY name",
    )
    .bind(event_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|row| {
            let score = fishers_domain::reliability::score(
                fishers_domain::reliability::ReliabilityCounts {
                    invites_received: row.invites_received,
                    responded: row.responded,
                    said_going: row.said_going,
                    turned_up: row.turned_up,
                    late_cancellations: row.late_cancellations,
                    fees_due: row.fees_due,
                    fees_paid: row.fees_paid,
                },
            );
            Candidate {
                user_id: row.user_id,
                name: row.name,
                position: row.position_role,
                skill_level: row.skill_level,
                availability: row.availability.as_deref().and_then(|s| match s {
                    "available" => Some(AvailabilityStatus::Available),
                    "unavailable" => Some(AvailabilityStatus::Unavailable),
                    "maybe" => Some(AvailabilityStatus::Maybe),
                    _ => None,
                }),
                reliability_score: score.score,
                reliability_band: serde_json::to_value(score.band)
                    .ok()
                    .and_then(|v| v.as_str().map(str::to_owned))
                    .unwrap_or_else(|| "unproven".into()),
                games_missed_out: row.games_missed_out,
                state: row
                    .selection_state
                    .as_deref()
                    .and_then(SelectionState::from_str)
                    .unwrap_or(SelectionState::Pool),
                is_confirmed: row.is_confirmed.unwrap_or(false),
            }
        })
        .collect())
}

/// Requirements for a fixture, from its sport and capacity.
pub async fn requirements_for(
    pool: &PgPool,
    event_id: Uuid,
) -> Result<SquadRequirements, sqlx::Error> {
    let row: (String, Option<i32>) =
        sqlx::query_as("SELECT sport::TEXT, capacity FROM events WHERE id = $1")
            .bind(event_id)
            .fetch_one(pool)
            .await?;
    Ok(SquadRequirements::for_sport(&row.0, row.1))
}

/// Write a decided squad. Selected players get a reconfirmation deadline;
/// everyone previously in the side who is no longer picked drops back out.
pub async fn set_squad(
    pool: &PgPool,
    event_id: Uuid,
    decided_by: Uuid,
    selected: &[Uuid],
    reserves: &[Uuid],
    by_agent: bool,
    confirm_lead_hours: i32,
) -> Result<(), sqlx::Error> {
    let mut tx = pool.begin().await?;

    let start_at: (DateTime<Utc>,) = sqlx::query_as("SELECT start_at FROM events WHERE id = $1")
        .bind(event_id)
        .fetch_one(&mut *tx)
        .await?;
    let confirm_deadline = start_at.0 - Duration::hours(confirm_lead_hours.max(0) as i64);

    // Anyone dropped from the side goes back to not_selected, keeping their RSVP.
    sqlx::query(
        "UPDATE event_invites
         SET selection_state = 'not_selected', selection_rank = NULL
         WHERE event_id = $1
           AND selection_state IN ('selected', 'reserve')
           AND NOT (user_id = ANY($2)) AND NOT (user_id = ANY($3))",
    )
    .bind(event_id)
    .bind(selected)
    .bind(reserves)
    .execute(&mut *tx)
    .await?;

    for (index, user_id) in selected.iter().enumerate() {
        upsert_selection(
            &mut tx,
            event_id,
            *user_id,
            decided_by,
            "selected",
            (index + 1) as i32,
            Some(confirm_deadline),
            by_agent,
        )
        .await?;
    }
    for (index, user_id) in reserves.iter().enumerate() {
        upsert_selection(
            &mut tx,
            event_id,
            *user_id,
            decided_by,
            "reserve",
            (index + 1) as i32,
            None,
            by_agent,
        )
        .await?;
    }

    tx.commit().await
}

#[allow(clippy::too_many_arguments)]
async fn upsert_selection(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    event_id: Uuid,
    user_id: Uuid,
    decided_by: Uuid,
    state: &str,
    rank: i32,
    confirm_deadline: Option<DateTime<Utc>>,
    by_agent: bool,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO event_invites (event_id, user_id, invited_by, status, selection_state,
                                    selection_rank, selected_at, selected_by, confirm_deadline,
                                    selected_by_agent)
         VALUES ($1, $2, $3, 'invited', $4, $5, NOW(), $3, $6, $7)
         ON CONFLICT (event_id, user_id) DO UPDATE SET
             selection_state = EXCLUDED.selection_state,
             selection_rank = EXCLUDED.selection_rank,
             selected_at = NOW(),
             selected_by = EXCLUDED.selected_by,
             confirm_deadline = EXCLUDED.confirm_deadline,
             selected_by_agent = EXCLUDED.selected_by_agent",
    )
    .bind(event_id)
    .bind(user_id)
    .bind(decided_by)
    .bind(state)
    .bind(rank)
    .bind(confirm_deadline)
    .bind(by_agent)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// A player's own answer to being picked. Declining inside the drop window is
/// recorded as a late cancellation, which is what reliability reads.
pub async fn respond(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
    confirming: bool,
    drop_lead_hours: i32,
) -> Result<(), sqlx::Error> {
    if confirming {
        sqlx::query(
            "UPDATE event_invites
             SET selection_state = 'confirmed', status = 'going',
                 confirmed_at = NOW(), responded_at = NOW(), declined_at = NULL
             WHERE event_id = $1 AND user_id = $2",
        )
        .bind(event_id)
        .bind(user_id)
        .execute(pool)
        .await?;
    } else {
        sqlx::query(
            "UPDATE event_invites i
             SET selection_state = 'declined', status = 'not_going',
                 declined_at = NOW(), responded_at = NOW(),
                 cancelled_at = CASE
                     WHEN i.selection_state IN ('selected', 'confirmed')
                      AND e.start_at - ($3 || ' hours')::INTERVAL < NOW()
                     THEN NOW() ELSE i.cancelled_at
                 END
             FROM events e
             WHERE i.event_id = $1 AND i.user_id = $2 AND e.id = i.event_id",
        )
        .bind(event_id)
        .bind(user_id)
        .bind(drop_lead_hours.to_string())
        .execute(pool)
        .await?;
    }
    Ok(())
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct PromotionRow {
    pub user_id: Uuid,
    pub name: String,
}

/// Fill empty places from the reserve list, in the captain's order. Returns who
/// moved up so they can be told.
pub async fn promote_reserves(
    pool: &PgPool,
    event_id: Uuid,
    confirm_lead_hours: i32,
) -> Result<Vec<PromotionRow>, sqlx::Error> {
    let mut tx = pool.begin().await?;

    let counts: (i64, Option<i32>, DateTime<Utc>) = sqlx::query_as(
        "SELECT (SELECT COUNT(*) FROM event_invites
                 WHERE event_id = $1 AND selection_state IN ('selected', 'confirmed')),
                e.capacity, e.start_at
         FROM events e WHERE e.id = $1",
    )
    .bind(event_id)
    .fetch_one(&mut *tx)
    .await?;

    let target = counts.1.unwrap_or(11).max(0) as i64;
    let gaps = (target - counts.0).max(0);
    if gaps == 0 {
        tx.commit().await?;
        return Ok(Vec::new());
    }

    let confirm_deadline = counts.2 - Duration::hours(confirm_lead_hours.max(0) as i64);
    let promoted = sqlx::query_as::<_, PromotionRow>(
        "WITH next_up AS (
             SELECT i.user_id FROM event_invites i
             WHERE i.event_id = $1 AND i.selection_state = 'reserve'
             ORDER BY i.selection_rank NULLS LAST, i.selected_at
             LIMIT $2
         )
         UPDATE event_invites i
         SET selection_state = 'selected', promoted_at = NOW(), confirm_deadline = $3
         FROM next_up, users u
         WHERE i.event_id = $1 AND i.user_id = next_up.user_id AND u.id = i.user_id
         RETURNING i.user_id, u.name",
    )
    .bind(event_id)
    .bind(gaps)
    .bind(confirm_deadline)
    .fetch_all(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(promoted)
}

/// Selected players who never confirmed by the deadline.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct UnconfirmedRow {
    pub event_id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub title: String,
    pub start_at: DateTime<Utc>,
    pub confirm_deadline: Option<DateTime<Utc>>,
    pub reminders_sent: i32,
    pub club_id: Uuid,
}

pub async fn unconfirmed_needing_reminder(
    pool: &PgPool,
) -> Result<Vec<UnconfirmedRow>, sqlx::Error> {
    sqlx::query_as::<_, UnconfirmedRow>(
        "SELECT i.event_id, i.user_id, u.name, e.title, e.start_at, i.confirm_deadline,
                i.reminders_sent, e.club_id
         FROM event_invites i
         JOIN events e ON e.id = i.event_id
         JOIN users u ON u.id = i.user_id
         WHERE i.selection_state = 'selected'
           AND e.status = 'scheduled'
           AND e.start_at > NOW()
           AND i.confirm_deadline IS NOT NULL
           AND NOW() >= i.confirm_deadline - INTERVAL '12 hours'
           AND i.reminders_sent < 2",
    )
    .fetch_all(pool)
    .await
}

pub async fn mark_reminded(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE event_invites SET reminders_sent = reminders_sent + 1
         WHERE event_id = $1 AND user_id = $2",
    )
    .bind(event_id)
    .bind(user_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Drop the still-unconfirmed once the drop deadline passes. Returns the
/// fixtures touched so reserves can be promoted and told.
pub async fn drop_unconfirmed(pool: &PgPool) -> Result<Vec<Uuid>, sqlx::Error> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        "UPDATE event_invites i
         SET selection_state = 'dropped'
         FROM events e, clubs c
         WHERE i.event_id = e.id
           AND c.id = e.club_id
           AND i.selection_state = 'selected'
           AND e.status = 'scheduled'
           AND e.start_at > NOW()
           AND i.confirmed_at IS NULL
           AND NOW() >= e.start_at - (c.drop_lead_hours || ' hours')::INTERVAL
         RETURNING i.event_id",
    )
    .fetch_all(pool)
    .await?;

    let mut event_ids: Vec<Uuid> = rows.into_iter().map(|r| r.0).collect();
    event_ids.sort();
    event_ids.dedup();
    Ok(event_ids)
}

/// Rain stops play: change the fixture's status and record the reason the squad
/// needs to hear.
pub async fn update_fixture_status(
    pool: &PgPool,
    event_id: Uuid,
    status: EventStatus,
    note: Option<&str>,
    rescheduled_to: Option<DateTime<Utc>>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE events
         SET status = $2, status_note = $3, rescheduled_to = $4,
             status_changed_at = NOW(), updated_at = NOW()
         WHERE id = $1",
    )
    .bind(event_id)
    .bind(status)
    .bind(note)
    .bind(rescheduled_to)
    .execute(pool)
    .await?;
    Ok(())
}

/// Squad members to notify about a fixture change.
pub async fn squad_user_ids(pool: &PgPool, event_id: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT user_id FROM event_invites
         WHERE event_id = $1
           AND selection_state IN ('selected', 'confirmed', 'reserve')",
    )
    .bind(event_id)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.0).collect())
}

// MARK: match fees

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OutstandingFeeRow {
    pub event_id: Uuid,
    pub club_id: Uuid,
    pub title: String,
    pub start_at: DateTime<Utc>,
    pub fee_amount_cents: Option<i32>,
    pub fee_currency: String,
    pub user_id: Uuid,
    pub name: String,
    pub email: String,
    pub fee_reminders_sent: i32,
    pub last_fee_reminder_at: Option<DateTime<Utc>>,
}

/// Unpaid match fees for a club, newest fixture first.
pub async fn outstanding_fees(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<OutstandingFeeRow>, sqlx::Error> {
    sqlx::query_as::<_, OutstandingFeeRow>(
        "SELECT * FROM outstanding_match_fees WHERE club_id = $1 ORDER BY start_at DESC, name",
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// Fees due a chase: the fixture has been played, the grace period has passed,
/// and we haven't nagged them today or hit the cap.
pub async fn fees_due_chasing(pool: &PgPool) -> Result<Vec<OutstandingFeeRow>, sqlx::Error> {
    sqlx::query_as::<_, OutstandingFeeRow>(
        "SELECT f.* FROM outstanding_match_fees f
         JOIN clubs c ON c.id = f.club_id
         WHERE f.start_at < NOW() - (c.fee_chase_after_hours || ' hours')::INTERVAL
           AND f.fee_reminders_sent < c.fee_chase_max_reminders
           AND (f.last_fee_reminder_at IS NULL
                OR f.last_fee_reminder_at < NOW() - INTERVAL '24 hours')
         ORDER BY f.start_at",
    )
    .fetch_all(pool)
    .await
}

pub async fn mark_fee_reminded(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE event_invites
         SET fee_reminders_sent = fee_reminders_sent + 1, last_fee_reminder_at = NOW()
         WHERE event_id = $1 AND user_id = $2",
    )
    .bind(event_id)
    .bind(user_id)
    .execute(pool)
    .await?;
    Ok(())
}
