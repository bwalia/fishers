//! Append-only platform event log (club activity bus seed).

use fishers_domain::{PlatformActor, PlatformEvent};
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

pub async fn emit(pool: &PgPool, event: &PlatformEvent) -> Result<(), sqlx::Error> {
    let actor = serde_json::to_value(&event.actor).unwrap_or(Value::Null);
    let payload = serde_json::to_value(&event.kind).unwrap_or(Value::Null);
    sqlx::query(
        r#"
        INSERT INTO platform_events (id, club_id, event_type, actor_json, payload, occurred_at)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (id) DO NOTHING
        "#,
    )
    .bind(event.id)
    .bind(event.club_id)
    .bind(event.type_name())
    .bind(actor)
    .bind(payload)
    .bind(event.occurred_at)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn list_for_club(
    pool: &PgPool,
    club_id: Uuid,
    limit: i64,
) -> Result<Vec<(Uuid, String, Value, chrono::DateTime<chrono::Utc>)>, sqlx::Error> {
    sqlx::query_as(
        r#"
        SELECT id, event_type, payload, occurred_at
        FROM platform_events
        WHERE club_id = $1
        ORDER BY occurred_at DESC
        LIMIT $2
        "#,
    )
    .bind(club_id)
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Best-effort emit — never fails the primary write path.
pub async fn emit_best_effort(pool: &PgPool, event: PlatformEvent) {
    if let Err(e) = emit(pool, &event).await {
        tracing::warn!(error = %e, "platform event emit failed");
    }
}

pub fn user_actor(user_id: Uuid) -> PlatformActor {
    PlatformActor::User { user_id }
}

pub fn agent_actor(proposal_id: Uuid) -> PlatformActor {
    PlatformActor::Agent { proposal_id }
}
