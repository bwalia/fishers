use chrono::NaiveDate;
use fishers_domain::{Availability, AvailabilityStatus, UpsertAvailabilityRequest};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn upsert(
    pool: &PgPool,
    user_id: Uuid,
    req: &UpsertAvailabilityRequest,
) -> Result<Availability, sqlx::Error> {
    sqlx::query_as::<_, Availability>(
        r#"
        INSERT INTO availability (user_id, date, status, note, recurrence_rule)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (user_id, date) DO UPDATE SET
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            recurrence_rule = COALESCE(EXCLUDED.recurrence_rule, availability.recurrence_rule),
            updated_at = NOW()
        RETURNING id, user_id, date, status, note, recurrence_rule, created_at, updated_at
        "#,
    )
    .bind(user_id)
    .bind(req.date)
    .bind(req.status)
    .bind(&req.note)
    .bind(&req.recurrence_rule)
    .fetch_one(pool)
    .await
}

pub async fn bulk_set(
    pool: &PgPool,
    user_id: Uuid,
    dates: &[NaiveDate],
    status: AvailabilityStatus,
    note: Option<&str>,
) -> Result<Vec<Availability>, sqlx::Error> {
    let mut out = Vec::with_capacity(dates.len());
    for date in dates {
        let row = upsert(
            pool,
            user_id,
            &UpsertAvailabilityRequest {
                date: *date,
                status,
                note: note.map(str::to_string),
                recurrence_rule: None,
            },
        )
        .await?;
        out.push(row);
    }
    Ok(out)
}

pub async fn list_range(
    pool: &PgPool,
    user_id: Uuid,
    from: NaiveDate,
    to: NaiveDate,
) -> Result<Vec<Availability>, sqlx::Error> {
    sqlx::query_as::<_, Availability>(
        r#"
        SELECT id, user_id, date, status, note, recurrence_rule, created_at, updated_at
        FROM availability
        WHERE user_id = $1 AND date >= $2 AND date <= $3
        ORDER BY date
        "#,
    )
    .bind(user_id)
    .bind(from)
    .bind(to)
    .fetch_all(pool)
    .await
}

pub async fn list_for_users_on_date(
    pool: &PgPool,
    user_ids: &[Uuid],
    date: NaiveDate,
) -> Result<Vec<Availability>, sqlx::Error> {
    sqlx::query_as::<_, Availability>(
        r#"
        SELECT id, user_id, date, status, note, recurrence_rule, created_at, updated_at
        FROM availability
        WHERE user_id = ANY($1) AND date = $2
        "#,
    )
    .bind(user_ids)
    .bind(date)
    .fetch_all(pool)
    .await
}
