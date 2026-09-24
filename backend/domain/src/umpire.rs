//! Umpiring, as a record a player builds rather than a job on one afternoon.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// What a player says about how somebody umpired.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct UmpireReview {
    pub id: Uuid,
    pub match_id: Uuid,
    pub umpire_id: Uuid,
    pub reviewer_id: Uuid,
    /// One to five.
    pub rating: i16,
    pub comment: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// A review with the things a reader needs that the row does not carry.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct UmpireReviewView {
    pub id: Uuid,
    pub match_id: Uuid,
    pub rating: i16,
    pub comment: Option<String>,
    pub created_at: DateTime<Utc>,
    /// Who wrote it. Shown, because an anonymous rating on somebody's profile
    /// is a thing that can be dropped on them by anyone with a grudge.
    pub reviewer_name: String,
    pub reviewer_avatar_url: Option<String>,
    /// What the match was, so a review reads as being about an afternoon.
    pub match_title: String,
    pub played_on: Option<DateTime<Utc>>,
}

/// An umpire's record: how often, how it went, and the last few in full.
#[derive(Debug, Clone, Serialize)]
pub struct UmpireProfile {
    pub user_id: Uuid,
    /// Whether they have said they will stand. Distinct from having stood:
    /// somebody who has umpired eleven times and stopped should not be in the
    /// list a captain picks from.
    pub umpires: bool,
    pub note: Option<String>,
    /// Completed matches where they were the named umpire.
    pub matches: i64,
    /// Mean of every rating, to one decimal. `None` until somebody reviews —
    /// not 0.0, which reads as "rated, badly".
    pub rating_average: Option<f64>,
    pub rating_count: i64,
    /// How the ratings fall, one to five. A 4.0 from ten fours is a different
    /// umpire from a 4.0 from five fives and five threes.
    pub rating_breakdown: [i64; 5],
    pub reviews: Vec<UmpireReviewView>,
}

/// Somebody who has said they will stand, for the list a captain picks from.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct AvailableUmpire {
    pub user_id: Uuid,
    pub name: String,
    pub avatar_url: Option<String>,
    pub note: Option<String>,
    pub matches: i64,
    pub rating_average: Option<f64>,
    pub rating_count: i64,
}

/// An umpire in a match, and whether the person asking has had their say.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct MatchUmpire {
    pub user_id: Uuid,
    pub name: String,
    pub avatar_url: Option<String>,
    /// The asking player's own review, if they have left one. Present so the
    /// form opens with what they said last time rather than blank.
    pub my_rating: Option<i16>,
    pub my_comment: Option<String>,
}

/// A finished match whose umpiring this player has not had their say on.
///
/// The way a review actually gets left. Asking somebody to navigate back to a
/// match from three Sundays ago to rate the umpire is asking for nothing to be
/// rated; this is the list that comes to them.
#[derive(Debug, Clone, Serialize)]
pub struct PendingUmpireReview {
    pub match_id: Uuid,
    pub match_title: String,
    pub played_on: Option<DateTime<Utc>>,
    /// Only the ones they have not reviewed. A match where they have rated one
    /// umpire and not the other stays here, with the other.
    pub umpires: Vec<MatchUmpire>,
}

/// The mean rating, to one decimal, from a one-to-five breakdown.
///
/// `None` rather than 0.0 when nobody has reviewed: zero is a rating, and
/// "rated, badly" is not what "not rated" means. Lives here rather than in the
/// repo so it can be checked without a database — the rounding is the kind of
/// thing that is quietly wrong for years.
pub fn rating_average(breakdown: &[i64; 5]) -> Option<f64> {
    let count: i64 = breakdown.iter().sum();
    if count == 0 {
        return None;
    }
    let total: i64 = breakdown
        .iter()
        .enumerate()
        .map(|(i, n)| (i as i64 + 1) * n)
        .sum();
    Some((total as f64 / count as f64 * 10.0).round() / 10.0)
}

#[cfg(test)]
mod tests {
    use super::rating_average;

    #[test]
    fn nobody_has_reviewed_is_not_a_zero() {
        assert_eq!(rating_average(&[0, 0, 0, 0, 0]), None);
    }

    #[test]
    fn one_review_is_that_review() {
        assert_eq!(rating_average(&[0, 0, 0, 1, 0]), Some(4.0));
    }

    #[test]
    fn the_mean_is_weighted_by_how_many_gave_each_rating() {
        // Ten fours and nothing else.
        assert_eq!(rating_average(&[0, 0, 0, 10, 0]), Some(4.0));
        // Five fives and five threes: the same 4.0, a different umpire — which
        // is why the breakdown is sent as well as the average.
        assert_eq!(rating_average(&[0, 0, 5, 0, 5]), Some(4.0));
    }

    #[test]
    fn it_rounds_to_one_decimal_rather_than_truncating() {
        // 1+2+3 = 6 over 3 = 2.0
        assert_eq!(rating_average(&[1, 1, 1, 0, 0]), Some(2.0));
        // 4,4,5 = 13 over 3 = 4.333… which is 4.3, not 4.4 and not 4.
        assert_eq!(rating_average(&[0, 0, 0, 2, 1]), Some(4.3));
        // 4,5,5 = 14 over 3 = 4.666… which rounds up.
        assert_eq!(rating_average(&[0, 0, 0, 1, 2]), Some(4.7));
    }

    #[test]
    fn the_extremes_are_the_extremes() {
        assert_eq!(rating_average(&[3, 0, 0, 0, 0]), Some(1.0));
        assert_eq!(rating_average(&[0, 0, 0, 0, 3]), Some(5.0));
    }
}
