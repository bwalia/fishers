use chrono::{DateTime, NaiveDate, Utc};
use fishers_domain::{AgentProposal, AgentRun};
use sqlx::types::JsonValue;
use sqlx::PgPool;
use uuid::Uuid;

const RUN_COLS: &str = "id, conversation_id, requested_by, model, status, input_tokens, \
     output_tokens, error, created_at, completed_at";

const PROPOSAL_COLS: &str = "id, agent_run_id, conversation_id, kind, subject_user_id, \
     event_id, payload, rationale, confidence, status, decided_by, decided_at, created_at";

pub async fn start_run(
    pool: &PgPool,
    conversation_id: Uuid,
    requested_by: Uuid,
    model: &str,
) -> Result<AgentRun, sqlx::Error> {
    sqlx::query_as::<_, AgentRun>(&format!(
        "INSERT INTO agent_runs (conversation_id, requested_by, model)
         VALUES ($1, $2, $3) RETURNING {RUN_COLS}"
    ))
    .bind(conversation_id)
    .bind(requested_by)
    .bind(model)
    .fetch_one(pool)
    .await
}

pub async fn finish_run(
    pool: &PgPool,
    run_id: Uuid,
    status: &str,
    input_tokens: Option<i32>,
    output_tokens: Option<i32>,
    error: Option<&str>,
) -> Result<AgentRun, sqlx::Error> {
    sqlx::query_as::<_, AgentRun>(&format!(
        "UPDATE agent_runs
         SET status = $2, input_tokens = $3, output_tokens = $4, error = $5, completed_at = NOW()
         WHERE id = $1
         RETURNING {RUN_COLS}"
    ))
    .bind(run_id)
    .bind(status)
    .bind(input_tokens)
    .bind(output_tokens)
    .bind(error)
    .fetch_one(pool)
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn insert_proposal(
    pool: &PgPool,
    agent_run_id: Uuid,
    conversation_id: Uuid,
    kind: &str,
    subject_user_id: Option<Uuid>,
    event_id: Option<Uuid>,
    payload: JsonValue,
    rationale: &str,
    confidence: &str,
) -> Result<AgentProposal, sqlx::Error> {
    sqlx::query_as::<_, AgentProposal>(&format!(
        "INSERT INTO agent_proposals (agent_run_id, conversation_id, kind, subject_user_id,
                                      event_id, payload, rationale, confidence)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING {PROPOSAL_COLS}"
    ))
    .bind(agent_run_id)
    .bind(conversation_id)
    .bind(kind)
    .bind(subject_user_id)
    .bind(event_id)
    .bind(payload)
    .bind(rationale)
    .bind(confidence)
    .fetch_one(pool)
    .await
}

