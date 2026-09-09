use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;
use validator::Validate;

use crate::{EventStatus, EventSubtype, HomeOrAway, SportType};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Event {
    pub id: Uuid,
    pub club_id: Uuid,
    /// The visiting club, when the fixture is against another Fishers club.
    /// Known at scheduling time so both sides can be asked who is available.
    pub opponent_club_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub sport: SportType,
    pub event_subtype: EventSubtype,
    pub title: String,
    pub venue_id: Option<Uuid>,
    pub start_at: DateTime<Utc>,
    pub end_at: DateTime<Utc>,
    pub recurrence_rule: Option<String>,
    pub recurrence_parent_id: Option<Uuid>,
    pub capacity: Option<i32>,
    pub fee_amount_cents: Option<i32>,
    pub fee_currency: String,
    pub status: EventStatus,
    /// "Called off — ground unplayable after Friday's rain."
    pub status_note: Option<String>,
    /// Set when a postponed fixture gets a new date.
    pub rescheduled_to: Option<DateTime<Utc>>,
    /// Cricket nets extras (lanes, machine, kit) or other sport metadata.
    pub metadata: Value,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct MatchResult {
    pub event_id: Uuid,
    pub format: Option<String>,
    pub opposition: Option<String>,
    pub home_or_away: Option<HomeOrAway>,
    pub scorecard_json: Value,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateEventRequest {
    pub club_id: Uuid,
    /// Who it is against, when they are a Fishers club — their members get
    /// asked about their availability too.
    pub opponent_club_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub sport: SportType,
    pub event_subtype: EventSubtype,
    #[validate(length(min = 1, max = 200))]
    pub title: String,
    pub venue_id: Option<Uuid>,
    pub start_at: DateTime<Utc>,
    pub end_at: DateTime<Utc>,
    /// iCal RRULE fragment, e.g. `FREQ=WEEKLY;BYDAY=WE`
    pub recurrence_rule: Option<String>,
    pub capacity: Option<i32>,
    pub fee_amount_cents: Option<i32>,
    pub fee_currency: Option<String>,
    pub metadata: Option<Value>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct UpdateEventRequest {
    pub title: Option<String>,
    pub venue_id: Option<Uuid>,
    pub start_at: Option<DateTime<Utc>>,
    pub end_at: Option<DateTime<Utc>>,
    pub capacity: Option<i32>,
    pub fee_amount_cents: Option<i32>,
    pub status: Option<EventStatus>,
    pub metadata: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetsMetadata {
    pub facility_type: Option<String>,
    pub lane_count: Option<i32>,
    pub max_players_per_lane: Option<i32>,
    pub bowling_machine: Option<bool>,
    pub kit_needed: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchMetadata {
    pub format: Option<String>,
    pub opposition: Option<String>,
    pub home_or_away: Option<HomeOrAway>,
    pub toss_at: Option<DateTime<Utc>>,
    pub umpires: Option<Vec<String>>,
    pub scorers: Option<Vec<String>>,
}
