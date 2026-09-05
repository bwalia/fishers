use fishers_domain::{
    AchievementDef, ClubSeasonBoard, ClubSeasonStats, MeStatsResponse, PlayCricketClubSite,
    PlayCricketPlayerLink, PlayerSeasonStats, PlayerSeasonStatsView, UserAchievementView,
};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn club_site(
    pool: &PgPool,
    club_id: Uuid,
) -> Result<Option<PlayCricketClubSite>, sqlx::Error> {
    sqlx::query_as::<_, PlayCricketClubSite>(
        r#"
        SELECT club_id, site_id, site_name, public_url, api_token_env,
               last_synced_at, created_at
        FROM play_cricket_club_sites
        WHERE club_id = $1
        "#,
    )
    .bind(club_id)
    .fetch_optional(pool)
    .await
}

pub async fn player_links_for_user(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<PlayCricketPlayerLink>, sqlx::Error> {
    sqlx::query_as::<_, PlayCricketPlayerLink>(
        r#"
        SELECT id, user_id, club_id, play_cricket_player_id, play_cricket_site_id,
               display_name, profile_url, linked_at, last_synced_at
        FROM play_cricket_player_links
        WHERE user_id = $1
        ORDER BY linked_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
}

fn to_view(
    stats: PlayerSeasonStats,
    player_name: Option<String>,
    club_name: Option<String>,
    profile_url: Option<String>,
    player_id: Option<String>,
) -> PlayerSeasonStatsView {
    let batting_average = stats.batting_average();
    let bowling_average = stats.bowling_average();
    let strike_rate = stats.strike_rate();
    PlayerSeasonStatsView {
        stats,
        player_name,
        club_name,
        play_cricket_profile_url: profile_url,
        play_cricket_player_id: player_id,
        batting_average,
        bowling_average,
        strike_rate,
    }
}

pub async fn player_season_views(
    pool: &PgPool,
    user_id: Uuid,
    season_year: Option<i32>,
) -> Result<Vec<PlayerSeasonStatsView>, sqlx::Error> {
    let rows = sqlx::query_as::<_, PlayerSeasonRow>(
        r#"
        SELECT p.id, p.user_id, p.club_id, p.team_id, p.sport, p.season_year, p.source,
               p.matches, p.runs, p.wickets, p.batting_innings, p.not_outs, p.balls_faced,
               p.fours, p.sixes, p.high_score, p.overs_bowled, p.bowling_runs, p.maidens,
               p.catches, p.stumpings, p.extras, p.updated_at,
               u.name AS player_name,
               c.name AS club_name,
               l.profile_url AS play_cricket_profile_url,
               l.play_cricket_player_id
        FROM player_season_stats p
        JOIN users u ON u.id = p.user_id
        LEFT JOIN clubs c ON c.id = p.club_id
        LEFT JOIN play_cricket_player_links l
               ON l.user_id = p.user_id AND l.club_id IS NOT DISTINCT FROM p.club_id
        WHERE p.user_id = $1
          AND ($2::int IS NULL OR p.season_year = $2)
        ORDER BY p.season_year DESC, p.runs DESC
        "#,
    )
    .bind(user_id)
    .bind(season_year)
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(PlayerSeasonRow::into_view).collect())
}

pub async fn club_season_stats(
    pool: &PgPool,
    club_id: Uuid,
    season_year: Option<i32>,
) -> Result<Vec<ClubSeasonStats>, sqlx::Error> {
    sqlx::query_as::<_, ClubSeasonStats>(
        r#"
        SELECT id, club_id, team_id, sport, season_year, source,
               matches_played, wins, losses, draws, no_results,
               runs_for, runs_against, wickets_taken, wickets_lost,
               extras, updated_at
        FROM club_season_stats
        WHERE club_id = $1
          AND ($2::int IS NULL OR season_year = $2)
        ORDER BY season_year DESC, matches_played DESC
        "#,
    )
    .bind(club_id)
    .bind(season_year)
    .fetch_all(pool)
    .await
}

pub async fn club_leaderboard(
    pool: &PgPool,
    club_id: Uuid,
    season_year: i32,
    limit: i64,
    by_wickets: bool,
) -> Result<Vec<PlayerSeasonStatsView>, sqlx::Error> {
    let order = if by_wickets {
        "p.wickets DESC, p.bowling_runs ASC"
    } else {
        "p.runs DESC"
    };
    // ORDER BY cannot be bound; whitelist only the two fixed clauses above.
    let sql = format!(
        r#"
        SELECT p.id, p.user_id, p.club_id, p.team_id, p.sport, p.season_year, p.source,
               p.matches, p.runs, p.wickets, p.batting_innings, p.not_outs, p.balls_faced,
               p.fours, p.sixes, p.high_score, p.overs_bowled, p.bowling_runs, p.maidens,
               p.catches, p.stumpings, p.extras, p.updated_at,
               u.name AS player_name,
               c.name AS club_name,
               l.profile_url AS play_cricket_profile_url,
               l.play_cricket_player_id
        FROM player_season_stats p
        JOIN users u ON u.id = p.user_id
        LEFT JOIN clubs c ON c.id = p.club_id
        LEFT JOIN play_cricket_player_links l
               ON l.user_id = p.user_id AND l.club_id IS NOT DISTINCT FROM p.club_id
        WHERE p.club_id = $1 AND p.season_year = $2
        ORDER BY {order}
        LIMIT $3
        "#
    );

    let rows = sqlx::query_as::<_, PlayerSeasonRow>(&sql)
        .bind(club_id)
        .bind(season_year)
        .bind(limit)
        .fetch_all(pool)
        .await?;

    Ok(rows.into_iter().map(PlayerSeasonRow::into_view).collect())
}

pub async fn club_board(
    pool: &PgPool,
    club_id: Uuid,
    season_year: i32,
) -> Result<Option<ClubSeasonBoard>, sqlx::Error> {
    let seasons = club_season_stats(pool, club_id, Some(season_year)).await?;
    // Prefer club-wide row (team_id NULL) over team-specific boards.
    let club = seasons
        .into_iter()
        .min_by_key(|s| if s.team_id.is_none() { 0 } else { 1 });

    let top_batters = club_leaderboard(pool, club_id, season_year, 8, false).await?;
    let top_bowlers = club_leaderboard(pool, club_id, season_year, 8, true).await?;
    let play_cricket = club_site(pool, club_id).await?;

    let Some(club) = club else {
        if top_batters.is_empty() && top_bowlers.is_empty() && play_cricket.is_none() {
            return Ok(None);
        }
        return Ok(Some(ClubSeasonBoard {
            club: ClubSeasonStats {
                id: Uuid::nil(),
                club_id,
                team_id: None,
                sport: "cricket".into(),
                season_year,
                source: "derived".into(),
                matches_played: 0,
                wins: 0,
                losses: 0,
                draws: 0,
                no_results: 0,
                runs_for: 0,
                runs_against: 0,
                wickets_taken: 0,
                wickets_lost: 0,
                extras: sqlx::types::Json(serde_json::json!({})),
                updated_at: chrono::Utc::now(),
            },
            play_cricket,
            top_batters,
            top_bowlers,
        }));
    };

    Ok(Some(ClubSeasonBoard {
        club,
        play_cricket,
        top_batters,
        top_bowlers,
    }))
}

pub async fn me_stats(
    pool: &PgPool,
    user_id: Uuid,
    season_year: Option<i32>,
) -> Result<MeStatsResponse, sqlx::Error> {
    let links = player_links_for_user(pool, user_id).await?;
    let seasons = player_season_views(pool, user_id, season_year).await?;
    let achievements = achievements_for_user(pool, user_id).await?;
    Ok(MeStatsResponse {
        links,
        seasons,
        achievements,
    })
}

pub async fn achievements_for_user(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<UserAchievementView>, sqlx::Error> {
    let rows = sqlx::query_as::<_, AchievementJoinRow>(
        r#"
        SELECT a.id, a.user_id, a.achievement_code, a.club_id, a.season_year,
               a.awarded_at, a.evidence,
               d.title, d.description, d.icon
        FROM user_achievements a
        JOIN achievement_defs d ON d.code = a.achievement_code
        WHERE a.user_id = $1
        ORDER BY a.awarded_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| UserAchievementView {
            award: fishers_domain::UserAchievement {
                id: r.id,
                user_id: r.user_id,
                achievement_code: r.achievement_code,
                club_id: r.club_id,
                season_year: r.season_year,
                awarded_at: r.awarded_at,
                evidence: r.evidence,
            },
            title: r.title,
            description: r.description,
            icon: r.icon,
        })
        .collect())
}

pub async fn list_achievement_defs(pool: &PgPool) -> Result<Vec<AchievementDef>, sqlx::Error> {
    sqlx::query_as::<_, AchievementDef>(
        r#"
        SELECT code, sport, title, description, icon, criteria
        FROM achievement_defs
        ORDER BY title
        "#,
    )
    .fetch_all(pool)
    .await
}

pub async fn touch_club_sync(pool: &PgPool, club_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE play_cricket_club_sites
        SET last_synced_at = NOW()
        WHERE club_id = $1
        "#,
    )
    .bind(club_id)
    .execute(pool)
    .await?;
    Ok(())
}

