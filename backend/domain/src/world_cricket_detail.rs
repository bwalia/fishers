//! One match from the outside feed, in full: the scorecard.
//!
//! The list these come from costs one request for every match being played
//! anywhere; this costs one request for *one* match, so it is fetched only when
//! somebody actually opens it, and a finished scorecard is fetched once and
//! never again.
//!
//! The only judgement here is [`dismissal_line`], which turns the feed's parts
//! into the phrase a scorecard is actually read in.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// How a batter got out, written the way a scorecard writes it.
///
/// Worth doing once on the server rather than three times on the clients: the
/// conventions are fiddly (a catch by the bowler is "c & b", a stumping names
/// the keeper, a run out names a fielder and no bowler at all), and three
/// implementations of fiddly is three chances to print something a cricketer
/// would laugh at.
///
/// `status` is the feed's own word. Anything unrecognised is passed through
/// rather than swallowed — a scorecard reading "retired hurt" is right, and one
/// silently reading "not out" because we did not know the word is not.
pub fn dismissal_line(
    status: Option<&str>,
    bowler: Option<&str>,
    fielders: &[&str],
    batted: bool,
) -> String {
    let Some(status) = status.map(str::trim).filter(|s| !s.is_empty()) else {
        // No status at all: either still in, or never went in.
        return if batted { "not out".into() } else { "did not bat".into() };
    };
    let fielder = fielders.first().copied();

    match status.to_ascii_lowercase().as_str() {
        "not out" | "notout" => "not out".into(),
        "caught" => match (fielder, bowler) {
            // Caught by the bowler is its own phrase; "c Mulani b Mulani" is
            // not something anybody writes.
            (Some(f), Some(b)) if f == b => format!("c & b {b}"),
            (Some(f), Some(b)) => format!("c {f} b {b}"),
            (None, Some(b)) => format!("c & b {b}"),
            (Some(f), None) => format!("c {f}"),
            (None, None) => "caught".into(),
        },
        "bowled" => match bowler {
            Some(b) => format!("b {b}"),
            None => "bowled".into(),
        },
        "lbw" => match bowler {
            Some(b) => format!("lbw b {b}"),
            None => "lbw".into(),
        },
        // No bowler is credited with a run out, so naming one would be wrong.
        "run out" | "runout" => match fielder {
            Some(f) => format!("run out ({f})"),
            None => "run out".into(),
        },
        "stumped" => match (fielder, bowler) {
            (Some(f), Some(b)) => format!("st {f} b {b}"),
            (None, Some(b)) => format!("st b {b}"),
            (Some(f), None) => format!("st {f}"),
            (None, None) => "stumped".into(),
        },
        "hit wicket" | "hitwicket" => match bowler {
            Some(b) => format!("hit wicket b {b}"),
            None => "hit wicket".into(),
        },
        // "retired hurt", "obstructing the field", and whatever else the feed
        // decides to send next.
        other => other.to_string(),
    }
}

/// A batter's line on the card.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BattingRow {
    pub name: String,
    /// `None` where the batter has not been in yet.
    pub runs: Option<i32>,
    pub balls: Option<i32>,
    pub fours: Option<i32>,
    pub sixes: Option<i32>,
    pub strike_rate: Option<f64>,
    /// Already composed: "c Kotian b Mulani", "not out", "did not bat".
    pub how_out: String,
    /// Whether they are still there. Drives the bold row on the card.
    pub not_out: bool,
}

/// A bowler's figures.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BowlingRow {
    pub name: String,
    pub overs: Option<f64>,
    pub maidens: Option<i32>,
    pub runs: Option<i32>,
    pub wickets: Option<i32>,
    pub economy: Option<f64>,
}

/// "3-127 (28.4 ov) J Sangha" — the wicket, the score it fell at, and who went.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FallOfWicket {
    /// 1 for the first wicket. The feed counts from zero; a scorecard does not.
    pub wicket: i32,
    pub runs: Option<i32>,
    pub overs: Option<f64>,
    pub batter: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Extras {
    pub total: Option<i32>,
    pub byes: Option<i32>,
    pub leg_byes: Option<i32>,
    pub wides: Option<i32>,
    pub no_balls: Option<i32>,
}

/// One innings: who batted, who bowled at them, and how it fell apart.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Innings {
    pub team_name: String,
    /// "AUS-A". What a tab is labelled with, because "Australia A 1st Innings"
    /// does not fit across a phone four times.
    pub team_short: Option<String>,
    pub team_logo: Option<String>,
    /// The innings total, computed here rather than by three clients.
    ///
    /// The feed does not send one, but cricket's own identity does: the runs
    /// off the bat plus the extras *are* the total. Checked against a real
    /// match — 255 off the bat, 27 extras, and the summary said 282/7.
    pub total_runs: Option<i32>,
    /// Wickets down: batters who went in and did not come back not out.
    pub wickets: Option<i32>,
    pub batting: Vec<BattingRow>,
    pub bowling: Vec<BowlingRow>,
    pub fall_of_wickets: Vec<FallOfWicket>,
    pub extras: Extras,
}

