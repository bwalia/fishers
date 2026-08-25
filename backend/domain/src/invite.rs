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
