//! Shared domain enums. Stored as TEXT in Postgres (CHECK-constrained);
//! serialised as snake_case strings over the API.

use serde::{Deserialize, Serialize};
use std::fmt;
use std::str::FromStr;

#[derive(Debug, thiserror::Error)]
#[error("invalid value `{value}` for {kind}")]
pub struct ParseEnumError {
    pub kind: &'static str,
    pub value: String,
}

macro_rules! str_enum {
    ($name:ident, $kind:literal, { $($variant:ident => $s:literal),+ $(,)? }) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
        #[serde(rename_all = "snake_case")]
        pub enum $name {
            $($variant),+
        }

        impl $name {
            pub fn as_str(&self) -> &'static str {
                match self {
                    $(Self::$variant => $s),+
                }
            }
        }

        impl FromStr for $name {
            type Err = ParseEnumError;
            fn from_str(s: &str) -> Result<Self, Self::Err> {
                match s {
                    $($s => Ok(Self::$variant),)+
                    other => Err(ParseEnumError { kind: $kind, value: other.to_string() }),
                }
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(self.as_str())
            }
        }
    };
}

str_enum!(EventSubtype, "event_subtype", {
    Nets => "nets",
    Friendly => "friendly",
    LeagueMatch => "league_match",
    Social => "social",
    Generic => "generic",
});

str_enum!(EventStatus, "event_status", {
    Scheduled => "scheduled",
    Cancelled => "cancelled",
    Completed => "completed",
});

str_enum!(RsvpStatus, "rsvp_status", {
    Pending => "pending",
    Going => "going",
    NotGoing => "not_going",
    Maybe => "maybe",
});

str_enum!(AvailabilityStatus, "availability_status", {
    Available => "available",
    Unavailable => "unavailable",
    Maybe => "maybe",
});

str_enum!(ClubRole, "club_role", {
    Admin => "admin",
    Captain => "captain",
    Member => "member",
});

str_enum!(ClubVisibility, "club_visibility", {
    Public => "public",
    InviteOnly => "invite_only",
});

str_enum!(InviteKind, "invite_kind", {
    Club => "club",
    Team => "team",
    Event => "event",
});

str_enum!(ProductCategory, "product_category", {
    Food => "food",
    Equipment => "equipment",
    KitHire => "kit_hire",
    Merchandise => "merchandise",
    Other => "other",
});

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        assert_eq!(EventSubtype::LeagueMatch.as_str(), "league_match");
        assert_eq!(
            "league_match".parse::<EventSubtype>().unwrap(),
            EventSubtype::LeagueMatch
        );
        assert!("cheese".parse::<EventSubtype>().is_err());
        assert_eq!(RsvpStatus::NotGoing.as_str(), "not_going");
        assert_eq!(
            "invite_only".parse::<ClubVisibility>().unwrap(),
            ClubVisibility::InviteOnly
        );
    }
}
