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
                  capacity, fee_amount_cents, fee_currency, status, metadata,
                  created_by, created_at, updated_at
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
               capacity, fee_amount_cents, fee_currency, status, metadata,
               created_by, created_at, updated_at
        FROM events WHERE id = $1
        "#,
    )
    .bind(event_id)
    .fetch_optional(pool)
    .await
}

pub async fn list_events(
    pool: &PgPool,
    club_id: Option<Uuid>,
    from: Option<DateTime<Utc>>,
    to: Option<DateTime<Utc>>,
    cricket_season: bool,
) -> Result<Vec<Event>, sqlx::Error> {
    // Cricket season filter: nets + games for cricket Apr–Sep (caller supplies from/to)
    let mut sql = String::from(
        r#"
        SELECT id, club_id, team_id, sport, event_subtype, title, venue_id,
               start_at, end_at, recurrence_rule, recurrence_parent_id,
               capacity, fee_amount_cents, fee_currency, status, metadata,
               created_by, created_at, updated_at
        FROM events WHERE status <> 'cancelled'
        "#,
    );

    if club_id.is_some() {
        sql.push_str(" AND club_id = $1");
    }
    if from.is_some() {
        sql.push_str(if club_id.is_some() {
            " AND start_at >= $2"
        } else {
            " AND start_at >= $1"
        });
    }
    if to.is_some() {
        let idx = 1 + club_id.is_some() as i32 + from.is_some() as i32;
        sql.push_str(&format!(" AND start_at <= ${idx}"));
    }
    if cricket_season {
        sql.push_str(" AND sport = 'cricket' AND event_subtype IN ('nets','friendly','league_match','tournament')");
    }
    sql.push_str(" ORDER BY start_at ASC LIMIT 500");

    let mut query = sqlx::query_as::<_, Event>(&sql);
    if let Some(id) = club_id {
        query = query.bind(id);
    }
    if let Some(f) = from {
        query = query.bind(f);
    }
    if let Some(t) = to {
        query = query.bind(t);
    }

    query.fetch_all(pool).await
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
                  capacity, fee_amount_cents, fee_currency, status, metadata,
                  created_by, created_at, updated_at
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
                  capacity, fee_amount_cents, fee_currency, status, metadata,
                  created_by, created_at, updated_at
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
