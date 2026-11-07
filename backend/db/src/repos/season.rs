//! A player's season, match by match, and a club's season from the same lines.
//! The arithmetic is in `fishers_domain::season`; this is the reading and
//! writing.

use chrono::{DateTime, Utc};
use fishers_domain::season::{
    match_figures, ClubRank, ClubSeason, Leader, Leaderboard, MatchLine, PlayerGame,
    SeasonRecordLine,
};
use fishers_domain::{MatchSide, MatchState};
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

/// Write one line per player for a finished match. Idempotent: a second call
/// for the same match writes nothing.
///
/// `club_id` is the club that scored it, `opponent_club_id` the other side if
/// it was arranged against a club on the app. Each player is credited to the
/// one of those two they are a member of — the scoring club first, if both.
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
    let Some((event_id, club_id, opponent_club_id, played_at, done)) = ctx else {
        return Ok(());
    };
    if done.is_some() {
        return Ok(());
    }

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
                bowling_balls, bowling_runs, wickets, maidens, catches, stumpings, player_of_match
            )
            SELECT $1, u.id, $3,
                   (SELECT cm.club_id FROM club_members cm
                     WHERE cm.user_id = u.id AND cm.status = 'active'
                       AND cm.club_id IN ($4, $5)
                     ORDER BY (cm.club_id = $4) DESC LIMIT 1),
                   $6, $7, $8, $9,
                   $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
                   $21, $22, $23, $24, $25, $26, $27
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
    l.player_of_match
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

    // A match counts for the club once, whatever number of its players were in
    // it; its result is what the club's players' lines say it was.
    let record: SeasonRecordLine = sqlx::query_as(
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
    .await?;
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
    Ok(Some(ClubSeason { club_id, club_name, season, seasons, record, players, boards }))
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
