//! The whole system, counted.
//!
//! Every query here is a count over one brand's own database. They are written
//! out rather than generated because each one has a decision in it — soft
//! deletes excluded, currencies kept apart, "recent" meaning the last 7 and 30
//! days — and a generated version would hide all three.

use chrono::Utc;
use fishers_domain::{
    AdminOverview, AdminUser, Clubs, Cricket, CurrencyTotal, Growth, Health, Money, People,
    RecentEvent, SportCount, StatusCount,
};
use sqlx::PgPool;
use uuid::Uuid;

/// `total`, `last_7d`, `last_30d` for a table with a `created_at`.
///
/// The table name is interpolated, which is only safe because every caller
/// passes a literal from this file. It is not reachable from a request.
async fn growth(pool: &PgPool, table: &str, extra_where: &str) -> Result<Growth, sqlx::Error> {
    sqlx::query_as::<_, Growth>(&format!(
        "SELECT COUNT(*) AS total,
                COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days')  AS last_7d,
                COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days') AS last_30d
           FROM {table} {extra_where}"
    ))
    .fetch_one(pool)
    .await
}

async fn count(pool: &PgPool, sql: &str) -> Result<i64, sqlx::Error> {
    let (n,): (i64,) = sqlx::query_as(sql).fetch_one(pool).await?;
    Ok(n)
}

pub async fn overview(pool: &PgPool) -> Result<AdminOverview, sqlx::Error> {
    let people = People {
        users: growth(pool, "users", "WHERE deleted_at IS NULL").await?,
        email_verified: count(
            pool,
            "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND email_verified_at IS NOT NULL",
        )
        .await?,
        phone_verified: count(
            pool,
            "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND phone_verified_at IS NOT NULL",
        )
        .await?,
        deleted: count(pool, "SELECT COUNT(*) FROM users WHERE deleted_at IS NOT NULL").await?,
        active_sessions: count(
            pool,
            "SELECT COUNT(*) FROM refresh_tokens WHERE expires_at > NOW() AND revoked_at IS NULL",
        )
        .await?,
        push_devices: count(pool, "SELECT COUNT(*) FROM device_tokens").await?,
    };

    let clubs = Clubs {
        clubs: growth(pool, "clubs", "").await?,
        teams: count(pool, "SELECT COUNT(*) FROM teams").await?,
        memberships: count(pool, "SELECT COUNT(*) FROM club_members").await?,
        empty: count(
            pool,
            "SELECT COUNT(*) FROM clubs c
              WHERE (SELECT COUNT(*) FROM club_members m WHERE m.club_id = c.id) <= 1",
        )
        .await?,
        // sport_types is an array; unnest so a club that plays two is counted
        // under both, which is what somebody reading this expects.
        by_sport: sqlx::query_as::<_, SportCount>(
            "SELECT sport, COUNT(*) AS clubs FROM (
                SELECT UNNEST(sport_types) AS sport FROM clubs
             ) s GROUP BY sport ORDER BY clubs DESC, sport",
        )
        .fetch_all(pool)
        .await?,
    };

    let cricket = Cricket {
        matches: growth(pool, "cricket_matches", "").await?,
        by_status: sqlx::query_as::<_, StatusCount>(
            "SELECT status::TEXT AS status, COUNT(*) AS count
               FROM cricket_matches GROUP BY status ORDER BY count DESC",
        )
        .fetch_all(pool)
        .await?,
        scoring_events: count(pool, "SELECT COUNT(*) FROM cricket_scoring_events").await?,
        fixtures_ahead: count(
            pool,
            "SELECT COUNT(*) FROM events WHERE start_at > NOW() AND status <> 'cancelled'",
        )
        .await?,
    };

    let money = Money {
        taken: sqlx::query_as::<_, CurrencyTotal>(
            "SELECT currency,
                    COALESCE(SUM(amount_cents), 0)::BIGINT AS amount_cents,
                    COUNT(*) AS payments
               FROM payments WHERE status = 'succeeded'
              GROUP BY currency ORDER BY amount_cents DESC",
        )
        .fetch_all(pool)
        .await?,
        payments: growth(pool, "payments", "").await?,
        failed_7d: count(
            pool,
            "SELECT COUNT(*) FROM payments
              WHERE status = 'failed' AND created_at > NOW() - INTERVAL '7 days'",
        )
        .await?,
        // `placed` is ordered and not yet paid. `draft` is a basket nobody
        // submitted, which is not money anybody is waiting for.
        unpaid_orders: count(pool, "SELECT COUNT(*) FROM orders WHERE status = 'placed'").await?,
    };

    let (migration,): (String,) = sqlx::query_as(
        "SELECT COALESCE(MAX(version)::TEXT, 'none') FROM _sqlx_migrations WHERE success",
    )
    .fetch_one(pool)
    .await?;

    let agent_last_error: Option<(Option<String>,)> = sqlx::query_as(
        "SELECT error FROM agent_runs
          WHERE error IS NOT NULL ORDER BY created_at DESC LIMIT 1",
    )
    .fetch_optional(pool)
    .await?;

    let health = Health {
        migration,
        migrations_failed: count(
            pool,
            "SELECT COUNT(*) FROM _sqlx_migrations WHERE NOT success",
        )
        .await?,
        webhooks_unprocessed: count(
            pool,
            "SELECT COUNT(*) FROM payment_webhook_events WHERE processed_at IS NULL",
        )
        .await?,
        agent_failures_7d: count(
            pool,
            "SELECT COUNT(*) FROM agent_runs
              WHERE error IS NOT NULL AND created_at > NOW() - INTERVAL '7 days'",
        )
        .await?,
        agent_last_error: agent_last_error.and_then(|(e,)| e),
        codes_pending: count(
            pool,
            "SELECT COUNT(*) FROM verification_codes
              WHERE consumed_at IS NULL AND expires_at > NOW()",
        )
        .await?,
        notifications_24h: count(
            pool,
            "SELECT COUNT(*) FROM notifications_log WHERE sent_at > NOW() - INTERVAL '24 hours'",
        )
        .await?,
        notifications_unread: count(
            pool,
            "SELECT COUNT(*) FROM notifications_log WHERE read_at IS NULL",
        )
        .await?,
        database_bytes: count(pool, "SELECT pg_database_size(current_database())::BIGINT").await?,
    };

    let recent = sqlx::query_as::<_, RecentEvent>(
        "SELECT e.id, e.event_type, e.occurred_at, c.name AS club_name
           FROM platform_events e
           LEFT JOIN clubs c ON c.id = e.club_id
          ORDER BY e.occurred_at DESC LIMIT 25",
    )
    .fetch_all(pool)
    .await?;

    Ok(AdminOverview {
        taken_at: Utc::now(),
        people,
        clubs,
        cricket,
        money,
        health,
        recent,
    })
}

