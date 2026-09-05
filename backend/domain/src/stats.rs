//! Season stats linked to ECB Play-Cricket profiles (runs, wickets, achievements).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::types::Json;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct PlayCricketClubSite {
    pub club_id: Uuid,
    pub site_id: String,
    pub site_name: Option<String>,
    pub public_url: Option<String>,
    pub api_token_env: Option<String>,
    pub last_synced_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct PlayCricketPlayerLink {
    pub id: Uuid,
    pub user_id: Uuid,
    pub club_id: Option<Uuid>,
    pub play_cricket_player_id: String,
    pub play_cricket_site_id: Option<String>,
    pub display_name: Option<String>,
    pub profile_url: Option<String>,
    pub linked_at: DateTime<Utc>,
    pub last_synced_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct PlayerSeasonStats {
    pub id: Uuid,
    pub user_id: Uuid,
    pub club_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub sport: String,
    pub season_year: i32,
    pub source: String,
    pub matches: i32,
    pub runs: i32,
    pub wickets: i32,
    pub batting_innings: i32,
    pub not_outs: i32,
    pub balls_faced: i32,
    pub fours: i32,
    pub sixes: i32,
    pub high_score: Option<i32>,
    pub overs_bowled: f64,
    pub bowling_runs: i32,
    pub maidens: i32,
    pub catches: i32,
    pub stumpings: i32,
    pub extras: Json<Value>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ClubSeasonStats {
    pub id: Uuid,
    pub club_id: Uuid,
    pub team_id: Option<Uuid>,
    pub sport: String,
    pub season_year: i32,
    pub source: String,
    pub matches_played: i32,
    pub wins: i32,
    pub losses: i32,
    pub draws: i32,
    pub no_results: i32,
    pub runs_for: i32,
    pub runs_against: i32,
    pub wickets_taken: i32,
    pub wickets_lost: i32,
    pub extras: Json<Value>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AchievementDef {
    pub code: String,
    pub sport: Option<String>,
    pub title: String,
    pub description: Option<String>,
    pub icon: Option<String>,
    pub criteria: Json<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct UserAchievement {
    pub id: Uuid,
    pub user_id: Uuid,
    pub achievement_code: String,
    pub club_id: Option<Uuid>,
    pub season_year: Option<i32>,
    pub awarded_at: DateTime<Utc>,
    pub evidence: Json<Value>,
}

/// API view: player season row plus Play-Cricket deep link and labels.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerSeasonStatsView {
    #[serde(flatten)]
    pub stats: PlayerSeasonStats,
    pub player_name: Option<String>,
    pub club_name: Option<String>,
    pub play_cricket_profile_url: Option<String>,
    pub play_cricket_player_id: Option<String>,
    pub batting_average: Option<f64>,
    pub bowling_average: Option<f64>,
    pub strike_rate: Option<f64>,
}

/// Achievement with catalogue metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserAchievementView {
    #[serde(flatten)]
    pub award: UserAchievement,
    pub title: String,
    pub description: Option<String>,
    pub icon: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClubSeasonBoard {
    pub club: ClubSeasonStats,
    pub play_cricket: Option<PlayCricketClubSite>,
    pub top_batters: Vec<PlayerSeasonStatsView>,
    pub top_bowlers: Vec<PlayerSeasonStatsView>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeStatsResponse {
    pub links: Vec<PlayCricketPlayerLink>,
    pub seasons: Vec<PlayerSeasonStatsView>,
    pub achievements: Vec<UserAchievementView>,
}

impl PlayerSeasonStats {
    pub fn batting_average(&self) -> Option<f64> {
        let outs = self.batting_innings.saturating_sub(self.not_outs);
        if outs <= 0 {
            return None;
        }
        Some(self.runs as f64 / outs as f64)
    }

    pub fn bowling_average(&self) -> Option<f64> {
        if self.wickets <= 0 {
            return None;
        }
        Some(self.bowling_runs as f64 / self.wickets as f64)
    }

    pub fn strike_rate(&self) -> Option<f64> {
        if self.balls_faced <= 0 {
            return None;
        }
        Some((self.runs as f64 / self.balls_faced as f64) * 100.0)
    }
}
