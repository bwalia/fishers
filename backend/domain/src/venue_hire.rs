//! Venue hire — spaces, rate cards, availability (Phase 1 of docs/VENUE_HIRE.md).

use chrono::{DateTime, NaiveDate, NaiveTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

/// What kind of bookable space this is inside a venue site.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "venue_space_kind", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum VenueSpaceKind {
    Pitch,
    Square,
    NetLane,
    Court,
    Hall,
    Pavilion,
    Bar,
    Room,
    Other,
}

/// How a rate card charges.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "venue_rate_unit", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum VenueRateUnit {
    PerHour,
    PerSession,
    PerHalfDay,
    PerDay,
    PerHead,
    Fixed,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct VenueSpace {
    pub id: Uuid,
    pub venue_id: Uuid,
    pub name: String,
    pub kind: VenueSpaceKind,
    pub sports: Vec<String>,
    pub capacity: Option<i32>,
    pub is_hireable: bool,
    pub requires_approval: bool,
    pub notice_hours_min: i32,
    pub notice_days_max: i32,
    pub slot_minutes: i32,
    pub buffer_minutes: i32,
    pub notes: Option<String>,
    pub active: bool,
    pub timezone: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateVenueSpaceRequest {
    #[validate(length(min = 1, max = 160))]
    pub name: String,
    pub kind: VenueSpaceKind,
    #[serde(default)]
    pub sports: Vec<String>,
    pub capacity: Option<i32>,
    #[serde(default)]
    pub is_hireable: bool,
    #[serde(default = "default_true")]
    pub requires_approval: bool,
    #[serde(default = "default_notice_hours")]
    pub notice_hours_min: i32,
    #[serde(default = "default_notice_days")]
    pub notice_days_max: i32,
    #[serde(default = "default_slot")]
    pub slot_minutes: i32,
    #[serde(default)]
    pub buffer_minutes: i32,
    pub notes: Option<String>,
    #[serde(default = "default_tz")]
    pub timezone: String,
}

fn default_true() -> bool {
    true
}
fn default_notice_hours() -> i32 {
    24
}
fn default_notice_days() -> i32 {
    365
}
fn default_slot() -> i32 {
    60
}
fn default_tz() -> String {
    "Europe/London".into()
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct UpdateVenueSpaceRequest {
    #[validate(length(min = 1, max = 160))]
    pub name: Option<String>,
    pub kind: Option<VenueSpaceKind>,
    pub sports: Option<Vec<String>>,
    pub capacity: Option<Option<i32>>,
    pub is_hireable: Option<bool>,
    pub requires_approval: Option<bool>,
    pub notice_hours_min: Option<i32>,
    pub notice_days_max: Option<i32>,
    pub slot_minutes: Option<i32>,
    pub buffer_minutes: Option<i32>,
    pub notes: Option<Option<String>>,
    pub active: Option<bool>,
    pub timezone: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct VenueRateCard {
    pub id: Uuid,
    pub space_id: Uuid,
    pub name: String,
    pub unit: VenueRateUnit,
    pub amount_cents: i32,
    pub currency: String,
    pub member_amount_cents: Option<i32>,
    pub days_of_week: Vec<i16>,
    pub time_from: Option<NaiveTime>,
    pub time_to: Option<NaiveTime>,
    pub season_from: Option<NaiveDate>,
    pub season_to: Option<NaiveDate>,
    pub min_units: i32,
    pub active: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateVenueRateCardRequest {
    #[validate(length(min = 1, max = 120))]
    pub name: String,
    pub unit: VenueRateUnit,
    #[validate(range(min = 0))]
    pub amount_cents: i32,
    #[serde(default = "default_currency")]
    pub currency: String,
    pub member_amount_cents: Option<i32>,
    #[serde(default)]
    pub days_of_week: Vec<i16>,
    pub time_from: Option<NaiveTime>,
    pub time_to: Option<NaiveTime>,
    pub season_from: Option<NaiveDate>,
    pub season_to: Option<NaiveDate>,
    #[serde(default = "default_min_units")]
    pub min_units: i32,
}

fn default_currency() -> String {
    "GBP".into()
}
fn default_min_units() -> i32 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct VenueAvailabilityWindow {
    pub id: Uuid,
    pub space_id: Uuid,
    pub day_of_week: i16,
    pub opens_at: NaiveTime,
    pub closes_at: NaiveTime,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct SetVenueAvailabilityRequest {
    pub windows: Vec<VenueAvailabilityWindowInput>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct VenueAvailabilityWindowInput {
    #[validate(range(min = 0, max = 6))]
    pub day_of_week: i16,
    pub opens_at: NaiveTime,
    pub closes_at: NaiveTime,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct VenueBlackout {
    pub id: Uuid,
    pub space_id: Uuid,
    pub starts_at: DateTime<Utc>,
    pub ends_at: DateTime<Utc>,
    pub reason: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateVenueBlackoutRequest {
    pub starts_at: DateTime<Utc>,
    pub ends_at: DateTime<Utc>,
    pub reason: Option<String>,
}

/// A hireable space as shown on the public/member discovery list.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct HireableSpaceRow {
    pub space_id: Uuid,
    pub space_name: String,
    pub kind: VenueSpaceKind,
    pub sports: Vec<String>,
    pub capacity: Option<i32>,
    pub requires_approval: bool,
    pub timezone: String,
    pub venue_id: Uuid,
    pub venue_name: String,
    pub venue_address: Option<String>,
    pub venue_lat: Option<f64>,
    pub venue_lng: Option<f64>,
    pub club_id: Uuid,
    pub club_name: String,
    /// Lowest active rate amount in minor units, when any rate exists.
    pub from_amount_cents: Option<i32>,
    pub currency: Option<String>,
}
