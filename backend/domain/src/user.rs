use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::types::Json;
use uuid::Uuid;
use validator::Validate;

use crate::profile::{profile_is_complete, PlayerLocation, SportProfile};
use crate::reliability::ReliabilityScore;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct User {
    pub id: Uuid,
    pub name: String,
    /// Absent for somebody who registered with a mobile number instead.
    pub email: Option<String>,
    pub phone: Option<String>,
    pub apple_id: Option<String>,
    pub avatar_url: Option<String>,
    pub sports_played: Vec<String>,
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
    pub emergency_contact: Option<String>,
    /// Sport the player leads with; the rest of the profile hangs off it.
    pub primary_sport: Option<String>,
    /// One entry per sport played, each with its own level, league and stats.
    pub sport_profiles: Json<Vec<SportProfile>>,
    pub location: Option<Json<PlayerLocation>>,
    /// Set the first time a standard is supplied — the app runs first-run
    /// profile setup until then.
    pub profile_completed_at: Option<DateTime<Utc>>,
    pub email_verified_at: Option<DateTime<Utc>>,
    pub phone_verified_at: Option<DateTime<Utc>>,
    /// "secretary" or "player": what they said they came to do.
    pub role_intent: Option<String>,
    pub profile_share_token: Option<String>,
    pub password_hash: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublicUser {
    pub id: Uuid,
    pub name: String,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub avatar_url: Option<String>,
    pub sports_played: Vec<String>,
    /// Position and standard of the primary sport, flattened for list views.
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
    pub emergency_contact: Option<String>,
    pub primary_sport: Option<String>,
    pub sport_profiles: Vec<SportProfile>,
    pub location: Option<PlayerLocation>,
    pub profile_complete: bool,
    pub email_verified: bool,
    pub phone_verified: bool,
    /// "secretary" or "player"; absent until they have been asked.
    pub role_intent: Option<String>,
    /// How much of the profile is filled in, and what to add next.
    pub profile_strength: ProfileStrength,
    /// Attached by the API from attendance history; never accepted on input.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reliability: Option<ReliabilityScore>,
    /// Whether this person may see the whole system. Attached by the API from
    /// PLATFORM_ADMIN_EMAILS; `From<User>` always leaves it false, so a route
    /// that forgets to set it denies rather than grants.
    #[serde(default)]
    pub platform_admin: bool,
}

impl From<User> for PublicUser {
    fn from(u: User) -> Self {
        let profile_strength = ProfileStrength::of(&u);
        let sport_profiles = u.sport_profiles.0;
        let profile_complete = profile_is_complete(&sport_profiles, u.primary_sport.as_deref());
        Self {
            id: u.id,
            name: u.name,
            email: u.email,
            phone: u.phone,
            avatar_url: u.avatar_url,
            sports_played: u.sports_played,
            position_role: u.position_role,
            skill_level: u.skill_level,
            emergency_contact: u.emergency_contact,
            primary_sport: u.primary_sport,
            sport_profiles,
            location: u.location.map(|l| l.0),
            profile_complete,
            email_verified: u.email_verified_at.is_some(),
            phone_verified: u.phone_verified_at.is_some(),
            role_intent: u.role_intent,
            profile_strength,
            reliability: None,
            // Never from the row. The API sets it on /me and nowhere else, so
            // forgetting to set it denies rather than grants.
            platform_admin: false,
        }
    }
}

/// How much of a profile is filled in.
///
/// Nothing here is needed to play — a name and a sport get somebody picked.
/// The rest is what makes a player someone a captain recognises, so it is
/// counted and asked for, never demanded. The iPhone app counts with the same
/// weights, so "35% complete" means the same thing on both.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProfileStrength {
    pub percent: u8,
    /// What is not filled in yet, the most valuable first.
    pub missing: Vec<String>,
    /// "Add a photo, the standard you play at and your position" — empty when
    /// there is nothing left to add.
    pub next_up: String,
}

impl ProfileStrength {
    pub fn of(u: &User) -> Self {
        let filled = |v: &Option<String>| v.as_deref().is_some_and(|s| !s.trim().is_empty());
        let profiles = &u.sport_profiles.0;
        let main = u
            .primary_sport
            .as_deref()
            .and_then(|sport| profiles.iter().find(|p| p.sport == sport))
            .or_else(|| profiles.first());
        let location = u.location.as_ref().map(|l| &l.0);
        // (key, words, weight, done) — the weights add up to 100.
        let items = [
            ("name", "your name", 10, !u.name.trim().is_empty()),
            ("sport", "what you play", 15, main.is_some()),
            ("phone", "your mobile number", 10, filled(&u.phone)),
            ("photo", "a photo", 15, filled(&u.avatar_url)),
            ("standard", "the standard you play at", 15, main.is_some_and(SportProfile::is_complete)),
            ("position", "your position", 10, main.is_some_and(|p| filled(&p.position))),
            ("verified", "a confirmed email or number", 10,
             u.email_verified_at.is_some() || u.phone_verified_at.is_some()),
            ("area", "where you're based", 5,
             location.is_some_and(|l| filled(&l.area) || filled(&l.postcode))),
            ("travel", "how you get to games", 5, location.is_some_and(|l| l.transport.is_some())),
            ("emergency", "an emergency contact", 5, filled(&u.emergency_contact)),
        ];
        let mut missing: Vec<_> = items.iter().filter(|i| !i.3).collect();
        // Stable, so equal weights keep the order above.
        missing.sort_by_key(|i| std::cmp::Reverse(i.2));
        let words: Vec<&str> = missing.iter().take(3).map(|i| i.1).collect();
        let next_up = match words.as_slice() {
            [] => String::new(),
            [one] => format!("Add {one}"),
            [rest @ .., last] => format!("Add {} and {last}", rest.join(", ")),
        };
        Self {
            percent: items.iter().filter(|i| i.3).map(|i| i.2).sum(),
            missing: missing.iter().map(|i| i.0.to_string()).collect(),
            next_up,
        }
    }

