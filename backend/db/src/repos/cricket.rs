//! Cricket match persistence + scoring event log.
//!
//! The log is the record; `state_json` is a cache of the projection so reads
//! are one row. Writes always replay the log, because the undo stack only
//! exists inside a replay — restoring a serialised snapshot cannot undo a ball
//! that was stored in an earlier batch.

use chrono::{DateTime, Utc};
use fishers_domain::{MatchSide, MatchState, MatchStatus, ScoringEvent, ScoringEventKind};
use serde_json::Value;
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct CricketMatchRow {
    pub id: Uuid,
    pub event_id: Uuid,
    pub club_id: Uuid,
    pub status: String,
    pub overs_limit: i32,
    pub overs_per_bowler: i32,
    pub powerplay_overs: i32,
    pub super_overs: i32,
    pub ground_type: String,
    pub ball_type: String,
    pub agreed_home: Option<String>,
    pub agreed_away: Option<String>,
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

const MATCH_COLS: &str = "id, event_id, club_id, status::TEXT, overs_limit, overs_per_bowler, \
     powerplay_overs, super_overs, ground_type, ball_type, agreed_home, agreed_away, \
     home_name, away_name, \
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
    opponent_club_id: Option<Uuid>,
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
            id, event_id, club_id, opponent_club_id, status, overs_limit,
            home_name, away_name, state_json, created_by
        )
        VALUES (COALESCE($1, gen_random_uuid()), $2, $3, $4, 'scheduled', $5, $6, $7, $8, $9)
        ON CONFLICT (event_id) DO UPDATE SET
            -- Naming the opposition later must stick; the rest is create-or-get.
            opponent_club_id = COALESCE(EXCLUDED.opponent_club_id, cricket_matches.opponent_club_id),
            updated_at = NOW()
        RETURNING {MATCH_COLS}
        "#
    ))
    .bind(match_id)
    .bind(event_id)
    .bind(club_id)
    .bind(opponent_club_id)
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

/// Take the scoring lock. Granted only when it is free, already yours, or held
/// by this same device.
///
/// There is deliberately no idle takeover: while someone is scoring, nobody
/// else may alter the match. It changes hands through [`handover`], or — when
/// the phone is genuinely gone — an officer's override, which is written to the
/// handover trail either way.
pub async fn claim_scorer(
    pool: &PgPool,
    match_id: Uuid,
    user_id: Uuid,
    device_id: &str,
) -> Result<Option<CricketMatchRow>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let previous: Option<(Option<Uuid>,)> =
        sqlx::query_as("SELECT active_scorer_user_id FROM cricket_matches WHERE id = $1")
            .bind(match_id)
            .fetch_optional(&mut *tx)
            .await?;
    let previous = previous.and_then(|row| row.0);

    let updated = sqlx::query_as::<_, CricketMatchRow>(&format!(
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
        RETURNING {MATCH_COLS}
        "#
    ))
    .bind(match_id)
    .bind(user_id)
    .bind(device_id)
    .fetch_optional(&mut *tx)
    .await?;

    if updated.is_some() && previous != Some(user_id) {
        log_handover(&mut tx, match_id, previous, user_id, "claim", user_id).await?;
    }
    tx.commit().await?;
    Ok(updated)
}

/// Pass the book to someone else. Only the scorer holding it may do this, which
/// is what makes the lock meaningful.
pub async fn handover(
    pool: &PgPool,
    match_id: Uuid,
    from_user: Uuid,
    to_user: Uuid,
) -> Result<Option<CricketMatchRow>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let updated = sqlx::query_as::<_, CricketMatchRow>(&format!(
        r#"
        UPDATE cricket_matches
        SET active_scorer_user_id = $3,
            -- The new scorer claims the lock from their own device on first sync.
            active_scorer_device_id = NULL,
            updated_at = NOW()
        WHERE id = $1 AND active_scorer_user_id = $2
        RETURNING {MATCH_COLS}
        "#
    ))
    .bind(match_id)
    .bind(from_user)
    .bind(to_user)
    .fetch_optional(&mut *tx)
    .await?;

    if updated.is_some() {
        log_handover(&mut tx, match_id, Some(from_user), to_user, "handover", from_user).await?;
    }
    tx.commit().await?;
    Ok(updated)
}

