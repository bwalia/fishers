use chrono::{DateTime, Utc};
use fishers_domain::{CreateEventRequest, Event, EventStatus, MatchResult, UpdateEventRequest};
use serde_json::json;
use sqlx::PgPool;
use uuid::Uuid;

pub async fn create_event(
    pool: &PgPool,
    created_by: Uuid,
    req: &CreateEventRequest,
) -> Result<Event, sqlx::Error> {
    let metadata = req.metadata.clone().unwrap_or_else(|| json!({}));
    let currency = req
        .fee_currency
        .clone()
        .unwrap_or_else(|| "GBP".to_string());

    sqlx::query_as::<_, Event>(
        r#"
        INSERT INTO events (
            club_id, team_id, sport, event_subtype, title, venue_id,
            start_at, end_at, recurrence_rule, capacity, fee_amount_cents,
            fee_currency, status, metadata, created_by
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'scheduled',$13,$14)
        RETURNING id, club_id, team_id, sport, event_subtype, title, venue_id,
                  start_at, end_at, recurrence_rule, recurrence_parent_id,
                  capacity, fee_amount_cents, fee_currency, status, status_note,
                  rescheduled_to, metadata, created_by, created_at, updated_at
        "#,
    )
    .bind(req.club_id)
    .bind(req.team_id)
    .bind(req.sport)
    .bind(req.event_subtype)
    .bind(&req.title)
    .bind(req.venue_id)
    .bind(req.start_at)
    .bind(req.end_at)
    .bind(&req.recurrence_rule)
    .bind(req.capacity)
    .bind(req.fee_amount_cents)
    .bind(currency)
    .bind(metadata)
    .bind(created_by)
    .fetch_one(pool)
    .await
}

pub async fn get_event(pool: &PgPool, event_id: Uuid) -> Result<Option<Event>, sqlx::Error> {
    sqlx::query_as::<_, Event>(
        r#"
        SELECT id, club_id, team_id, sport, event_subtype, title, venue_id,
               start_at, end_at, recurrence_rule, recurrence_parent_id,
               capacity, fee_amount_cents, fee_currency, status, status_note,
               rescheduled_to, metadata, created_by, created_at, updated_at
        FROM events WHERE id = $1
        "#,
    )
    .bind(event_id)
    .fetch_optional(pool)
    .await
}

/// Fixtures the user is entitled to see. Without a `club_id` this is every
/// club they belong to — never the whole table.
pub async fn list_events(
    pool: &PgPool,
    viewer_id: Uuid,
    club_id: Option<Uuid>,
    from: Option<DateTime<Utc>>,
    to: Option<DateTime<Utc>>,
    cricket_season: bool,
    limit: i64,
) -> Result<Vec<Event>, sqlx::Error> {
    let mut sql = String::from(
        r#"
        SELECT e.id, e.club_id, e.team_id, e.sport, e.event_subtype, e.title, e.venue_id,
               e.start_at, e.end_at, e.recurrence_rule, e.recurrence_parent_id,
               e.capacity, e.fee_amount_cents, e.fee_currency, e.status, e.status_note,
               e.rescheduled_to, e.metadata, e.created_by, e.created_at, e.updated_at
        FROM events e
        JOIN club_members cm ON cm.club_id = e.club_id
                            AND cm.user_id = $1
                            AND cm.status = 'active'
        WHERE e.status <> 'cancelled'
        "#,
    );
    let mut next = 2;
    let club_param = club_id.map(|_| { let p = next; next += 1; p });
    let from_param = from.map(|_| { let p = next; next += 1; p });
    let to_param = to.map(|_| { let p = next; next += 1; p });

    if let Some(p) = club_param {
        sql.push_str(&format!(" AND e.club_id = ${p}"));
    }
    if let Some(p) = from_param {
        sql.push_str(&format!(" AND e.start_at >= ${p}"));
    }
    if let Some(p) = to_param {
        sql.push_str(&format!(" AND e.start_at <= ${p}"));
    }
    if cricket_season {
        sql.push_str(
            " AND e.sport = 'cricket' \
              AND e.event_subtype IN ('nets','friendly','league_match','tournament')",
        );
    }
    sql.push_str(&format!(" ORDER BY e.start_at ASC LIMIT ${next}"));

    let mut query = sqlx::query_as::<_, Event>(&sql).bind(viewer_id);
    if let Some(id) = club_id {
        query = query.bind(id);
    }
    if let Some(f) = from {
        query = query.bind(f);
    }
    if let Some(t) = to {
        query = query.bind(t);
    }
    query.bind(limit.clamp(1, 500)).fetch_all(pool).await
}

