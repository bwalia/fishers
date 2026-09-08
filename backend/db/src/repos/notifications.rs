use chrono::{DateTime, Utc};
use serde::Serialize;
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

/// Something that happened which somebody needs to know about.
///
/// `notifications_log` has been in the schema since the first migration and
/// nothing ever wrote to it, so "you'll get a notification" was never true.
/// Storing it here means it survives whether or not a push is ever delivered —
/// the app can show it the next time it is opened, which is the only delivery
/// that works today.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct Notification {
    pub id: Uuid,
    pub user_id: Uuid,
    #[sqlx(rename = "type")]
    #[serde(rename = "type")]
    pub kind: String,
    pub payload: Value,
    pub sent_at: DateTime<Utc>,
    pub read_at: Option<DateTime<Utc>>,
}

pub async fn record(
    pool: &PgPool,
    user_id: Uuid,
    kind: &str,
    payload: &Value,
) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO notifications_log (user_id, type, payload) VALUES ($1, $2, $3)")
        .bind(user_id)
        .bind(kind)
        .bind(payload)
        .execute(pool)
        .await?;
    Ok(())
}

/// Newest first, capped — this feeds a bell, not an archive.
pub async fn list_for(
    pool: &PgPool,
    user_id: Uuid,
    limit: i64,
) -> Result<Vec<Notification>, sqlx::Error> {
    sqlx::query_as::<_, Notification>(
        "SELECT id, user_id, type, payload, sent_at, read_at
         FROM notifications_log
         WHERE user_id = $1
         ORDER BY sent_at DESC
         LIMIT $2",
    )
    .bind(user_id)
    .bind(limit.clamp(1, 100))
    .fetch_all(pool)
    .await
}

pub async fn unread_count(pool: &PgPool, user_id: Uuid) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM notifications_log WHERE user_id = $1 AND read_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Mark one as read, or all of them when no id is given.
pub async fn mark_read(
    pool: &PgPool,
    user_id: Uuid,
    id: Option<Uuid>,
) -> Result<u64, sqlx::Error> {
    let result = match id {
        Some(id) => {
            sqlx::query(
                "UPDATE notifications_log SET read_at = NOW()
                 WHERE user_id = $1 AND id = $2 AND read_at IS NULL",
            )
            .bind(user_id)
            .bind(id)
            .execute(pool)
            .await?
        }
        None => {
            sqlx::query(
                "UPDATE notifications_log SET read_at = NOW()
                 WHERE user_id = $1 AND read_at IS NULL",
            )
            .bind(user_id)
            .execute(pool)
            .await?
        }
    };
    Ok(result.rows_affected())
}