/// Break glass: a captain or secretary takes the book because the scorer's
/// phone is dead. Always recorded, never silent.
pub async fn override_scorer(
    pool: &PgPool,
    match_id: Uuid,
    to_user: Uuid,
    acted_by: Uuid,
    device_id: &str,
) -> Result<Option<CricketMatchRow>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let previous: Option<(Option<Uuid>,)> =
        sqlx::query_as("SELECT active_scorer_user_id FROM cricket_matches WHERE id = $1")
            .bind(match_id)
            .fetch_optional(&mut *tx)
            .await?;
    let previous = previous.and_then(|row| row.0);

    let updated = sqlx::query_as::<_, CricketMatchRow>(&format!(
        r#"
        UPDATE cricket_matches
        SET active_scorer_user_id = $2,
            active_scorer_device_id = $3,
            updated_at = NOW()
        WHERE id = $1
        RETURNING {MATCH_COLS}
        "#
    ))
    .bind(match_id)
    .bind(to_user)
    .bind(device_id)
    .fetch_optional(&mut *tx)
    .await?;

    if updated.is_some() {
        log_handover(&mut tx, match_id, previous, to_user, "override", acted_by).await?;
    }
    tx.commit().await?;
    Ok(updated)
}

async fn log_handover(
    tx: &mut Transaction<'_, Postgres>,
    match_id: Uuid,
    from_user: Option<Uuid>,
    to_user: Uuid,
    reason: &str,
    acted_by: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO cricket_scorer_handovers (match_id, from_user, to_user, reason, acted_by)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(match_id)
    .bind(from_user)
    .bind(to_user)
    .bind(reason)
    .bind(acted_by)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// Who has held the book, most recent first.
#[derive(Debug, Clone, serde::Serialize, sqlx::FromRow)]
pub struct HandoverRow {
    pub from_name: Option<String>,
    pub to_name: String,
    pub reason: String,
    pub acted_by_name: String,
    pub created_at: DateTime<Utc>,
}

pub async fn handover_trail(
    pool: &PgPool,
    match_id: Uuid,
) -> Result<Vec<HandoverRow>, sqlx::Error> {
    sqlx::query_as::<_, HandoverRow>(
        r#"
        SELECT prev.name AS from_name, next.name AS to_name, h.reason,
               actor.name AS acted_by_name, h.created_at
        FROM cricket_scorer_handovers h
        JOIN users next ON next.id = h.to_user
        JOIN users actor ON actor.id = h.acted_by
        LEFT JOIN users prev ON prev.id = h.from_user
        WHERE h.match_id = $1
        ORDER BY h.created_at DESC
        LIMIT 50
        "#,
    )
    .bind(match_id)
    .fetch_all(pool)
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

/// Appoint an umpire or a scorer. Either may score the match, which is the
/// point: the umpire standing at square leg often keeps the book.
pub async fn add_official(
    pool: &PgPool,
    match_id: Uuid,
    user_id: Uuid,
    role: &str,
    appointed_by: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO cricket_match_officials (match_id, user_id, role, appointed_by)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (match_id, user_id) DO UPDATE SET
            role = EXCLUDED.role,
            appointed_by = EXCLUDED.appointed_by,
            appointed_at = NOW()
        "#,
    )
    .bind(match_id)
    .bind(user_id)
    .bind(role)
    .bind(appointed_by)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn remove_official(
    pool: &PgPool,
    match_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM cricket_match_officials WHERE match_id = $1 AND user_id = $2")
        .bind(match_id)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}

#[derive(Debug, Clone, serde::Serialize, sqlx::FromRow)]
pub struct OfficialRow {
    pub user_id: Uuid,
    pub name: String,
    pub role: String,
}

pub async fn list_officials(
    pool: &PgPool,
    match_id: Uuid,
) -> Result<Vec<OfficialRow>, sqlx::Error> {
    sqlx::query_as::<_, OfficialRow>(
        r#"
        SELECT o.user_id, u.name, o.role
        FROM cricket_match_officials o
        JOIN users u ON u.id = o.user_id
        WHERE o.match_id = $1
        ORDER BY o.role, u.name
        "#,
    )
    .bind(match_id)
    .fetch_all(pool)
    .await
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
    let rows = sqlx::query_as::<_, (i64, Uuid, Value, DateTime<Utc>)>(
        r#"
        SELECT seq, client_event_id, payload, created_at
        FROM cricket_scoring_events
        WHERE match_id = $1
        ORDER BY seq ASC
        "#,
    )
    .bind(match_id)
    .fetch_all(&mut **tx)
    .await?;

    let mut events = Vec::with_capacity(rows.len());
    for (seq, client_event_id, payload, created_at) in rows {
        let kind: ScoringEventKind = serde_json::from_value(payload)
            .map_err(|e| anyhow::anyhow!("stored event {seq} is unreadable: {e}"))?;
        events.push(ScoringEvent {
            client_event_id,
            seq,
            kind,
            // When the row was written, so the over rate survives a replay.
            at: Some(created_at),
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

fn ground_str(ground: fishers_domain::GroundType) -> &'static str {
    match ground {
        fishers_domain::GroundType::Open => "open",
        fishers_domain::GroundType::Boxed => "boxed",
        fishers_domain::GroundType::Indoor => "indoor",
    }
}

fn ball_str(ball: fishers_domain::BallType) -> &'static str {
    match ball {
        fishers_domain::BallType::Red => "red",
        fishers_domain::BallType::White => "white",
        fishers_domain::BallType::Pink => "pink",
        fishers_domain::BallType::Tennis => "tennis",
        fishers_domain::BallType::Tape => "tape",
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
        if event.seq <= state.last_seq {
            // The client worked from a state it had already moved past — two
            // quick taps both numbering the same ball, say. The engine treats
            // this as applied and does nothing, so inserting it anyway would
            // collide with the row already holding that sequence number, and
            // the scorer would see a duplicate key error for a ball that was
            // recorded perfectly well.
            continue;
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
            overs_limit = $8,
            overs_per_bowler = $9,
            ground_type = $10,
            ball_type = $11,
            agreed_home = $12,
            agreed_away = $13,
            powerplay_overs = $14,
            super_overs = $15,
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
    .bind(state.conditions.overs_limit as i32)
    .bind(state.conditions.overs_per_bowler as i32)
    .bind(ground_str(state.conditions.ground))
    .bind(ball_str(state.conditions.ball))
    .bind(&state.agreed_home)
    .bind(&state.agreed_away)
    .bind(state.conditions.powerplay_overs as i32)
    .bind(state.super_overs as i32)
    .execute(&mut **tx)
    .await?;

    if matches!(state.status, MatchStatus::Complete | MatchStatus::Published) {
        record_match_outcomes(tx, match_id, state).await?;
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


/// What one player did in a match, ready to fold into their season.
#[derive(Default, Debug, Clone, Copy)]
struct PlayerTally {
    matches: i32,
    runs: i32,
    balls_faced: i32,
    fours: i32,
    sixes: i32,
    batting_innings: i32,
    not_outs: i32,
    high_score: i32,
    bowling_balls: i32,
    bowling_runs: i32,
    wickets: i32,
    maidens: i32,
    catches: i32,
    stumpings: i32,
}

/// Everything a finished match owes the rest of the app: who turned up, what it
/// did to their season, and — if it was a tournament fixture — the result.
///
/// Runs at most once per match. The first caller claims `stats_recorded_at`
/// inside the transaction, so a resync or a replayed batch cannot count a
/// hundred twice.
async fn record_match_outcomes(
    tx: &mut Transaction<'_, Postgres>,
    match_id: Uuid,
    state: &MatchState,
) -> Result<(), sqlx::Error> {
    let claimed: Option<(Uuid, Uuid, i32)> = sqlx::query_as(
        r#"
        UPDATE cricket_matches m
        SET stats_recorded_at = NOW()
        FROM events e
        WHERE m.id = $1
          AND m.stats_recorded_at IS NULL
          AND e.id = m.event_id
        RETURNING m.event_id, m.club_id,
                  EXTRACT(YEAR FROM e.start_at)::INT AS season_year
        "#,
    )
    .bind(match_id)
    .fetch_optional(&mut **tx)
    .await?;

    let Some((event_id, club_id, season_year)) = claimed else {
        return Ok(()); // already folded in
    };

    // 1. Who played. This is the attendance half of the reliability score,
    //    which until now nothing ever set.
    let played: Vec<Uuid> = state
        .home_xi
        .iter()
        .chain(state.away_xi.iter())
        .copied()
        .collect();
    if !played.is_empty() {
        sqlx::query(
            r#"
            UPDATE event_invites
            SET attended = TRUE
            WHERE event_id = $1 AND user_id = ANY($2) AND attended IS DISTINCT FROM TRUE
            "#,
        )
        .bind(event_id)
        .bind(&played)
        .execute(&mut **tx)
        .await?;
    }

    // 2. The season. Guests have ids that are not users, and the insert simply
    //    finds no row for them.
    let tallies = tally_players(state);
    for (player_id, tally) in tallies {
        sqlx::query(
            r#"
            INSERT INTO player_season_stats (
                user_id, club_id, sport, season_year, source,
                matches, runs, wickets, batting_innings, not_outs, balls_faced,
                fours, sixes, high_score, overs_bowled, bowling_runs, maidens,
                catches, stumpings
            )
            SELECT u.id, $2, 'cricket', $3, 'fishers_scoring',
                   $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17
            FROM users u WHERE u.id = $1
            ON CONFLICT (user_id, club_id, sport, season_year, source) DO UPDATE SET
                matches         = player_season_stats.matches + EXCLUDED.matches,
                runs            = player_season_stats.runs + EXCLUDED.runs,
                wickets         = player_season_stats.wickets + EXCLUDED.wickets,
                batting_innings = player_season_stats.batting_innings + EXCLUDED.batting_innings,
                not_outs        = player_season_stats.not_outs + EXCLUDED.not_outs,
                balls_faced     = player_season_stats.balls_faced + EXCLUDED.balls_faced,
                fours           = player_season_stats.fours + EXCLUDED.fours,
                sixes           = player_season_stats.sixes + EXCLUDED.sixes,
                high_score      = GREATEST(
                                      COALESCE(player_season_stats.high_score, 0),
                                      COALESCE(EXCLUDED.high_score, 0)
                                  ),
                overs_bowled    = player_season_stats.overs_bowled + EXCLUDED.overs_bowled,
                bowling_runs    = player_season_stats.bowling_runs + EXCLUDED.bowling_runs,
                maidens         = player_season_stats.maidens + EXCLUDED.maidens,
                catches         = player_season_stats.catches + EXCLUDED.catches,
                stumpings       = player_season_stats.stumpings + EXCLUDED.stumpings,
                updated_at      = NOW()
            "#,
        )
        .bind(player_id)
        .bind(club_id)
        .bind(season_year)
        .bind(tally.matches)
        .bind(tally.runs)
        .bind(tally.wickets)
        .bind(tally.batting_innings)
        .bind(tally.not_outs)
        .bind(tally.balls_faced)
        .bind(tally.fours)
        .bind(tally.sixes)
        .bind(if tally.batting_innings > 0 { Some(tally.high_score) } else { None })
        .bind(tally.bowling_balls as f64 / 6.0)
        .bind(tally.bowling_runs)
        .bind(tally.maidens)
        .bind(tally.catches)
        .bind(tally.stumpings)
        .execute(&mut **tx)
        .await?;
    }

    // 3. The club's season board. Until now only the Play-Cricket sync wrote
    //    this, so a club scoring its own matches showed "Played 0" forever.
    record_club_season(tx, club_id, season_year, state).await?;

    // 4. The tournament table, if this fixture is in one. Without this a
    //    ball-by-ball scored tournament game left the table blank and somebody
    //    had to type the result in a second time.
    record_tournament_result(tx, event_id, state).await?;

    Ok(())
}

/// Fold one finished match into the club's season board.
///
/// Which side the club batted as is not recorded anywhere, so it is worked out
/// from the team sheets: the XI holding more of the club's own members is the
/// club's side. A guest-only match falls back to the home side, which is the
/// convention everywhere else in the app.
async fn record_club_season(
    tx: &mut Transaction<'_, Postgres>,
    club_id: Uuid,
    season_year: i32,
    state: &MatchState,
) -> Result<(), sqlx::Error> {
    const MEMBERS_IN_XI: &str =
        "SELECT COUNT(*) FROM club_members WHERE club_id = $1 AND user_id = ANY($2)";
    let home_members: i64 = sqlx::query_scalar(MEMBERS_IN_XI)
        .bind(club_id)
        .bind(&state.home_xi[..])
        .fetch_one(&mut **tx)
        .await?;
    let away_members: i64 = sqlx::query_scalar(MEMBERS_IN_XI)
        .bind(club_id)
        .bind(&state.away_xi[..])
        .fetch_one(&mut **tx)
        .await?;
    let club_side = if away_members > home_members {
        MatchSide::Away
    } else {
        MatchSide::Home
    };

    // Runs and wickets across every innings, from the club's point of view.
    let (mut runs_for, mut runs_against) = (0i32, 0i32);
    let (mut wickets_taken, mut wickets_lost) = (0i32, 0i32);
    for inn in &state.innings {
        if inn.batting == club_side {
            runs_for += inn.runs as i32;
            wickets_lost += inn.wickets as i32;
        } else {
            runs_against += inn.runs as i32;
            wickets_taken += inn.wickets as i32;
        }
    }

    let (win, loss, draw, no_result) = match state.winner {
        Some(side) if side == club_side => (1, 0, 0, 0),
        Some(_) => (0, 1, 0, 0),
        // A finished match with no winner is a tie; anything else abandoned.
        None if state.innings.iter().all(|i| i.complete) => (0, 0, 1, 0),
        None => (0, 0, 0, 1),
    };

    sqlx::query(
        r#"
        INSERT INTO club_season_stats (
            club_id, team_id, sport, season_year, source,
            matches_played, wins, losses, draws, no_results,
            runs_for, runs_against, wickets_taken, wickets_lost
        ) VALUES ($1, NULL, 'cricket', $2, 'fishers_scoring',
                  1, $3, $4, $5, $6, $7, $8, $9, $10)
        ON CONFLICT (club_id, sport, season_year, source) WHERE team_id IS NULL
        DO UPDATE SET
            matches_played = club_season_stats.matches_played + 1,
            wins           = club_season_stats.wins + EXCLUDED.wins,
            losses         = club_season_stats.losses + EXCLUDED.losses,
            draws          = club_season_stats.draws + EXCLUDED.draws,
            no_results     = club_season_stats.no_results + EXCLUDED.no_results,
            runs_for       = club_season_stats.runs_for + EXCLUDED.runs_for,
            runs_against   = club_season_stats.runs_against + EXCLUDED.runs_against,
            wickets_taken  = club_season_stats.wickets_taken + EXCLUDED.wickets_taken,
            wickets_lost   = club_season_stats.wickets_lost + EXCLUDED.wickets_lost,
            updated_at     = NOW()
        "#,
    )
    .bind(club_id)
    .bind(season_year)
    .bind(win)
    .bind(loss)
    .bind(draw)
    .bind(no_result)
    .bind(runs_for)
    .bind(runs_against)
    .bind(wickets_taken)
    .bind(wickets_lost)
    .execute(&mut **tx)
    .await?;

    Ok(())
}

/// Fold the scorecard into one row per player.
fn tally_players(state: &MatchState) -> std::collections::HashMap<Uuid, PlayerTally> {
    use fishers_domain::DismissalKind;
    let mut tallies: std::collections::HashMap<Uuid, PlayerTally> = Default::default();

    for id in state.home_xi.iter().chain(state.away_xi.iter()) {
        tallies.entry(*id).or_default().matches = 1;
    }

    for innings in &state.innings {
        for batter in &innings.batters {
            if !batter.has_batted() {
                continue;
            }
            let tally = tallies.entry(batter.player_id).or_default();
            tally.runs += batter.runs as i32;
            tally.balls_faced += batter.balls as i32;
            tally.fours += batter.fours as i32;
            tally.sixes += batter.sixes as i32;
            tally.batting_innings += 1;
            if !batter.out {
                tally.not_outs += 1;
            }
            tally.high_score = tally.high_score.max(batter.runs as i32);

            // Fielding credit comes off the dismissal that took the wicket.
            if let (Some(fielder), Some(kind)) = (batter.fielder_id, batter.dismissal) {
                let fielding = tallies.entry(fielder).or_default();
                match kind {
                    DismissalKind::Caught => fielding.catches += 1,
                    DismissalKind::Stumped => fielding.stumpings += 1,
                    _ => {}
                }
            }
        }

        for bowler in &innings.bowlers {
            if bowler.balls == 0 && bowler.runs == 0 {
                continue;
            }
            let tally = tallies.entry(bowler.player_id).or_default();
            tally.bowling_balls += bowler.balls as i32;
            tally.bowling_runs += bowler.runs as i32;
            tally.wickets += bowler.wickets as i32;
            tally.maidens += bowler.maidens as i32;
        }
    }

    tallies
}

/// Write the result onto the fixture's tournament entrants, when it has any.
async fn record_tournament_result(
    tx: &mut Transaction<'_, Postgres>,
    event_id: Uuid,
    state: &MatchState,
) -> Result<(), sqlx::Error> {
    let rules: Option<(i32, i32, i32)> = sqlx::query_as(
        r#"
        SELECT b.points_win, b.points_draw, b.points_no_result
        FROM events e
        JOIN fixture_blocks b ON b.id = e.fixture_block_id
        WHERE e.id = $1
        "#,
    )
    .bind(event_id)
    .fetch_optional(&mut **tx)
    .await?;

    let Some((points_win, points_draw, _points_no_result)) = rules else {
        return Ok(()); // not part of a tournament
    };

    // The score each side made, from whichever innings they batted in.
    let score_for = |side: fishers_domain::MatchSide| -> Option<i32> {
        state
            .innings
            .iter()
            .find(|inn| inn.batting == side)
            .map(|inn| inn.runs as i32)
    };
    let home = score_for(fishers_domain::MatchSide::Home);
    let away = score_for(fishers_domain::MatchSide::Away);

    for (side, score, other) in [
        ("home", home, away),
        ("away", away, home),
    ] {
        let (result, points) = match (score, other) {
            (Some(a), Some(b)) if a > b => ("win", points_win),
            (Some(a), Some(b)) if a < b => ("loss", 0),
            (Some(_), Some(_)) => ("draw", points_draw),
            _ => continue,
        };
        sqlx::query(
            r#"
            UPDATE event_entrants
            SET score = $3, result = $4, points = $5
            WHERE event_id = $1 AND side = $2
            "#,
        )
        .bind(event_id)
        .bind(side)
        .bind(score)
        .bind(result)
        .bind(points)
        .execute(&mut **tx)
        .await?;
    }

    Ok(())
}