/// Somebody at the crease right now, or bowling right now.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CurrentPlayer {
    pub name: String,
    pub team_name: Option<String>,
    /// "101 (153b, 7x4, 3x6)" for a batter, "11.6-6-19-1" for a bowler —
    /// composed here so the three clients cannot format it three ways.
    pub line: String,
}

/// The whole detail payload for one match.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WorldMatchDetail {
    pub venue: Option<String>,
    /// Only while play is going on.
    pub batting_now: Vec<CurrentPlayer>,
    pub bowling_now: Vec<CurrentPlayer>,
    /// One entry per innings played so far, in order.
    pub innings: Vec<Innings>,
}

impl WorldMatchDetail {
    /// Whether there is anything worth drawing a scorecard for. A match that
    /// has not started returns a detail with no innings, and the screen should
    /// say so rather than render empty tables.
    pub fn has_scorecard(&self) -> bool {
        self.innings.iter().any(|i| !i.batting.is_empty())
    }
}

/// The detail plus how old it is, as the API returns it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldMatchDetailView {
    /// The summary row, so the page can be drawn from one request.
    pub summary: super::world_cricket::WorldMatch,
    /// `None` when we have not fetched a scorecard for this match yet — the
    /// screen shows the summary and says the card is on its way.
    pub detail: Option<WorldMatchDetail>,
    pub detail_as_of: Option<DateTime<Utc>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_catch_names_the_fielder_then_the_bowler() {
        assert_eq!(
            dismissal_line(Some("caught"), Some("Shams Mulani"), &["Tanush Kotian"], true),
            "c Tanush Kotian b Shams Mulani"
        );
    }

    /// The one every naive implementation gets wrong: caught by the bowler is
    /// "c & b", never "c Mulani b Mulani".
    #[test]
    fn caught_and_bowled_is_its_own_phrase() {
        assert_eq!(
            dismissal_line(Some("caught"), Some("Mulani"), &["Mulani"], true),
            "c & b Mulani"
        );
        // The feed sometimes gives the bowler and no fielder for the same thing.
        assert_eq!(dismissal_line(Some("caught"), Some("Mulani"), &[], true), "c & b Mulani");
    }

    /// Some matches come back with `dismissalBowler: {}` — an empty object, no
    /// name. Seen on a real women's domestic match. The card then says what it
    /// knows and no more; inventing a bowler would be worse than omitting one.
    #[test]
    fn a_missing_bowler_is_omitted_rather_than_invented() {
        assert_eq!(dismissal_line(Some("caught"), None, &["Hasrat Gill"], true), "c Hasrat Gill");
        assert_eq!(dismissal_line(Some("bowled"), None, &[], true), "bowled");
        assert_eq!(dismissal_line(Some("lbw"), None, &[], true), "lbw");
        assert_eq!(dismissal_line(Some("caught"), None, &[], true), "caught");
        assert_eq!(dismissal_line(Some("stumped"), None, &["Kushagra"], true), "st Kushagra");
    }

    #[test]
    fn bowled_and_lbw_name_only_the_bowler() {
        assert_eq!(dismissal_line(Some("bowled"), Some("Kamboj"), &[], true), "b Kamboj");
        assert_eq!(dismissal_line(Some("lbw"), Some("Kamboj"), &[], true), "lbw b Kamboj");
    }

    /// Nobody is credited with a run out, so naming a bowler would be a lie.
    #[test]
    fn a_run_out_names_a_fielder_and_no_bowler() {
        assert_eq!(
            dismissal_line(Some("run out"), Some("Kamboj"), &["Padikkal"], true),
            "run out (Padikkal)"
        );
        assert_eq!(dismissal_line(Some("run out"), None, &[], true), "run out");
    }

    #[test]
    fn a_stumping_names_the_keeper_and_the_bowler() {
        assert_eq!(
            dismissal_line(Some("stumped"), Some("Mulani"), &["Kushagra"], true),
            "st Kushagra b Mulani"
        );
    }

    #[test]
    fn not_out_and_did_not_bat_are_different_things() {
        assert_eq!(dismissal_line(Some("not out"), None, &[], true), "not out");
        // No status and no innings: they never went in.
        assert_eq!(dismissal_line(None, None, &[], false), "did not bat");
        // No status but they did bat: still there.
        assert_eq!(dismissal_line(None, None, &[], true), "not out");
    }

    /// A word we have never seen must reach the screen as itself. Printing
    /// "not out" for a batter who retired hurt is worse than printing nothing.
    #[test]
    fn an_unknown_status_is_passed_through() {
        assert_eq!(dismissal_line(Some("retired hurt"), None, &[], true), "retired hurt");
        assert_eq!(
            dismissal_line(Some("obstructing the field"), None, &[], true),
            "obstructing the field"
        );
    }

    #[test]
    fn an_empty_status_is_not_a_dismissal() {
        assert_eq!(dismissal_line(Some("   "), None, &[], true), "not out");
    }

    #[test]
    fn a_match_with_no_innings_has_no_scorecard() {
        let empty = WorldMatchDetail {
            venue: None,
            batting_now: vec![],
            bowling_now: vec![],
            innings: vec![],
        };
        assert!(!empty.has_scorecard());
    }
}
