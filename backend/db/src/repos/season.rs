//! A player's season, match by match, and a club's season from the same lines.
//! The arithmetic is in `fishers_domain::season`; this is the reading and
//! writing.

use chrono::{DateTime, Utc};
use fishers_domain::season::{
    match_figures, ClosePreview, ClubRank, ClubSeason, DueSeasonEmail, Leader, Leaderboard,
    MatchLine, PlayerGame, SeasonRecordLine,
};
use fishers_domain::{MatchSide, MatchState};
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

/// Write one line per player for a finished match, replacing any it had.
/// Called every time a finished match is saved, because the match goes on
/// changing after the last ball: player of the match is given then, and a
/// card can be corrected. A line written once would miss both.
///
/// `club_id` is the club that scored it, `opponent_club_id` the other side if
/// it was arranged against a club on the app. Each player is credited to the
/// one of those two they are a member of — the scoring club first, if both —
/// counting a club they have since left: they still played for it.
/// The match, its fixture, the two clubs, when, and whether lines are done.
type MatchContext = (Uuid, Uuid, Option<Uuid>, DateTime<Utc>, Option<DateTime<Utc>>);
/// Club name, players ranked, and their rank by runs, wickets and catches.
type RankRow = (String, i64, Option<i64>, Option<i64>, Option<i64>);

