//! One-time codes for confirming an email address or a phone number.
//!
//! Only a hash of each code is stored. Attempts are counted per code, and the
//! API caps how many codes a person can have sent in an hour, so guessing a
//! six-digit code is bounded on both sides.

use sqlx::PgPool;
use uuid::Uuid;

pub struct ActiveCode {
    pub id: Uuid,
    pub target: String,
    pub code_hash: String,
    pub attempts: i32,
}

pub async fn create(
    pool: &PgPool,
    user_id: Uuid,
    channel: &str,
    target: &str,
    code_hash: &str,
    ttl_secs: i64,
) -> Result<(), sqlx::Error> {
    // A new code retires the old ones: only the latest is ever accepted.
    let mut tx = pool.begin().await?;
    sqlx::query(
        "UPDATE verification_codes SET consumed_at = now()
         WHERE user_id = $1 AND channel = $2 AND consumed_at IS NULL",
    )
    .bind(user_id)
    .bind(channel)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "INSERT INTO verification_codes (user_id, channel, target, code_hash, expires_at)
         VALUES ($1, $2, $3, $4, now() + make_interval(secs => $5))",
    )
    .bind(user_id)
    .bind(channel)
    .bind(target)
    .bind(code_hash)
    .bind(ttl_secs as f64)
    .execute(&mut *tx)
    .await?;
    tx.commit().await
}

/// Codes sent on this channel within the window, and seconds since the last.
pub async fn recent_sends(
    pool: &PgPool,
    user_id: Uuid,
    channel: &str,
    window_secs: i64,
) -> Result<(i64, Option<i64>), sqlx::Error> {
    sqlx::query_as(
        "SELECT count(*) FILTER (WHERE created_at > now() - make_interval(secs => $3)),
                extract(epoch FROM now() - max(created_at))::bigint
         FROM verification_codes WHERE user_id = $1 AND channel = $2",
    )
    .bind(user_id)
    .bind(channel)
    .bind(window_secs as f64)
    .fetch_one(pool)
    .await
}

/// The one live code for this channel, if any: unconsumed and unexpired.
pub async fn active(
    pool: &PgPool,
    user_id: Uuid,
    channel: &str,
) -> Result<Option<ActiveCode>, sqlx::Error> {
    let row: Option<(Uuid, String, String, i32)> = sqlx::query_as(
        "SELECT id, target, code_hash, attempts FROM verification_codes
         WHERE user_id = $1 AND channel = $2 AND consumed_at IS NULL AND expires_at > now()
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(user_id)
    .bind(channel)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|(id, target, code_hash, attempts)| ActiveCode {
        id,
        target,
        code_hash,
        attempts,
    }))
}

/// Counts a guess before it is checked, so a failed comparison can never be
/// retried for free.
pub async fn record_attempt(pool: &PgPool, id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE verification_codes SET attempts = attempts + 1 WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await
        .map(|_| ())
}

pub async fn consume(pool: &PgPool, id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE verification_codes SET consumed_at = now() WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await
        .map(|_| ())
}
