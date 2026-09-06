//! Cricket match persistence + scoring event log.
//!
//! The log is the record; `state_json` is a cache of the projection so reads
//! are one row. Writes always replay the log, because the undo stack only
//! exists inside a replay — restoring a serialised snapshot cannot undo a ball
//! that was stored in an earlier batch.

use chrono::{DateTime, Utc};
use fishers_domain::{MatchState, MatchStatus, ScoringEvent, ScoringEventKind};
use serde_json::Value;
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

/// How long a scorer's lock survives without a sync before another device on
/// the ground may take it over. Phones die mid-innings.
const SCORER_LOCK_IDLE_MINUTES: i64 = 15;

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

const MATCH_COLS: &str = "id, event_id, club_id, status::TEXT, overs_limit, home_name, away_name, \
     active_scorer_user_id, active_scorer_device_id, last_seq, state_json, created_by, \
     created_at, updated_at";

/// Create the match, or return the one this fixture already has.
///
/// `match_id` lets the device choose the id up front, so a match started with
/// no signal can be scored locally and registered later under the same id.
#[allow(clippy::too_many_arguments)]
pub async fn create_match(
    pool: &PgPool,
    match_id: Option<Uuid>,
    event_id: Uuid,
    club_id: Uuid,
    created_by: Uuid,
    home_name: &str,
    away_name: &str,
    overs_limit: i32,
) -> Result<CricketMatchRow, sqlx::Error> {
    let state = MatchState {
        overs_limit: overs_limit.clamp(1, 255) as u8,
        home_name: home_name.to_string(),
        away_name: away_name.to_string(),
        ..Default::default()
    };
    sqlx::query_as::<_, CricketMatchRow>(&format!(
        r#"
        INSERT INTO cricket_matches (
            id, event_id, club_id, status, overs_limit, home_name, away_name,
            state_json, created_by
        )
        VALUES (COALESCE($1, gen_random_uuid()), $2, $3, 'scheduled', $4, $5, $6, $7, $8)
        ON CONFLICT (event_id) DO UPDATE SET updated_at = NOW()
        RETURNING {MATCH_COLS}
        "#
    ))
    .bind(match_id)
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

pub async fn get_match(
    pool: &PgPool,
    match_id: Uuid,
) -> Result<Option<CricketMatchRow>, sqlx::Error> {
    sqlx::query_as::<_, CricketMatchRow>(&format!(
        "SELECT {MATCH_COLS} FROM cricket_matches WHERE id = $1"
    ))
    .bind(match_id)
    .fetch_optional(pool)
    .await
}

pub async fn get_match_by_event(
    pool: &PgPool,
    event_id: Uuid,
) -> Result<Option<CricketMatchRow>, sqlx::Error> {
    sqlx::query_as::<_, CricketMatchRow>(&format!(
        "SELECT {MATCH_COLS} FROM cricket_matches WHERE event_id = $1"
    ))
    .bind(event_id)
    .fetch_optional(pool)
    .await
}

/// Take the scoring lock. Granted when it is free, already yours, held by this
/// device, gone quiet for [`SCORER_LOCK_IDLE_MINUTES`], or when `force` is set
/// — a captain taking over from a dead phone.
pub async fn claim_scorer(
    pool: &PgPool,
    match_id: Uuid,
    user_id: Uuid,
    device_id: &str,
    force: bool,
) -> Result<Option<CricketMatchRow>, sqlx::Error> {
    sqlx::query_as::<_, CricketMatchRow>(&format!(
        r#"
        UPDATE cricket_matches
        SET active_scorer_user_id = $2,
            active_scorer_device_id = $3,
            updated_at = NOW()
        WHERE id = $1
          AND (
            $4
            OR active_scorer_user_id IS NULL
            OR active_scorer_user_id = $2
            OR active_scorer_device_id = $3
            OR updated_at < NOW() - ($5 || ' minutes')::INTERVAL
          )
        RETURNING {MATCH_COLS}
        "#
    ))
    .bind(match_id)
    .bind(user_id)
    .bind(device_id)
    .bind(force)
    .bind(SCORER_LOCK_IDLE_MINUTES.to_string())
    .fetch_optional(pool)
    .await
}

pub async fn is_official(
    pool: &PgPool,
    match_id: Uuid,
    user_id: Uuid,
) -> Result<bool, sqlx::Error> {
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

/// The whole log, as domain events, ready to replay.
async fn load_log(
    tx: &mut Transaction<'_, Postgres>,
    match_id: Uuid,
) -> Result<Vec<ScoringEvent>, anyhow::Error> {
    let rows = sqlx::query_as::<_, (i64, Uuid, Value)>(
        r#"
        SELECT seq, client_event_id, payload
        FROM cricket_scoring_events
        WHERE match_id = $1
        ORDER BY seq ASC
        "#,
    )
    .bind(match_id)
    .fetch_all(&mut **tx)
    .await?;

    let mut events = Vec::with_capacity(rows.len());
    for (seq, client_event_id, payload) in rows {
        let kind: ScoringEventKind = serde_json::from_value(payload)
            .map_err(|e| anyhow::anyhow!("stored event {seq} is unreadable: {e}"))?;
        events.push(ScoringEvent {
            client_event_id,
            seq,
            kind,
        });
    }
    Ok(events)
}

/// Read-only projection for GET routes. Falls back to the match row's own
/// details when the cache is empty or from an older shape.
pub fn parse_state(row: &CricketMatchRow) -> MatchState {
    serde_json::from_value(row.state_json.clone()).unwrap_or_else(|_| MatchState {
        overs_limit: row.overs_limit.clamp(1, 255) as u8,
        home_name: row.home_name.clone(),
        away_name: row.away_name.clone(),
        last_seq: row.last_seq,
        ..Default::default()
    })
}

pub fn status_str(state: &MatchState) -> &'static str {
    match state.status {
        MatchStatus::Scheduled => "scheduled",
        MatchStatus::Preparing => "preparing",
        MatchStatus::Toss => "toss",
        MatchStatus::SelectingXi => "selecting_xi",
        MatchStatus::Ready => "ready",
        MatchStatus::Live => "live",
        MatchStatus::InningsBreak => "innings_break",
        MatchStatus::Complete => "complete",
        MatchStatus::Published => "published",
    }
}

fn side_str(side: fishers_domain::MatchSide) -> &'static str {
    match side {
        fishers_domain::MatchSide::Home => "home",
        fishers_domain::MatchSide::Away => "away",
    }
}

