//! Venue hire repositories — spaces, rates, availability, blackouts.

use fishers_domain::{
    CreateVenueBlackoutRequest, CreateVenueRateCardRequest, CreateVenueSpaceRequest,
    HireableSpaceRow, SetVenueAvailabilityRequest, UpdateVenueSpaceRequest, VenueAvailabilityWindow,
    VenueBlackout, VenueRateCard, VenueSpace,
};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn get_venue_club_id(pool: &PgPool, venue_id: Uuid) -> Result<Option<Uuid>, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>("SELECT club_id FROM venues WHERE id = $1")
        .bind(venue_id)
        .fetch_optional(pool)
        .await
}

pub async fn get_space(pool: &PgPool, space_id: Uuid) -> Result<Option<VenueSpace>, sqlx::Error> {
    sqlx::query_as::<_, VenueSpace>(
        r#"
        SELECT id, venue_id, name, kind, sports, capacity, is_hireable, requires_approval,
               notice_hours_min, notice_days_max, slot_minutes, buffer_minutes, notes, active,
               timezone, created_at, updated_at
        FROM venue_spaces WHERE id = $1
        "#,
    )
    .bind(space_id)
    .fetch_optional(pool)
    .await
}

pub async fn space_club_id(pool: &PgPool, space_id: Uuid) -> Result<Option<Uuid>, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        r#"
        SELECT v.club_id
        FROM venue_spaces s
        JOIN venues v ON v.id = s.venue_id
        WHERE s.id = $1
        "#,
    )
    .bind(space_id)
    .fetch_optional(pool)
    .await
}

pub async fn list_spaces_for_venue(
    pool: &PgPool,
    venue_id: Uuid,
) -> Result<Vec<VenueSpace>, sqlx::Error> {
    sqlx::query_as::<_, VenueSpace>(
        r#"
        SELECT id, venue_id, name, kind, sports, capacity, is_hireable, requires_approval,
               notice_hours_min, notice_days_max, slot_minutes, buffer_minutes, notes, active,
               timezone, created_at, updated_at
        FROM venue_spaces
        WHERE venue_id = $1
        ORDER BY name
        "#,
    )
    .bind(venue_id)
    .fetch_all(pool)
    .await
}

