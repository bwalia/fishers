//! Storage for the outside scores feed.
//!
//! Two jobs live here. Reading, which every request does and which never
//! touches anything but Postgres; and the bookkeeping the poller needs to
//! decide whether it may spend one of the day's hundred requests.

use chrono::{DateTime, NaiveDate, Utc};
use fishers_domain::world_cricket::{phase_for, WorldMatch};
use fishers_domain::world_cricket_detail::WorldMatchDetail;
use sqlx::PgPool;

/// The provider's quota resets on its own clock, which is not documented, so
/// everything here counts against the UTC day and lets the figure the provider
/// returns correct it.
const TODAY_UTC: &str = "(NOW() AT TIME ZONE 'UTC')::date";

/// The columns [`WorldMatch`] is read from. Written once so the three queries
/// below cannot drift apart from each other.
const MATCH_COLUMNS: &str = r#"
    id, league_name, league_season,
    home_team_name, home_team_short, home_team_logo,
    away_team_name, away_team_short, away_team_logo,
    country_code, country_name,
    format, day_type,
    start_time, start_date, end_date,
    state, phase, report,
    home_score, home_info, away_score, away_info
"#;

/// What is being played now, soonest first.
pub async fn live(pool: &PgPool, limit: i64) -> Result<Vec<WorldMatch>, sqlx::Error> {
    sqlx::query_as::<_, WorldMatch>(&format!(
        "SELECT {MATCH_COLUMNS} FROM world_cricket_matches
          WHERE phase = 'live'
          ORDER BY start_time NULLS LAST
          LIMIT $1"
    ))
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// What is coming, soonest first. Anything whose start time has passed is left
/// out: a fixture the feed still calls `Scheduled` an hour after it should
/// have begun is not "upcoming" to a reader, it is a fixture nobody is
/// covering.
pub async fn upcoming(pool: &PgPool, limit: i64) -> Result<Vec<WorldMatch>, sqlx::Error> {
    sqlx::query_as::<_, WorldMatch>(&format!(
        "SELECT {MATCH_COLUMNS} FROM world_cricket_matches
          WHERE phase = 'pending'
            AND (start_time IS NULL OR start_time > NOW() - INTERVAL '1 hour')
          ORDER BY start_time NULLS LAST
          LIMIT $1"
    ))
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// What just finished, latest first. Only matches that actually got played —
/// a row abandoned without a ball bowled has nothing to report.
pub async fn recent(pool: &PgPool, limit: i64) -> Result<Vec<WorldMatch>, sqlx::Error> {
    sqlx::query_as::<_, WorldMatch>(&format!(
        "SELECT {MATCH_COLUMNS} FROM world_cricket_matches
          WHERE phase = 'done'
            AND state <> 'No live coverage'
            AND report IS NOT NULL
          ORDER BY start_time DESC NULLS LAST
          LIMIT $1"
    ))
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// When the feed was last read at all. This is what the reader is shown, so it
/// has to mean "how old are these scores", not "when did this row change".
pub async fn as_of(pool: &PgPool) -> Result<Option<DateTime<Utc>>, sqlx::Error> {
    sqlx::query_scalar("SELECT MAX(fetched_at) FROM world_cricket_days")
        .fetch_one(pool)
        .await
}

/// Somebody opened the scores.
///
/// This is what tells the poller to read the feed every couple of minutes
/// rather than every quarter of an hour, so it is the difference between a
/// hundred requests spread uselessly across a quiet night and a hundred spent
/// while people are watching.
///
/// Throttled to one write a minute: it is called on every page load, and a row
/// update per request to show a score strip would be a silly thing to do to
/// the database.
pub async fn note_watched(pool: &PgPool) -> Result<(), sqlx::Error> {
    sqlx::query(&format!(
        "INSERT INTO world_cricket_budget (day, watched_at) VALUES ({TODAY_UTC}, NOW())
         ON CONFLICT (day) DO UPDATE SET watched_at = NOW()
          WHERE world_cricket_budget.watched_at IS NULL
             OR world_cricket_budget.watched_at < NOW() - INTERVAL '1 minute'"
    ))
    .execute(pool)
    .await
    .map(|_| ())
}

/// Today's spend, what the provider last said was left, and when anybody last
/// looked.
pub async fn budget(
    pool: &PgPool,
) -> Result<(i32, Option<i32>, Option<DateTime<Utc>>), sqlx::Error> {
    let row: Option<(i32, Option<i32>, Option<DateTime<Utc>>)> = sqlx::query_as(&format!(
        "SELECT spent, upstream_remaining, watched_at
           FROM world_cricket_budget WHERE day = {TODAY_UTC}"
    ))
    .fetch_optional(pool)
    .await?;
    Ok(row.unwrap_or((0, None, None)))
}

/// Claim one of the day's requests, or refuse.
///
/// This is the hard limit, and it is one statement on purpose. Checking the
/// count and then making the call would be two steps with a gap in the middle,
/// and prod runs more than one API pod — two of them reading "99 spent" at the
/// same moment would both go on to spend the hundredth. `Ok(None)` means the
/// allowance is gone and the caller must not contact the provider at all.
pub async fn try_spend(pool: &PgPool, cap: i32) -> Result<Option<i32>, sqlx::Error> {
    if cap <= 0 {
        return Ok(None);
    }
    sqlx::query_scalar(&format!(
        "INSERT INTO world_cricket_budget (day, spent) VALUES ({TODAY_UTC}, 1)
         ON CONFLICT (day) DO UPDATE
            SET spent = world_cricket_budget.spent + 1, updated_at = NOW()
          WHERE world_cricket_budget.spent < $1
         RETURNING spent"
    ))
    .bind(cap)
    .fetch_optional(pool)
    .await
}

/// Give a spent request back, when the call never reached the provider.
///
/// A connection that times out before it is answered has cost nothing at
/// their end, and charging ourselves for it would let a spell of network
/// trouble eat the day's cricket.
pub async fn refund(pool: &PgPool) -> Result<(), sqlx::Error> {
    sqlx::query(&format!(
        "UPDATE world_cricket_budget SET spent = GREATEST(0, spent - 1)
          WHERE day = {TODAY_UTC}"
    ))
    .execute(pool)
    .await
    .map(|_| ())
}

/// Write back what the provider's own headers said was left.
///
/// Their figure wins over ours whenever it is lower. Our count starts at zero
/// each UTC midnight and theirs may not; it also knows about requests made by
/// anything else sharing the key, which ours cannot. Taking the lower of the
/// two is the reading that cannot overspend.
pub async fn reconcile(pool: &PgPool, limit: i32, remaining: i32) -> Result<(), sqlx::Error> {
    sqlx::query(&format!(
        "UPDATE world_cricket_budget
            SET upstream_remaining = $2,
                spent = GREATEST(spent, $1 - $2),
                updated_at = NOW()
          WHERE day = {TODAY_UTC}"
    ))
    .bind(limit)
    .bind(remaining)
    .execute(pool)
    .await
    .map(|_| ())
}

/// Is anything actually being played right now?
///
/// The poller's first question: with nothing on, there is no reason to spend a
/// request more than once in a while, however many are left.
pub async fn live_count(pool: &PgPool) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar("SELECT COUNT(*) FROM world_cricket_matches WHERE phase = 'live'")
        .fetch_one(pool)
        .await
}

/// The date whose live play is most overdue a refresh, if any is.
///
/// Almost always just today, and that is the point. Asking the feed for a date
/// returns every match *in progress on* that date, not merely those starting
/// on it — a four-day Test that began on Monday comes back in Wednesday's
/// answer. So one request refreshes the whole world's cricket.
///
/// This first shipped as a union with every live match's own start date, which
/// looked careful and was simply waste: on real data all five matches in
/// progress, including two that had started the day before, were already in
/// today's answer, so the second request fetched nothing new and doubled the
/// cost of every refresh.
///
/// The one match today's answer genuinely cannot reach is one that started
/// late yesterday, was due to finish yesterday, and is still going after
/// midnight UTC — its whole date range is behind us. That, and only that, is
/// what the union is for now.
pub async fn due_refresh(
    pool: &PgPool,
    max_age_mins: i32,
) -> Result<Option<NaiveDate>, sqlx::Error> {
    sqlx::query_scalar(&format!(
        "SELECT d FROM (
             SELECT start_date AS d FROM world_cricket_matches
              WHERE phase = 'live'
                AND (end_date IS NULL OR end_date < {TODAY_UTC})
             UNION SELECT {TODAY_UTC}
         ) days
          WHERE NOT EXISTS (
                    SELECT 1 FROM world_cricket_days wd
                     WHERE wd.day = days.d
                       AND wd.fetched_at > NOW() - make_interval(mins => $1)
                )
          ORDER BY d
          LIMIT 1"
    ))
    .bind(max_age_mins)
    .fetch_optional(pool)
    .await
}

/// The next day in the window worth asking about: never fetched, or fetched
/// longer ago than `max_age_mins`, and not already settled.
///
/// Settled days are skipped for good. Yesterday's results do not change, and
/// this is most of what makes the allowance last.
pub async fn stale_day(
    pool: &PgPool,
    from: NaiveDate,
    to: NaiveDate,
    max_age_mins: i32,
) -> Result<Option<NaiveDate>, sqlx::Error> {
    sqlx::query_scalar(
        r#"
        SELECT d::date FROM generate_series($1::date, $2::date, '1 day') AS d
         WHERE NOT EXISTS (
                   SELECT 1 FROM world_cricket_days wd
                    WHERE wd.day = d::date
                      AND (wd.settled
                           OR wd.fetched_at > NOW() - make_interval(mins => $3))
               )
         ORDER BY d
         LIMIT 1
        "#,
    )
    .bind(from)
    .bind(to)
    .bind(max_age_mins)
    .fetch_optional(pool)
    .await
}

/// Store a day's worth of matches and note that we have been told about it.
///
/// One transaction: a half-written day that also recorded itself as fetched
/// would not be looked at again for a quarter of an hour, showing a partial
/// card the whole time.
///
/// `settled` is decided here rather than by the caller because it is a
/// property of what came back — the day is over and nothing on it can change
/// again — and getting it wrong in either direction is expensive. Too eager
/// and a score freezes half-played; too shy and finished cricket costs a
/// request a day for ever.
pub async fn store_day(
    pool: &PgPool,
    day: NaiveDate,
    matches: &[WorldMatch],
    today_utc: NaiveDate,
) -> Result<bool, sqlx::Error> {
    let mut tx = pool.begin().await?;

    for m in matches {
        sqlx::query(
            r#"
            INSERT INTO world_cricket_matches (
                id, league_name, league_season,
                home_team_name, home_team_short, home_team_logo,
                away_team_name, away_team_short, away_team_logo,
                country_code, country_name,
                format, day_type, start_time, start_date, end_date,
                state, phase, report,
                home_score, home_info, away_score, away_info,
                fetched_at, updated_at
            ) VALUES (
                $1, $2, $3,
                $4, $5, $6,
                $7, $8, $9,
                $10, $11,
                $12, $13, $14, $15, $16,
                $17, $18, $19,
                $20, $21, $22, $23,
                NOW(), NOW()
            )
            ON CONFLICT (id) DO UPDATE SET
                league_name = EXCLUDED.league_name,
                league_season = EXCLUDED.league_season,
                home_team_name = EXCLUDED.home_team_name,
                home_team_short = EXCLUDED.home_team_short,
                home_team_logo = EXCLUDED.home_team_logo,
                away_team_name = EXCLUDED.away_team_name,
                away_team_short = EXCLUDED.away_team_short,
                away_team_logo = EXCLUDED.away_team_logo,
                country_code = EXCLUDED.country_code,
                country_name = EXCLUDED.country_name,
                format = EXCLUDED.format,
                day_type = EXCLUDED.day_type,
                start_time = EXCLUDED.start_time,
                start_date = EXCLUDED.start_date,
                end_date = EXCLUDED.end_date,
                state = EXCLUDED.state,
                phase = EXCLUDED.phase,
                report = EXCLUDED.report,
                home_score = EXCLUDED.home_score,
                home_info = EXCLUDED.home_info,
                away_score = EXCLUDED.away_score,
                away_info = EXCLUDED.away_info,
                fetched_at = NOW(),
                updated_at = NOW()
            "#,
        )
        .bind(&m.id)
        .bind(&m.league_name)
        .bind(m.league_season)
        .bind(&m.home_team_name)
        .bind(&m.home_team_short)
        .bind(&m.home_team_logo)
        .bind(&m.away_team_name)
        .bind(&m.away_team_short)
        .bind(&m.away_team_logo)
        .bind(&m.country_code)
        .bind(&m.country_name)
        .bind(&m.format)
        .bind(&m.day_type)
        .bind(m.start_time)
        .bind(m.start_date)
        .bind(m.end_date)
        .bind(&m.state)
        .bind(phase_for(&m.state))
        .bind(&m.report)
        .bind(&m.home_score)
        .bind(&m.home_info)
        .bind(&m.away_score)
        .bind(&m.away_info)
        .execute(&mut *tx)
        .await?;
    }

    // Past, and everything on it has ended. A day with nothing on it at all is
    // settled too once it is behind us — there is no cricket to wait for.
    let settled = day < today_utc
        && matches
            .iter()
            .all(|m| phase_for(&m.state) == fishers_domain::world_cricket::PHASE_DONE);

    sqlx::query(
        r#"
        INSERT INTO world_cricket_days (day, fetched_at, settled, match_count)
        VALUES ($1, NOW(), $2, $3)
        ON CONFLICT (day) DO UPDATE
           SET fetched_at = NOW(), settled = EXCLUDED.settled, match_count = EXCLUDED.match_count
        "#,
    )
    .bind(day)
    .bind(settled)
    .bind(matches.len() as i32)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(settled)
}

/// Drop matches nobody is going to scroll back to, so the table stays the size
/// of a season rather than growing for ever.
pub async fn prune(pool: &PgPool, keep_days: i32) -> Result<u64, sqlx::Error> {
    let matches = sqlx::query("DELETE FROM world_cricket_matches WHERE start_date < CURRENT_DATE - make_interval(days => $1)")
        .bind(keep_days)
        .execute(pool)
        .await?
        .rows_affected();
    sqlx::query("DELETE FROM world_cricket_days WHERE day < CURRENT_DATE - make_interval(days => $1)")
        .bind(keep_days)
        .execute(pool)
        .await?;
    // Budget rows are one per day and tiny, but there is no reason to keep a
    // year of them either.
    sqlx::query("DELETE FROM world_cricket_budget WHERE day < CURRENT_DATE - INTERVAL '30 days'")
        .execute(pool)
        .await?;
    Ok(matches)
}

// ---------------------------------------------------------------------------
// One match in full — the scorecard behind the page you get when you tap one.
// ---------------------------------------------------------------------------

/// A distinct advisory-lock class, so a match's fetch lock cannot collide with
/// the scheduler's or the poller's.
const DETAIL_LOCK_CLASS: i32 = 0x_6669_7301;

/// The summary row for one match, for the page header.
pub async fn find(pool: &PgPool, id: &str) -> Result<Option<WorldMatch>, sqlx::Error> {
    sqlx::query_as::<_, WorldMatch>(&format!(
        "SELECT {MATCH_COLUMNS} FROM world_cricket_matches WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(pool)
    .await
}

/// The stored scorecard, how old it is, and whether it is the final one.
pub async fn detail(
    pool: &PgPool,
    id: &str,
) -> Result<Option<(WorldMatchDetail, DateTime<Utc>, bool)>, sqlx::Error> {
    let row: Option<(sqlx::types::Json<WorldMatchDetail>, DateTime<Utc>, bool)> = sqlx::query_as(
        "SELECT detail, fetched_at, final FROM world_cricket_match_details WHERE match_id = $1",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|(d, at, final_)| (d.0, at, final_)))
}

/// Become the one that fetches this match, or don't.
///
/// Ten people opening the same live match at the same moment must cost one
/// request, not ten — and on a hundred a day, ten would be a tenth of the
/// allowance spent on one match in one second. Whoever takes the lock fetches;
/// everybody else is served what is already stored, which is at most a few
/// minutes old.
///
/// The lock is released by [`release_detail_lock`], on the same connection, so
/// a caller must hold the returned connection until it is done.
pub async fn claim_detail(
    pool: &PgPool,
    id: &str,
) -> Result<Option<sqlx::pool::PoolConnection<sqlx::Postgres>>, sqlx::Error> {
    let mut conn = pool.acquire().await?;
    let held: bool = sqlx::query_scalar("SELECT pg_try_advisory_lock($1, hashtext($2))")
        .bind(DETAIL_LOCK_CLASS)
        .bind(id)
        .fetch_one(&mut *conn)
        .await?;
    Ok(held.then_some(conn))
}

pub async fn release_detail_lock(
    conn: &mut sqlx::pool::PoolConnection<sqlx::Postgres>,
    id: &str,
) -> Result<(), sqlx::Error> {
    // On the connection that took it, before it goes back to the pool: one
    // handed back still holding this would lock out every later view of this
    // match until it happened to be recycled.
    sqlx::query("SELECT pg_advisory_unlock($1, hashtext($2))")
        .bind(DETAIL_LOCK_CLASS)
        .bind(id)
        .execute(&mut **conn)
        .await
        .map(|_| ())
}

/// Store a scorecard. `final` means the match is over and this card can never
/// change — it is what stops a finished match costing a request every time
/// somebody looks at it.
pub async fn store_detail(
    pool: &PgPool,
    id: &str,
    detail: &WorldMatchDetail,
    final_: bool,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO world_cricket_match_details (match_id, detail, fetched_at, final)
        VALUES ($1, $2, NOW(), $3)
        ON CONFLICT (match_id) DO UPDATE
           SET detail = EXCLUDED.detail, fetched_at = NOW(), final = EXCLUDED.final
        "#,
    )
    .bind(id)
    .bind(sqlx::types::Json(detail))
    .bind(final_)
    .execute(pool)
    .await
    .map(|_| ())
}