pub async fn get_proposal(
    pool: &PgPool,
    id: Uuid,
) -> Result<Option<AgentProposal>, sqlx::Error> {
    sqlx::query_as::<_, AgentProposal>(&format!(
        "SELECT {PROPOSAL_COLS} FROM agent_proposals WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(pool)
    .await
}

pub async fn list_proposals(
    pool: &PgPool,
    conversation_id: Uuid,
    pending_only: bool,
) -> Result<Vec<AgentProposal>, sqlx::Error> {
    sqlx::query_as::<_, AgentProposal>(&format!(
        "SELECT {PROPOSAL_COLS} FROM agent_proposals
         WHERE conversation_id = $1 AND ($2 = FALSE OR status = 'pending')
         ORDER BY created_at DESC"
    ))
    .bind(conversation_id)
    .bind(pending_only)
    .fetch_all(pool)
    .await
}

/// `status` is `applied`, `dismissed` or `failed`; only a pending proposal moves.
pub async fn decide_proposal(
    pool: &PgPool,
    id: Uuid,
    status: &str,
    decided_by: Uuid,
) -> Result<Option<AgentProposal>, sqlx::Error> {
    sqlx::query_as::<_, AgentProposal>(&format!(
        "UPDATE agent_proposals
         SET status = $2, decided_by = $3, decided_at = NOW()
         WHERE id = $1 AND status = 'pending'
         RETURNING {PROPOSAL_COLS}"
    ))
    .bind(id)
    .bind(status)
    .bind(decided_by)
    .fetch_optional(pool)
    .await
}

// MARK: context queries — what the agent is allowed to see

/// Roster row with the two signals a captain actually weighs: reliability and
/// how often someone has been available but left out.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct RosterContextRow {
    pub user_id: Uuid,
    pub name: String,
    pub role: String,
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
    pub invites_received: i64,
    pub responded: i64,
    pub said_going: i64,
    pub turned_up: i64,
    pub late_cancellations: i64,
    pub fees_due: i64,
    pub fees_paid: i64,
    pub games_missed_out: i64,
}

pub async fn roster_context(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<RosterContextRow>, sqlx::Error> {
    sqlx::query_as::<_, RosterContextRow>(
        r#"
        SELECT cm.user_id,
               u.name,
               cm.role::TEXT AS role,
               u.position_role,
               u.skill_level,
               r.invites_received, r.responded, r.said_going, r.turned_up,
               r.late_cancellations, r.fees_due, r.fees_paid,
               -- Available but not invited, over the last 60 days: the rotation debt.
               COALESCE((
                   SELECT COUNT(*)
                   FROM events e
                   JOIN availability a
                     ON a.user_id = cm.user_id
                    AND a.date = (e.start_at AT TIME ZONE 'UTC')::date
                    AND a.status = 'available'
                   LEFT JOIN event_invites i ON i.event_id = e.id AND i.user_id = cm.user_id
                   WHERE e.club_id = $1
                     AND e.start_at < NOW()
                     AND e.start_at > NOW() - INTERVAL '60 days'
                     AND e.status <> 'cancelled'
                     AND i.id IS NULL
               ), 0) AS games_missed_out
        FROM club_members cm
        JOIN users u ON u.id = cm.user_id
        LEFT JOIN player_reliability_counts r ON r.user_id = cm.user_id
        WHERE cm.club_id = $1 AND cm.status = 'active'
        ORDER BY u.name
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct FixtureContextRow {
    pub event_id: Uuid,
    pub title: String,
    pub sport: String,
    pub subtype: String,
    pub start_at: DateTime<Utc>,
    pub capacity: Option<i32>,
    pub fee_amount_cents: Option<i32>,
    pub already_invited: Vec<Uuid>,
    pub confirmed: Vec<Uuid>,
}

/// Upcoming fixtures for a club (optionally one team), with who is already on
/// the sheet so the agent doesn't re-invite them.
pub async fn fixture_context(
    pool: &PgPool,
    club_id: Uuid,
    team_id: Option<Uuid>,
    days_ahead: i32,
) -> Result<Vec<FixtureContextRow>, sqlx::Error> {
    sqlx::query_as::<_, FixtureContextRow>(
        r#"
        SELECT e.id AS event_id,
               e.title,
               e.sport::TEXT AS sport,
               e.event_subtype::TEXT AS subtype,
               e.start_at,
               e.capacity,
               e.fee_amount_cents,
               COALESCE(ARRAY_AGG(i.user_id) FILTER (WHERE i.user_id IS NOT NULL), '{}') AS already_invited,
               COALESCE(ARRAY_AGG(i.user_id) FILTER (WHERE i.status = 'going'), '{}') AS confirmed
        FROM events e
        LEFT JOIN event_invites i ON i.event_id = e.id
        WHERE e.club_id = $1
          AND ($2::uuid IS NULL OR e.team_id = $2)
          AND e.status <> 'cancelled'
          AND e.start_at BETWEEN NOW() - INTERVAL '1 day'
                             AND NOW() + ($3 || ' days')::INTERVAL
        GROUP BY e.id
        ORDER BY e.start_at
        "#,
    )
    .bind(club_id)
    .bind(team_id)
    .bind(days_ahead.to_string())
    .fetch_all(pool)
    .await
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct AvailabilityContextRow {
    pub user_id: Uuid,
    pub date: NaiveDate,
    pub status: String,
}

pub async fn availability_context(
    pool: &PgPool,
    user_ids: &[Uuid],
    days_ahead: i32,
) -> Result<Vec<AvailabilityContextRow>, sqlx::Error> {
    sqlx::query_as::<_, AvailabilityContextRow>(
        r#"
        SELECT user_id, date, status::TEXT AS status
        FROM availability
        WHERE user_id = ANY($1)
          AND date BETWEEN CURRENT_DATE AND CURRENT_DATE + ($2 || ' days')::INTERVAL
        ORDER BY date, user_id
        "#,
    )
    .bind(user_ids)
    .bind(days_ahead.to_string())
    .fetch_all(pool)
    .await
}

/// Members who said they were going to a fee-bearing fixture in the last 30
/// days and have no successful payment against it.
pub async fn unpaid_fee_users(pool: &PgPool, club_id: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        r#"
        SELECT DISTINCT i.user_id
        FROM event_invites i
        JOIN events e ON e.id = i.event_id
        WHERE e.club_id = $1
          AND e.fee_amount_cents IS NOT NULL
          AND e.fee_amount_cents > 0
          AND e.start_at > NOW() - INTERVAL '30 days'
          AND i.status = 'going'
          AND NOT EXISTS (
              SELECT 1 FROM payments p
              WHERE p.event_id = e.id AND p.user_id = i.user_id AND p.status = 'succeeded'
          )
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.0).collect())
}
