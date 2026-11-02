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
    /// Vice captain — can score matches and help with selection.
    TeamViceCaptain,
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

impl SportType {
    /// Every sport the column accepts, in the order a picker should offer
    /// them. Cricket first because that is what the scoring is for; `Other`
    /// last because it is the escape hatch rather than a choice.
    ///
    /// The one list. A second one written out somewhere else is a sport that
    /// exists in the database and nowhere a person can pick it.
    pub const ALL: [SportType; 7] = [
        SportType::Cricket,
        SportType::Football,
        SportType::Badminton,
        SportType::Paddle,
        SportType::Pickleball,
        SportType::Tennis,
        SportType::Other,
    ];

    /// The wire spelling — what serde writes, and what the Postgres enum
    /// holds. Kept beside `ALL` so the two cannot disagree.
    pub const fn as_str(self) -> &'static str {
        match self {
            SportType::Cricket => "cricket",
            SportType::Football => "football",
            SportType::Badminton => "badminton",
            SportType::Paddle => "paddle",
            SportType::Pickleball => "pickleball",
            SportType::Tennis => "tennis",
            SportType::Other => "other",
        }
    }

    /// Read a wire spelling back, case and padding forgiven.
    ///
    /// `padel` is accepted for `paddle`: both apps spelled it that way before
    /// the enums were lined up, and profiles saved then still say it.
    pub fn parse(raw: &str) -> Option<SportType> {
        let key = raw.trim().to_ascii_lowercase();
        let key = if key == "padel" { "paddle" } else { key.as_str() };
        SportType::ALL.into_iter().find(|s| s.as_str() == key)
    }
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

/// What state a thing is in.
///
/// The whole point of the second-hand half: a club selling last season's pads
/// and a club selling pads it made itself are offering different things, and
/// the price alone does not say which is which.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "product_condition", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum ProductCondition {
    New,
    Used,
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
