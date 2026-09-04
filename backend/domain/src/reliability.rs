//! Reliability scoring — "will this player actually turn up?".
//!
//! Captains weigh the score alongside skill when picking a squad, so the
//! weighting is deliberately simple and explainable to the player:
//! turning up is half of it, answering invites and paying fees a quarter each,
//! and every late drop-out costs five points.

use serde::{Deserialize, Serialize};

/// Below this many past invites there isn't enough evidence to judge anyone.
pub const MINIMUM_SAMPLE: i64 = 3;

const LATE_CANCELLATION_PENALTY: i64 = 5;

/// Raw counters, straight off the `player_reliability_counts` view.
#[derive(Debug, Clone, Copy, Default, sqlx::FromRow)]
pub struct ReliabilityCounts {
    pub invites_received: i64,
    pub responded: i64,
    pub said_going: i64,
    pub turned_up: i64,
    pub late_cancellations: i64,
    pub fees_due: i64,
    pub fees_paid: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReliabilityBand {
    Unproven,
    Patchy,
    Dependable,
    RockSolid,
}

/// What the API returns on a user: the score plus the parts it is made of, so
/// the app can show a player exactly why they sit where they do.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct ReliabilityScore {
    pub score: i64,
    pub attendance_rate: f64,
    pub response_rate: f64,
    pub payment_rate: f64,
    pub late_cancellations: i64,
    pub sample_size: i64,
    pub band: ReliabilityBand,
}

fn rate(numerator: i64, denominator: i64, default: f64) -> f64 {
    if denominator <= 0 {
        default
    } else {
        numerator as f64 / denominator as f64
    }
}

fn band_for(score: i64, sample_size: i64) -> ReliabilityBand {
    if sample_size < MINIMUM_SAMPLE {
        return ReliabilityBand::Unproven;
    }
    match score {
        85..=i64::MAX => ReliabilityBand::RockSolid,
        65..=84 => ReliabilityBand::Dependable,
        _ => ReliabilityBand::Patchy,
    }
}

/// Weighted 0–100 score. Players with no fees due aren't punished for it, so
/// the payment rate defaults to 1.0 when nothing was owed.
pub fn score(counts: ReliabilityCounts) -> ReliabilityScore {
    let response_rate = rate(counts.responded, counts.invites_received, 0.0);
    let attendance_rate = rate(counts.turned_up, counts.said_going, 0.0);
    let payment_rate = rate(counts.fees_paid, counts.fees_due, 1.0);

    let weighted = 0.5 * attendance_rate + 0.25 * response_rate + 0.25 * payment_rate;
    let penalty = LATE_CANCELLATION_PENALTY * counts.late_cancellations;
    let score = ((weighted * 100.0).round() as i64 - penalty).clamp(0, 100);

    ReliabilityScore {
        score,
        attendance_rate,
        response_rate,
        payment_rate,
        late_cancellations: counts.late_cancellations,
        sample_size: counts.invites_received,
        band: band_for(score, counts.invites_received),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn perfect() -> ReliabilityCounts {
        ReliabilityCounts {
            invites_received: 10,
            responded: 10,
            said_going: 8,
            turned_up: 8,
            late_cancellations: 0,
            fees_due: 8,
            fees_paid: 8,
        }
    }

    #[test]
    fn perfect_record_scores_one_hundred() {
        let result = score(perfect());
        assert_eq!(result.score, 100);
        assert_eq!(result.band, ReliabilityBand::RockSolid);
    }

    #[test]
    fn no_history_is_unproven() {
        let result = score(ReliabilityCounts::default());
        assert_eq!(result.sample_size, 0);
        assert_eq!(result.band, ReliabilityBand::Unproven);
    }

    #[test]
    fn short_history_stays_unproven_however_good() {
        let counts = ReliabilityCounts {
            invites_received: 2,
            responded: 2,
            said_going: 2,
            turned_up: 2,
            fees_due: 2,
            fees_paid: 2,
            ..Default::default()
        };
        assert_eq!(score(counts).band, ReliabilityBand::Unproven);
    }

    #[test]
    fn late_cancellations_cost_five_points_each() {
        let mut counts = perfect();
        counts.late_cancellations = 3;
        assert_eq!(score(counts).score, 85);
    }

    #[test]
    fn no_show_after_saying_going_hurts_most() {
        let mut counts = perfect();
        counts.turned_up = 4; // half the games they committed to
        assert_eq!(score(counts).score, 75);
        assert_eq!(score(counts).band, ReliabilityBand::Dependable);
    }

    #[test]
    fn owing_nothing_does_not_penalise_payment_rate() {
        let mut counts = perfect();
        counts.fees_due = 0;
        counts.fees_paid = 0;
        assert_eq!(score(counts).payment_rate, 1.0);
        assert_eq!(score(counts).score, 100);
    }

    #[test]
    fn ignoring_invites_lands_in_patchy() {
        let counts = ReliabilityCounts {
            invites_received: 20,
            responded: 6,
            said_going: 6,
            turned_up: 3,
            late_cancellations: 2,
            fees_due: 6,
            fees_paid: 3,
        };
        let result = score(counts);
        assert!(result.score < 65, "expected patchy, got {}", result.score);
        assert_eq!(result.band, ReliabilityBand::Patchy);
    }

    #[test]
    fn score_never_leaves_zero_to_one_hundred() {
        let counts = ReliabilityCounts {
            invites_received: 5,
            responded: 0,
            said_going: 0,
            turned_up: 0,
            late_cancellations: 50,
            fees_due: 5,
            fees_paid: 0,
        };
        assert_eq!(score(counts).score, 0);
    }
}
