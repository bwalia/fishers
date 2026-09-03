use crate::rows::{AttendeeRow, EventRow};
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

const EVENT_COLS: &str = "id, club_id, team_id, sport, event_subtype, title, description, venue_id, \
     start_at, end_at, recurrence_rule, recurrence_parent_id, capacity, fee_amount, currency, \
     status, nets_lanes, nets_max_per_lane, nets_bowling_machine, created_by, created_at";

pub struct NewEvent<'a> {
    pub club_id: Uuid,
    pub team_id: Option<Uuid>,
    pub sport: &'a str,
    pub event_subtype: &'a str,
    pub title: &'a str,
    pub description: Option<&'a str>,
    pub venue_id: Option<Uuid>,
    pub start_at: DateTime<Utc>,
    pub end_at: DateTime<Utc>,
    pub recurrence_rule: Option<&'a str>,
    pub capacity: Option<i32>,
    pub fee_amount: Option<i64>,
    pub currency: &'a str,
    pub nets_lanes: Option<i32>,
    pub nets_max_per_lane: Option<i32>,
    pub nets_bowling_machine: Option<bool>,
    pub created_by: Uuid,
}

pub async fn create(pool: &PgPool, ev: &NewEvent<'_>) -> Result<EventRow, sqlx::Error> {
    sqlx::query_as::<_, EventRow>(&format!(
        "INSERT INTO events (club_id, team_id, sport, event_subtype, title, description, venue_id,
                             start_at, end_at, recurrence_rule, capacity, fee_amount, currency,
                             nets_lanes, nets_max_per_lane, nets_bowling_machine, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
         RETURNING {EVENT_COLS}"
    ))
    .bind(ev.club_id)
    .bind(ev.team_id)
    .bind(ev.sport)
    .bind(ev.event_subtype)
    .bind(ev.title)
    .bind(ev.description)
    .bind(ev.venue_id)
    .bind(ev.start_at)
    .bind(ev.end_at)
    .bind(ev.recurrence_rule)
    .bind(ev.capacity)
    .bind(ev.fee_amount)
    .bind(ev.currency)
    .bind(ev.nets_lanes)
    .bind(ev.nets_max_per_lane)
    .bind(ev.nets_bowling_machine)
    .bind(ev.created_by)
    .fetch_one(pool)
    .await
}

/// Events visible to `user_id` (member clubs only), with optional filters.
pub async fn list(
    pool: &PgPool,
    user_id: Uuid,
    club_id: Option<Uuid>,
    team_id: Option<Uuid>,
    from: Option<DateTime<Utc>>,
    to: Option<DateTime<Utc>>,
) -> Result<Vec<EventRow>, sqlx::Error> {
    sqlx::query_as::<_, EventRow>(&format!(
        "SELECT {EVENT_COLS} FROM events e
         WHERE (e.club_id IN (SELECT club_id FROM club_members
                              WHERE user_id = $1 AND status = 'active')
                OR e.id IN (SELECT event_id FROM event_invites WHERE user_id = $1))
           AND ($2::uuid IS NULL OR e.club_id = $2)
           AND ($3::uuid IS NULL OR e.team_id = $3)
           AND ($4::timestamptz IS NULL OR e.start_at >= $4)
           AND ($5::timestamptz IS NULL OR e.start_at <= $5)
         ORDER BY e.start_at
         LIMIT 500"
    ))
    .bind(user_id)
    .bind(club_id)
    .bind(team_id)
    .bind(from)
    .bind(to)
    .fetch_all(pool)
    .await
}

pub async fn find_by_id(pool: &PgPool, id: Uuid) -> Result<Option<EventRow>, sqlx::Error> {
    sqlx::query_as::<_, EventRow>(&format!("SELECT {EVENT_COLS} FROM events WHERE id = $1"))
        .bind(id)
        .fetch_optional(pool)
        .await
}

/// Upsert the caller's RSVP for an event.
pub async fn rsvp(
    pool: &PgPool,
    event_id: Uuid,
    user_id: Uuid,
    status: &str,
) -> Result<AttendeeRow, sqlx::Error> {
    sqlx::query(
        "INSERT INTO event_invites (event_id, user_id, invited_by, status, responded_at)
         VALUES ($1, $2, $2, $3, now())
         ON CONFLICT (event_id, user_id)
         DO UPDATE SET status = EXCLUDED.status, responded_at = now()",
    )
    .bind(event_id)
    .bind(user_id)
    .bind(status)
    .execute(pool)
    .await?;

    sqlx::query_as::<_, AttendeeRow>(&format!("{ATTENDEE_QUERY} AND ei.user_id = $2"))
        .bind(event_id)
        .bind(user_id)
        .fetch_one(pool)
        .await
}

