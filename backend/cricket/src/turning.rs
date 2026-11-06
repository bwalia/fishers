//! The moment a match turned.
//!
//! Every finished chase has one over people argue about on the way home: the
//! six that brought it back, the wicket that ended it. The scorecard shows the
//! result and the log holds every ball, so the moment can be read straight back
//! out — nothing more for the scorer to record.
//!
//! # How it is found
//!
//! After each ball of the chase, the winner's chance is estimated from what is
//! left: runs needed, balls left and wickets in hand. The estimate reuses the
//! DLS resource curve for "how much batting is left", so a reduced-overs game
//! works without a second model. It is a small, honest model — good enough to
//! say which ball swung things, not to price a bet — and it is labelled as an
//! estimate wherever it surfaces.
//!
//! The turning point is the ball that moved the winner's chance the most:
//!
//! - **Comeback** — if the winners were ever behind (under 50%), the biggest
//!   swing in their favour during the stretch in which they were still behind,
//!   up to the ball that put them level.
//! - **Decider** — if they were never behind, the biggest swing in their favour
//!   anywhere in the chase: where it was put out of reach.
//!
//! If nothing moved the needle by [`MIN_SWING`], there was no moment worth
//! naming and the answer is `None`, rather than a ball chosen to fill a slot.
//! First innings are not modelled: with no target there is nothing to measure
//! a ball against, so only the chase is read.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::dls::ResourceTable;
use super::types::*;

/// The smallest swing worth naming, as a fraction of certainty. Below this the
/// match drifted rather than turned.
const MIN_SWING: f64 = 0.05;

/// How the winners got there.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TurningKind {
    /// They were behind, and this is the ball that brought them back.
    Comeback,
    /// They were never behind; this is where it was put out of reach.
    Decider,
}

/// The ball that decided it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurningPoint {
    /// The side it helped: the winner. The other side watched it slip away.
    pub side: MatchSide,
    pub kind: TurningKind,
    /// Which innings of the match, 0-indexed. Always the chase.
    pub innings: u8,
    /// The over, as a scorer says it: "14.3".
    pub over: String,
    /// What the scorebook shows for the ball: "6", "W", "4".
    pub label: String,
    pub runs: u8,
    pub is_wicket: bool,
    pub batter_id: Option<Uuid>,
    pub bowler_id: Option<Uuid>,
    /// The winner's chance, in whole percent, just before and just after.
    pub before_percent: u8,
    pub after_percent: u8,
    /// What the chasing side still needed once the ball was done, and in how
    /// many balls — what a listener wants to hear after "the turning point".
    pub runs_needed: u16,
    pub balls_left: u16,
}

/// Chance the side batting second wins, `0.0..=1.0`.
fn chase_chance(
    table: &ResourceTable,
    base: f64,
    start_resource: f64,
    needed: i32,
    balls_left: u16,
    wickets: u8,
    wickets_allowed: u8,
) -> f64 {
    if needed <= 0 {
        return 1.0;
    }
    if balls_left == 0 || wickets >= wickets_allowed {
        return 0.0;
    }
    let left = table.resource(balls_left as f64 / 6.0, wickets);
    if start_resource <= 0.0 || left <= 0.0 {
        return 0.0;
    }
    let share = left / start_resource;
    // A side with all its resources is expected to make what the first
    // innings made; the same side with half of them, half of it.
    let expected = base * share;
    let margin = expected - needed as f64;
    // Uncertainty shrinks as the innings runs out — a hundred to get off six
    // balls is not 50-50 because the maths straddles zero.
    let spread = 0.30 * base * share.sqrt() + 3.0;
    1.0 / (1.0 + (-1.7 * margin / spread).exp())
}

fn percent(p: f64) -> u8 {
    (p * 100.0).round().clamp(0.0, 100.0) as u8
}

