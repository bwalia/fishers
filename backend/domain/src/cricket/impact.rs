//! Who had the biggest game — the shortlist behind the player of the match.
//!
//! Nobody in cricket *computes* this award. An adjudicator — a former player,
//! a commentator, one of the umpires at club level — watches the game and
//! picks. What they are weighing, though, is the scorecard, so the app does
//! the weighing and leaves the picking to whoever was there. The scorer still
//! taps the name; they just no longer have to hold twenty-two performances in
//! their head to do it.
//!
//! The weights are the ones club scoring has used for years — a wicket runs
//! about twenty, a catch about eight — plus two adjustments taken from the
//! match itself rather than from a constant: runs above the match run rate for
//! a batter, runs saved against it for a bowler. Those are what separate fifty
//! off thirty from fifty off sixty, and 2-18 from 2-48, without the formula
//! needing to know whether this is a five-over tape-ball game or a fifty-over
//! league match.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use uuid::Uuid;

use super::types::*;

/// A wicket, in the runs club scoring has always valued it at.
const WICKET: f64 = 20.0;
const MAIDEN: f64 = 8.0;
const CATCH: f64 = 8.0;
const STUMPING: f64 = 10.0;
const RUN_OUT: f64 = 8.0;

/// The winning side's edge. An adjudicator nearly always picks from the
/// winners, so this is enough to break a near-tie that way — and deliberately
/// not enough to beat a real performance in a losing side, which is the one
/// case where the human overrules the list anyway.
const WINNER_EDGE: f64 = 1.1;

/// Milestones an adjudicator notices. The highest one only — a hundred does
/// not also collect the fifty.
fn milestone(runs: u16) -> f64 {
    match runs {
        100.. => 40.0,
        50..=99 => 20.0,
        30..=49 => 8.0,
        _ => 0.0,
    }
}

fn haul(wickets: u16) -> f64 {
    match wickets {
        5.. => 25.0,
        3..=4 => 10.0,
        _ => 0.0,
    }
}

/// One player's match, scored. Enough to rank the list and to say why.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerImpact {
    pub player_id: Uuid,
    pub name: String,
    pub side: MatchSide,
    /// Higher is better. Runs-flavoured, but not runs — do not put it on a
    /// scorecard as if it were one.
    pub score: f64,
    /// "75* (45) · 2-18 (4.0) · 1 ct" — why they are on the list.
    pub line: String,
}

/// Running totals for one player across every innings of the match.
#[derive(Default)]
struct Tally {
    runs: u16,
    balls: u16,
    fours: u16,
    sixes: u16,
    not_out: bool,
    wickets: u16,
    conceded: u16,
    bowled: u16,
    maidens: u16,
    catches: u16,
    stumpings: u16,
    run_outs: u16,
}

impl Tally {
    fn did_something(&self) -> bool {
        self.balls > 0
            || self.runs > 0
            || self.bowled > 0
            || self.catches + self.stumpings + self.run_outs > 0
    }

    fn score(&self, par: f64) -> f64 {
        // Both halves fall to zero on their own for a player who did not bat
        // or did not bowl, so neither needs a guard.
        let batting = self.runs as f64
            + self.fours as f64
            + 2.0 * self.sixes as f64
            + milestone(self.runs)
            + (self.runs as f64 - self.balls as f64 * par);
        let bowling = self.wickets as f64 * WICKET
            + self.maidens as f64 * MAIDEN
            + haul(self.wickets)
            + (self.bowled as f64 * par - self.conceded as f64);
        let fielding = self.catches as f64 * CATCH
            + self.stumpings as f64 * STUMPING
            + self.run_outs as f64 * RUN_OUT;
        batting + bowling + fielding
    }

    fn line(&self) -> String {
        let mut parts = Vec::new();
        if self.balls > 0 || self.runs > 0 {
            parts.push(format!(
                "{}{} ({})",
                self.runs,
                if self.not_out { "*" } else { "" },
                self.balls
            ));
        }
        if self.bowled > 0 {
            parts.push(format!(
                "{}-{} ({})",
                self.wickets,
                self.conceded,
                MatchState::overs_balls_display(self.bowled)
            ));
        }
        for (count, label) in [
            (self.catches, "ct"),
            (self.stumpings, "st"),
            (self.run_outs, "ro"),
        ] {
            if count > 0 {
                parts.push(format!("{count} {label}"));
            }
        }
        parts.join(" · ")
    }
}

