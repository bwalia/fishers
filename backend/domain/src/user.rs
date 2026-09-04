use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::types::Json;
use uuid::Uuid;
use validator::Validate;

use crate::profile::{profile_is_complete, PlayerLocation, SportProfile};
use crate::reliability::ReliabilityScore;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct User {
    pub id: Uuid,
    pub name: String,
    pub email: String,
    pub phone: Option<String>,
    pub apple_id: Option<String>,
    pub avatar_url: Option<String>,
    pub sports_played: Vec<String>,
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
    pub emergency_contact: Option<String>,
    /// Sport the player leads with; the rest of the profile hangs off it.
    pub primary_sport: Option<String>,
    /// One entry per sport played, each with its own level, league and stats.
    pub sport_profiles: Json<Vec<SportProfile>>,
    pub location: Option<Json<PlayerLocation>>,
    /// Set the first time a standard is supplied — the app runs first-run
    /// profile setup until then.
    pub profile_completed_at: Option<DateTime<Utc>>,
    pub password_hash: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublicUser {
    pub id: Uuid,
    pub name: String,
    pub email: String,
    pub phone: Option<String>,
    pub avatar_url: Option<String>,
    pub sports_played: Vec<String>,
    /// Position and standard of the primary sport, flattened for list views.
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
    pub emergency_contact: Option<String>,
    pub primary_sport: Option<String>,
    pub sport_profiles: Vec<SportProfile>,
    pub location: Option<PlayerLocation>,
    pub profile_complete: bool,
    /// Attached by the API from attendance history; never accepted on input.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reliability: Option<ReliabilityScore>,
}

impl From<User> for PublicUser {
    fn from(u: User) -> Self {
        let sport_profiles = u.sport_profiles.0;
        let profile_complete = profile_is_complete(&sport_profiles, u.primary_sport.as_deref());
        Self {
            id: u.id,
            name: u.name,
            email: u.email,
            phone: u.phone,
            avatar_url: u.avatar_url,
            sports_played: u.sports_played,
            position_role: u.position_role,
            skill_level: u.skill_level,
            emergency_contact: u.emergency_contact,
            primary_sport: u.primary_sport,
            sport_profiles,
            location: u.location.map(|l| l.0),
            profile_complete,
            reliability: None,
        }
    }
}

impl PublicUser {
    /// Routes call this after loading the player's attendance counters.
    pub fn with_reliability(mut self, reliability: ReliabilityScore) -> Self {
        self.reliability = Some(reliability);
        self
    }
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct SignupRequest {
    #[validate(length(min = 1, max = 120))]
    pub name: String,
    #[validate(email)]
    pub email: String,
    #[validate(length(min = 8, max = 128))]
    pub password: String,
    pub phone: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct LoginRequest {
    #[validate(email)]
    pub email: String,
    #[validate(length(min = 1))]
    pub password: String,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct UpdateProfileRequest {
    #[validate(length(min = 1, max = 120))]
    pub name: Option<String>,
    pub phone: Option<String>,
    pub avatar_url: Option<String>,
    pub sports_played: Option<Vec<String>>,
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
    pub emergency_contact: Option<String>,
    pub primary_sport: Option<String>,
    /// Sent whole: the client always submits every sport it holds.
    pub sport_profiles: Option<Vec<SportProfile>>,
    pub location: Option<PlayerLocation>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AuthTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
    pub user: PublicUser,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}
