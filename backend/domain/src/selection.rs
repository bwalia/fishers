//! Squad selection: who is in, who is on standby, and who is owed a game.
//!
//! The ranking here is deliberately deterministic and explainable — a captain
//! can see exactly why a player is ahead of another, it works with no API key,
//! and it is what the assistant is handed as its starting point.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::enums::AvailabilityStatus;

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

    pub fn from_str(raw: &str) -> Option<Self> {
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
    pub availability: Option<AvailabilityStatus>,
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