impl MatchState {
    /// Every player who did something, best game first.
    ///
    /// Empty before a ball is bowled. Safe to call at any point in a match —
    /// it is only *shown* at the end, but a leading-performers panel mid-game
    /// would read the same list.
    pub fn impact(&self) -> Vec<PlayerImpact> {
        // The par rate comes from the match proper. A super over is one over
        // of hitting and would drag it somewhere no normal innings lives.
        let (runs, balls) = self
            .innings
            .iter()
            .filter(|inn| !inn.super_over)
            .fold((0u32, 0u32), |(r, b), inn| {
                (r + inn.runs as u32, b + inn.legal_balls as u32)
            });
        if balls == 0 {
            return Vec::new();
        }
        let par = runs as f64 / balls as f64;

        let mut tallies: BTreeMap<Uuid, Tally> = BTreeMap::new();
        // Contributions count from every innings, super over included — the
        // player who wins it one-handed is exactly who this list is for.
        for inn in &self.innings {
            for bat in &inn.batters {
                if !bat.has_batted() {
                    continue;
                }
                let t = tallies.entry(bat.player_id).or_default();
                t.runs += bat.runs;
                t.balls += bat.balls;
                t.fours += bat.fours;
                t.sixes += bat.sixes;
                t.not_out |= !bat.out;

                // The fielder is on the other side, so this credits them in
                // their own tally, not the batter's.
                if let (Some(fielder), Some(kind)) = (bat.fielder_id, bat.dismissal) {
                    let f = tallies.entry(fielder).or_default();
                    match kind {
                        DismissalKind::Caught => f.catches += 1,
                        DismissalKind::Stumped => f.stumpings += 1,
                        DismissalKind::RunOut => f.run_outs += 1,
                        _ => {}
                    }
                }
            }
            for bowl in &inn.bowlers {
                let t = tallies.entry(bowl.player_id).or_default();
                t.wickets += bowl.wickets;
                t.conceded += bowl.runs;
                t.bowled += bowl.balls;
                t.maidens += bowl.maidens;
            }
        }

        let mut out: Vec<PlayerImpact> = tallies
            .into_iter()
            .filter(|(_, t)| t.did_something())
            .map(|(player_id, t)| {
                let side = self.side_of(player_id);
                let mut score = t.score(par);
                if score > 0.0 && side.is_some() && self.winner == side {
                    score *= WINNER_EDGE;
                }
                PlayerImpact {
                    player_id,
                    name: self.name_for(player_id),
                    side: side.unwrap_or(MatchSide::Home),
                    score,
                    line: t.line(),
                }
            })
            .collect();
        // Name breaks a tie so two runs of the same log rank identically.
        out.sort_by(|a, b| b.score.total_cmp(&a.score).then_with(|| a.name.cmp(&b.name)));
        out
    }

    /// The best game on the losing side — the one who made a contest of it.
    ///
    /// Club cricket gives this award more than the professional game does, and
    /// it is usually the right call: somebody carried their bat through a
    /// collapse, or took four while the other ten watched. Three things have
    /// to hold, or there is no fighter and the app says nothing rather than
    /// inventing one:
    ///
    /// - somebody won, so there is a losing side to pick from;
    /// - they played above the match's own par, because a heavy defeat where
    ///   nobody did anything had no fight in it;
    /// - they are not already the player of the match, since a performance
    ///   that beat everyone on the day does not also need the consolation.
    pub fn fighter_of_the_match(&self) -> Option<PlayerImpact> {
        let losing = self.winner?.opposite();
        let ranked = self.impact();
        let best = ranked.first()?;
        let fighter = ranked
            .iter()
            .find(|p| p.side == losing && p.score > 0.0)?;
        (fighter.player_id != best.player_id).then(|| fighter.clone())
    }

    /// Which team sheet a player is on, if either.
    pub fn side_of(&self, player_id: Uuid) -> Option<MatchSide> {
        if self.home_xi.contains(&player_id) {
            Some(MatchSide::Home)
        } else if self.away_xi.contains(&player_id) {
            Some(MatchSide::Away)
        } else {
            None
        }
    }
}

