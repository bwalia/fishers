//! Background jobs: recurring event materialisation and reminders.

use chrono::{Duration, Utc};
use fishers_notifications::PushService;
use sqlx::PgPool;
use tracing::{info, warn};

pub fn spawn_scheduler(pool: PgPool, push: PushService) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(300));
        loop {
            interval.tick().await;
            if let Err(e) = run_tick(&pool, &push).await {
                warn!(error = %e, "job tick failed");
            }
        }
    });
}

async fn run_tick(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    materialise_recurring(pool).await?;
    send_rsvp_reminders(pool, push).await?;
    Ok(())
}

/// Expand parent recurring events into concrete instances within the next 60 days.
async fn materialise_recurring(pool: &PgPool) -> anyhow::Result<()> {
    let parents = sqlx::query_as::<_, (uuid::Uuid, chrono::DateTime<Utc>, Option<String>)>(
        r#"
        SELECT id, start_at, recurrence_rule FROM events
        WHERE recurrence_rule IS NOT NULL
          AND recurrence_parent_id IS NULL
          AND status = 'scheduled'
        "#,
    )
    .fetch_all(pool)
    .await?;

    let mut created = 0u32;
    for (parent_id, start_at, rule) in parents {
        let Some(rule) = rule else { continue };
        // Minimal WEEKLY support: create next 8 weekly clones if missing.
        if !rule.to_uppercase().contains("FREQ=WEEKLY") {
            continue;
        }
        for week in 1..=8 {
            let next_start = start_at + Duration::weeks(week);
            if next_start > Utc::now() + Duration::days(60) {
                break;
            }
            let exists: (bool,) = sqlx::query_as(
                r#"
                SELECT EXISTS(
                  SELECT 1 FROM events
                  WHERE recurrence_parent_id = $1 AND start_at = $2
                )
                "#,
            )
            .bind(parent_id)
            .bind(next_start)
            .fetch_one(pool)
            .await?;
            if exists.0 {
                continue;
            }

            let res = sqlx::query(
                r#"
                INSERT INTO events (
                    club_id, team_id, sport, event_subtype, title, venue_id,
                    start_at, end_at, recurrence_rule, recurrence_parent_id,
                    capacity, fee_amount_cents, fee_currency, status, metadata, created_by
                )
                SELECT
                    club_id, team_id, sport, event_subtype, title, venue_id,
                    start_at + ($2::int * INTERVAL '1 week'),
                    end_at + ($2::int * INTERVAL '1 week'),
                    NULL, id,
                    capacity, fee_amount_cents, fee_currency, status, metadata, created_by
                FROM events WHERE id = $1
                "#,
            )
            .bind(parent_id)
            .bind(week as i32)
            .execute(pool)
            .await;
            if res.is_ok() {
                created += 1;
            }
        }
    }
    if created > 0 {
        info!(created, "materialised recurring event instances");
    }
    Ok(())
}

async fn send_rsvp_reminders(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    let rows = sqlx::query_as::<_, (uuid::Uuid, uuid::Uuid, String)>(
        r#"
        SELECT ei.user_id, e.id, e.title
        FROM event_invites ei
        JOIN events e ON e.id = ei.event_id
        WHERE ei.status = 'invited'
          AND e.start_at BETWEEN NOW() AND NOW() + INTERVAL '48 hours'
          AND e.status = 'scheduled'
        LIMIT 50
        "#,
    )
    .fetch_all(pool)
    .await?;

    for (user_id, event_id, title) in rows {
        push.send(
            user_id,
            "rsvp_reminder",
            "RSVP reminder",
            &format!("Please respond for {title}"),
            serde_json::json!({ "event_id": event_id }),
        )
        .await?;
    }
    Ok(())
}
