//! The whole system, counted.
//!
//! Every query here is a count over one brand's own database. They are written
//! out rather than generated because each one has a decision in it — soft
//! deletes excluded, currencies kept apart, "recent" meaning the last 7 and 30
//! days — and a generated version would hide all three.

use chrono::Utc;
use fishers_domain::{
    AdminOverview, Clubs, Cricket, CurrencyTotal, Growth, Health, Money, People, RecentEvent,
    SportCount, StatusCount,
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

/// The columns every people query selects. One list, so the table and the
/// dossier cannot drift into showing different things about the same person.
const USER_ROW: &str = "u.id, u.name, u.email, u.phone,
    (u.email_verified_at IS NOT NULL) AS email_verified,
    (u.phone_verified_at IS NOT NULL) AS phone_verified,
    u.avatar_url, u.primary_sport, u.position_role, u.skill_level,
    (SELECT COUNT(*) FROM club_members m WHERE m.user_id = u.id) AS clubs,
    COALESCE((SELECT SUM(s.matches) FROM player_season_stats s WHERE s.user_id = u.id), 0)::BIGINT
      AS matches,
    u.created_at,
    (SELECT MAX(t.created_at) FROM refresh_tokens t WHERE t.user_id = u.id) AS last_seen,
    u.deleted_at";

/// A page of people, newest first or by whatever was asked for.
///
/// `q` is optional: with none, this is the whole table, which is the view
/// somebody wants when they are not looking for anybody in particular.
pub async fn users_page(
    pool: &PgPool,
    query: Option<&str>,
    sort: &str,
    page: i64,
    per_page: i64,
) -> Result<fishers_domain::AdminUserPage, sqlx::Error> {
    // An allowlist, not the caller's string: this is the one place an admin
    // parameter reaches SQL, and ORDER BY cannot be bound.
    let order = match sort {
        "name" => "u.name ASC",
        "oldest" => "u.created_at ASC",
        "matches" => "matches DESC, u.name ASC",
        "clubs" => "clubs DESC, u.name ASC",
        "last_seen" => "last_seen DESC NULLS LAST",
        _ => "u.created_at DESC",
    };
    let per_page = per_page.clamp(1, 200);
    let page = page.max(1);
    let like = query.map(|q| format!("%{q}%"));

    let (total,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM users u
          WHERE $1::text IS NULL
             OR u.name ILIKE $1 OR u.email ILIKE $1 OR u.phone ILIKE $1",
    )
    .bind(like.as_deref())
    .fetch_one(pool)
    .await?;

    let rows = sqlx::query_as::<_, fishers_domain::AdminUserRow>(&format!(
        "SELECT {USER_ROW} FROM users u
          WHERE $1::text IS NULL
             OR u.name ILIKE $1 OR u.email ILIKE $1 OR u.phone ILIKE $1
          ORDER BY {order}
          LIMIT $2 OFFSET $3"
    ))
    .bind(like.as_deref())
    .bind(per_page)
    .bind((page - 1) * per_page)
    .fetch_all(pool)
    .await?;

    Ok(fishers_domain::AdminUserPage {
        rows,
        total,
        page,
        per_page,
    })
}

/// Everything held about one person.
pub async fn user_detail(
    pool: &PgPool,
    id: Uuid,
) -> Result<Option<fishers_domain::AdminUserDetail>, sqlx::Error> {
    let Some(user) = sqlx::query_as::<_, fishers_domain::AdminUserRow>(&format!(
        "SELECT {USER_ROW} FROM users u WHERE u.id = $1"
    ))
    .bind(id)
    .fetch_optional(pool)
    .await?
    else {
        return Ok(None);
    };

    // A row rather than a nine-tuple: `profile.6` is not a thing anybody
    // should have to count commas to understand.
    #[derive(sqlx::FromRow)]
    struct ProfileRow {
        sport_profiles: serde_json::Value,
        location: serde_json::Value,
        role_intent: Option<String>,
        profile_completed_at: Option<chrono::DateTime<chrono::Utc>>,
        umpires: bool,
        umpire_note: Option<String>,
        has_password: bool,
        has_google: bool,
        has_apple: bool,
    }

    let profile = sqlx::query_as::<_, ProfileRow>(
        "SELECT COALESCE(sport_profiles, '[]'::jsonb) AS sport_profiles,
                COALESCE(location, 'null'::jsonb)     AS location,
                role_intent, profile_completed_at, umpires, umpire_note,
                (password_hash IS NOT NULL) AS has_password,
                (google_sub IS NOT NULL)    AS has_google,
                (apple_id IS NOT NULL)      AS has_apple
           FROM users WHERE id = $1",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    let clubs = sqlx::query_as::<_, fishers_domain::AdminUserClub>(
        "SELECT m.club_id, c.name AS club_name, m.role::TEXT AS role,
                COALESCE(m.is_captain, false) AS is_captain,
                m.status::TEXT AS status, m.joined_at
           FROM club_members m JOIN clubs c ON c.id = m.club_id
          WHERE m.user_id = $1
          ORDER BY c.name",
    )
    .bind(id)
    .fetch_all(pool)
    .await?;

    let seasons = sqlx::query_as::<_, fishers_domain::AdminUserSeason>(
        "SELECT s.season_year, s.sport, c.name AS club_name,
                s.matches, s.runs, s.batting_innings, s.not_outs, s.balls_faced,
                s.fours, s.sixes, s.high_score, s.wickets,
                s.overs_bowled::float8 AS overs_bowled,
                s.bowling_runs, s.maidens, s.catches, s.stumpings
           FROM player_season_stats s
           LEFT JOIN clubs c ON c.id = s.club_id
          WHERE s.user_id = $1
          ORDER BY s.season_year DESC, s.sport",
    )
    .bind(id)
    .fetch_all(pool)
    .await?;

    // `status` is their own answer; `attended` is what happened. Both matter:
    // somebody who always says yes and never turns up looks reliable until
    // these two are read side by side.
    let availability = sqlx::query_as::<_, fishers_domain::AdminAvailability>(
        "SELECT COUNT(*) AS invited,
                COUNT(*) FILTER (WHERE status = 'going')      AS said_yes,
                COUNT(*) FILTER (WHERE status = 'not_going')  AS said_no,
                COUNT(*) FILTER (WHERE status = 'invited')    AS never_answered,
                COUNT(*) FILTER (WHERE selection_state IN ('selected','confirmed')) AS selected,
                COUNT(*) FILTER (WHERE attended)              AS attended
           FROM event_invites WHERE user_id = $1",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    let (umpired,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM cricket_match_officials o
           JOIN cricket_matches m ON m.id = o.match_id
          WHERE o.user_id = $1 AND o.role = 'umpire' AND m.status = 'complete'",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    let (umpire_rating, umpire_reviews): (Option<f64>, i64) = sqlx::query_as(
        "SELECT ROUND(AVG(rating), 1)::float8, COUNT(*)
           FROM cricket_umpire_reviews WHERE umpire_id = $1",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    let (achievements,): (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM user_achievements WHERE user_id = $1")
            .bind(id)
            .fetch_one(pool)
            .await?;
    let (active_sessions,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM refresh_tokens
          WHERE user_id = $1 AND expires_at > NOW() AND revoked_at IS NULL",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;
    let (push_devices,): (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM device_tokens WHERE user_id = $1")
            .bind(id)
            .fetch_one(pool)
            .await?;

    Ok(Some(fishers_domain::AdminUserDetail {
        user,
        sport_profiles: profile.sport_profiles,
        location: profile.location,
        role_intent: profile.role_intent,
        profile_completed_at: profile.profile_completed_at,
        umpires: profile.umpires,
        umpire_note: profile.umpire_note,
        has_password: profile.has_password,
        has_google: profile.has_google,
        has_apple: profile.has_apple,
        clubs,
        seasons,
        availability,
        umpired,
        umpire_rating,
        umpire_reviews,
        achievements,
        active_sessions,
        push_devices,
    }))
}
