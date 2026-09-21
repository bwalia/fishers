//! Man of the match, as voted for by the club.
//!
//! Distinct from `MatchState::player_of_the_match`, which is the scorer's
//! award and is written into the scoring event log. This is the club's vote:
//! it opens when the game ends, anyone in the club may vote — including the
//! people who watched rather than played — and closing it writes the winner
//! back to the scorecard as the award.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct MotmPoll {
    pub id: Uuid,
    pub club_id: Uuid,
    pub event_id: Uuid,
    pub match_id: Option<Uuid>,
    pub conversation_id: Option<Uuid>,
    pub message_id: Option<Uuid>,
    pub title: String,
    /// `open` | `closed`
    pub status: String,
    pub closes_at: DateTime<Utc>,
    pub winner_user_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub closed_at: Option<DateTime<Utc>>,
}

impl MotmPoll {
    /// Whether a vote cast right now would count. A poll past its closing
    /// time is over whether or not anybody has run the close yet — otherwise
    /// the result depends on who asked last.
    pub fn is_open(&self) -> bool {
        self.status == "open" && self.closes_at > Utc::now()
    }
}

/// Somebody who can be voted for: everyone named on either team sheet.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct MotmCandidate {
    pub user_id: Uuid,
    pub display_name: String,
    /// `home` | `away`
    pub side: String,
    /// Votes cast for them. Zero for everybody until the tally is shown.
    pub votes: i64,
}

/// A poll as one person sees it: the poll, who is on the list, and whether
/// the tally is theirs to see yet.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MotmPollView {
    #[serde(flatten)]
    pub poll: MotmPoll,
    pub candidates: Vec<MotmCandidate>,
    /// Who this viewer voted for, if they have.
    pub my_vote: Option<Uuid>,
    /// Everyone who has voted so far, whatever they voted for.
    pub total_votes: i64,
    /// Whether `candidates[].votes` carries the real count.
    ///
    /// A running tally shown before you vote is a nudge towards whoever is
    /// already ahead, so the numbers stay hidden until you have voted or the
    /// poll has closed. The flag is explicit rather than inferred so a client
    /// can say "hidden until you vote" instead of drawing a row of zeroes.
    pub tally_visible: bool,
    /// Whether this viewer may still vote.
    pub can_vote: bool,
    /// The scorer's own award, when one was given. Shown alongside the vote
    /// so the two never look like the same thing.
    pub scorer_award_user_id: Option<Uuid>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CastMotmVoteRequest {
    pub candidate_user_id: Uuid,
}

/// The tally of one candidate, for announcing a result.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct MotmTallyRow {
    pub user_id: Uuid,
    pub display_name: String,
    pub votes: i64,
}
