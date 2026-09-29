//! What the two sides actually did, side by side.
//!
//! The scorecard says who scored what. This says where the game was won: who
//! left more dot balls, who cashed in during the powerplay, whose middle order
//! held. Every figure is read back off the ball-by-ball log, so nothing here
//! has to be recorded separately by a scorer who already has enough to do.

use serde::{Deserialize, Serialize};

use super::types::*;

/// Runs and wickets in one stretch of an innings.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhaseScore {
    /// "Powerplay", "Middle", "Death".
    pub name: String,
    /// The overs it covers, as a scorer would say them: "1-6".
    pub overs: String,
    pub runs: u16,
    pub wickets: u8,
    pub balls: u16,
}

impl PhaseScore {
    pub fn run_rate(&self) -> f64 {
        if self.balls == 0 {
            return 0.0;
        }
        (self.runs as f64) * 6.0 / (self.balls as f64)
    }
}

/// One side's innings, totalled every way a post-match chat asks about.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SideInsights {
    pub side: MatchSide,
    pub name: String,
    pub runs: u16,
    pub wickets: u8,
    pub balls: u16,
    /// "19.4"
    pub overs: String,
    pub run_rate: f64,
    /// Legal deliveries that went for nothing. A wicket off a dot is still a
    /// dot — the batting side got no runs from it either way.
    pub dots: u16,
    pub dot_percent: f64,
    pub fours: u16,
    pub sixes: u16,
    pub boundary_runs: u16,
    /// How much of the total came in fours and sixes rather than in ones.
    pub boundary_percent: f64,
    pub extras: u16,
    /// Powerplay, middle, death — whichever of them this innings was long
    /// enough to have.
    pub phases: Vec<PhaseScore>,
    /// Runs by where they came in: 1-3, 4-7, and 8 down.
    pub top_order: u16,
    pub middle_order: u16,
    pub lower_order: u16,
    /// The biggest stand of the innings, broken or not.
    pub best_partnership: u16,
}

/// Both sides, for the comparison.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchInsights {
    pub home: SideInsights,
    pub away: SideInsights,
}

/// Where one innings divides. Returned as 0-indexed over ranges.
///
/// The powerplay is whatever was agreed. The death is the last fifth, which
/// gives four overs of a twenty and ten of a fifty — what everyone already
/// calls it. Anything shorter than ten overs is all one passage of play and
/// gets no phases at all.
fn phase_ranges(inn: &InningsState) -> Vec<(&'static str, u16, u16)> {
    let total = if inn.overs_available > 0 {
        inn.overs_available as u16
    } else {
        inn.legal_balls.div_ceil(6)
    };
    if total < 10 {
        return Vec::new();
    }
    let powerplay = (inn.powerplay_overs as u16).min(total);
    let death_len = (total / 5).max(1);
    let death_start = total.saturating_sub(death_len).max(powerplay);

    let mut out = Vec::new();
    if powerplay > 0 {
        out.push(("Powerplay", 0, powerplay));
    }
    if death_start > powerplay {
        out.push(("Middle", powerplay, death_start));
    }
    if total > death_start {
        out.push(("Death", death_start, total));
    }
    out
}

impl MatchState {
    /// Both sides totalled up, or `None` before the second innings has begun —
    /// there is nothing to compare a side with until someone has replied.
    pub fn insights(&self) -> Option<MatchInsights> {
        let home = self.side_insights(MatchSide::Home)?;
        let away = self.side_insights(MatchSide::Away)?;
        Some(MatchInsights { home, away })
    }

