//! Row types returned by queries. Serialize directly to the API's JSON shapes
//! (snake_case fields, RFC 3339 UTC timestamps, money as integer pence).

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::prelude::FromRow;
use sqlx::types::JsonValue;
use uuid::Uuid;

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct UserRow {
    pub id: Uuid,
    pub name: String,
    pub email: String,
    pub phone: Option<String>,
    pub avatar_url: Option<String>,
    pub emergency_contact: Option<String>,
    /// Sport the player leads with; the rest of the profile hangs off it.
    pub primary_sport: Option<String>,
    pub sports: Vec<String>,
    /// Position and standard of the primary sport, mirrored flat for list views.
    pub position: Option<String>,
    pub skill_level: Option<String>,
    /// `[{sport, position, skill_level, current_division, target_division,
    /// age_group, team_name, years_playing, stats: [{key, value}]}]`
    pub sport_profiles: JsonValue,
    /// `{area, postcode, travel_radius_miles, transport, spare_seats,
    /// preferred_days, notes}`
    pub location: Option<JsonValue>,
    pub profile_completed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

/// Body of `PATCH /users/me`. Everything except the name is optional to set,
/// but the client always sends the whole profile it holds.
#[derive(Debug, Clone, Deserialize)]
pub struct ProfileUpdate {
    pub name: String,
    pub phone: Option<String>,
    pub avatar_url: Option<String>,
    pub emergency_contact: Option<String>,
    pub primary_sport: Option<String>,
    #[serde(default)]
    pub sports: Vec<String>,
    pub position: Option<String>,
    pub skill_level: Option<String>,
    #[serde(default)]
    pub sport_profiles: JsonValue,
    pub location: Option<JsonValue>,
}

/// Raw counters from the `player_reliability_counts` view, fed to
/// `fishers_domain::reliability::score`.
#[derive(Debug, Clone, Copy, FromRow)]
pub struct ReliabilityCountsRow {
    pub user_id: Uuid,
    pub invites_received: i64,
    pub responded: i64,
    pub said_going: i64,
    pub turned_up: i64,
    pub late_cancellations: i64,
    pub fees_due: i64,
    pub fees_paid: i64,
}

/// Credential lookup only — never serialised.
#[derive(Debug, Clone, FromRow)]
pub struct UserAuthRow {
    pub id: Uuid,
    pub password_hash: String,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct ClubRow {
    pub id: Uuid,
    pub name: String,
    pub sport_types: Vec<String>,
    pub visibility: String,
    pub owner_id: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct TeamRow {
    pub id: Uuid,
    pub club_id: Uuid,
    pub sport: String,
    pub name: String,
    /// League grade the side plays in, e.g. `division3`.
    pub division: Option<String>,
    /// Age band the side selects from, e.g. `senior` or `u15`.
    pub age_group: Option<String>,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct ClubMemberRow {
    pub user_id: Uuid,
    pub name: String,
    pub avatar_url: Option<String>,
    pub role: String,
    pub status: String,
    pub joined_at: DateTime<Utc>,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct EventRow {
    pub id: Uuid,
    pub club_id: Uuid,
    pub team_id: Option<Uuid>,
    pub sport: String,
    pub event_subtype: String,
    pub title: String,
    pub description: Option<String>,
    pub venue_id: Option<Uuid>,
    pub start_at: DateTime<Utc>,
    pub end_at: DateTime<Utc>,
    pub recurrence_rule: Option<String>,
    pub recurrence_parent_id: Option<Uuid>,
    pub capacity: Option<i32>,
    pub fee_amount: Option<i64>,
    pub currency: String,
    pub status: String,
    pub nets_lanes: Option<i32>,
    pub nets_max_per_lane: Option<i32>,
    pub nets_bowling_machine: Option<bool>,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct AttendeeRow {
    pub user_id: Uuid,
    pub name: String,
    pub avatar_url: Option<String>,
    pub status: String,
    pub responded_at: Option<DateTime<Utc>>,
    pub paid: bool,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct AvailabilityRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub date: NaiveDate,
    pub status: String,
    pub note: Option<String>,
    pub recurrence_rule: Option<String>,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct InviteRow {
    pub id: Uuid,
    pub kind: String,
    pub club_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub event_id: Option<Uuid>,
    pub inviter_id: Uuid,
    pub invitee_id: Option<Uuid>,
    pub invitee_email: Option<String>,
    pub token: Option<String>,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub responded_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct PaymentRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub event_id: Option<Uuid>,
    pub amount: i64,
    pub currency: String,
    pub status: String,
    pub stripe_payment_intent_id: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct ProductRow {
    pub id: Uuid,
    pub club_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub price: i64,
    pub currency: String,
    pub category: String,
    pub stock: Option<i32>,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct OrderRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub event_id: Option<Uuid>,
    pub status: String,
    pub total_amount: i64,
    pub currency: String,
    pub note: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct OrderItemRow {
    pub order_id: Uuid,
    pub product_id: Uuid,
    pub product_name: String,
    pub quantity: i32,
    pub unit_price: i64,
}

#[derive(Debug, Clone, FromRow, Serialize)]
pub struct DeviceRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_token: String,
    pub platform: String,
    pub created_at: DateTime<Utc>,
}
