use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::{InviteTarget, RsvpStatus};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct EventInvite {
    pub id: Uuid,
    pub event_id: Uuid,
    pub user_id: Uuid,
    pub invited_by: Uuid,
    pub status: RsvpStatus,
    pub responded_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Invite {
    pub id: Uuid,
    pub target_type: InviteTarget,
    pub target_id: Uuid,
    pub invited_user_id: Option<Uuid>,
    pub invited_email: Option<String>,
    pub invited_by: Uuid,
    pub token: String,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub accepted_at: Option<DateTime<Utc>>,
    /// What the invite is to — the club, "team · club", or the fixture — and
    /// who sent it. Filled in only when listing somebody's own invites: an
    /// invite reading "A club invitation" asks people to join without saying
    /// what they are joining. `default` so every other query can leave them out.
    #[sqlx(default)]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_name: Option<String>,
    #[sqlx(default)]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub invited_by_name: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateInviteRequest {
    pub target_type: InviteTarget,
    pub target_id: Uuid,
    pub invited_user_id: Option<Uuid>,
    pub invited_email: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RsvpRequest {
    pub status: RsvpStatus,
}

#[derive(Debug, Clone, Serialize)]
pub struct AttendeeSummary {
    pub user_id: Uuid,
    pub name: String,
    pub status: RsvpStatus,
    pub availability: Option<crate::AvailabilityStatus>,
    pub paid: bool,
}