impl MatchState {
    /// The ball the match turned on, or `None` where there is no honest answer:
    /// no winner, no chase, an unlimited-overs game, or a result that was never
    /// in doubt.
    pub fn turning_point(&self) -> Option<TurningPoint> {
        let winner = self.winner?;
        let innings: Vec<&InningsState> = self.innings.iter().filter(|i| !i.super_over).collect();
        let [first, chase] = innings[..] else {
            return None;
        };
        let overs = if chase.overs_available > 0 {
            chase.overs_available
        } else {
            self.overs_limit
        };
        if overs == 0 || chase.deliveries.is_empty() {
            return None;
        }

        let target = self.target.unwrap_or(first.runs.saturating_add(1)) as i32;
        let table = ResourceTable::default();
        let base = (target - 1).max(1) as f64;
        let start = table.resource(overs as f64, 0);
        let total_balls = overs as u16 * 6;
        let allowed = chase.wickets_allowed.max(1);
        let winner_is_chasing = chase.batting == winner;

        // The winner's chance after every delivery, with the chance before the
        // first ball as the starting point.
        let winner_chance = |p: f64| if winner_is_chasing { p } else { 1.0 - p };
        let mut runs: i32 = 0;
        let mut legal: u16 = 0;
        let mut wickets: u8 = 0;
        let mut series: Vec<f64> = Vec::with_capacity(chase.deliveries.len() + 1);
        series.push(winner_chance(chase_chance(
            &table, base, start, target, total_balls, 0, allowed,
        )));
        for d in &chase.deliveries {
            runs += d.runs as i32;
            if d.is_legal {
                legal += 1;
            }
            if d.is_wicket {
                wickets += 1;
            }
            series.push(winner_chance(chase_chance(
                &table,
                base,
                start,
                target - runs,
                total_balls.saturating_sub(legal),
                wickets,
                allowed,
            )));
        }

        // series[i + 1] is the chance after delivery i.
        let swing = |i: usize| series[i + 1] - series[i];
        let n = chase.deliveries.len();
        let last_behind = (1..=n).rev().find(|&i| series[i] < 0.5);

        let (kind, range) = match last_behind {
            Some(last) => {
                let mut start_of_stretch = last;
                while start_of_stretch > 1 && series[start_of_stretch - 1] < 0.5 {
                    start_of_stretch -= 1;
                }
                // Deliveries are 0-indexed; series is one longer. The stretch
                // runs from the first behind-state up to the ball that levelled.
                (TurningKind::Comeback, (start_of_stretch - 1)..(last + 1).min(n))
            }
            None => (TurningKind::Decider, 0..n),
        };

        let best = range
            .filter(|&i| swing(i) > 0.0)
            .max_by(|&a, &b| swing(a).total_cmp(&swing(b)))?;
        if swing(best) < MIN_SWING {
            return None;
        }

        let d = &chase.deliveries[best];
        // Totals after the ball, for "needed from how many".
        let (mut r, mut l) = (0i32, 0u16);
        for x in &chase.deliveries[..=best] {
            r += x.runs as i32;
            l += x.is_legal as u16;
        }
        Some(TurningPoint {
            side: winner,
            kind,
            innings: chase.index,
            over: format!("{}.{}", d.over, d.ball_in_over.max(1)),
            label: d.label.clone(),
            runs: d.runs,
            is_wicket: d.is_wicket,
            batter_id: d.batter_id,
            bowler_id: d.bowler_id,
            before_percent: percent(series[best]),
            after_percent: percent(series[best + 1]),
            runs_needed: (target - r).max(0) as u16,
            balls_left: total_balls.saturating_sub(l),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ball(runs: u8, wicket: bool) -> DeliveryRecord {
        DeliveryRecord {
            over: 0,
            ball_in_over: 0,
            label: if wicket { "W".into() } else { runs.to_string() },
            runs,
            is_legal: true,
            is_wicket: wicket,
            batter_id: None,
            bowler_id: None,
            shot: None,
        }
    }

    /// A twenty-over game: `first` batted first for Home, and the chase is
    /// whatever `balls` say, with over numbers filled in as the engine would.
    fn game(first: u16, balls: Vec<DeliveryRecord>, winner: MatchSide) -> MatchState {
        let mut chase_balls = balls;
        for (i, b) in chase_balls.iter_mut().enumerate() {
            b.over = (i / 6) as u16;
            b.ball_in_over = (i % 6) as u8 + 1;
        }
        let runs = chase_balls.iter().map(|b| b.runs as u16).sum();
        let wickets = chase_balls.iter().filter(|b| b.is_wicket).count() as u8;
        let legal = chase_balls.len() as u16;
        MatchState {
            status: MatchStatus::Complete,
            winner: Some(winner),
            overs_limit: 20,
            target: Some(first + 1),
            innings: vec![
                InningsState {
                    index: 0,
                    batting: MatchSide::Home,
                    bowling: MatchSide::Away,
                    runs: first,
                    legal_balls: 120,
                    complete: true,
                    ..InningsState::default()
                },
                InningsState {
                    index: 1,
                    batting: MatchSide::Away,
                    bowling: MatchSide::Home,
                    runs,
                    wickets,
                    legal_balls: legal,
                    deliveries: chase_balls,
                    complete: true,
                    ..InningsState::default()
                },
            ],
            ..MatchState::default()
        }
    }

    /// Five down for next to nothing, then sixes: the chasers were dead and
    /// are not. The turning ball has to be in the hitting, not the collapse.
    #[test]
    fn a_comeback_turns_on_the_hitting_that_started_it() {
        let mut balls: Vec<_> = (0..30).map(|i| ball(0, i % 6 == 5)).collect(); // 0-5
        balls.extend((0..17).map(|_| ball(6, false))); // 102
        let state = game(100, balls, MatchSide::Away);

        let tp = state.turning_point().expect("it was won from nowhere");
        assert_eq!(tp.kind, TurningKind::Comeback);
        assert_eq!(tp.side, MatchSide::Away);
        assert!(tp.after_percent > tp.before_percent);
        assert!(!tp.is_wicket, "the turn was a six, not a wicket");
        assert_eq!(tp.label, "6");
        assert!(tp.after_percent >= 50 || tp.runs_needed > 0);
    }

    /// The same shape the other way: the chasers cruise, then lose five for
    /// nothing. The turn belongs to the side that defended, and it is a wicket.
    #[test]
    fn a_collapse_turns_for_the_defenders_on_a_wicket() {
        // 80 off 60 with nobody out: needing 71 off 60 is a coin toss, which is
        // what makes the next ball matter. Then five wickets in five balls.
        let mut balls: Vec<_> = (0..40).map(|_| ball(2, false)).collect();
        balls.extend((0..20).map(|_| ball(0, false)));
        balls.extend((0..5).map(|_| ball(0, true)));
        balls.extend((0..35).map(|_| ball(0, false)));
        let state = game(150, balls, MatchSide::Home);

        let tp = state.turning_point().expect("the defenders came back");
        assert_eq!(tp.side, MatchSide::Home);
        assert_eq!(tp.kind, TurningKind::Comeback);
        assert!(tp.is_wicket);
        assert!(tp.after_percent > tp.before_percent);
    }

    /// Winners who were never behind have a decider, not a comeback.
    #[test]
    fn a_cruise_has_a_decider_not_a_comeback() {
        let mut balls: Vec<_> = (0..30).map(|_| ball(2, false)).collect(); // 60 off 30
        balls.extend((0..10).map(|_| ball(6, false))); // 120 off 40
        balls.extend((0..20).map(|_| ball(2, false))); // 160 off 60 > 151
        let state = game(150, balls, MatchSide::Away);

        if let Some(tp) = state.turning_point() {
            assert_eq!(tp.kind, TurningKind::Decider);
            assert_eq!(tp.side, MatchSide::Away);
        }
    }

    #[test]
    fn nothing_without_a_winner() {
        let mut state = game(100, vec![ball(6, false); 10], MatchSide::Away);
        state.winner = None;
        assert!(state.turning_point().is_none(), "a tie or no result has no winning side");
    }

    #[test]
    fn nothing_without_a_chase() {
        let mut state = game(100, vec![ball(6, false); 10], MatchSide::Away);
        state.innings.truncate(1);
        assert!(state.turning_point().is_none());
        assert!(MatchState::default().turning_point().is_none());
    }

    #[test]
    fn the_chance_is_monotone_in_what_is_needed() {
        let t = ResourceTable::default();
        let start = t.resource(20.0, 0);
        let easy = chase_chance(&t, 150.0, start, 20, 60, 2, 10);
        let hard = chase_chance(&t, 150.0, start, 90, 60, 2, 10);
        assert!(easy > 0.5 && hard < 0.5 && easy > hard);
        assert_eq!(chase_chance(&t, 150.0, start, 0, 0, 10, 10), 1.0, "nothing needed is won");
        assert_eq!(chase_chance(&t, 150.0, start, 5, 0, 3, 10), 0.0, "no balls left is lost");
    }
}