pub async fn record_lines(
    tx: &mut Transaction<'_, Postgres>,
    match_id: Uuid,
    state: &MatchState,
) -> Result<(), sqlx::Error> {
    let ctx: Option<MatchContext> = sqlx::query_as(
        r#"
        SELECT m.event_id, m.club_id, e.opponent_club_id, e.start_at, m.lines_recorded_at
        FROM cricket_matches m JOIN events e ON e.id = m.event_id
        WHERE m.id = $1
        FOR UPDATE OF m
        "#,
    )
    .bind(match_id)
    .fetch_optional(&mut **tx)
    .await?;
    let Some((event_id, club_id, opponent_club_id, played_at, _done)) = ctx else {
        return Ok(());
    };
    // Rewritten whole: somebody taken out of the XI by a correction must not
    // keep a line for a match they no longer played in.
    sqlx::query("DELETE FROM player_match_lines WHERE match_id = $1")
        .bind(match_id)
        .execute(&mut **tx)
        .await?;

    let season = fishers_domain::season::season_of(played_at);
    for (user_id, f) in match_figures(state) {
        let (opposition, won) = match f.side {
            Some(MatchSide::Home) => (state.away_name.clone(), state.winner.map(|w| w == MatchSide::Home)),
            Some(MatchSide::Away) => (state.home_name.clone(), state.winner.map(|w| w == MatchSide::Away)),
            // A substitute fielder: on neither sheet, so no result to claim.
            None => (String::new(), None),
        };
        sqlx::query(
            r#"
            INSERT INTO player_match_lines (
                match_id, user_id, event_id, club_id, season_year, played_at, opposition, won,
                batting_innings, not_outs, runs, balls_faced, fours, sixes,
                high_score, high_score_not_out, fifties, hundreds, ducks,
                bowling_balls, bowling_runs, wickets, maidens, catches, stumpings, player_of_match,
                magic_moments
            )
            SELECT $1, u.id, $3,
                   (SELECT cm.club_id FROM club_members cm
                     WHERE cm.user_id = u.id AND cm.status IN ('active', 'left')
                       AND cm.club_id IN ($4, $5)
                     ORDER BY (cm.club_id = $4) DESC, (cm.status = 'active') DESC LIMIT 1),
                   $6, $7, $8, $9,
                   $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
                   $21, $22, $23, $24, $25, $26, $27, $28
            FROM users u WHERE u.id = $2
            ON CONFLICT (match_id, user_id) DO NOTHING
            "#,
        )
        .bind(match_id)
        .bind(user_id)
        .bind(event_id)
        .bind(club_id)
        .bind(opponent_club_id)
        .bind(season)
        .bind(played_at)
        .bind(&opposition)
        .bind(won)
        .bind(f.batting_innings)
        .bind(f.not_outs)
        .bind(f.runs)
        .bind(f.balls_faced)
        .bind(f.fours)
        .bind(f.sixes)
        .bind(f.high_score)
        .bind(f.high_score_not_out)
        .bind(f.fifties)
        .bind(f.hundreds)
        .bind(f.ducks)
        .bind(f.bowling_balls)
        .bind(f.bowling_runs)
        .bind(f.wickets)
        .bind(f.maidens)
        .bind(f.catches)
        .bind(f.stumpings)
        .bind(f.player_of_match)
        .bind(f.magic_moments)
        .execute(&mut **tx)
        .await?;
    }
    sqlx::query("UPDATE cricket_matches SET lines_recorded_at = NOW() WHERE id = $1")
        .bind(match_id)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

/// Lines for matches finished before lines existed. A batch at a time, from
/// the scheduler; returns how many matches it did, so it knows to stop.
pub async fn backfill_lines(pool: &PgPool, batch: i64) -> Result<usize, sqlx::Error> {
    let due: Vec<(Uuid, serde_json::Value)> = sqlx::query_as(
        r#"
        SELECT id, state_json FROM cricket_matches
        WHERE stats_recorded_at IS NOT NULL AND lines_recorded_at IS NULL
        ORDER BY stats_recorded_at
        LIMIT $1
        "#,
    )
    .bind(batch)
    .fetch_all(pool)
    .await?;
    let n = due.len();
    for (match_id, json) in due {
        let mut tx = pool.begin().await?;
        match serde_json::from_value::<MatchState>(json) {
            Ok(state) => record_lines(&mut tx, match_id, &state).await?,
            // A state this build cannot read is not going to read next tick
            // either: mark it rather than retry it forever.
            Err(e) => {
                tracing::warn!(%match_id, error = %e, "match state unreadable; no lines");
                sqlx::query("UPDATE cricket_matches SET lines_recorded_at = NOW() WHERE id = $1")
                    .bind(match_id)
                    .execute(&mut *tx)
                    .await?;
            }
        }
        tx.commit().await?;
    }
    Ok(n)
}

const LINE_COLUMNS: &str = r#"
    l.match_id, l.event_id, l.club_id, c.name AS club_name, l.season_year, l.played_at,
    l.opposition, l.won, l.batting_innings, l.not_outs, l.runs, l.balls_faced, l.fours,
    l.sixes, l.high_score, l.high_score_not_out, l.fifties, l.hundreds, l.ducks,
    l.bowling_balls, l.bowling_runs, l.wickets, l.maidens, l.catches, l.stumpings,
    l.player_of_match, l.magic_moments
"#;

pub async fn lines_for_user(pool: &PgPool, user_id: Uuid) -> Result<Vec<MatchLine>, sqlx::Error> {
    sqlx::query_as::<_, MatchLine>(&format!(
        "SELECT {LINE_COLUMNS} FROM player_match_lines l
         LEFT JOIN clubs c ON c.id = l.club_id
         WHERE l.user_id = $1 ORDER BY l.played_at"
    ))
    .bind(user_id)
    .fetch_all(pool)
    .await
}

/// Where they stand in a club for a season: 1-based ranks by runs, wickets and
/// catches among everyone with lines for that club that season.
pub async fn club_rank(
    pool: &PgPool,
    club_id: Uuid,
    season: i32,
    user_id: Uuid,
) -> Result<Option<ClubRank>, sqlx::Error> {
    let row: Option<RankRow> = sqlx::query_as(
        r#"
        WITH t AS (
            SELECT user_id, SUM(runs) AS runs, SUM(wickets) AS wickets,
                   SUM(catches + stumpings) AS held
            FROM player_match_lines
            WHERE club_id = $1 AND season_year = $2
            GROUP BY user_id
        ), r AS (
            SELECT user_id,
                   CASE WHEN runs > 0 THEN RANK() OVER (ORDER BY runs DESC) END AS runs_rank,
                   CASE WHEN wickets > 0 THEN RANK() OVER (ORDER BY wickets DESC) END AS wickets_rank,
                   CASE WHEN held > 0 THEN RANK() OVER (ORDER BY held DESC) END AS held_rank
            FROM t
        )
        SELECT c.name, (SELECT COUNT(*) FROM t), r.runs_rank, r.wickets_rank, r.held_rank
        FROM r JOIN clubs c ON c.id = $1
        WHERE r.user_id = $3
        "#,
    )
    .bind(club_id)
    .bind(season)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|(club_name, players, runs, wickets, catches)| ClubRank {
        club_id,
        club_name,
        runs: runs.map(|v| v as i32),
        wickets: wickets.map(|v| v as i32),
        catches: catches.map(|v| v as i32),
        players: players as i32,
    }))
}