pub async fn create_space(
    pool: &PgPool,
    venue_id: Uuid,
    req: &CreateVenueSpaceRequest,
) -> Result<VenueSpace, sqlx::Error> {
    sqlx::query_as::<_, VenueSpace>(
        r#"
        INSERT INTO venue_spaces (
            venue_id, name, kind, sports, capacity, is_hireable, requires_approval,
            notice_hours_min, notice_days_max, slot_minutes, buffer_minutes, notes, timezone
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
        RETURNING id, venue_id, name, kind, sports, capacity, is_hireable, requires_approval,
                  notice_hours_min, notice_days_max, slot_minutes, buffer_minutes, notes, active,
                  timezone, created_at, updated_at
        "#,
    )
    .bind(venue_id)
    .bind(&req.name)
    .bind(req.kind)
    .bind(&req.sports)
    .bind(req.capacity)
    .bind(req.is_hireable)
    .bind(req.requires_approval)
    .bind(req.notice_hours_min)
    .bind(req.notice_days_max)
    .bind(req.slot_minutes)
    .bind(req.buffer_minutes)
    .bind(&req.notes)
    .bind(&req.timezone)
    .fetch_one(pool)
    .await
}

pub async fn update_space(
    pool: &PgPool,
    space_id: Uuid,
    req: &UpdateVenueSpaceRequest,
) -> Result<Option<VenueSpace>, sqlx::Error> {
    let Some(existing) = get_space(pool, space_id).await? else {
        return Ok(None);
    };
    let name = req.name.clone().unwrap_or(existing.name);
    let kind = req.kind.unwrap_or(existing.kind);
    let sports = req.sports.clone().unwrap_or(existing.sports);
    let capacity = match &req.capacity {
        Some(v) => *v,
        None => existing.capacity,
    };
    let is_hireable = req.is_hireable.unwrap_or(existing.is_hireable);
    let requires_approval = req.requires_approval.unwrap_or(existing.requires_approval);
    let notice_hours_min = req.notice_hours_min.unwrap_or(existing.notice_hours_min);
    let notice_days_max = req.notice_days_max.unwrap_or(existing.notice_days_max);
    let slot_minutes = req.slot_minutes.unwrap_or(existing.slot_minutes);
    let buffer_minutes = req.buffer_minutes.unwrap_or(existing.buffer_minutes);
    let notes = match &req.notes {
        Some(v) => v.clone(),
        None => existing.notes,
    };
    let active = req.active.unwrap_or(existing.active);
    let timezone = req.timezone.clone().unwrap_or(existing.timezone);

    let row = sqlx::query_as::<_, VenueSpace>(
        r#"
        UPDATE venue_spaces SET
            name = $2, kind = $3, sports = $4, capacity = $5, is_hireable = $6,
            requires_approval = $7, notice_hours_min = $8, notice_days_max = $9,
            slot_minutes = $10, buffer_minutes = $11, notes = $12, active = $13,
            timezone = $14, updated_at = NOW()
        WHERE id = $1
        RETURNING id, venue_id, name, kind, sports, capacity, is_hireable, requires_approval,
                  notice_hours_min, notice_days_max, slot_minutes, buffer_minutes, notes, active,
                  timezone, created_at, updated_at
        "#,
    )
    .bind(space_id)
    .bind(&name)
    .bind(kind)
    .bind(&sports)
    .bind(capacity)
    .bind(is_hireable)
    .bind(requires_approval)
    .bind(notice_hours_min)
    .bind(notice_days_max)
    .bind(slot_minutes)
    .bind(buffer_minutes)
    .bind(&notes)
    .bind(active)
    .bind(&timezone)
    .fetch_one(pool)
    .await?;
    Ok(Some(row))
}

pub async fn list_rate_cards(
    pool: &PgPool,
    space_id: Uuid,
) -> Result<Vec<VenueRateCard>, sqlx::Error> {
    sqlx::query_as::<_, VenueRateCard>(
        r#"
        SELECT id, space_id, name, unit, amount_cents, currency, member_amount_cents,
               days_of_week, time_from, time_to, season_from, season_to, min_units, active,
               created_at
        FROM venue_rate_cards
        WHERE space_id = $1
        ORDER BY amount_cents, name
        "#,
    )
    .bind(space_id)
    .fetch_all(pool)
    .await
}

pub async fn create_rate_card(
    pool: &PgPool,
    space_id: Uuid,
    req: &CreateVenueRateCardRequest,
) -> Result<VenueRateCard, sqlx::Error> {
    sqlx::query_as::<_, VenueRateCard>(
        r#"
        INSERT INTO venue_rate_cards (
            space_id, name, unit, amount_cents, currency, member_amount_cents,
            days_of_week, time_from, time_to, season_from, season_to, min_units
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
        RETURNING id, space_id, name, unit, amount_cents, currency, member_amount_cents,
                  days_of_week, time_from, time_to, season_from, season_to, min_units, active,
                  created_at
        "#,
    )
    .bind(space_id)
    .bind(&req.name)
    .bind(req.unit)
    .bind(req.amount_cents)
    .bind(&req.currency)
    .bind(req.member_amount_cents)
    .bind(&req.days_of_week)
    .bind(req.time_from)
    .bind(req.time_to)
    .bind(req.season_from)
    .bind(req.season_to)
    .bind(req.min_units)
    .fetch_one(pool)
    .await
}

pub async fn set_rate_card_active(
    pool: &PgPool,
    rate_id: Uuid,
    active: bool,
) -> Result<Option<VenueRateCard>, sqlx::Error> {
    sqlx::query_as::<_, VenueRateCard>(
        r#"
        UPDATE venue_rate_cards SET active = $2
        WHERE id = $1
        RETURNING id, space_id, name, unit, amount_cents, currency, member_amount_cents,
                  days_of_week, time_from, time_to, season_from, season_to, min_units, active,
                  created_at
        "#,
    )
    .bind(rate_id)
    .bind(active)
    .fetch_optional(pool)
    .await
}

pub async fn rate_card_club_id(pool: &PgPool, rate_id: Uuid) -> Result<Option<Uuid>, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        r#"
        SELECT v.club_id
        FROM venue_rate_cards r
        JOIN venue_spaces s ON s.id = r.space_id
        JOIN venues v ON v.id = s.venue_id
        WHERE r.id = $1
        "#,
    )
    .bind(rate_id)
    .fetch_optional(pool)
    .await
}

pub async fn list_availability(
    pool: &PgPool,
    space_id: Uuid,
) -> Result<Vec<VenueAvailabilityWindow>, sqlx::Error> {
    sqlx::query_as::<_, VenueAvailabilityWindow>(
        r#"
        SELECT id, space_id, day_of_week, opens_at, closes_at
        FROM venue_availability
        WHERE space_id = $1
        ORDER BY day_of_week, opens_at
        "#,
    )
    .bind(space_id)
    .fetch_all(pool)
    .await
}

