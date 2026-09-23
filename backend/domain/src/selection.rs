//! Squad selection: who is in, who is on standby, and who is owed a game.
//!
//! The ranking here is deliberately deterministic and explainable — a captain
//! can see exactly why a player is ahead of another, it works with no API key,
//! and it is what the assistant is handed as its starting point.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::enums::AvailabilityStatus;
use crate::enums::RsvpStatus;

/// Where a player sits in the selection for one fixture.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SelectionState {
    /// Eligible and not yet decided.
    Pool,
    Selected,
    Reserve,
    NotSelected,
    /// Selected and has since confirmed they are playing.
    Confirmed,
    Declined,
    /// Selected, never confirmed, dropped at the deadline.
    Dropped,
}

impl SelectionState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pool => "pool",
            Self::Selected => "selected",
            Self::Reserve => "reserve",
            Self::NotSelected => "not_selected",
            Self::Confirmed => "confirmed",
            Self::Declined => "declined",
            Self::Dropped => "dropped",
        }
    }

    /// The inverse of `as_str`. Not `FromStr`: an unrecognised string is
    /// not an error worth a type, it is simply not one of these.
    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "pool" => Some(Self::Pool),
            "selected" => Some(Self::Selected),
            "reserve" => Some(Self::Reserve),
            "not_selected" => Some(Self::NotSelected),
            "confirmed" => Some(Self::Confirmed),
            "declined" => Some(Self::Declined),
            "dropped" => Some(Self::Dropped),
            _ => None,
        }
    }

    /// Counts towards the eleven.
    pub fn is_in_squad(&self) -> bool {
        matches!(self, Self::Selected | Self::Confirmed)
    }
}

/// One eligible player, with the signals selection weighs.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Candidate {
    pub user_id: Uuid,
    pub name: String,
    pub position: Option<String>,
    pub skill_level: Option<String>,
    /// Their general calendar for that date, if they keep one.
    pub availability: Option<AvailabilityStatus>,
    /// Their answer to *this* fixture — "can you play on Sunday?". The direct
    /// answer, and the one a captain picks off; the calendar above is a
    /// weaker, standing signal.
    pub rsvp: Option<RsvpStatus>,
    pub reliability_score: i64,
    pub reliability_band: String,
    /// Fixtures they were available for but left out of, last 60 days.
    pub games_missed_out: i64,
    pub state: SelectionState,
    pub is_confirmed: bool,
}

/// What the side needs. `position_quotas` is advisory: quotas are filled first,
/// then the rest of the places go to the best remaining players.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SquadRequirements {
    pub size: usize,
    pub reserves: usize,
    pub position_quotas: Vec<PositionQuota>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PositionQuota {
    pub position: String,
    pub minimum: usize,
}