    pub fn is_complete(&self) -> bool {
        self.percent >= 100
    }
}

impl PublicUser {
    /// Routes call this after loading the player's attendance counters.
    pub fn with_reliability(mut self, reliability: ReliabilityScore) -> Self {
        self.reliability = Some(reliability);
        self
    }
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct SignupRequest {
    #[validate(length(min = 1, max = 120))]
    pub name: String,
    /// One of these two is required — the API says which is missing rather
    /// than insisting on an address somebody may not have.
    #[validate(email)]
    pub email: Option<String>,
    pub phone: Option<String>,
    #[validate(length(min = 8, max = 128))]
    pub password: String,
}

impl SignupRequest {
    /// The email or the phone, whichever they gave, trimmed.
    pub fn identifiers(&self) -> (Option<String>, Option<String>) {
        let clean = |v: &Option<String>| {
            v.as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
        };
        (clean(&self.email), clean(&self.phone))
    }
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct LoginRequest {
    /// An email or a mobile number. `email` is still accepted so anything
    /// already pointed at this endpoint keeps working.
    #[serde(alias = "email")]
    #[validate(length(min = 1))]
    pub identifier: String,
    #[validate(length(min = 1))]
    pub password: String,
}

#[derive(Default, Debug, Clone, Deserialize, Validate)]
pub struct UpdateProfileRequest {
    #[validate(length(min = 1, max = 120))]
    pub name: Option<String>,
    pub phone: Option<String>,
    pub avatar_url: Option<String>,
    pub sports_played: Option<Vec<String>>,
    pub position_role: Option<String>,
    pub skill_level: Option<String>,
    pub emergency_contact: Option<String>,
    pub primary_sport: Option<String>,
    /// Sent whole: the client always submits every sport it holds.
    pub sport_profiles: Option<Vec<SportProfile>>,
    pub location: Option<PlayerLocation>,
    /// "secretary" or "player". Anything else is refused.
    #[validate(custom(function = "validate_role_intent"))]
    pub role_intent: Option<String>,
}

fn validate_role_intent(v: &str) -> Result<(), validator::ValidationError> {
    match v {
        "secretary" | "player" => Ok(()),
        _ => Err(validator::ValidationError::new("role_intent must be secretary or player")),
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct AuthTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: i64,
    pub user: PublicUser,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[cfg(test)]
mod strength_tests {
    use super::*;

    fn user() -> User {
        User {
            id: Uuid::nil(),
            name: "Pat Player".into(),
            email: Some("pat@x.test".into()),
            phone: None,
            apple_id: None,
            avatar_url: None,
            sports_played: vec![],
            position_role: None,
            skill_level: None,
            emergency_contact: None,
            primary_sport: None,
            sport_profiles: Json(vec![]),
            location: None,
            profile_completed_at: None,
            email_verified_at: None,
            phone_verified_at: None,
            role_intent: None,
            profile_share_token: None,
            password_hash: None,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    #[test]
    fn a_new_account_has_its_name_and_little_else() {
        let s = ProfileStrength::of(&user());
        assert_eq!(s.percent, 10);
        assert_eq!(s.next_up, "Add what you play, a photo and the standard you play at");
        assert_eq!(s.missing[0], "sport");
    }

    #[test]
    fn the_quick_start_is_a_third_of_the_way() {
        let mut u = user();
        u.phone = Some("07700900123".into());
        u.primary_sport = Some("cricket".into());
        u.sport_profiles = Json(vec![SportProfile { sport: "cricket".into(), ..Default::default() }]);
        let s = ProfileStrength::of(&u);
        assert_eq!(s.percent, 35);
        assert_eq!(s.next_up, "Add a photo, the standard you play at and your position");
    }

    #[test]
    fn everything_filled_in_is_complete() {
        let mut u = user();
        u.phone = Some("07700900123".into());
        u.avatar_url = Some("https://x/p.jpg".into());
        u.emergency_contact = Some("Mum".into());
        u.email_verified_at = Some(Utc::now());
        u.primary_sport = Some("cricket".into());
        u.sport_profiles = Json(vec![SportProfile {
            sport: "cricket".into(),
            skill_level: Some("Club".into()),
            position: Some("Batter".into()),
            ..Default::default()
        }]);
        u.location = Some(Json(PlayerLocation {
            area: Some("Hemel".into()),
            transport: Some("driver".into()),
            ..Default::default()
        }));
        let s = ProfileStrength::of(&u);
        assert!(s.is_complete());
        assert!(s.missing.is_empty());
        assert_eq!(s.next_up, "");
    }
}
