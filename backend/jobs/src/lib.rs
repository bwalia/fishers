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

/// Each job is isolated: one failing must not stop the rest of the tick, or a
/// single bad fixture would stall reconfirmations for the whole club.
async fn run_tick(pool: &PgPool, push: &PushService, email: &EmailService) -> anyhow::Result<()> {
    if let Err(e) = materialise_recurring(pool).await {
        warn!(error = %e, "materialising recurring fixtures failed");
    }
    if let Err(e) = send_rsvp_reminders(pool, push).await {
        warn!(error = %e, "rsvp reminders failed");
    }
    if let Err(e) = request_reconfirmations(pool, push, email).await {
        warn!(error = %e, "reconfirmation requests failed");
    }
    if let Err(e) = drop_and_promote(pool, push).await {
        warn!(error = %e, "drop and promote failed");
    }
    if let Err(e) = chase_match_fees(pool, push, email).await {
        warn!(error = %e, "fee chasing failed");
    }
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

/// Keep every weekly series populated for the next 60 days.
///
/// The first version only ever looked at weeks 1–8 from the series' original
/// date, so a Wednesday nets booking quietly stopped appearing eight weeks after
/// it was created. The window now rolls: each series remembers how far it has
/// been expanded and carries on from there.
async fn materialise_recurring(pool: &PgPool) -> anyhow::Result<()> {
    const HORIZON_DAYS: i64 = 60;

    let parents = sqlx::query_as::<_, (uuid::Uuid, chrono::DateTime<Utc>, Option<String>, Option<chrono::DateTime<Utc>>)>(
        r#"
        SELECT id, start_at, recurrence_rule, recurrence_expanded_to
        FROM events
        WHERE recurrence_rule IS NOT NULL
          AND recurrence_parent_id IS NULL
          AND status = 'scheduled'
        "#,
    )
    .fetch_all(pool)
    .await?;

    let horizon = Utc::now() + Duration::days(HORIZON_DAYS);
    let mut created = 0u32;

    for (parent_id, anchor, rule, expanded_to) in parents {
        let Some(rule) = rule else { continue };
        if !rule.to_uppercase().contains("FREQ=WEEKLY") {
            continue;
        }

        // Start from the later of the anchor and wherever we got to last time,
        // and never create a fixture in the past.
        let resume_from = expanded_to.unwrap_or(anchor).max(Utc::now() - Duration::days(1));
        let mut week = 1i64;
        let mut furthest = expanded_to.unwrap_or(anchor);

        loop {
            let next_start = anchor + Duration::weeks(week);
            week += 1;
            if next_start > horizon {
                break;
            }
            // Guard against a runaway loop on a very old anchor.
            if week > 520 {
                warn!(%parent_id, "recurring series is implausibly old; skipping");
                break;
            }
            if next_start <= resume_from {
                continue;
            }

            let inserted = sqlx::query(
                r#"
                INSERT INTO events (
                    club_id, team_id, sport, event_subtype, title, venue_id,
                    start_at, end_at, recurrence_rule, recurrence_parent_id,
                    capacity, fee_amount_cents, fee_currency, status, metadata, created_by
                )
                SELECT
                    club_id, team_id, sport, event_subtype, title, venue_id,
                    start_at + ($2::bigint * INTERVAL '1 week'),
                    end_at + ($2::bigint * INTERVAL '1 week'),
                    NULL, id,
                    capacity, fee_amount_cents, fee_currency, 'scheduled', metadata, created_by
                FROM events WHERE id = $1
                  AND NOT EXISTS (
                      SELECT 1 FROM events child
                      WHERE child.recurrence_parent_id = $1
                        AND child.start_at = events.start_at + ($2::bigint * INTERVAL '1 week')
                  )
                "#,
            )
            .bind(parent_id)
            .bind(week - 1)
            .execute(pool)
            .await?;

            created += inserted.rows_affected() as u32;
            furthest = furthest.max(next_start);
        }

        sqlx::query("UPDATE events SET recurrence_expanded_to = $2 WHERE id = $1")
            .bind(parent_id)
            .bind(furthest)
            .execute(pool)
            .await?;
    }

    if created > 0 {
        info!(created, "materialised recurring fixture instances");
    }
    Ok(())
}

/// One nudge per player per fixture, 48 hours out. The first version had no
/// sent-marker and re-sent on every five-minute tick.
async fn send_rsvp_reminders(pool: &PgPool, push: &PushService) -> anyhow::Result<()> {
    let rows = sqlx::query_as::<_, (uuid::Uuid, uuid::Uuid, String)>(
        r#"
        SELECT ei.user_id, e.id, e.title
        FROM event_invites ei
        JOIN events e ON e.id = ei.event_id
        WHERE ei.status = 'invited'
          AND ei.rsvp_reminded_at IS NULL
          AND e.start_at BETWEEN NOW() AND NOW() + INTERVAL '48 hours'
          AND e.status = 'scheduled'
        ORDER BY e.start_at
        LIMIT 200
        "#,
    )
    .fetch_all(pool)
    .await?;

    for (user_id, event_id, title) in &rows {
        if let Err(e) = push
            .send(
                *user_id,
                "rsvp_reminder",
                "Are you playing?",
                &format!("Let the captain know about {title}."),
                serde_json::json!({ "event_id": event_id }),
            )
            .await
        {
            warn!(error = %e, "rsvp reminder push failed");
            continue;
        }
        sqlx::query(
            "UPDATE event_invites SET rsvp_reminded_at = NOW()
             WHERE event_id = $1 AND user_id = $2",
        )
        .bind(event_id)
        .bind(user_id)
        .execute(pool)
        .await?;
    }

    if !rows.is_empty() {
        info!(count = rows.len(), "rsvp reminders sent");
    }
    Ok(())
}
