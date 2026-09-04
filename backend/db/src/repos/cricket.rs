//! Cricket match persistence + scoring event log.

use chrono::{DateTime, Utc};
use fishers_domain::{MatchState, ScoringEvent, ScoringEventKind};
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct CricketMatchRow {
    pub id: Uuid,
    pub event_id: Uuid,
    pub club_id: Uuid,
    pub status: String,
    pub overs_limit: i32,
    pub home_name: String,
    pub away_name: String,
    pub active_scorer_user_id: Option<Uuid>,
    pub active_scorer_device_id: Option<String>,
    pub last_seq: i64,
    pub state_json: Value,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

pub async fn create_match(
    pool: &PgPool,
    event_id: Uuid,
    club_id: Uuid,
    created_by: Uuid,
    home_name: &str,
    away_name: &str,
    overs_limit: i32,
) -> Result<CricketMatchRow, sqlx::Error> {
    let state = MatchState {
        overs_limit: overs_limit as u8,
        home_name: home_name.to_string(),
        away_name: away_name.to_string(),
        ..Default::default()
    };
    sqlx::query_as::<_, CricketMatchRow>(
        r#"
        INSERT INTO cricket_matches (
            event_id, club_id, status, overs_limit, home_name, away_name,
            state_json, created_by
        )
        VALUES ($1, $2, 'scheduled', $3, $4, $5, $6, $7)
        ON CONFLICT (event_id) DO UPDATE SET updated_at = NOW()
        RETURNING id, event_id, club_id, status::TEXT, overs_limit, home_name, away_name,
                  active_scorer_user_id, active_scorer_device_id, last_seq, state_json,
                  created_by, created_at, updated_at
        "#,
    )
    .bind(event_id)
    .bind(club_id)
    .bind(overs_limit)
    .bind(home_name)
    .bind(away_name)
    .bind(serde_json::to_value(&state).unwrap_or(Value::Object(Default::default())))
    .bind(created_by)
    .fetch_one(pool)
    .await
}

pub async fn get_match(pool: &PgPool, match_id: Uuid) -> Result<Option<CricketMatchRow>, sqlx::Error> {
    sqlx::query_as::<_, CricketMatchRow>(
        r#"
        SELECT id, event_id, club_id, status::TEXT, overs_limit, home_name, away_name,
               active_scorer_user_id, active_scorer_device_id, last_seq, state_json,
               created_by, created_at, updated_at
        FROM cricket_matches WHERE id = $1
        "#,
    )
    .bind(match_id)
    .fetch_optional(pool)
    .await
}

pub async fn get_match_by_event(
    pool: &PgPool,
    event_id: Uuid,
) -> Result<Option<CricketMatchRow>, sqlx::Error> {
    sqlx::query_as::<_, CricketMatchRow>(
        r#"
        SELECT id, event_id, club_id, status::TEXT, overs_limit, home_name, away_name,
               active_scorer_user_id, active_scorer_device_id, last_seq, state_json,
               created_by, created_at, updated_at
        FROM cricket_matches WHERE event_id = $1
        "#,
    )
    .bind(event_id)
    .fetch_optional(pool)
    .await
}

pub async fn claim_scorer(
    pool: &PgPool,
    match_id: Uuid,
    user_id: Uuid,
    device_id: &str,
) -> Result<CricketMatchRow, sqlx::Error> {
    sqlx::query_as::<_, CricketMatchRow>(
        r#"
        UPDATE cricket_matches
        SET active_scorer_user_id = $2,
            active_scorer_device_id = $3,
            updated_at = NOW()
        WHERE id = $1
          AND (
            active_scorer_user_id IS NULL
            OR active_scorer_user_id = $2
            OR active_scorer_device_id = $3
          )
        RETURNING id, event_id, club_id, status::TEXT, overs_limit, home_name, away_name,
                  active_scorer_user_id, active_scorer_device_id, last_seq, state_json,
                  created_by, created_at, updated_at
        "#,
    )
    .bind(match_id)
    .bind(user_id)
    .bind(device_id)
    .fetch_one(pool)
    .await
}

pub async fn is_official(pool: &PgPool, match_id: Uuid, user_id: Uuid) -> Result<bool, sqlx::Error> {
    let row: (bool,) = sqlx::query_as(
        r#"
        SELECT EXISTS(
          SELECT 1 FROM cricket_match_officials
          WHERE match_id = $1 AND user_id = $2
        )
        "#,
    )
    .bind(match_id)
    .bind(user_id)
    .fetch_one(pool)
    .await?;
    Ok(row.0)
}

pub async fn add_official(
    pool: &PgPool,
    match_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO cricket_match_officials (match_id, user_id, role)
        VALUES ($1, $2, 'scorer')
        ON CONFLICT DO NOTHING
        "#,
    )
    .bind(match_id)
    .bind(user_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn client_event_exists(
    pool: &PgPool,
    match_id: Uuid,
    client_event_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let row: (bool,) = sqlx::query_as(
        "SELECT EXISTS(SELECT 1 FROM cricket_scoring_events WHERE match_id = $1 AND client_event_id = $2)",
    )
    .bind(match_id)
    .bind(client_event_id)
    .fetch_one(pool)
    .await?;
    Ok(row.0)
}

pub async fn insert_event(
    pool: &PgPool,
    match_id: Uuid,
    seq: i64,
    client_event_id: Uuid,
    kind: &ScoringEventKind,
    created_by: Uuid,
    device_id: Option<&str>,
) -> Result<(), sqlx::Error> {
    let payload = serde_json::to_value(kind).unwrap_or(Value::Null);
    let event_type = payload
        .get("type")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_string();
    sqlx::query(
        r#"
        INSERT INTO cricket_scoring_events (
            match_id, seq, client_event_id, event_type, payload, created_by, device_id
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        "#,
    )
    .bind(match_id)
    .bind(seq)
    .bind(client_event_id)
    .bind(event_type)
    .bind(payload)
    .bind(created_by)
    .bind(device_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn save_state(
    pool: &PgPool,
    match_id: Uuid,
    state: &MatchState,
    status: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE cricket_matches
        SET last_seq = $2,
            state_json = $3,
            status = $4::cricket_match_status,
            target = $5,
            margin = $6,
            updated_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(match_id)
    .bind(state.last_seq)
    .bind(serde_json::to_value(state).unwrap_or(Value::Object(Default::default())))
    .bind(status)
    .bind(state.target.map(|t| t as i32))
    .bind(&state.margin)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn list_events_after(
    pool: &PgPool,
    match_id: Uuid,
    after_seq: i64,
) -> Result<Vec<(i64, Uuid, Value)>, sqlx::Error> {
    sqlx::query_as::<_, (i64, Uuid, Value)>(
        r#"
        SELECT seq, client_event_id, payload
        FROM cricket_scoring_events
        WHERE match_id = $1 AND seq > $2
        ORDER BY seq ASC
        "#,
    )
    .bind(match_id)
    .bind(after_seq)
    .fetch_all(pool)
    .await
}

pub fn parse_state(row: &CricketMatchRow) -> MatchState {
    serde_json::from_value(row.state_json.clone()).unwrap_or_else(|_| MatchState {
        overs_limit: row.overs_limit as u8,
        home_name: row.home_name.clone(),
        away_name: row.away_name.clone(),
        last_seq: row.last_seq,
        ..Default::default()
    })
}

pub fn status_str(state: &MatchState) -> &'static str {
    use fishers_domain::MatchStatus::*;
    match state.status {
        Scheduled => "scheduled",
        Preparing => "preparing",
        Toss => "toss",
        SelectingXi => "selecting_xi",
        Ready => "ready",
        Live => "live",
        InningsBreak => "innings_break",
        Complete => "complete",
        Published => "published",
    }
}

/// Apply a batch of client events; returns updated state.
pub async fn apply_event_batch(
    pool: &PgPool,
    match_id: Uuid,
    events: &[ScoringEvent],
    user_id: Uuid,
    device_id: Option<&str>,
) -> Result<MatchState, anyhow::Error> {
    let row = get_match(pool, match_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("match not found"))?;
    let mut state = parse_state(&row);

    for ev in events {
        if client_event_exists(pool, match_id, ev.client_event_id).await? {
            continue;
        }
        state.apply(ev)?;
        insert_event(
            pool,
            match_id,
            ev.seq,
            ev.client_event_id,
            &ev.kind,
            user_id,
            device_id,
        )
        .await?;
    }
    save_state(pool, match_id, &state, status_str(&state)).await?;
    Ok(state)
}