/// Apply a batch of client events inside one transaction: replay the stored log
/// to rebuild state (and its undo stack), apply what is new, append it, and
/// cache the projection. All of it lands or none of it does.
pub async fn apply_event_batch(
    pool: &PgPool,
    match_id: Uuid,
    events: &[ScoringEvent],
    user_id: Uuid,
    device_id: Option<&str>,
) -> Result<MatchState, anyhow::Error> {
    let mut tx = pool.begin().await?;

    let row = sqlx::query_as::<_, CricketMatchRow>(&format!(
        "SELECT {MATCH_COLS} FROM cricket_matches WHERE id = $1 FOR UPDATE"
    ))
    .bind(match_id)
    .fetch_one(&mut *tx)
    .await?;

    let stored = load_log(&mut tx, match_id).await?;
    let mut state = MatchState::replay(&stored)?;
    if state.last_seq == 0 {
        // Nothing scored yet: keep the names and overs the fixture was set up with.
        state.overs_limit = row.overs_limit.clamp(1, 255) as u8;
        state.home_name = row.home_name.clone();
        state.away_name = row.away_name.clone();
    }
    let seen: std::collections::HashSet<Uuid> =
        stored.iter().map(|e| e.client_event_id).collect();

    for event in events {
        if seen.contains(&event.client_event_id) {
            continue; // already applied — the client is retrying a batch
        }
        state.apply(event)?;

        let payload = serde_json::to_value(&event.kind)?;
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
        .bind(event.seq)
        .bind(event.client_event_id)
        .bind(event_type)
        .bind(payload)
        .bind(user_id)
        .bind(device_id)
        .execute(&mut *tx)
        .await?;
    }

    save_state(&mut tx, match_id, &state).await?;
    tx.commit().await?;
    Ok(state)
}

/// Cache the projection on the match row, and close the fixture off when the
/// match finishes so attendance and reliability see a completed game.
async fn save_state(
    tx: &mut Transaction<'_, Postgres>,
    match_id: Uuid,
    state: &MatchState,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE cricket_matches
        SET last_seq = $2,
            state_json = $3,
            status = $4::cricket_match_status,
            target = $5,
            winner = $6::cricket_match_side,
            margin = $7,
            updated_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(match_id)
    .bind(state.last_seq)
    .bind(serde_json::to_value(state).unwrap_or(Value::Object(Default::default())))
    .bind(status_str(state))
    .bind(state.target.map(|t| t as i32))
    .bind(state.winner.map(side_str))
    .bind(&state.margin)
    .execute(&mut **tx)
    .await?;

    if matches!(state.status, MatchStatus::Complete | MatchStatus::Published) {
        sqlx::query(
            r#"
            UPDATE events SET status = 'completed', updated_at = NOW()
            WHERE id = (SELECT event_id FROM cricket_matches WHERE id = $1)
              AND status NOT IN ('cancelled', 'completed')
            "#,
        )
        .bind(match_id)
        .execute(&mut **tx)
        .await?;

        // The scorecard belongs on the fixture too, so the result survives
        // independently of the scoring projection.
        sqlx::query(
            r#"
            INSERT INTO match_results (event_id, format, opposition, scorecard_json)
            SELECT m.event_id, m.overs_limit || ' overs', m.away_name, $2
            FROM cricket_matches m WHERE m.id = $1
            ON CONFLICT (event_id) DO UPDATE SET
                scorecard_json = EXCLUDED.scorecard_json,
                format = EXCLUDED.format,
                opposition = EXCLUDED.opposition
            "#,
        )
        .bind(match_id)
        .bind(serde_json::to_value(state).unwrap_or(Value::Object(Default::default())))
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}