#[derive(sqlx::FromRow)]
struct PlayerSeasonRow {
    id: Uuid,
    user_id: Uuid,
    club_id: Option<Uuid>,
    team_id: Option<Uuid>,
    sport: String,
    season_year: i32,
    source: String,
    matches: i32,
    runs: i32,
    wickets: i32,
    batting_innings: i32,
    not_outs: i32,
    balls_faced: i32,
    fours: i32,
    sixes: i32,
    high_score: Option<i32>,
    overs_bowled: f64,
    bowling_runs: i32,
    maidens: i32,
    catches: i32,
    stumpings: i32,
    extras: sqlx::types::Json<serde_json::Value>,
    updated_at: chrono::DateTime<chrono::Utc>,
    player_name: Option<String>,
    club_name: Option<String>,
    play_cricket_profile_url: Option<String>,
    play_cricket_player_id: Option<String>,
}

impl PlayerSeasonRow {
    fn into_view(self) -> PlayerSeasonStatsView {
        to_view(
            PlayerSeasonStats {
                id: self.id,
                user_id: self.user_id,
                club_id: self.club_id,
                team_id: self.team_id,
                sport: self.sport,
                season_year: self.season_year,
                source: self.source,
                matches: self.matches,
                runs: self.runs,
                wickets: self.wickets,
                batting_innings: self.batting_innings,
                not_outs: self.not_outs,
                balls_faced: self.balls_faced,
                fours: self.fours,
                sixes: self.sixes,
                high_score: self.high_score,
                overs_bowled: self.overs_bowled,
                bowling_runs: self.bowling_runs,
                maidens: self.maidens,
                catches: self.catches,
                stumpings: self.stumpings,
                extras: self.extras,
                updated_at: self.updated_at,
            },
            self.player_name,
            self.club_name,
            self.play_cricket_profile_url,
            self.play_cricket_player_id,
        )
    }
}

#[derive(sqlx::FromRow)]
struct AchievementJoinRow {
    id: Uuid,
    user_id: Uuid,
    achievement_code: String,
    club_id: Option<Uuid>,
    season_year: Option<i32>,
    awarded_at: chrono::DateTime<chrono::Utc>,
    evidence: sqlx::types::Json<serde_json::Value>,
    title: String,
    description: Option<String>,
    icon: Option<String>,
}
