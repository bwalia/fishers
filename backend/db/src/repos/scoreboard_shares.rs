//! Revocable secure tokens for public live scoreboard links.

use chrono::{DateTime, Duration, Utc};
use rand::RngCore;
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct ScoreboardShareRow {
    pub id: Uuid,
    pub match_id: Uuid,
    pub token: String,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub revoked_at: Option<DateTime<Utc>>,
    pub conversation_id: Option<Uuid>,
}

fn new_token() -> String {
    let mut bytes = [0u8; 24];
    rand::thread_rng().fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Create a share token (default TTL). Reuses an active unexpired token for the same match.
pub async fn create_or_reuse(
    pool: &PgPool,
    match_id: Uuid,
    created_by: Uuid,
    ttl_hours: i64,
) -> Result<ScoreboardShareRow, sqlx::Error> {
    if let Some(existing) = active_for_match(pool, match_id).await? {
        return Ok(existing);
    }

    let token = new_token();
    let expires_at = Utc::now() + Duration::hours(ttl_hours.max(1));
    sqlx::query_as::<_, ScoreboardShareRow>(
        r#"
        INSERT INTO cricket_scoreboard_shares (match_id, token, created_by, expires_at)
        VALUES ($1, $2, $3, $4)
        RETURNING id, match_id, token, created_by, created_at, expires_at, revoked_at, conversation_id
        "#,
    )
    .bind(match_id)
    .bind(token)
    .bind(created_by)
    .bind(expires_at)
    .fetch_one(pool)
    .await
}

pub async fn active_for_match(
    pool: &PgPool,
    match_id: Uuid,
) -> Result<Option<ScoreboardShareRow>, sqlx::Error> {
    sqlx::query_as::<_, ScoreboardShareRow>(
        r#"
        SELECT id, match_id, token, created_by, created_at, expires_at, revoked_at, conversation_id
        FROM cricket_scoreboard_shares
        WHERE match_id = $1
          AND revoked_at IS NULL
          AND expires_at > NOW()
        ORDER BY created_at DESC
        LIMIT 1
        "#,
    )
    .bind(match_id)
    .fetch_optional(pool)
    .await
}

pub async fn find_valid_by_token(
    pool: &PgPool,
    token: &str,
) -> Result<Option<ScoreboardShareRow>, sqlx::Error> {
    sqlx::query_as::<_, ScoreboardShareRow>(
        r#"
        SELECT id, match_id, token, created_by, created_at, expires_at, revoked_at, conversation_id
        FROM cricket_scoreboard_shares
        WHERE token = $1
          AND revoked_at IS NULL
          AND expires_at > NOW()
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await
}

pub async fn attach_conversation(
    pool: &PgPool,
    share_id: Uuid,
    conversation_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE cricket_scoreboard_shares SET conversation_id = $2 WHERE id = $1",
    )
    .bind(share_id)
    .bind(conversation_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn revoke(pool: &PgPool, match_id: Uuid, token: &str) -> Result<u64, sqlx::Error> {
    let res = sqlx::query(
        r#"
        UPDATE cricket_scoreboard_shares
        SET revoked_at = NOW()
        WHERE match_id = $1 AND token = $2 AND revoked_at IS NULL
        "#,
    )
    .bind(match_id)
    .bind(token)
    .execute(pool)
    .await?;
    Ok(res.rows_affected())
}