const ATTENDEE_QUERY: &str = "SELECT ei.user_id, u.name, u.avatar_url, ei.status, ei.responded_at,
        EXISTS(SELECT 1 FROM payments p
               WHERE p.event_id = ei.event_id AND p.user_id = ei.user_id
                 AND p.status = 'succeeded') AS paid
     FROM event_invites ei
     JOIN users u ON u.id = ei.user_id
     WHERE ei.event_id = $1";

pub async fn attendees(pool: &PgPool, event_id: Uuid) -> Result<Vec<AttendeeRow>, sqlx::Error> {
    sqlx::query_as::<_, AttendeeRow>(&format!("{ATTENDEE_QUERY} ORDER BY ei.status, u.name"))
        .bind(event_id)
        .fetch_all(pool)
        .await
}

pub async fn count_going(pool: &PgPool, event_id: Uuid) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar::<_, i64>(
        "SELECT count(*) FROM event_invites WHERE event_id = $1 AND status = 'going'",
    )
    .bind(event_id)
    .fetch_one(pool)
    .await
}

/// True when the user has any RSVP/invite row for the event.
pub async fn has_invite(pool: &PgPool, event_id: Uuid, user_id: Uuid) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM event_invites WHERE event_id = $1 AND user_id = $2)",
    )
    .bind(event_id)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

// ---- recurring-event materialisation (jobs) ----

/// Recurrence templates: rule set, not themselves materialised instances.
pub async fn recurring_templates(pool: &PgPool) -> Result<Vec<EventRow>, sqlx::Error> {
    sqlx::query_as::<_, EventRow>(&format!(
        "SELECT {EVENT_COLS} FROM events
         WHERE recurrence_rule IS NOT NULL AND recurrence_parent_id IS NULL
           AND status = 'scheduled'"
    ))
    .fetch_all(pool)
    .await
}

/// Insert one materialised instance of a recurring template. Idempotent via
/// the (recurrence_parent_id, start_at) unique index.
pub async fn insert_instance(
    pool: &PgPool,
    template: &EventRow,
    start_at: DateTime<Utc>,
    end_at: DateTime<Utc>,
) -> Result<bool, sqlx::Error> {
    let res = sqlx::query(
        "INSERT INTO events (club_id, team_id, sport, event_subtype, title, description, venue_id,
                             start_at, end_at, recurrence_parent_id, capacity, fee_amount, currency,
                             nets_lanes, nets_max_per_lane, nets_bowling_machine, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
         ON CONFLICT (recurrence_parent_id, start_at) WHERE recurrence_parent_id IS NOT NULL
         DO NOTHING",
    )
    .bind(template.club_id)
    .bind(template.team_id)
    .bind(&template.sport)
    .bind(&template.event_subtype)
    .bind(&template.title)
    .bind(&template.description)
    .bind(template.venue_id)
    .bind(start_at)
    .bind(end_at)
    .bind(template.id)
    .bind(template.capacity)
    .bind(template.fee_amount)
    .bind(&template.currency)
    .bind(template.nets_lanes)
    .bind(template.nets_max_per_lane)
    .bind(template.nets_bowling_machine)
    .bind(template.created_by)
    .execute(pool)
    .await?;
    Ok(res.rows_affected() > 0)
}

// ---- reminder queries (jobs) ----

/// Scheduled events starting in (now, until].
pub async fn starting_before(
    pool: &PgPool,
    until: DateTime<Utc>,
) -> Result<Vec<EventRow>, sqlx::Error> {
    sqlx::query_as::<_, EventRow>(&format!(
        "SELECT {EVENT_COLS} FROM events
         WHERE status = 'scheduled' AND start_at > now() AND start_at <= $1"
    ))
    .bind(until)
    .fetch_all(pool)
    .await
}

pub async fn pending_invitees(pool: &PgPool, event_id: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        "SELECT user_id FROM event_invites WHERE event_id = $1 AND status = 'pending'",
    )
    .bind(event_id)
    .fetch_all(pool)
    .await
}

/// Users going to a fee-charging event who have not paid yet.
pub async fn unpaid_going(pool: &PgPool, event_id: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        "SELECT ei.user_id FROM event_invites ei
         WHERE ei.event_id = $1 AND ei.status = 'going'
           AND NOT EXISTS(SELECT 1 FROM payments p
                          WHERE p.event_id = ei.event_id AND p.user_id = ei.user_id
                            AND p.status = 'succeeded')",
    )
    .bind(event_id)
    .fetch_all(pool)
    .await
}