/// The whole "My game" page. `season` defaults to the latest they played in,
/// or this year; `club` to the club they played most for that season.
pub async fn player_game(
    pool: &PgPool,
    user_id: Uuid,
    season: Option<i32>,
    club: Option<Uuid>,
) -> Result<Option<PlayerGame>, sqlx::Error> {
    let name: Option<String> = sqlx::query_scalar("SELECT name FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(pool)
        .await?;
    let Some(name) = name else { return Ok(None) };
    let lines = lines_for_user(pool, user_id).await?;
    let season = season
        .or_else(|| lines.iter().map(|l| l.season_year).max())
        .unwrap_or_else(|| fishers_domain::season::season_of(Utc::now()));
    let club = club.or_else(|| {
        let mut counts: std::collections::HashMap<Uuid, usize> = Default::default();
        for l in lines.iter().filter(|l| l.season_year == season) {
            if let Some(c) = l.club_id {
                *counts.entry(c).or_default() += 1;
            }
        }
        counts.into_iter().max_by_key(|(_, n)| *n).map(|(c, _)| c)
    });
    let rank = match club {
        Some(c) => club_rank(pool, c, season, user_id).await?,
        None => None,
    };
    Ok(Some(PlayerGame::build(user_id, name, season, lines, rank)))
}

/// The club's season: its record and its leaderboards, from the lines of the
/// players who played *for* it.
pub async fn club_season(
    pool: &PgPool,
    club_id: Uuid,
    season: Option<i32>,
) -> Result<Option<ClubSeason>, sqlx::Error> {
    let club_name: Option<String> = sqlx::query_scalar("SELECT name FROM clubs WHERE id = $1")
        .bind(club_id)
        .fetch_optional(pool)
        .await?;
    let Some(club_name) = club_name else { return Ok(None) };
    let seasons: Vec<i32> = sqlx::query_scalar(
        "SELECT DISTINCT season_year FROM player_match_lines WHERE club_id = $1 ORDER BY 1 DESC",
    )
    .bind(club_id)
    .fetch_all(pool)
    .await?;
    let season = season
        .or_else(|| seasons.first().copied())
        .unwrap_or_else(|| fishers_domain::season::season_of(Utc::now()));

    // A match counts for the club once, whatever number of its players were
    // in it; its result is what the club's players' lines say it was.
    let record = club_record(pool, club_id, season).await?;
    let players: i64 = sqlx::query_scalar(
        "SELECT COUNT(DISTINCT user_id) FROM player_match_lines WHERE club_id = $1 AND season_year = $2",
    )
    .bind(club_id)
    .bind(season)
    .fetch_one(pool)
    .await?;

    let mut boards = Vec::new();
    for (code, sql) in BOARDS {
        let leaders: Vec<Leader> = sqlx::query_as(sql)
            .bind(club_id)
            .bind(season)
            .fetch_all(pool)
            .await?;
        if !leaders.is_empty() {
            boards.push(Leaderboard { code: (*code).into(), leaders });
        }
    }
    let closed_at = closed_at(pool, club_id, season).await?;
    Ok(Some(ClubSeason { club_id, club_name, season, closed_at, seasons, record, players, boards }))
}

pub async fn closed_at(
    pool: &PgPool,
    club_id: Uuid,
    season: i32,
) -> Result<Option<DateTime<Utc>>, sqlx::Error> {
    sqlx::query_scalar("SELECT closed_at FROM club_seasons WHERE club_id = $1 AND season_year = $2")
        .bind(club_id)
        .bind(season)
        .fetch_optional(pool)
        .await
}

/// The club's record for a season.
pub async fn club_record(pool: &PgPool, club_id: Uuid, season: i32) -> Result<SeasonRecordLine, sqlx::Error> {
    sqlx::query_as(
        r#"
        WITH m AS (
            SELECT match_id, bool_or(won) AS won, bool_and(won IS NOT NULL) AS decided
            FROM player_match_lines
            WHERE club_id = $1 AND season_year = $2
            GROUP BY match_id
        )
        SELECT COUNT(*) AS played,
               COUNT(*) FILTER (WHERE won) AS won,
               COUNT(*) FILTER (WHERE decided AND NOT won) AS lost,
               COUNT(*) FILTER (WHERE NOT decided) AS tied_or_no_result
        FROM m
        "#,
    )
    .bind(club_id)
    .bind(season)
    .fetch_one(pool)
    .await
}

/// Who closing the season would email, before anybody presses the button.
pub async fn close_preview(pool: &PgPool, club_id: Uuid, season: i32) -> Result<ClosePreview, sqlx::Error> {
    sqlx::query_as(
        r#"
        SELECT $2::INT AS season,
               (SELECT closed_at FROM club_seasons WHERE club_id = $1 AND season_year = $2) AS closed_at,
               COUNT(*) AS members,
               COUNT(*) FILTER (WHERE u.email IS NOT NULL AND NOT u.season_emails_off) AS will_email,
               COUNT(*) FILTER (WHERE EXISTS (
                   SELECT 1 FROM player_match_lines l
                   WHERE l.user_id = u.id AND l.club_id = $1 AND l.season_year = $2)) AS played
        FROM club_members m JOIN users u ON u.id = m.user_id
        WHERE m.club_id = $1 AND m.status = 'active' AND u.deleted_at IS NULL
        "#,
    )
    .bind(club_id)
    .bind(season)
    .fetch_one(pool)
    .await
}

/// Close the season and queue an email for every active member; returns how
/// many will actually be emailed. None when it was already closed: closing
/// twice must not email anybody twice.
pub async fn close_season(
    pool: &PgPool,
    club_id: Uuid,
    season: i32,
    by: Uuid,
) -> Result<Option<i64>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    let closed: Option<DateTime<Utc>> = sqlx::query_scalar(
        r#"
        INSERT INTO club_seasons (club_id, season_year, closed_by) VALUES ($1, $2, $3)
        ON CONFLICT DO NOTHING
        RETURNING closed_at
        "#,
    )
    .bind(club_id)
    .bind(season)
    .bind(by)
    .fetch_optional(&mut *tx)
    .await?;
    if closed.is_none() {
        return Ok(None);
    }
    // Everybody is queued — the push and the bell reach those with no email
    // too — but the number reported is the one the preview promised: emails
    // that will actually go. Counting the opted-out told a secretary "34 on
    // their way" a moment after the preview said 33.
    let emailed: i64 = sqlx::query_scalar(
        r#"
        WITH q AS (
            INSERT INTO season_emails (club_id, season_year, user_id)
            SELECT $1, $2, m.user_id
            FROM club_members m JOIN users u ON u.id = m.user_id
            WHERE m.club_id = $1 AND m.status = 'active' AND u.deleted_at IS NULL
            ON CONFLICT DO NOTHING
            RETURNING user_id
        )
        SELECT COUNT(*) FROM q JOIN users u ON u.id = q.user_id
        WHERE u.email IS NOT NULL AND NOT u.season_emails_off
        "#,
    )
    .bind(club_id)
    .bind(season)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Some(emailed))
}

