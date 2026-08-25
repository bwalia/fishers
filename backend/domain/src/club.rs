use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::{ClubVisibility, MembershipStatus, SportType, UserRole};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Club {
    pub id: Uuid,
    pub name: String,
    /// Stored as Postgres `text[]`; values match `SportType` snake_case.
    pub sport_types: Vec<String>,
    pub visibility: ClubVisibility,
    pub owner_id: Uuid,
    pub description: Option<String>,
    pub is_informal_group: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ClubMember {
    pub club_id: Uuid,
    pub user_id: Uuid,
    pub role: UserRole,
    pub status: MembershipStatus,
    pub joined_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Team {
    pub id: Uuid,
    pub club_id: Uuid,
    pub sport: SportType,
    pub name: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct TeamMember {
    pub team_id: Uuid,
    pub user_id: Uuid,
    pub role: UserRole,
    pub joined_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Venue {
    pub id: Uuid,
    pub club_id: Uuid,
    pub name: String,
    pub address: Option<String>,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateClubRequest {
    #[validate(length(min = 2, max = 160))]
    pub name: String,
    pub sport_types: Vec<SportType>,
    pub visibility: Option<ClubVisibility>,
    pub description: Option<String>,
    pub is_informal_group: Option<bool>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateTeamRequest {
    #[validate(length(min = 1, max = 120))]
    pub name: String,
    pub sport: SportType,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateVenueRequest {
    #[validate(length(min = 1, max = 160))]
    pub name: String,
    pub address: Option<String>,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AddMemberRequest {
    pub user_id: Uuid,
    pub role: Option<UserRole>,
}