impl SquadRequirements {
    /// Sensible defaults per sport, used when a fixture has no capacity set.
    pub fn for_sport(sport: &str, capacity: Option<i32>) -> Self {
        let (default_size, quotas) = match sport.to_lowercase().as_str() {
            "cricket" => (
                11,
                vec![
                    PositionQuota { position: "Wicketkeeper".into(), minimum: 1 },
                    PositionQuota { position: "Fast Bowler".into(), minimum: 2 },
                    PositionQuota { position: "Spinner".into(), minimum: 1 },
                ],
            ),
            "football" => (
                11,
                vec![
                    PositionQuota { position: "Goalkeeper".into(), minimum: 1 },
                    PositionQuota { position: "Defender".into(), minimum: 3 },
                    PositionQuota { position: "Midfielder".into(), minimum: 3 },
                    PositionQuota { position: "Forward".into(), minimum: 1 },
                ],
            ),
            "rugby" => (15, Vec::new()),
            "hockey" => (11, vec![PositionQuota { position: "Goalkeeper".into(), minimum: 1 }]),
            "netball" => (7, Vec::new()),
            "basketball" => (5, Vec::new()),
            "badminton" | "padel" | "tennis" => (4, Vec::new()),
            _ => (11, Vec::new()),
        };
        Self {
            size: capacity.map(|c| c.max(1) as usize).unwrap_or(default_size),
            reserves: 3,
            position_quotas: quotas,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RankedCandidate {
    pub user_id: Uuid,
    pub name: String,
    pub score: i64,
    /// Plain-English reasons, in the order they were applied.
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct SquadSuggestion {
    pub selected: Vec<RankedCandidate>,
    pub reserves: Vec<RankedCandidate>,
    pub ranked_out: Vec<RankedCandidate>,
    /// Quotas the available pool could not satisfy — worth telling the captain.
    pub unmet_quotas: Vec<String>,
}

/// What a captain's selection screen needs in one call.
#[derive(Debug, Clone, Serialize)]
pub struct SelectionBoard {
    pub event_id: Uuid,
    pub title: String,
    pub sport: String,
    pub starts_at: chrono::DateTime<chrono::Utc>,
    pub status: String,
    pub status_note: Option<String>,
    pub requirements: SquadRequirements,
    /// `off` | `suggest` | `auto_publish`
    pub autonomy: String,
    pub confirm_lead_hours: i32,
    pub drop_lead_hours: i32,
    pub candidates: Vec<Candidate>,
    /// Deterministic order, so the screen can show "why" per player.
    pub ranked: Vec<RankedCandidate>,
    pub selected_count: usize,
    pub confirmed_count: usize,
}

/// A proposed squad awaiting a captain's publish, from either the ranking or
/// the assistant.
#[derive(Debug, Clone, Serialize)]
pub struct SquadProposalView {
    /// `ranking` when the deterministic model produced it, `assistant` when the
    /// model did.
    pub source: String,
    pub selected: Vec<RankedCandidate>,
    pub reserves: Vec<RankedCandidate>,
    pub unmet_quotas: Vec<String>,
    pub announcement: Option<String>,
    pub concerns: Option<String>,
    pub confidence: Option<String>,
    /// True when club policy had it published immediately.
    pub published: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SetSquadRequest {
    #[serde(default)]
    pub selected: Vec<Uuid>,
    #[serde(default)]
    pub reserves: Vec<Uuid>,
    /// Posted to the thread when publishing; a default is written if omitted.
    pub announcement: Option<String>,
    /// Announce straight away rather than leaving it as a draft squad.
    #[serde(default)]
    pub publish: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RespondToSelectionRequest {
    pub confirming: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FixtureStatusRequest {
    /// `scheduled` | `postponed` | `cancelled` | `completed`
    pub status: String,
    /// "Called off — ground unplayable after Friday's rain."
    pub note: Option<String>,
    pub rescheduled_to: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Clone, Deserialize, validator::Validate)]
pub struct CreateFixtureBlockRequest {
    #[validate(length(min = 1, max = 120))]
    pub name: String,
    pub club_id: Uuid,
    pub team_id: Option<Uuid>,
    /// `block` | `tour` | `tournament` | `season`
    pub kind: Option<String>,
    pub starts_on: Option<chrono::NaiveDate>,
    pub ends_on: Option<chrono::NaiveDate>,
    /// Existing fixtures to pull into the block.
    #[serde(default)]
    pub event_ids: Vec<Uuid>,
    /// Everything a tournament settles up front. Optional so creating a plain
    /// block of fixtures stays one name and two dates.
    #[serde(flatten, default)]
    pub settings: TournamentSettings,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct FixtureBlock {
    pub id: Uuid,
    pub club_id: Uuid,
    pub team_id: Option<Uuid>,
    pub name: String,
    pub kind: String,
    pub starts_on: Option<chrono::NaiveDate>,
    pub ends_on: Option<chrono::NaiveDate>,
    pub created_at: chrono::DateTime<chrono::Utc>,

    // MARK: what a tournament has to settle before anybody enters
    /// The organiser's own description, shown to a club deciding whether to enter.
    pub description: Option<String>,
    /// The main ground. Individual pitches hang off `tournament_slots`, which
    /// is how a tournament runs across more than one.
    pub venue_id: Option<Uuid>,
    /// How many sides fit. `None` is no limit.
    pub max_entrants: Option<i32>,
    pub entry_deadline: Option<chrono::DateTime<chrono::Utc>>,
    /// What a side pays to enter — not a spectator's ticket, and not the match
    /// fee a player owes for being picked.
    pub entry_fee_cents: Option<i32>,
    /// Eleven normally; six for sixes, eight for eights.
    pub players_per_side: i32,
    /// 0 means every player must belong to the entering club. This is the rule
    /// clubs argue about on the day when nobody wrote it down.
    pub guest_players_allowed: i32,
    /// `open` | `u11` | `u13` | `u15` | `u17` | `u19` | `veterans`
    pub age_group: String,
    /// `open` | `men` | `women` | `mixed`
    pub gender: String,
    /// Overs, overs per bowler, ball, ground, powerplay — the same terms two
    /// captains agree before a one-off match. Set once here and every fixture
    /// in the tournament inherits it. `None` means the sport's default.
    // `nullable`, not a bare `json`: every block that existed before a
    // tournament could carry conditions has NULL here, and a bare `json`
    // decodes that as a hard error rather than as `None`.
    #[sqlx(json(nullable))]
    pub conditions: Option<crate::MatchConditions>,
    /// Everything a form cannot hold: last-over rules, ties, boundary counts.
    pub rules_notes: Option<String>,
}

/// The tournament settings an organiser can change after it is created.
///
/// Every field optional and every one applied only when present, so a screen
/// that edits the entry rules cannot wipe the playing conditions.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct TournamentSettings {
    pub description: Option<String>,
    pub venue_id: Option<Uuid>,
    pub max_entrants: Option<i32>,
    pub entry_deadline: Option<chrono::DateTime<chrono::Utc>>,
    pub entry_fee_cents: Option<i32>,
    pub players_per_side: Option<i32>,
    pub guest_players_allowed: Option<i32>,
    pub age_group: Option<String>,
    pub gender: Option<String>,
    pub conditions: Option<crate::MatchConditions>,
    pub rules_notes: Option<String>,
    /// Settings to unset, by name — `["max_entrants", "entry_deadline"]`.
    ///
    /// A missing field and a field set to null look identical over JSON, and
    /// every other field here is "leave it alone if you did not send it". That
    /// makes a cap impossible to remove once set, which is what the form
    /// offering "leave empty for no limit" promises. Naming them is explicit,
    /// and avoids every field becoming a double option.
    #[serde(default)]
    pub clear: Vec<String>,
}

pub const AGE_GROUPS: [&str; 7] = ["open", "u11", "u13", "u15", "u17", "u19", "veterans"];
pub const GENDERS: [&str; 4] = ["open", "men", "women", "mixed"];

impl TournamentSettings {
    /// What is wrong with these settings, in the organiser's words. `None` when
    /// they are usable.
    ///
    /// The database has the same constraints; this exists so the answer is a
    /// sentence rather than a constraint violation.
    /// Settings that may be unset. The rest have a value at all times — a side
    /// is always some number of players — so clearing them means nothing.
    pub const CLEARABLE: [&'static str; 7] = [
        "description",
        "venue_id",
        "max_entrants",
        "entry_deadline",
        "entry_fee_cents",
        "conditions",
        "rules_notes",
    ];

    pub fn problem(&self) -> Option<String> {
        if let Some(unknown) = self
            .clear
            .iter()
            .find(|name| !Self::CLEARABLE.contains(&name.as_str()))
        {
            return Some(format!("{unknown} is not something that can be cleared"));
        }
        if self.max_entrants.is_some_and(|n| n < 2) {
            return Some("a tournament needs room for at least two sides".into());
        }
        if self.entry_fee_cents.is_some_and(|c| c < 0) {
            return Some("an entry fee cannot be negative".into());
        }
        if self.players_per_side.is_some_and(|n| !(2..=15).contains(&n)) {
            return Some("a side is between 2 and 15 players".into());
        }
        if self.guest_players_allowed.is_some_and(|n| !(0..=11).contains(&n)) {
            return Some("guest players must be between 0 and 11".into());
        }
        if let (Some(side), Some(guests)) = (self.players_per_side, self.guest_players_allowed) {
            if guests > side {
                return Some("a side cannot be more guests than players".into());
            }
        }
        if let Some(age) = self.age_group.as_deref() {
            if !AGE_GROUPS.contains(&age) {
                return Some(format!("{age} is not an age group"));
            }
        }
        if let Some(gender) = self.gender.as_deref() {
            if !GENDERS.contains(&gender) {
                return Some(format!("{gender} is not one of the options"));
            }
        }
        if let Some(c) = &self.conditions {
            if c.overs_limit == 0 {
                return Some("an innings needs at least one over".into());
            }
            if c.overs_per_bowler > c.overs_limit {
                return Some("a bowler cannot be allowed more overs than the innings has".into());
            }
        }
        None
    }
}

/// Weights. Availability dominates: picking someone who said no wastes the slot.
const AVAILABLE_POINTS: i64 = 1_000;
const MAYBE_POINTS: i64 = 400;
const UNKNOWN_POINTS: i64 = 200;
/// Each fixture missed out on is worth this much, so rotation self-corrects.
const ROTATION_POINTS: i64 = 40;
const ROTATION_CAP: i64 = 6;
const CONFIRMED_POINTS: i64 = 150;

fn availability_points(status: Option<AvailabilityStatus>) -> Option<(i64, &'static str)> {
    match status {
        Some(AvailabilityStatus::Available) => Some((AVAILABLE_POINTS, "said available")),
        Some(AvailabilityStatus::Maybe) => Some((MAYBE_POINTS, "said maybe")),
        Some(AvailabilityStatus::Unavailable) => None,
        None => Some((UNKNOWN_POINTS, "no availability marked")),
    }
}

/// Score every candidate who hasn't ruled themselves out, best first.
pub fn rank(candidates: &[Candidate]) -> Vec<RankedCandidate> {
    let mut ranked: Vec<RankedCandidate> = candidates
        .iter()
        .filter_map(|c| {
            let (mut score, availability_reason) = availability_points(c.availability)?;
            let mut reasons = vec![availability_reason.to_string()];

            if c.is_confirmed {
                score += CONFIRMED_POINTS;
                reasons.push("already confirmed".into());
            }

            score += c.reliability_score;
            reasons.push(format!("reliability {} ({})", c.reliability_score, c.reliability_band));

            let debt = c.games_missed_out.clamp(-ROTATION_CAP, ROTATION_CAP);
            if debt != 0 {
                score += debt * ROTATION_POINTS;
                if debt > 0 {
                    reasons.push(format!(
                        "missed out on {} game{}",
                        debt,
                        if debt == 1 { "" } else { "s" }
                    ));
                } else {
                    reasons.push("already played earlier in this block".into());
                }
            }

            Some(RankedCandidate {
                user_id: c.user_id,
                name: c.name.clone(),
                score,
                reasons,
            })
        })
        .collect();

    // Name breaks ties so the same pool always produces the same squad.
    ranked.sort_by(|a, b| b.score.cmp(&a.score).then_with(|| a.name.cmp(&b.name)));
    ranked
}

/// Fill the position quotas first, then the remaining places by score.
pub fn suggest(candidates: &[Candidate], requirements: &SquadRequirements) -> SquadSuggestion {
    let ranked = rank(candidates);
    let position_of = |user_id: Uuid| {
        candidates
            .iter()
            .find(|c| c.user_id == user_id)
            .and_then(|c| c.position.clone())
    };

    let mut selected: Vec<RankedCandidate> = Vec::new();
    let mut unmet_quotas: Vec<String> = Vec::new();

    for quota in &requirements.position_quotas {
        let already = selected
            .iter()
            .filter(|r| position_of(r.user_id).as_deref() == Some(quota.position.as_str()))
            .count();
        let mut taken = already;
        for candidate in &ranked {
            if taken >= quota.minimum || selected.len() >= requirements.size {
                break;
            }
            if selected.iter().any(|s| s.user_id == candidate.user_id) {
                continue;
            }
            if position_of(candidate.user_id).as_deref() == Some(quota.position.as_str()) {
                let mut picked = candidate.clone();
                picked.reasons.push(format!("fills the {} slot", quota.position.to_lowercase()));
                selected.push(picked);
                taken += 1;
            }
        }
        if taken < quota.minimum {
            unmet_quotas.push(format!(
                "{} short of {} {}",
                quota.minimum - taken,
                quota.minimum,
                quota.position
            ));
        }
    }

    for candidate in &ranked {
        if selected.len() >= requirements.size {
            break;
        }
        if selected.iter().any(|s| s.user_id == candidate.user_id) {
            continue;
        }
        selected.push(candidate.clone());
    }

    // Keep the published order by merit, not by which quota pass found them.
    selected.sort_by(|a, b| b.score.cmp(&a.score).then_with(|| a.name.cmp(&b.name)));

    let remaining: Vec<RankedCandidate> = ranked
        .into_iter()
        .filter(|r| !selected.iter().any(|s| s.user_id == r.user_id))
        .collect();
    let reserves: Vec<RankedCandidate> =
        remaining.iter().take(requirements.reserves).cloned().collect();
    let ranked_out = remaining.into_iter().skip(requirements.reserves).collect();

    SquadSuggestion {
        selected,
        reserves,
        ranked_out,
        unmet_quotas,
    }
}

/// One fixture inside a block, with its own pool and requirements.
#[derive(Debug, Clone)]
pub struct BlockFixture {
    pub event_id: Uuid,
    pub candidates: Vec<Candidate>,
    pub requirements: SquadRequirements,
}

#[derive(Debug, Clone, Serialize)]
pub struct BlockSquad {
    pub event_id: Uuid,
    pub selected: Vec<RankedCandidate>,
    pub reserves: Vec<RankedCandidate>,
    pub unmet_quotas: Vec<String>,
}

/// Every place already taken inside the block costs a player this much, so a
/// tour or tournament spreads the games instead of playing the same eleven.
const BLOCK_APPEARANCE_PENALTY: i64 = 120;

/// Pick squads across a whole block — a tour, a tournament, or the next few
/// weeks — rotating so nobody sits out the entire thing. Fixtures are decided
/// in the order given, each one aware of who has already been picked.
pub fn suggest_block(fixtures: &[BlockFixture]) -> Vec<BlockSquad> {
    let mut appearances: std::collections::HashMap<Uuid, i64> = std::collections::HashMap::new();
    let mut squads = Vec::with_capacity(fixtures.len());

    for fixture in fixtures {
        // Spend the block's appearances as rotation debt in reverse: a player
        // already picked twice drops behind someone still waiting for a game.
        let adjusted: Vec<Candidate> = fixture
            .candidates
            .iter()
            .cloned()
            .map(|mut candidate| {
                let played = appearances.get(&candidate.user_id).copied().unwrap_or(0);
                let cost = played * BLOCK_APPEARANCE_PENALTY / ROTATION_POINTS;
                candidate.games_missed_out = (candidate.games_missed_out - cost).max(-ROTATION_CAP);
                candidate
            })
            .collect();

        let suggestion = suggest(&adjusted, &fixture.requirements);
        for picked in &suggestion.selected {
            *appearances.entry(picked.user_id).or_insert(0) += 1;
        }
        squads.push(BlockSquad {
            event_id: fixture.event_id,
            selected: suggestion.selected,
            reserves: suggestion.reserves,
            unmet_quotas: suggestion.unmet_quotas,
        });
    }

    squads
}

#[cfg(test)]
mod tests {
    use super::*;

    fn candidate(name: &str, availability: Option<AvailabilityStatus>) -> Candidate {
        Candidate {
            user_id: Uuid::new_v4(),
            name: name.into(),
            position: None,
            skill_level: None,
            availability,
            // These tests weigh the standing calendar; the fixture answer is
            // exercised where selection is read, not where it is ranked.
            rsvp: None,
            reliability_score: 70,
            reliability_band: "dependable".into(),
            games_missed_out: 0,
            state: SelectionState::Pool,
            is_confirmed: false,
        }
    }

    fn requirements(size: usize) -> SquadRequirements {
        SquadRequirements { size, reserves: 2, position_quotas: Vec::new() }
    }

    #[test]
    fn unavailable_players_are_never_ranked() {
        let pool = vec![
            candidate("Available Alice", Some(AvailabilityStatus::Available)),
            candidate("Busy Bob", Some(AvailabilityStatus::Unavailable)),
        ];
        let ranked = rank(&pool);
        assert_eq!(ranked.len(), 1);
        assert_eq!(ranked[0].name, "Available Alice");
    }

    #[test]
    fn availability_outranks_reliability() {
        let mut flaky_but_free = candidate("Free Fran", Some(AvailabilityStatus::Available));
        flaky_but_free.reliability_score = 20;
        let mut solid_but_maybe = candidate("Maybe Mo", Some(AvailabilityStatus::Maybe));
        solid_but_maybe.reliability_score = 100;

        let ranked = rank(&[solid_but_maybe, flaky_but_free]);
        assert_eq!(ranked[0].name, "Free Fran");
    }

    #[test]
    fn rotation_debt_breaks_a_tie() {
        let steady = candidate("Regular Rita", Some(AvailabilityStatus::Available));
        let mut overlooked = candidate("Overlooked Omar", Some(AvailabilityStatus::Available));
        overlooked.games_missed_out = 3;

        let ranked = rank(&[steady, overlooked]);
        assert_eq!(ranked[0].name, "Overlooked Omar");
        assert!(ranked[0].reasons.iter().any(|r| r.contains("missed out on 3 games")));
    }

    #[test]
    fn rotation_debt_cannot_swamp_availability() {
        let mut long_overlooked = candidate("Omar", Some(AvailabilityStatus::Maybe));
        long_overlooked.games_missed_out = 40;
        let free = candidate("Alice", Some(AvailabilityStatus::Available));

        let ranked = rank(&[long_overlooked, free]);
        assert_eq!(ranked[0].name, "Alice", "an available player still comes first");
    }

    #[test]
    fn confirmed_players_stay_in_the_side() {
        let mut confirmed = candidate("Confirmed Cara", Some(AvailabilityStatus::Available));
        confirmed.is_confirmed = true;
        confirmed.reliability_score = 60;
        let unconfirmed = candidate("Unconfirmed Ulf", Some(AvailabilityStatus::Available));

        let ranked = rank(&[unconfirmed, confirmed]);
        assert_eq!(ranked[0].name, "Confirmed Cara");
    }

    #[test]
    fn squad_respects_size_and_names_reserves() {
        let pool: Vec<Candidate> = (0..8)
            .map(|i| candidate(&format!("Player {i}"), Some(AvailabilityStatus::Available)))
            .collect();
        let suggestion = suggest(&pool, &requirements(5));
        assert_eq!(suggestion.selected.len(), 5);
        assert_eq!(suggestion.reserves.len(), 2);
        assert_eq!(suggestion.ranked_out.len(), 1);
    }

    #[test]
    fn quota_pulls_in_a_keeper_over_a_better_batter() {
        let mut keeper = candidate("Keeper Kim", Some(AvailabilityStatus::Available));
        keeper.position = Some("Wicketkeeper".into());
        keeper.reliability_score = 10; // would not make it on merit alone

        let mut pool: Vec<Candidate> = (0..3)
            .map(|i| {
                let mut c = candidate(&format!("Batter {i}"), Some(AvailabilityStatus::Available));
                c.position = Some("Batter".into());
                c.reliability_score = 95;
                c
            })
            .collect();
        pool.push(keeper);

        let requirements = SquadRequirements {
            size: 3,
            reserves: 1,
            position_quotas: vec![PositionQuota { position: "Wicketkeeper".into(), minimum: 1 }],
        };
        let suggestion = suggest(&pool, &requirements);
        assert!(suggestion.selected.iter().any(|s| s.name == "Keeper Kim"));
        assert_eq!(suggestion.selected.len(), 3);
        assert!(suggestion.unmet_quotas.is_empty());
    }

    #[test]
    fn unmet_quota_is_reported_rather_than_hidden() {
        let pool: Vec<Candidate> = (0..4)
            .map(|i| candidate(&format!("Player {i}"), Some(AvailabilityStatus::Available)))
            .collect();
        let requirements = SquadRequirements {
            size: 4,
            reserves: 0,
            position_quotas: vec![PositionQuota { position: "Goalkeeper".into(), minimum: 1 }],
        };
        let suggestion = suggest(&pool, &requirements);
        assert_eq!(suggestion.unmet_quotas.len(), 1);
        assert!(suggestion.unmet_quotas[0].contains("Goalkeeper"));
    }

    #[test]
    fn selection_is_stable_for_the_same_pool() {
        let pool: Vec<Candidate> = (0..6)
            .map(|i| candidate(&format!("Player {i}"), Some(AvailabilityStatus::Available)))
            .collect();
        let first = suggest(&pool, &requirements(4));
        let second = suggest(&pool, &requirements(4));
        assert_eq!(
            first.selected.iter().map(|s| s.user_id).collect::<Vec<_>>(),
            second.selected.iter().map(|s| s.user_id).collect::<Vec<_>>()
        );
    }

    #[test]
    fn cricket_defaults_pick_eleven_with_a_keeper_quota() {
        let requirements = SquadRequirements::for_sport("cricket", None);
        assert_eq!(requirements.size, 11);
        assert!(requirements
            .position_quotas
            .iter()
            .any(|q| q.position == "Wicketkeeper"));
    }

    #[test]
    fn a_block_spreads_games_instead_of_playing_the_same_side() {
        let pool: Vec<Candidate> = (0..6)
            .map(|i| candidate(&format!("Player {i}"), Some(AvailabilityStatus::Available)))
            .collect();
        let fixtures: Vec<BlockFixture> = (0..3)
            .map(|_| BlockFixture {
                event_id: Uuid::new_v4(),
                candidates: pool.clone(),
                requirements: SquadRequirements { size: 3, reserves: 1, position_quotas: Vec::new() },
            })
            .collect();

        let squads = suggest_block(&fixtures);
        assert_eq!(squads.len(), 3);

        let mut appearances: std::collections::HashMap<Uuid, usize> = Default::default();
        for squad in &squads {
            for picked in &squad.selected {
                *appearances.entry(picked.user_id).or_insert(0) += 1;
            }
        }
        // Nine places across six available players: everyone gets a game.
        assert_eq!(appearances.len(), 6, "every available player featured");
        let most = appearances.values().max().copied().unwrap_or(0);
        let least = appearances.values().min().copied().unwrap_or(0);
        assert!(most - least <= 1, "games spread evenly, got {most} vs {least}");
    }

    #[test]
    fn a_block_still_puts_availability_first() {
        let mut pool: Vec<Candidate> = (0..3)
            .map(|i| candidate(&format!("Player {i}"), Some(AvailabilityStatus::Available)))
            .collect();
        pool.push(candidate("Busy Bob", Some(AvailabilityStatus::Unavailable)));

        let fixtures: Vec<BlockFixture> = (0..2)
            .map(|_| BlockFixture {
                event_id: Uuid::new_v4(),
                candidates: pool.clone(),
                requirements: SquadRequirements { size: 2, reserves: 0, position_quotas: Vec::new() },
            })
            .collect();

        for squad in suggest_block(&fixtures) {
            assert!(
                !squad.selected.iter().any(|s| s.name == "Busy Bob"),
                "an unavailable player is never picked, however short of games they are"
            );
        }
    }

    #[test]
    fn capacity_overrides_the_sport_default() {
        let requirements = SquadRequirements::for_sport("cricket", Some(8));
        assert_eq!(requirements.size, 8);
    }
}

#[cfg(test)]
mod settings_tests {
    use super::*;
    use crate::MatchConditions;

    fn ok(s: TournamentSettings) {
        assert_eq!(s.problem(), None, "expected these settings to be usable");
    }

    fn refuses(s: TournamentSettings, because: &str) {
        let problem = s.problem().expect("expected these settings to be refused");
        assert!(
            problem.contains(because),
            "refused for the wrong reason: {problem:?} does not mention {because:?}"
        );
    }

    #[test]
    fn empty_settings_are_fine() {
        // Creating a plain block of fixtures sets none of this.
        ok(TournamentSettings::default());
    }

    #[test]
    fn a_tournament_needs_room_for_two() {
        refuses(
            TournamentSettings { max_entrants: Some(1), ..Default::default() },
            "at least two",
        );
        ok(TournamentSettings { max_entrants: Some(2), ..Default::default() });
    }

    #[test]
    fn a_side_is_a_believable_number_of_players() {
        ok(TournamentSettings { players_per_side: Some(6), ..Default::default() });
        ok(TournamentSettings { players_per_side: Some(11), ..Default::default() });
        refuses(
            TournamentSettings { players_per_side: Some(1), ..Default::default() },
            "between 2 and 15",
        );
        refuses(
            TournamentSettings { players_per_side: Some(16), ..Default::default() },
            "between 2 and 15",
        );
    }

    #[test]
    fn a_side_cannot_be_more_guests_than_players() {
        ok(TournamentSettings {
            players_per_side: Some(11),
            guest_players_allowed: Some(2),
            ..Default::default()
        });
        refuses(
            TournamentSettings {
                players_per_side: Some(6),
                guest_players_allowed: Some(8),
                ..Default::default()
            },
            "more guests than players",
        );
    }

    #[test]
    fn the_age_group_and_gender_come_from_the_lists() {
        ok(TournamentSettings { age_group: Some("u15".into()), ..Default::default() });
        ok(TournamentSettings { gender: Some("women".into()), ..Default::default() });
        refuses(
            TournamentSettings { age_group: Some("u14".into()), ..Default::default() },
            "not an age group",
        );
        refuses(
            TournamentSettings { gender: Some("anything".into()), ..Default::default() },
            "not one of the options",
        );
    }

    #[test]
    fn a_bowler_cannot_be_allowed_more_overs_than_the_innings_has() {
        ok(TournamentSettings {
            conditions: Some(MatchConditions::standard(20)),
            ..Default::default()
        });
        refuses(
            TournamentSettings {
                conditions: Some(MatchConditions {
                    overs_limit: 6,
                    overs_per_bowler: 10,
                    ..MatchConditions::standard(6)
                }),
                ..Default::default()
            },
            "more overs than the innings has",
        );
    }

    #[test]
    fn an_innings_needs_an_over() {
        refuses(
            TournamentSettings {
                conditions: Some(MatchConditions {
                    overs_limit: 0,
                    ..MatchConditions::standard(20)
                }),
                ..Default::default()
            },
            "at least one over",
        );
    }

    #[test]
    fn an_entry_fee_cannot_be_negative() {
        ok(TournamentSettings { entry_fee_cents: Some(0), ..Default::default() });
        refuses(
            TournamentSettings { entry_fee_cents: Some(-1), ..Default::default() },
            "cannot be negative",
        );
    }
}
