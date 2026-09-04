//! Background jobs: recurring event materialisation and reminders.

use chrono::{Duration, Utc};
use fishers_db::repos::selection as selection_repo;
use fishers_notifications::{EmailService, PushService};
use sqlx::PgPool;
use tracing::{info, warn};

pub fn spawn_scheduler(pool: PgPool, push: PushService, email: EmailService) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(300));
        loop {
            interval.tick().await;
            if let Err(e) = run_tick(&pool, &push, &email).await {
                warn!(error = %e, "job tick failed");
            }
        }
    });
}

async fn run_tick(pool: &PgPool, push: &PushService, email: &EmailService) -> anyhow::Result<()> {
    materialise_recurring(pool).await?;
    send_rsvp_reminders(pool, push).await?;
    request_reconfirmations(pool, push, email).await?;
    drop_and_promote(pool, push).await?;
    chase_match_fees(pool, push, email).await?;
    Ok(())
}

/// Ask selected players to reconfirm as the deadline approaches — the point of
/// the whole workflow is that this happens two days out, not on the morning.
async fn request_reconfirmations(
    pool: &PgPool,
    push: &PushService,
    email: &EmailService,
) -> anyhow::Result<()> {
    let pending = selection_repo::unconfirmed_needing_reminder(pool).await?;
    for row in &pending {
        let body = format!(
            "You're picked for {} on {}. Confirm in the app so the captain knows.",
            row.title,
            row.start_at.format("%a %-d %b, %H:%M")
        );
        if let Err(e) = push
            .send(
                row.user_id,
                "selection_reconfirm",
                "Confirm you're playing",
                &body,
                serde_json::json!({ "event_id": row.event_id }),
            )
            .await
        {
            warn!(error = %e, "reconfirm push failed");
        }
        // Email needs the address; the push path already has the user id.
        if let Ok(Some(user)) = fishers_db::repos::users::find_by_id(pool, row.user_id).await {
            if let Err(e) = email
                .send(&user.email, &format!("Confirm: {}", row.title), &body)
                .await
            {
                warn!(error = %e, "reconfirm email failed");
            }
        }
        selection_repo::mark_reminded(pool, row.event_id, row.user_id).await?;
    }
    if !pending.is_empty() {
        info!(count = pending.len(), "reconfirmation reminders sent");
    }
    Ok(())
}

/// Past the drop deadline, the unconfirmed come out and reserves go in — so a
/// captain isn't chasing eleven people the night before.
async fn drop_and_promote(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    let affected = selection_repo::drop_unconfirmed(pool).await?;
    for event_id in affected {
        let policy = match sqlx::query_as::<_, (uuid::Uuid,)>(
            "SELECT club_id FROM events WHERE id = $1",
        )
        .bind(event_id)
        .fetch_one(pool)
        .await
        {
            Ok(row) => selection_repo::policy_for_club(pool, row.0).await?,
            Err(e) => {
                warn!(error = %e, "could not load club policy");
                continue;
            }
        };

        let promoted =
            selection_repo::promote_reserves(pool, event_id, policy.confirm_lead_hours).await?;
        for player in &promoted {
            if let Err(e) = push
                .send(
                    player.user_id,
                    "squad_promoted",
                    "You're in",
                    "A place opened up — you're in the squad. Confirm in the app.",
                    serde_json::json!({ "event_id": event_id }),
                )
                .await
            {
                warn!(error = %e, "promotion push failed");
            }
        }
        if !promoted.is_empty() {
            info!(count = promoted.len(), %event_id, "reserves promoted");
        }
    }
    Ok(())
}

/// Chase unpaid match fees on a schedule, capped per club, so the credit
/// controller never keeps a list.
async fn chase_match_fees(
    pool: &PgPool,
    push: &PushService,
    email: &EmailService,
) -> anyhow::Result<()> {
    let owed = selection_repo::fees_due_chasing(pool).await?;
    for row in &owed {
        let amount = row.fee_amount_cents.unwrap_or(0) as f64 / 100.0;
        let body = format!(
            "£{amount:.2} match fee for {} on {} is still outstanding. You can pay in the app.",
            row.title,
            row.start_at.format("%-d %b")
        );
        if let Err(e) = push
            .send(
                row.user_id,
                "fee_reminder",
                "Match fee due",
                &body,
                serde_json::json!({ "event_id": row.event_id }),
            )
            .await
        {
            warn!(error = %e, "fee push failed");
        }
        if let Err(e) = email
            .send(&row.email, &format!("Match fee for {}", row.title), &body)
            .await
        {
            warn!(error = %e, "fee email failed");
        }
        selection_repo::mark_fee_reminded(pool, row.event_id, row.user_id).await?;
    }
    if !owed.is_empty() {
        info!(count = owed.len(), "match fee reminders sent");
    }
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
