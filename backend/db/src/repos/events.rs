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
/// A page of results, with the total so a list can say "21–40 of 143" rather
/// than leaving the reader to guess whether there is more.
#[derive(Debug, Clone, serde::Serialize)]
pub struct Page<T> {
    pub items: Vec<T>,
    pub total: i64,
    pub page: i64,
    pub per_page: i64,
    pub has_more: bool,
}

/// What a list can be ordered by.
///
/// An enum rather than a string, because the only safe way to put a column
/// name into SQL is to never take one from the caller.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventSort {
    StartAt,
    Title,
    CreatedAt,
}

impl Default for EventSort {
    fn default() -> Self {
        Self::StartAt
    }
}

impl EventSort {
    fn column(self) -> &'static str {
        match self {
            Self::StartAt => "e.start_at",
            // Case-insensitive, or "aardvark" sorts after "Zebra".
            Self::Title => "LOWER(e.title)",
            Self::CreatedAt => "e.created_at",
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct EventFilter {
    pub club_id: Option<Uuid>,
    pub from: Option<DateTime<Utc>>,
    pub to: Option<DateTime<Utc>>,
    /// Cricket nets and match subtypes only — the season view.
    pub cricket_season: bool,
    pub sport: Option<String>,
    pub subtype: Option<String>,
    pub status: Option<String>,
    /// Matched against the title.
    pub search: Option<String>,
    pub sort: EventSort,
    pub descending: bool,
    /// 1-based.
    pub page: i64,
    pub per_page: i64,
}

/// Fixtures this person can see, filtered, sorted and paged in the database.
///
/// Everything a list screen needs happens here rather than in the browser:
/// a club with five seasons of history is not something to download and then
/// filter, and "showing 20 of 143" needs a count the client cannot work out
/// from a truncated page.
pub async fn list_events(
    pool: &PgPool,
    viewer_id: Uuid,
    filter: &EventFilter,
) -> Result<Page<Event>, sqlx::Error> {
    // Built once and used for both the count and the page, so the two can
    // never disagree about what is being asked for.
    let mut where_sql = String::from(
        r#"
        WHERE e.status <> 'cancelled'
          AND (
            EXISTS (
              SELECT 1 FROM club_members cm
              WHERE cm.club_id = e.club_id AND cm.user_id = $1 AND cm.status = 'active'
            )
            -- The visiting club has to see the fixture too. Without this the
            -- opposition captain cannot open the match they are being asked to
            -- agree terms for, and any notification about it leads nowhere.
            OR EXISTS (
              SELECT 1 FROM cricket_matches m
              JOIN club_members cm ON cm.club_id = m.opponent_club_id
                                  AND cm.user_id = $1 AND cm.status = 'active'
              WHERE m.event_id = e.id
            )
          )
        "#,
    );

    let mut next = 2;
    let mut bind = |used: bool| {
        used.then(|| {
            let p = next;
            next += 1;
            p
        })
    };
    let club_p = bind(filter.club_id.is_some());
    let from_p = bind(filter.from.is_some());
    let to_p = bind(filter.to.is_some());
    let sport_p = bind(filter.sport.is_some());
    let subtype_p = bind(filter.subtype.is_some());
    let status_p = bind(filter.status.is_some());
    let search_p = bind(filter.search.is_some());

    if let Some(p) = club_p {
        where_sql.push_str(&format!(" AND e.club_id = ${p}"));
    }
    if let Some(p) = from_p {
        where_sql.push_str(&format!(" AND e.start_at >= ${p}"));
    }
    if let Some(p) = to_p {
        where_sql.push_str(&format!(" AND e.start_at <= ${p}"));
    }
    if let Some(p) = sport_p {
        where_sql.push_str(&format!(" AND e.sport::TEXT = ${p}"));
    }
    if let Some(p) = subtype_p {
        where_sql.push_str(&format!(" AND e.event_subtype::TEXT = ${p}"));
    }
    if let Some(p) = status_p {
        where_sql.push_str(&format!(" AND e.status::TEXT = ${p}"));
    }
    if let Some(p) = search_p {
        where_sql.push_str(&format!(" AND e.title ILIKE '%' || ${p} || '%'"));
    }
    if filter.cricket_season {
        where_sql.push_str(
            " AND e.sport = 'cricket' \
              AND e.event_subtype IN ('nets','friendly','league_match','tournament')",
        );
    }

    /// Every filter binds in the same order for both queries.
    macro_rules! bind_filters {
        ($q:expr) => {{
            let mut q = $q.bind(viewer_id);
            if let Some(v) = filter.club_id {
                q = q.bind(v);
            }
            if let Some(v) = filter.from {
                q = q.bind(v);
            }
            if let Some(v) = filter.to {
                q = q.bind(v);
            }
            if let Some(v) = filter.sport.as_deref() {
                q = q.bind(v.to_string());
            }
            if let Some(v) = filter.subtype.as_deref() {
                q = q.bind(v.to_string());
            }
            if let Some(v) = filter.status.as_deref() {
                q = q.bind(v.to_string());
            }
            if let Some(v) = filter.search.as_deref() {
                q = q.bind(v.to_string());
            }
            q
        }};
    }

    // The query borrows the string, so it has to outlive the statement.
    let count_sql = format!("SELECT COUNT(*) FROM events e {where_sql}");
    let total: i64 = bind_filters!(sqlx::query_scalar::<_, i64>(&count_sql))
        .fetch_one(pool)
        .await?;

    let per_page = filter.per_page.clamp(1, 200);
    let page = filter.page.max(1);
    let offset = (page - 1) * per_page;
    let direction = if filter.descending { "DESC" } else { "ASC" };
    // `id` breaks ties, or two fixtures at the same time can swap between
    // pages and one of them is never seen.
    let sql = format!(
        r#"
        SELECT e.id, e.club_id, e.team_id, e.sport, e.event_subtype, e.title, e.venue_id,
               e.start_at, e.end_at, e.recurrence_rule, e.recurrence_parent_id,
               e.capacity, e.fee_amount_cents, e.fee_currency, e.status, e.status_note,
               e.rescheduled_to, e.metadata, e.created_by, e.created_at, e.updated_at
        FROM events e
        {where_sql}
        ORDER BY {} {direction}, e.id {direction}
        LIMIT ${} OFFSET ${}
        "#,
        filter.sort.column(),
        next,
        next + 1,
    );

    let items = bind_filters!(sqlx::query_as::<_, Event>(&sql))
        .bind(per_page)
        .bind(offset)
        .fetch_all(pool)
        .await?;

    Ok(Page {
        has_more: offset + (items.len() as i64) < total,
        items,
        total,
        page,
        per_page,
    })
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
