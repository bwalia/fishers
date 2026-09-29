//! Matches from the wider game — the internationals and domestic competitions
//! read from an outside feed, as opposed to the club's own fixtures scored in
//! this app.
//!
//! Nothing here is scored by us; these are rows copied from a feed and handed
//! on. The one piece of judgement is [`phase_for`], which sorts the feed's
//! dozen-odd match states into the three buckets everything else asks about.

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};

/// Play is going on right now — including the intervals, which are part of a
/// match rather than the end of one.
pub const PHASE_LIVE: &str = "live";
/// Hasn't started yet.
pub const PHASE_PENDING: &str = "pending";
/// Over, one way or another. A match in this phase will never change again,
/// which is what lets the poller stop asking about it.
pub const PHASE_DONE: &str = "done";

/// Sort a feed match state into one of the three phases.
///
/// The distinction that matters is that an interval is not an ending. A Test
/// sitting at `Stumps` or `Tea` is very much still a live match — treating it
/// as finished would drop it off the screen overnight and, worse, would let
/// the poller mark the day settled and never look at it again.
///
/// Anything unrecognised counts as pending rather than done, so a state the
/// feed adds later keeps being refreshed instead of being quietly frozen
/// half-finished.
pub fn phase_for(state: &str) -> &'static str {
    match state {
        "In play" | "Innings break" | "Drinks" | "Lunch" | "Tea" | "Stumps" | "Timeout"
        | "Match delayed" => PHASE_LIVE,
        // "No live coverage" means the feed will never carry a score for this
        // one. There is nothing to wait for, so it is done rather than pending
        // — otherwise it would hold its day open for ever.
        "Finished" | "Abandoned" | "Cancelled" | "Postponed" | "No live coverage" => PHASE_DONE,
        _ => PHASE_PENDING,
    }
}

/// One match, as stored and as served. The column list and the JSON are the
/// same shape on purpose: there is no transformation worth having between
/// them.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct WorldMatch {
    pub id: String,
    pub league_name: String,
    pub league_season: Option<i32>,

    pub home_team_name: String,
    pub home_team_short: Option<String>,
    pub home_team_logo: Option<String>,
    pub away_team_name: String,
    pub away_team_short: Option<String>,
    pub away_team_logo: Option<String>,

    pub country_code: Option<String>,
    pub country_name: Option<String>,

    /// `T20`, `ODI` or `TEST`.
    pub format: Option<String>,
    /// `SINGLE` or `MULTI` — whether it runs over more than one day.
    pub day_type: Option<String>,

    pub start_time: Option<DateTime<Utc>>,
    pub start_date: NaiveDate,
    pub end_date: Option<NaiveDate>,

    /// The feed's own words: `In play`, `Tea`, `Stumps`, `Finished`.
    pub state: String,
    /// `live`, `pending` or `done` — see [`phase_for`].
    pub phase: String,
    /// The feed's sentence about it: "Day 2 - Hindukush trail by 79 runs."
    pub report: Option<String>,

    /// Strings, not numbers: a Test innings reads "128 & 59/5".
    pub home_score: Option<String>,
    pub home_info: Option<String>,
    pub away_score: Option<String>,
    pub away_info: Option<String>,
}

/// Everything the scores screen needs, in one response.
///
/// Split into three lists server-side rather than sending one list and a
/// filter, so that web, iOS and Android cannot disagree about what counts as
/// live — the same reason ownership of a shop listing is decided here.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldScores {
    /// False where no feed key is configured — int and test, for instance.
    /// The clients hide the section entirely rather than showing an empty one.
    pub enabled: bool,
    /// When the feed was last read. Shown to the reader, because on the free
    /// allowance this is minutes rather than seconds old and a score that is
    /// quietly stale is worse than one that says how old it is.
    pub as_of: Option<DateTime<Utc>>,
    pub live: Vec<WorldMatch>,
    pub upcoming: Vec<WorldMatch>,
    pub recent: Vec<WorldMatch>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn intervals_are_still_live() {
        // The one that matters: a Test at tea or stumps has not finished, and
        // treating it as finished would drop it off the screen overnight.
        for state in ["In play", "Innings break", "Drinks", "Lunch", "Tea", "Stumps", "Timeout"] {
            assert_eq!(phase_for(state), PHASE_LIVE, "{state} should be live");
        }
    }

    #[test]
    fn a_delay_is_not_an_ending() {
        // Rain stops play; rain does not end the match.
        assert_eq!(phase_for("Match delayed"), PHASE_LIVE);
        assert_eq!(phase_for("Abandoned"), PHASE_DONE);
    }

    #[test]
    fn finished_and_never_covered_are_both_done() {
        for state in ["Finished", "Abandoned", "Cancelled", "Postponed", "No live coverage"] {
            assert_eq!(phase_for(state), PHASE_DONE, "{state} should be done");
        }
    }

    #[test]
    fn scheduled_and_unknown_wait() {
        assert_eq!(phase_for("Scheduled"), PHASE_PENDING);
        assert_eq!(phase_for("Unknown"), PHASE_PENDING);
    }

    /// A state nobody has seen before must keep being refreshed, not be
    /// frozen half-played. Pending is the safe side of that bet.
    #[test]
    fn an_unknown_state_is_never_treated_as_finished() {
        assert_eq!(phase_for("Super Over"), PHASE_PENDING);
        assert_eq!(phase_for(""), PHASE_PENDING);
    }
}
