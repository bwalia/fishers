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

/// One page of somebody's notifications.
#[derive(Debug, Clone, Serialize)]
pub struct NotificationPage {
    pub items: Vec<Notification>,
    pub total: i64,
    pub page: i64,
    pub per_page: i64,
    pub has_more: bool,
    /// Unread across everything, not just this page — it is what the bell
    /// shows, and a filtered page must not change it.
    pub unread: i64,
    /// Every kind this person has ever been sent, so the filter offers only
    /// what would actually match something.
    pub kinds: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct NotificationFilter {
    /// One `notifications_log.type`.
    pub kind: Option<String>,
    pub unread_only: bool,
    /// Matched against the payload's title and body.
    pub search: Option<String>,
    /// 1-based.
    pub page: i64,
    pub per_page: i64,
}

/// Filtered, counted and paged in the database.
///
/// An active club generates thousands of these. Sending the lot to a browser
/// so it can slice twenty out of them is the kind of thing that works for a
/// month and then does not, and "showing 20 of 1,431" needs a count the client
/// cannot get from a truncated page.
pub async fn page_for(
    pool: &PgPool,
    user_id: Uuid,
    filter: &NotificationFilter,
) -> Result<NotificationPage, sqlx::Error> {
    let page = filter.page.max(1);
    let per_page = filter.per_page.clamp(1, 100);

    // One WHERE for the count and the page, so the two can never disagree
    // about what was asked for.
    let mut where_sql = String::from("WHERE user_id = $1");
    if filter.kind.is_some() {
        where_sql.push_str(" AND type = $2");
    }
    if filter.unread_only {
        where_sql.push_str(" AND read_at IS NULL");
    }
    if filter.search.is_some() {
        // The payload is free-form JSON; title and body are what a person
        // reads, so they are what a search looks in.
        where_sql.push_str(
            " AND (payload->>'title' ILIKE $3 OR payload->>'body' ILIKE $3)",
        );
    }

    let like = filter.search.as_ref().map(|s| format!("%{s}%"));

    let total: i64 = sqlx::query_scalar(&format!(
        "SELECT COUNT(*) FROM notifications_log {where_sql}"
    ))
    .bind(user_id)
    .bind(filter.kind.as_deref())
    .bind(like.as_deref())
    .fetch_one(pool)
    .await?;

    let items = sqlx::query_as::<_, Notification>(&format!(
        "SELECT id, user_id, type, payload, sent_at, read_at
         FROM notifications_log
         {where_sql}
         ORDER BY sent_at DESC, id DESC
         LIMIT $4 OFFSET $5"
    ))
    .bind(user_id)
    .bind(filter.kind.as_deref())
    .bind(like.as_deref())
    .bind(per_page)
    .bind((page - 1) * per_page)
    .fetch_all(pool)
    .await?;

    let kinds: Vec<String> = sqlx::query_scalar(
        "SELECT DISTINCT type FROM notifications_log WHERE user_id = $1 ORDER BY type",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(NotificationPage {
        has_more: page * per_page < total,
        items,
        total,
        page,
        per_page,
        unread: unread_count(pool, user_id).await?,
        kinds,
    })
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