/// The next rows with something still to do, oldest close first: a push not
/// yet sent, or — only when this server can send mail — an email not yet
/// settled. With mail off, the waiting emails are not even read, so they can
/// never crowd a newly closed club's pushes out of the batch.
pub async fn due_season_emails(
    pool: &PgPool,
    limit: i64,
    mail_on: bool,
) -> Result<Vec<DueSeasonEmail>, sqlx::Error> {
    sqlx::query_as(
        r#"
        SELECT e.club_id, c.name AS club_name, e.season_year, e.user_id,
               u.email, u.season_emails_off, u.email_prefs_token, e.attempts,
               e.pushed_at, (e.sent_at IS NOT NULL OR e.skipped IS NOT NULL) AS email_done
        FROM season_emails e
        JOIN clubs c ON c.id = e.club_id
        JOIN users u ON u.id = e.user_id
        WHERE e.pushed_at IS NULL
           OR ($2 AND e.sent_at IS NULL AND e.skipped IS NULL)
        ORDER BY e.queued_at, e.user_id
        LIMIT $1
        "#,
    )
    .bind(limit)
    .bind(mail_on)
    .fetch_all(pool)
    .await
}

/// The push for this row went.
pub async fn mark_season_pushed(pool: &PgPool, due: &DueSeasonEmail) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE season_emails SET pushed_at = NOW()
         WHERE club_id = $1 AND season_year = $2 AND user_id = $3",
    )
    .bind(due.club_id)
    .bind(due.season_year)
    .bind(due.user_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// `skipped` None means it went.
pub async fn mark_season_email(
    pool: &PgPool,
    due: &DueSeasonEmail,
    skipped: Option<&str>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE season_emails
        SET sent_at = CASE WHEN $4::TEXT IS NULL THEN NOW() END, skipped = $4, attempts = attempts + 1
        WHERE club_id = $1 AND season_year = $2 AND user_id = $3
        "#,
    )
    .bind(due.club_id)
    .bind(due.season_year)
    .bind(due.user_id)
    .bind(skipped)
    .execute(pool)
    .await?;
    Ok(())
}