pub async fn update_event(
    pool: &PgPool,
    event_id: Uuid,
    req: &UpdateEventRequest,
) -> Result<Event, sqlx::Error> {
    let current = get_event(pool, event_id)
        .await?
        .ok_or(sqlx::Error::RowNotFound)?;

    let title = req.title.clone().unwrap_or(current.title);
    let venue_id = req.venue_id.or(current.venue_id);
    let start_at = req.start_at.unwrap_or(current.start_at);
    let end_at = req.end_at.unwrap_or(current.end_at);
    let capacity = req.capacity.or(current.capacity);
    let fee = req.fee_amount_cents.or(current.fee_amount_cents);
    let status = req.status.unwrap_or(current.status);
    let metadata = req.metadata.clone().unwrap_or(current.metadata);

    sqlx::query_as::<_, Event>(
        r#"
        UPDATE events SET
            title = $2, venue_id = $3, start_at = $4, end_at = $5,
            capacity = $6, fee_amount_cents = $7, status = $8,
            metadata = $9, updated_at = NOW()
        WHERE id = $1
        RETURNING id, club_id, team_id, sport, event_subtype, title, venue_id,
                  start_at, end_at, recurrence_rule, recurrence_parent_id,
                  capacity, fee_amount_cents, fee_currency, status, status_note,
                  rescheduled_to, metadata, created_by, created_at, updated_at
        "#,
    )
    .bind(event_id)
    .bind(title)
    .bind(venue_id)
    .bind(start_at)
    .bind(end_at)
    .bind(capacity)
    .bind(fee)
    .bind(status)
    .bind(metadata)
    .fetch_one(pool)
    .await
}

pub async fn cancel_event(pool: &PgPool, event_id: Uuid) -> Result<Event, sqlx::Error> {
    sqlx::query_as::<_, Event>(
        r#"
        UPDATE events SET status = $2, updated_at = NOW() WHERE id = $1
        RETURNING id, club_id, team_id, sport, event_subtype, title, venue_id,
                  start_at, end_at, recurrence_rule, recurrence_parent_id,
                  capacity, fee_amount_cents, fee_currency, status, status_note,
                  rescheduled_to, metadata, created_by, created_at, updated_at
        "#,
    )
    .bind(event_id)
    .bind(EventStatus::Cancelled)
    .fetch_one(pool)
    .await
}

pub async fn upsert_match_result(
    pool: &PgPool,
    result: &MatchResult,
) -> Result<MatchResult, sqlx::Error> {
    sqlx::query_as::<_, MatchResult>(
        r#"
        INSERT INTO match_results (event_id, format, opposition, home_or_away, scorecard_json)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (event_id) DO UPDATE SET
            format = EXCLUDED.format,
            opposition = EXCLUDED.opposition,
            home_or_away = EXCLUDED.home_or_away,
            scorecard_json = EXCLUDED.scorecard_json
        RETURNING event_id, format, opposition, home_or_away, scorecard_json, created_at
        "#,
    )
    .bind(result.event_id)
    .bind(&result.format)
    .bind(&result.opposition)
    .bind(result.home_or_away)
    .bind(&result.scorecard_json)
    .fetch_one(pool)
    .await
}

/// Create a tour, tournament or "next few weeks" block, pulling in fixtures.
pub async fn create_fixture_block(
    pool: &PgPool,
    created_by: Uuid,
    req: &fishers_domain::CreateFixtureBlockRequest,
) -> Result<fishers_domain::FixtureBlock, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let block = sqlx::query_as::<_, fishers_domain::FixtureBlock>(
        r#"
        INSERT INTO fixture_blocks (club_id, team_id, name, kind, starts_on, ends_on, created_by)
        VALUES ($1, $2, $3, COALESCE($4, 'block'), $5, $6, $7)
        RETURNING id, club_id, team_id, name, kind, starts_on, ends_on, created_at
        "#,
    )
    .bind(req.club_id)
    .bind(req.team_id)
    .bind(&req.name)
    .bind(&req.kind)
    .bind(req.starts_on)
    .bind(req.ends_on)
    .bind(created_by)
    .fetch_one(&mut *tx)
    .await?;

    if !req.event_ids.is_empty() {
        sqlx::query("UPDATE events SET fixture_block_id = $1 WHERE id = ANY($2) AND club_id = $3")
            .bind(block.id)
            .bind(&req.event_ids)
            .bind(req.club_id)
            .execute(&mut *tx)
            .await?;
    }

    tx.commit().await?;
    Ok(block)
}

pub async fn list_fixture_blocks(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Vec<fishers_domain::FixtureBlock>, sqlx::Error> {
    sqlx::query_as::<_, fishers_domain::FixtureBlock>(
        r#"
        SELECT id, club_id, team_id, name, kind, starts_on, ends_on, created_at
        FROM fixture_blocks WHERE club_id = $1 ORDER BY starts_on DESC NULLS LAST, created_at DESC
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// Fixtures in a block, in playing order.
pub async fn list_block_events(
    pool: &PgPool,
    block_id: Uuid,
) -> Result<Vec<fishers_domain::Event>, sqlx::Error> {
    sqlx::query_as::<_, fishers_domain::Event>(
        r#"
        SELECT id, club_id, team_id, sport, event_subtype, title, venue_id, start_at, end_at,
               recurrence_rule, recurrence_parent_id, capacity, fee_amount_cents, fee_currency,
               status, status_note, rescheduled_to, metadata, created_by, created_at, updated_at
        FROM events
        WHERE fixture_block_id = $1 AND status <> 'cancelled'
        ORDER BY start_at
        "#,
    )
    .bind(block_id)
    .fetch_all(pool)
    .await
}
