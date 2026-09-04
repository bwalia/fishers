use serde::{Deserialize, Serialize};

/// Club / team membership role.
///
/// Product language: **Club secretary** is stored as [`UserRole::ClubAdmin`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "user_role", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum UserRole {
    SuperAdmin,
    /// Club secretary — roster, invites, venues, fees, selection oversight.
    ClubAdmin,
    TeamCaptain,
    Member,
    Guest,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "membership_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum MembershipStatus {
    Active,
    Invited,
    Suspended,
    Left,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "club_visibility", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum ClubVisibility {
    Public,
    InviteOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "sport_type", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum SportType {
    Cricket,
    Football,
    Badminton,
    Paddle,
    Pickleball,
    Tennis,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "event_subtype", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum EventSubtype {
    Nets,
    Friendly,
    LeagueMatch,
    Tournament,
    Social,
    Training,
    Generic,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "event_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum EventStatus {
    Draft,
    Scheduled,
    /// Called off for now — rain, unplayable ground, opposition pulled out.
    Postponed,
    Cancelled,
    Completed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "availability_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum AvailabilityStatus {
    Available,
    Unavailable,
    Maybe,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "rsvp_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum RsvpStatus {
    Going,
    NotGoing,
    Maybe,
    Invited,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "invite_target", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum InviteTarget {
    Club,
    Team,
    Event,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "payment_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum PaymentStatus {
    Pending,
    RequiresAction,
    Succeeded,
    Failed,
    Refunded,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "order_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum OrderStatus {
    Draft,
    Placed,
    Paid,
    Fulfilled,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "product_category", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum ProductCategory {
    Food,
    Drink,
    KitHire,
    Merchandise,
    Equipment,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "home_or_away", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum HomeOrAway {
    Home,
    Away,
    Neutral,
}
