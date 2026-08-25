use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

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
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
}

impl From<User> for PublicUser {
    fn from(u: User) -> Self {
        Self {
            id: u.id,
            name: u.name,
            email: u.email,
            phone: u.phone,
            avatar_url: u.avatar_url,
            sports_played: u.sports_played,
            position_role: u.position_role,
            skill_level: u.skill_level,
        }
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
