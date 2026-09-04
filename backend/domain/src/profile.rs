//! Player profiles — what someone plays, at what standard, and how they get
//! to fixtures. One `SportProfile` per sport the player picked at setup.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Per-sport level, league grade and stats. `stats` keys are open-ended and
/// defined by the client's sport catalog (batting_average, padel_level, …).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SportProfile {
    pub sport: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub position: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub skill_level: Option<String>,
    /// League grade played now, e.g. `division3`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_division: Option<String>,
    /// League grade the player is working towards — what "levelling up" means.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_division: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub age_group: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub team_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub years_playing: Option<i32>,
    #[serde(default)]
    pub stats: BTreeMap<String, String>,
}

impl SportProfile {
    /// A sport counts as set up once the player has stated a standard.
    pub fn is_complete(&self) -> bool {
        self.skill_level.as_deref().is_some_and(|s| !s.is_empty())
    }
}

/// Where the player is based and how they travel — drives lift sharing on away
/// fixtures and "is this venue realistic for them" filtering.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PlayerLocation {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub area: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub postcode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub travel_radius_miles: Option<i32>,
    /// `driverWithSeats` | `driver` | `publicTransport` | `needsLift`
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub transport: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub spare_seats: Option<i32>,
    /// Calendar weekday numbers, 1 = Sunday.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preferred_days: Option<Vec<i16>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

/// The gate the app uses to decide whether to run first-run profile setup:
/// a primary sport with a stated standard.
pub fn profile_is_complete(profiles: &[SportProfile], primary_sport: Option<&str>) -> bool {
    let primary = primary_sport
        .and_then(|sport| profiles.iter().find(|p| p.sport == sport))
        .or_else(|| profiles.first());
    primary.is_some_and(SportProfile::is_complete)
}