    /// One side's batting, across every innings they batted that was not a
    /// super over — one over of a tie-break belongs in nobody's powerplay.
    pub fn side_insights(&self, side: MatchSide) -> Option<SideInsights> {
        let innings: Vec<&InningsState> = self
            .innings
            .iter()
            .filter(|inn| inn.batting == side && !inn.super_over)
            .collect();
        if innings.is_empty() {
            return None;
        }

        let mut out = SideInsights {
            side,
            name: self.side_name(side).to_string(),
            runs: 0,
            wickets: 0,
            balls: 0,
            overs: String::new(),
            run_rate: 0.0,
            dots: 0,
            dot_percent: 0.0,
            fours: 0,
            sixes: 0,
            boundary_runs: 0,
            boundary_percent: 0.0,
            extras: 0,
            phases: Vec::new(),
            top_order: 0,
            middle_order: 0,
            lower_order: 0,
            best_partnership: 0,
        };

        for inn in &innings {
            out.runs += inn.runs;
            out.wickets += inn.wickets;
            out.balls += inn.legal_balls;
            out.extras += inn.extras;
            out.dots += inn
                .deliveries
                .iter()
                .filter(|d| d.is_legal && d.runs == 0)
                .count() as u16;

            for (position, bat) in inn.batters.iter().enumerate() {
                out.fours += bat.fours;
                out.sixes += bat.sixes;
                match position {
                    0..=2 => out.top_order += bat.runs,
                    3..=6 => out.middle_order += bat.runs,
                    _ => out.lower_order += bat.runs,
                }
            }

            // Every stand that ended, plus the one that never did.
            let broken = inn.fall.iter().map(|f| f.partnership_runs).max().unwrap_or(0);
            out.best_partnership = out
                .best_partnership
                .max(broken)
                .max(inn.partnership_runs);

            for (name, from, to) in phase_ranges(inn) {
                let balls = inn
                    .deliveries
                    .iter()
                    .filter(|d| d.is_legal && d.over >= from && d.over < to)
                    .count() as u16;
                let runs: u16 = inn
                    .deliveries
                    .iter()
                    .filter(|d| d.over >= from && d.over < to)
                    .map(|d| d.runs as u16)
                    .sum();
                let wickets = inn
                    .deliveries
                    .iter()
                    .filter(|d| d.is_wicket && d.over >= from && d.over < to)
                    .count() as u8;
                // A side bowled out in the eighth over of a twenty never
                // reached the death. Saying "Death 0/0" invites the reader to
                // work out why; leaving the row out says it already.
                if balls > 0 || runs > 0 {
                    out.phases.push(PhaseScore {
                        name: name.to_string(),
                        overs: format!("{}-{}", from + 1, to),
                        runs,
                        wickets,
                        balls,
                    });
                }
            }
        }

        out.overs = MatchState::overs_balls_display(out.balls);
        out.boundary_runs = out.fours * 4 + out.sixes * 6;
        if out.balls > 0 {
            out.run_rate = (out.runs as f64) * 6.0 / (out.balls as f64);
            out.dot_percent = (out.dots as f64) * 100.0 / (out.balls as f64);
        }
        if out.runs > 0 {
            out.boundary_percent = (out.boundary_runs as f64) * 100.0 / (out.runs as f64);
        }
        Some(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn ball(over: u16, runs: u8) -> DeliveryRecord {
        DeliveryRecord {
            over,
            ball_in_over: 1,
            label: runs.to_string(),
            runs,
            is_legal: true,
            is_wicket: false,
            batter_id: None,
            bowler_id: None,
            shot: None,
        }
    }

    fn wicket(over: u16) -> DeliveryRecord {
        DeliveryRecord { is_wicket: true, label: "W".into(), ..ball(over, 0) }
    }

    fn bat(runs: u16, fours: u16, sixes: u16) -> BatterStats {
        BatterStats { runs, fours, sixes, balls: runs.max(1), ..BatterStats::new(Uuid::new_v4()) }
    }

    /// A twenty-over innings: `per_over` runs off every ball of every over.
    fn innings(overs: u8, powerplay: u8, per_over: u8) -> InningsState {
        let mut deliveries = Vec::new();
        for over in 0..overs as u16 {
            for _ in 0..6 {
                deliveries.push(ball(over, per_over));
            }
        }
        let runs = (overs as u16) * 6 * (per_over as u16);
        InningsState {
            batting: MatchSide::Home,
            bowling: MatchSide::Away,
            runs,
            legal_balls: (overs as u16) * 6,
            overs_available: overs,
            powerplay_overs: powerplay,
            deliveries,
            complete: true,
            ..InningsState::default()
        }
    }

    fn state_with(home: InningsState) -> MatchState {
        let mut away = InningsState { batting: MatchSide::Away, bowling: MatchSide::Home, ..home.clone() };
        away.deliveries = vec![];
        MatchState { innings: vec![home, away], ..MatchState::default() }
    }

    #[test]
    fn dots_come_off_the_ball_log() {
        let mut inn = innings(10, 2, 1);
        // Turn the first over into maidens' worth of nothing.
        for d in inn.deliveries.iter_mut().take(6) {
            d.runs = 0;
        }
        inn.runs -= 6;
        let side = state_with(inn).side_insights(MatchSide::Home).unwrap();
        assert_eq!(side.dots, 6);
        assert_eq!(side.balls, 60);
        assert_eq!(side.dot_percent, 10.0);
    }

    #[test]
    fn a_wicket_off_a_dot_is_still_a_dot() {
        let mut inn = innings(10, 2, 1);
        inn.deliveries[0] = wicket(0);
        inn.runs -= 1;
        let side = state_with(inn).side_insights(MatchSide::Home).unwrap();
        assert_eq!(side.dots, 1, "the batting side got nothing from it either way");
    }

    #[test]
    fn phases_split_the_innings_where_a_scorer_would() {
        let side = state_with(innings(20, 6, 1)).side_insights(MatchSide::Home).unwrap();
        let named: Vec<(&str, &str)> = side
            .phases
            .iter()
            .map(|p| (p.name.as_str(), p.overs.as_str()))
            .collect();
        assert_eq!(
            named,
            vec![("Powerplay", "1-6"), ("Middle", "7-16"), ("Death", "17-20")]
        );
        // Every ball lands in exactly one phase.
        assert_eq!(side.phases.iter().map(|p| p.balls).sum::<u16>(), side.balls);
        assert_eq!(side.phases.iter().map(|p| p.runs).sum::<u16>(), side.runs);
    }

    #[test]
    fn a_fifty_over_innings_gets_a_ten_over_death() {
        let side = state_with(innings(50, 10, 1)).side_insights(MatchSide::Home).unwrap();
        let death = side.phases.last().unwrap();
        assert_eq!(death.name, "Death");
        assert_eq!(death.overs, "41-50");
    }

    #[test]
    fn a_short_game_is_all_one_passage_of_play() {
        let side = state_with(innings(8, 2, 1)).side_insights(MatchSide::Home).unwrap();
        assert!(side.phases.is_empty(), "eight overs has no middle to speak of");
    }

    #[test]
    fn runs_are_grouped_by_where_the_batter_came_in() {
        let mut inn = innings(20, 6, 0);
        inn.batters = vec![
            bat(10, 1, 0), bat(20, 2, 0), bat(30, 3, 0),   // 1-3
            bat(40, 0, 1), bat(1, 0, 0), bat(2, 0, 0), bat(3, 0, 0), // 4-7
            bat(5, 0, 1), bat(6, 0, 0),                     // 8-9
        ];
        let side = state_with(inn).side_insights(MatchSide::Home).unwrap();
        assert_eq!(side.top_order, 60);
        assert_eq!(side.middle_order, 46);
        assert_eq!(side.lower_order, 11);
        assert_eq!(side.fours, 6);
        assert_eq!(side.sixes, 2);
        assert_eq!(side.boundary_runs, 6 * 4 + 2 * 6);
    }

    #[test]
    fn the_best_stand_counts_the_one_that_never_ended() {
        let mut inn = innings(20, 6, 1);
        inn.fall = vec![FallOfWicket {
            score: 40, wickets: 1, batter_id: Uuid::new_v4(),
            over_ball: "5.2".into(), partnership_runs: 40, partnership_balls: 32,
        }];
        inn.partnership_runs = 75; // unbroken, and the bigger of the two
        let side = state_with(inn).side_insights(MatchSide::Home).unwrap();
        assert_eq!(side.best_partnership, 75);
    }

    #[test]
    fn an_innings_that_ended_early_has_no_death_overs() {
        // Twenty overs available, all out inside eight.
        let mut inn = innings(20, 6, 1);
        inn.deliveries.retain(|d| d.over < 8);
        inn.legal_balls = 48;
        inn.runs = 48;
        inn.wickets = 10;
        let side = state_with(inn).side_insights(MatchSide::Home).unwrap();
        let names: Vec<&str> = side.phases.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, vec!["Powerplay", "Middle"], "they never got to the death");
        assert_eq!(side.phases.iter().map(|p| p.balls).sum::<u16>(), side.balls);
    }

    #[test]
    fn a_side_that_never_batted_has_nothing_to_show() {
        let state = MatchState::default();
        assert!(state.insights().is_none());
    }
}
