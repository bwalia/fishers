use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::AvailabilityStatus;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Availability {
    pub id: Uuid,
    pub user_id: Uuid,
    pub date: NaiveDate,
    pub status: AvailabilityStatus,
    pub note: Option<String>,
    pub recurrence_rule: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct UpsertAvailabilityRequest {
    pub date: NaiveDate,
    pub status: AvailabilityStatus,
    pub note: Option<String>,
    pub recurrence_rule: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct BulkAvailabilityRequest {
    pub dates: Vec<NaiveDate>,
    pub status: AvailabilityStatus,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AvailabilityQuery {
    pub from: NaiveDate,
    pub to: NaiveDate,
    pub user_id: Option<Uuid>,
}