impl MatchStatus {
    /// The game is over, one way or another.
    pub fn is_finished(self) -> bool {
        matches!(self, Self::Complete | Self::Published)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bat(player_id: Uuid, runs: u16, balls: u16, out: bool) -> BatterStats {
        BatterStats {
            runs,
            balls,
            out,
            ..BatterStats::new(player_id)
        }
    }

    fn bowl(player_id: Uuid, balls: u16, runs: u16, wickets: u16) -> BowlerStats {
        BowlerStats {
            balls,
            runs,
            wickets,
            ..BowlerStats::new(player_id)
        }
    }

    /// A twenty-over game: 150 apiece off 120 balls, so par is 1.25 a ball.
    /// Home bat first; the caller sets the result where it matters.
    fn match_of(batters: Vec<BatterStats>, bowlers: Vec<BowlerStats>) -> MatchState {
        let home_xi = batters.iter().map(|b| b.player_id).collect();
        let away_xi = bowlers.iter().map(|b| b.player_id).collect();
        MatchState {
            home_xi,
            away_xi,
            status: MatchStatus::Complete,
            innings: vec![
                InningsState {
                    index: 0,
                    batting: MatchSide::Home,
                    bowling: MatchSide::Away,
                    runs: 150,
                    legal_balls: 120,
                    batters,
                    bowlers,
                    complete: true,
                    ..InningsState::default()
                },
                InningsState {
                    index: 1,
                    batting: MatchSide::Away,
                    bowling: MatchSide::Home,
                    runs: 150,
                    legal_balls: 120,
                    complete: true,
                    ..InningsState::default()
                },
            ],
            ..MatchState::default()
        }
    }

    #[test]
    fn the_biggest_game_tops_the_list() {
        let opener = Uuid::new_v4();
        let plodder = Uuid::new_v4();
        let seamer = Uuid::new_v4();
        let state = match_of(
            vec![bat(opener, 75, 45, true), bat(plodder, 30, 50, true)],
            vec![bowl(seamer, 24, 20, 3)],
        );

        let list = state.impact();
        assert_eq!(list[0].player_id, opener, "75 off 45 is the game");
        assert!(
            list.iter().position(|p| p.player_id == seamer).unwrap()
                < list.iter().position(|p| p.player_id == plodder).unwrap(),
            "3-20 off four beats 30 off 50"
        );
        assert_eq!(list[0].line, "75 (45)");
    }

    #[test]
    fn tempo_separates_two_innings_of_the_same_size() {
        let quick = Uuid::new_v4();
        let slow = Uuid::new_v4();
        let state = match_of(
            vec![bat(quick, 50, 30, true), bat(slow, 50, 60, true)],
            vec![],
        );
        let list = state.impact();
        assert_eq!(list[0].player_id, quick);
        assert!(
            list[0].score > list[1].score,
            "same runs, fewer balls, higher score"
        );
    }

    #[test]
    fn the_winning_side_gets_the_benefit_of_a_tie() {
        let home = Uuid::new_v4();
        let away = Uuid::new_v4();
        let mut state = match_of(vec![bat(home, 50, 40, true)], vec![]);
        // The same innings for the other side, so only the result separates
        // them.
        state.away_xi = vec![away];
        state.innings[1].batters = vec![bat(away, 50, 40, true)];
        state.winner = Some(MatchSide::Away);

        let list = state.impact();
        assert_eq!(list[0].player_id, away, "level performances, the winner");
    }

    #[test]
    fn a_catch_is_worth_something_and_reads_on_the_line() {
        let keeper = Uuid::new_v4();
        let batter = Uuid::new_v4();
        let mut out = bat(batter, 10, 10, true);
        out.dismissal = Some(DismissalKind::Caught);
        out.fielder_id = Some(keeper);
        let mut state = match_of(vec![out], vec![]);
        state.away_xi = vec![keeper];

        let list = state.impact();
        let fielder = list.iter().find(|p| p.player_id == keeper).unwrap();
        assert_eq!(fielder.line, "1 ct");
        assert!(fielder.score > 0.0);
    }

    #[test]
    fn the_fighter_is_the_best_game_in_the_losing_side() {
        let winner = Uuid::new_v4();
        let loser = Uuid::new_v4();
        let alsoran = Uuid::new_v4();
        // The sheets are set below, so the helper only supplies the shape.
        let mut state = match_of(vec![], vec![]);
        // Home batted first and lost; the 80 is theirs.
        state.home_xi = vec![loser, alsoran];
        state.innings[0].batters = vec![bat(loser, 80, 50, true), bat(alsoran, 2, 9, true)];
        state.away_xi = vec![winner];
        state.innings[1].batters = vec![bat(winner, 95, 55, false)];
        state.winner = Some(MatchSide::Away);

        let fighter = state.fighter_of_the_match().expect("somebody made a game of it");
        assert_eq!(fighter.player_id, loser);
        assert_eq!(fighter.side, MatchSide::Home);
        assert_ne!(
            fighter.player_id,
            state.impact()[0].player_id,
            "the fighter is never also the player of the match"
        );
    }

    #[test]
    fn no_fighter_when_the_losing_side_had_the_best_game_anyway() {
        let hero = Uuid::new_v4();
        let winner = Uuid::new_v4();
        let mut state = match_of(vec![], vec![]);
        state.home_xi = vec![hero];
        state.away_xi = vec![winner];
        // A hundred in a losing cause still tops the whole list, so it is the
        // award itself, not the consolation.
        state.innings[0].batters = vec![bat(hero, 140, 60, false)];
        state.innings[1].batters = vec![bat(winner, 20, 18, true)];
        state.winner = Some(MatchSide::Away);

        assert_eq!(state.impact()[0].player_id, hero);
        assert!(state.fighter_of_the_match().is_none());
    }

    #[test]
    fn no_fighter_without_a_result() {
        let state = match_of(vec![bat(Uuid::new_v4(), 50, 30, true)], vec![]);
        assert!(state.winner.is_none());
        assert!(state.fighter_of_the_match().is_none(), "a tie has no losing side");
    }

    #[test]
    fn nothing_bowled_means_nothing_to_rank() {
        assert!(MatchState::default().impact().is_empty());
    }
}