/// A failed send: try again next tick, up to three times.
pub async fn retry_season_email(pool: &PgPool, due: &DueSeasonEmail) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE season_emails
        SET attempts = attempts + 1,
            skipped = CASE WHEN attempts + 1 >= 3 THEN 'failed' END
        WHERE club_id = $1 AND season_year = $2 AND user_id = $3
        "#,
    )
    .bind(due.club_id)
    .bind(due.season_year)
    .bind(due.user_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Turn season emails off or on from the link in one. True when the token
/// was somebody's.
pub async fn set_season_emails_off(pool: &PgPool, token: &str, off: bool) -> Result<bool, sqlx::Error> {
    let done = sqlx::query("UPDATE users SET season_emails_off = $2 WHERE email_prefs_token = $1")
        .bind(token)
        .bind(off)
        .execute(pool)
        .await?;
    Ok(done.rows_affected() > 0)
}

/// Each board: the top five. The qualifying bars keep one lucky innings off
/// the average board and one tidy over off the economy board.
const BOARDS: &[(&str, &str)] = &[
    (
        "runs",
        r#"SELECT l.user_id, u.name, SUM(l.runs)::TEXT AS value,
                  SUM(l.batting_innings) || ' inns' AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2
           GROUP BY l.user_id, u.name HAVING SUM(l.runs) > 0
           ORDER BY SUM(l.runs) DESC, u.name LIMIT 5"#,
    ),
    (
        "wickets",
        r#"SELECT l.user_id, u.name, SUM(l.wickets)::TEXT AS value,
                  'at ' || ROUND(SUM(l.bowling_runs)::NUMERIC / SUM(l.wickets), 1) AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2
           GROUP BY l.user_id, u.name HAVING SUM(l.wickets) > 0
           ORDER BY SUM(l.wickets) DESC, SUM(l.bowling_runs), u.name LIMIT 5"#,
    ),
    (
        "batting_average",
        r#"SELECT l.user_id, u.name,
                  ROUND(SUM(l.runs)::NUMERIC / NULLIF(SUM(l.batting_innings - l.not_outs), 0), 1)::TEXT AS value,
                  SUM(l.batting_innings) || ' inns' AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2
           GROUP BY l.user_id, u.name
           HAVING SUM(l.batting_innings) >= 3 AND SUM(l.batting_innings - l.not_outs) > 0
           ORDER BY SUM(l.runs)::NUMERIC / SUM(l.batting_innings - l.not_outs) DESC, u.name LIMIT 5"#,
    ),
    (
        "strike_rate",
        r#"SELECT l.user_id, u.name,
                  ROUND(SUM(l.runs) * 100.0 / SUM(l.balls_faced), 1)::TEXT AS value,
                  SUM(l.balls_faced) || ' balls' AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2
           GROUP BY l.user_id, u.name HAVING SUM(l.balls_faced) >= 30
           ORDER BY SUM(l.runs) * 1.0 / SUM(l.balls_faced) DESC, u.name LIMIT 5"#,
    ),
    (
        "economy",
        r#"SELECT l.user_id, u.name,
                  ROUND(SUM(l.bowling_runs) * 6.0 / SUM(l.bowling_balls), 2)::TEXT AS value,
                  (SUM(l.bowling_balls) / 6) || '.' || (SUM(l.bowling_balls) % 6) || ' overs' AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2
           GROUP BY l.user_id, u.name HAVING SUM(l.bowling_balls) >= 36
           ORDER BY SUM(l.bowling_runs) * 1.0 / SUM(l.bowling_balls), u.name LIMIT 5"#,
    ),
    (
        "best_innings",
        r#"SELECT l.user_id, u.name,
                  l.high_score || CASE WHEN l.high_score_not_out THEN '*' ELSE '' END AS value,
                  'v ' || l.opposition AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2 AND l.high_score IS NOT NULL AND l.high_score > 0
           ORDER BY l.high_score DESC, l.high_score_not_out DESC, l.played_at LIMIT 5"#,
    ),
    (
        "best_bowling",
        r#"SELECT l.user_id, u.name, l.wickets || '/' || l.bowling_runs AS value,
                  'v ' || l.opposition AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2 AND l.wickets > 0
           ORDER BY l.wickets DESC, l.bowling_runs, l.played_at LIMIT 5"#,
    ),
    (
        "catches",
        r#"SELECT l.user_id, u.name, SUM(l.catches + l.stumpings)::TEXT AS value,
                  NULL::TEXT AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2
           GROUP BY l.user_id, u.name HAVING SUM(l.catches + l.stumpings) > 0
           ORDER BY SUM(l.catches + l.stumpings) DESC, u.name LIMIT 5"#,
    ),
    (
        "sixes",
        r#"SELECT l.user_id, u.name, SUM(l.sixes)::TEXT AS value, NULL::TEXT AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2
           GROUP BY l.user_id, u.name HAVING SUM(l.sixes) > 0
           ORDER BY SUM(l.sixes) DESC, u.name LIMIT 5"#,
    ),
    (
        "player_of_match",
        r#"SELECT l.user_id, u.name, COUNT(*)::TEXT AS value, NULL::TEXT AS detail
           FROM player_match_lines l JOIN users u ON u.id = l.user_id
           WHERE l.club_id = $1 AND l.season_year = $2 AND l.player_of_match
           GROUP BY l.user_id, u.name
           ORDER BY COUNT(*) DESC, u.name LIMIT 5"#,
    ),
];