/// Replace the whole weekly opening-hours set for a space.
pub async fn replace_availability(
    pool: &PgPool,
    space_id: Uuid,
    req: &SetVenueAvailabilityRequest,
) -> Result<Vec<VenueAvailabilityWindow>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    sqlx::query("DELETE FROM venue_availability WHERE space_id = $1")
        .bind(space_id)
        .execute(&mut *tx)
        .await?;
    for w in &req.windows {
        sqlx::query(
            r#"
            INSERT INTO venue_availability (space_id, day_of_week, opens_at, closes_at)
            VALUES ($1, $2, $3, $4)
            "#,
        )
        .bind(space_id)
        .bind(w.day_of_week)
        .bind(w.opens_at)
        .bind(w.closes_at)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    list_availability(pool, space_id).await
}

pub async fn list_blackouts(
    pool: &PgPool,
    space_id: Uuid,
) -> Result<Vec<VenueBlackout>, sqlx::Error> {
    sqlx::query_as::<_, VenueBlackout>(
        r#"
        SELECT id, space_id, starts_at, ends_at, reason, created_at
        FROM venue_blackouts
        WHERE space_id = $1
        ORDER BY starts_at
        "#,
    )
    .bind(space_id)
    .fetch_all(pool)
    .await
}

pub async fn create_blackout(
    pool: &PgPool,
    space_id: Uuid,
    req: &CreateVenueBlackoutRequest,
) -> Result<VenueBlackout, sqlx::Error> {
    sqlx::query_as::<_, VenueBlackout>(
        r#"
        INSERT INTO venue_blackouts (space_id, starts_at, ends_at, reason)
        VALUES ($1, $2, $3, $4)
        RETURNING id, space_id, starts_at, ends_at, reason, created_at
        "#,
    )
    .bind(space_id)
    .bind(req.starts_at)
    .bind(req.ends_at)
    .bind(&req.reason)
    .fetch_one(pool)
    .await
}

pub async fn delete_blackout(pool: &PgPool, blackout_id: Uuid) -> Result<bool, sqlx::Error> {
    let r = sqlx::query("DELETE FROM venue_blackouts WHERE id = $1")
        .bind(blackout_id)
        .execute(pool)
        .await?;
    Ok(r.rows_affected() > 0)
}

pub async fn blackout_club_id(
    pool: &PgPool,
    blackout_id: Uuid,
) -> Result<Option<Uuid>, sqlx::Error> {
    sqlx::query_scalar::<_, Uuid>(
        r#"
        SELECT v.club_id
        FROM venue_blackouts b
        JOIN venue_spaces s ON s.id = b.space_id
        JOIN venues v ON v.id = s.venue_id
        WHERE b.id = $1
        "#,
    )
    .bind(blackout_id)
    .fetch_optional(pool)
    .await
}

/// Public / member browse of hireable active spaces across clubs.
pub async fn list_hireable_spaces(
    pool: &PgPool,
    sport: Option<&str>,
    q: Option<&str>,
    limit: i64,
) -> Result<Vec<HireableSpaceRow>, sqlx::Error> {
    let limit = limit.clamp(1, 100);
    sqlx::query_as::<_, HireableSpaceRow>(
        r#"
        SELECT
            s.id AS space_id,
            s.name AS space_name,
            s.kind,
            s.sports,
            s.capacity,
            s.requires_approval,
            s.timezone,
            v.id AS venue_id,
            v.name AS venue_name,
            v.address AS venue_address,
            v.lat AS venue_lat,
            v.lng AS venue_lng,
            c.id AS club_id,
            c.name AS club_name,
            (
                SELECT MIN(r.amount_cents)
                FROM venue_rate_cards r
                WHERE r.space_id = s.id AND r.active
            ) AS from_amount_cents,
            (
                SELECT r.currency
                FROM venue_rate_cards r
                WHERE r.space_id = s.id AND r.active
                ORDER BY r.amount_cents
                LIMIT 1
            ) AS currency
        FROM venue_spaces s
        JOIN venues v ON v.id = s.venue_id
        JOIN clubs c ON c.id = v.club_id
        WHERE s.is_hireable AND s.active
          AND ($1::text IS NULL OR $1 = ANY(s.sports))
          AND (
            $2::text IS NULL
            OR s.name ILIKE '%' || $2 || '%'
            OR v.name ILIKE '%' || $2 || '%'
            OR c.name ILIKE '%' || $2 || '%'
          )
        ORDER BY c.name, v.name, s.name
        LIMIT $3
        "#,
    )
    .bind(sport)
    .bind(q)
    .bind(limit)
    .fetch_all(pool)
    .await
}