/// Look somebody up by name, email or phone.
///
/// Deleted accounts are included and marked: "I deleted my account and want it
/// back" is one of the reasons somebody writes in, and a search that cannot
/// find them answers the wrong question.
pub async fn find_users(pool: &PgPool, query: &str, limit: i64) -> Result<Vec<AdminUser>, sqlx::Error> {
    sqlx::query_as::<_, AdminUser>(
        "SELECT u.id, u.name, u.email, u.phone,
                (u.email_verified_at IS NOT NULL) AS email_verified,
                (u.phone_verified_at IS NOT NULL) AS phone_verified,
                u.created_at, u.deleted_at,
                (SELECT COUNT(*) FROM club_members m WHERE m.user_id = u.id) AS clubs,
                (SELECT COUNT(*) FROM refresh_tokens t
                  WHERE t.user_id = u.id AND t.expires_at > NOW() AND t.revoked_at IS NULL)
                  AS active_sessions
           FROM users u
          WHERE u.name ILIKE $1 OR u.email ILIKE $1 OR u.phone ILIKE $1
          ORDER BY u.created_at DESC
          LIMIT $2",
    )
    .bind(format!("%{query}%"))
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// One person by id, for a link straight to them.
pub async fn find_user(pool: &PgPool, id: Uuid) -> Result<Option<AdminUser>, sqlx::Error> {
    sqlx::query_as::<_, AdminUser>(
        "SELECT u.id, u.name, u.email, u.phone,
                (u.email_verified_at IS NOT NULL) AS email_verified,
                (u.phone_verified_at IS NOT NULL) AS phone_verified,
                u.created_at, u.deleted_at,
                (SELECT COUNT(*) FROM club_members m WHERE m.user_id = u.id) AS clubs,
                (SELECT COUNT(*) FROM refresh_tokens t
                  WHERE t.user_id = u.id AND t.expires_at > NOW() AND t.revoked_at IS NULL)
                  AS active_sessions
           FROM users u WHERE u.id = $1",
    )
    .bind(id)
    .fetch_optional(pool)
    .await
}
