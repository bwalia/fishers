//! Pure cricket scoring engine — apply events, support undo.

use uuid::Uuid;

use super::types::*;
use crate::DomainError;

type Result<T> = std::result::Result<T, DomainError>;

impl MatchState {
    fn push_history(&mut self) {
        self.history.push(MatchStateSnapshot {
            status: self.status,
            innings: self.innings.clone(),
            target: self.target,
            winner: self.winner,
            margin: self.margin.clone(),
        });
        // Cap history depth for memory.
        if self.history.len() > 200 {
            self.history.remove(0);
        }
    }

    fn restore_history(&mut self) -> Result<()> {
        let snap = self
            .history
            .pop()
            .ok_or_else(|| DomainError::Validation("nothing to undo".into()))?;
        self.status = snap.status;
        self.innings = snap.innings;
        self.target = snap.target;
        self.winner = snap.winner;
        self.margin = snap.margin;
        Ok(())
    }

    /// Apply one scoring event. Updates `last_seq` to `event.seq`.
    pub fn apply(&mut self, event: &ScoringEvent) -> Result<()> {
        if event.seq != self.last_seq + 1 && !(self.last_seq == 0 && event.seq == 1) {
            // Allow seq 1 on fresh state; otherwise require monotonic.
            if event.seq <= self.last_seq {
                return Ok(()); // idempotent skip
            }
            if event.seq != self.last_seq + 1 {
                return Err(DomainError::Conflict(format!(
                    "expected seq {}, got {}",
                    self.last_seq + 1,
                    event.seq
                )));
            }
        }

        match &event.kind {
            ScoringEventKind::UndoLast => {
                self.restore_history()?;
                self.last_seq = event.seq;
                return Ok(());
            }
            _ => self.push_history(),
        }

        match &event.kind {
            ScoringEventKind::MatchPrepared {
                overs_limit,
                home_name,
                away_name,
            } => {
                self.overs_limit = *overs_limit;
                self.home_name = home_name.clone();
                self.away_name = away_name.clone();
                self.status = MatchStatus::Preparing;
            }
            ScoringEventKind::TossRecorded { winner, decision } => {
                self.toss_winner = Some(*winner);
                self.toss_decision = Some(*decision);
                self.status = MatchStatus::SelectingXi;
            }
            ScoringEventKind::XiSelected {
                side,
                player_ids,
                captain_id,
                keeper_id,
            } => {
                if player_ids.len() != 11 {
                    return Err(DomainError::Validation("playing XI must be 11".into()));
                }
                match side {
                    MatchSide::Home => {
                        self.home_xi = player_ids.clone();
                        self.home_captain = *captain_id;
                        self.home_keeper = *keeper_id;
                    }
                    MatchSide::Away => {
                        self.away_xi = player_ids.clone();
                        self.away_captain = *captain_id;
                        self.away_keeper = *keeper_id;
                    }
                }
                if self.home_xi.len() == 11 && self.away_xi.len() == 11 {
                    self.status = MatchStatus::Ready;
                }
            }
            ScoringEventKind::InningsStarted {
                innings_index,
                batting,
                striker_id,
                non_striker_id,
                bowler_id,
            } => {
                let bowling = match batting {
                    MatchSide::Home => MatchSide::Away,
                    MatchSide::Away => MatchSide::Home,
                };
                let batting_xi = match batting {
                    MatchSide::Home => &self.home_xi,
                    MatchSide::Away => &self.away_xi,
                };
                let mut batters: Vec<BatterStats> = batting_xi
                    .iter()
                    .map(|id| BatterStats::new(*id))
                    .collect();
                for id in [*striker_id, *non_striker_id] {
                    if !batters.iter().any(|b| b.player_id == id) {
                        batters.push(BatterStats::new(id));
                    }
                }
                let mut inn = InningsState {
                    index: *innings_index,
                    batting: *batting,
                    bowling,
                    batters,
                    striker_id: Some(*striker_id),
                    non_striker_id: Some(*non_striker_id),
                    bowler_id: Some(*bowler_id),
                    ..Default::default()
                };
                inn.ensure_bowler(*bowler_id);
                self.innings.push(inn);
                self.status = MatchStatus::Live;
                if *innings_index == 1 {
                    if let Some(first) = self.innings.first() {
                        self.target = Some(first.runs + 1);
                    }
                }
            }
            ScoringEventKind::DeliveryRecorded {
                runs,
                is_legal,
                is_boundary_four,
                is_boundary_six,
            } => {
                self.apply_delivery(*runs, *is_legal, *is_boundary_four, *is_boundary_six, false)?;
            }
            ScoringEventKind::ExtrasRecorded { kind, runs } => {
                self.apply_extras(*kind, *runs)?;
            }
            ScoringEventKind::WicketRecorded {
                batter_id,
                kind,
                fielder_id: _,
                new_batter_id,
            } => {
                self.apply_wicket(*batter_id, *kind, *new_batter_id)?;
            }
            ScoringEventKind::BowlerChanged { bowler_id } => {
                let inn = self
                    .current_innings_mut()
                    .ok_or_else(|| DomainError::Validation("no innings".into()))?;
                inn.ensure_bowler(*bowler_id);
                inn.bowler_id = Some(*bowler_id);
                inn.balls_in_current_over = 0;
            }
            ScoringEventKind::InningsCompleted => {
                self.complete_innings()?;
            }
            ScoringEventKind::MatchCompleted { winner, margin } => {
                self.winner = *winner;
                self.margin = Some(margin.clone());
                self.status = MatchStatus::Complete;
            }
            ScoringEventKind::UndoLast => unreachable!(),
        }

        self.last_seq = event.seq;
        self.check_auto_complete()?;
        Ok(())
    }

    fn apply_delivery(
        &mut self,
        runs: u8,
        is_legal: bool,
        four: bool,
        six: bool,
        from_extra_bat: bool,
    ) -> Result<()> {
        let overs_limit = self.overs_limit;
        let inn = self
            .current_innings_mut()
            .ok_or_else(|| DomainError::Validation("no live innings".into()))?;
        if inn.complete {
            return Err(DomainError::Validation("innings complete".into()));
        }
        let striker = inn
            .striker_id
            .ok_or_else(|| DomainError::Validation("no striker".into()))?;
        let bowler = inn
            .bowler_id
            .ok_or_else(|| DomainError::Validation("no bowler".into()))?;

        inn.runs += runs as u16;
        if !from_extra_bat {
            // bat runs
        }
        {
            let b = inn.batter_mut(striker)?;
            b.runs += runs as u16;
            if is_legal {
                b.balls += 1;
            }
            if four {
                b.fours += 1;
            }
            if six {
                b.sixes += 1;
            }
        }
        {
            let bowl = inn.bowler_mut(bowler)?;
            bowl.runs += runs as u16;
            bowl.current_over_runs += runs as u16;
            if is_legal {
                bowl.balls += 1;
            }
        }

        let label = if six {
            "SIX".into()
        } else if four {
            "FOUR".into()
        } else if runs == 0 {
            "0".into()
        } else {
            format!("{runs}")
        };
        let over = inn.legal_balls / 6;
        let ball_in = inn.balls_in_current_over + if is_legal { 1 } else { 0 };
        inn.deliveries.push(DeliveryRecord {
            over,
            ball_in_over: ball_in,
            label,
            runs,
            is_legal,
            is_wicket: false,
        });

        if is_legal {
            inn.legal_balls += 1;
            inn.balls_in_current_over += 1;
            if runs % 2 == 1 {
                inn.swap_strike();
            }
            if inn.balls_in_current_over >= 6 {
                // Complete over — maiden?
                if let Some(bowl) = inn.bowlers.iter_mut().find(|b| b.player_id == bowler) {
                    if bowl.current_over_runs == 0 {
                        bowl.maidens += 1;
                    }
                    bowl.current_over_runs = 0;
                }
                inn.balls_in_current_over = 0;
                inn.swap_strike();
            }
        }

        let balls_cap = (overs_limit as u16) * 6;
        if inn.legal_balls >= balls_cap || inn.wickets >= 10 {
            inn.complete = true;
        }
        Ok(())
    }

    fn apply_extras(&mut self, kind: ExtraKind, runs: u8) -> Result<()> {
        let inn = self
            .current_innings_mut()
            .ok_or_else(|| DomainError::Validation("no live innings".into()))?;
        let bowler = inn
            .bowler_id
            .ok_or_else(|| DomainError::Validation("no bowler".into()))?;
        let striker = inn
            .striker_id
            .ok_or_else(|| DomainError::Validation("no striker".into()))?;

        let (team_runs, legal, bat_runs, bowl_runs) = match kind {
            ExtraKind::Wide => (runs.max(1), false, 0, runs.max(1)),
            ExtraKind::NoBall => (runs.max(1), false, runs.saturating_sub(1), runs.max(1)),
            ExtraKind::Bye | ExtraKind::LegBye => (runs, true, 0, 0),
            ExtraKind::Penalty => (runs, false, 0, 0),
        };

        inn.runs += team_runs as u16;
        inn.extras += team_runs as u16;

        if bat_runs > 0 {
            let b = inn.batter_mut(striker)?;
            b.runs += bat_runs as u16;
            // no-ball + runs off bat: ball faced? typically yes for off-bat
            b.balls += 1;
        }

        {
            let bowl = inn.bowler_mut(bowler)?;
            bowl.runs += bowl_runs as u16;
            bowl.current_over_runs += bowl_runs as u16;
            if legal {
                bowl.balls += 1;
            }
        }

        let label = format!("{:?} {team_runs}", kind);
        let over = inn.legal_balls / 6;
        inn.deliveries.push(DeliveryRecord {
            over,
            ball_in_over: inn.balls_in_current_over + if legal { 1 } else { 0 },
            label,
            runs: team_runs,
            is_legal: legal,
            is_wicket: false,
        });

        if legal {
            inn.legal_balls += 1;
            inn.balls_in_current_over += 1;
            // byes/leg-byes: odd runs rotate strike
            if matches!(kind, ExtraKind::Bye | ExtraKind::LegBye) && runs % 2 == 1 {
                inn.swap_strike();
            }
            if inn.balls_in_current_over >= 6 {
                if let Some(bowl) = inn.bowlers.iter_mut().find(|b| b.player_id == bowler) {
                    if bowl.current_over_runs == 0 {
                        bowl.maidens += 1;
                    }
                    bowl.current_over_runs = 0;
                }
                inn.balls_in_current_over = 0;
                inn.swap_strike();
            }
        } else if matches!(kind, ExtraKind::Wide | ExtraKind::NoBall)
            && bat_runs == 0
            && team_runs > 1
            && (team_runs - 1) % 2 == 1
        {
            // additional runs on wide/no-ball from running — rotate
            inn.swap_strike();
        }

        Ok(())
    }

    fn apply_wicket(
        &mut self,
        batter_id: Uuid,
        kind: DismissalKind,
        new_batter_id: Option<Uuid>,
    ) -> Result<()> {
        let overs_limit = self.overs_limit;
        let inn = self
            .current_innings_mut()
            .ok_or_else(|| DomainError::Validation("no live innings".into()))?;
        let bowler = inn.bowler_id;

        // Legal ball for most dismissals except some run-outs on free hit — simplify: legal.
        let is_legal = !matches!(kind, DismissalKind::Retired);
        {
            let b = inn.batter_mut(batter_id)?;
            b.out = true;
            b.dismissal = Some(kind);
            if is_legal {
                b.balls += 1;
            }
        }
        inn.wickets += 1;
        if is_legal {
            inn.legal_balls += 1;
            inn.balls_in_current_over += 1;
            if let Some(bid) = bowler {
                if matches!(
                    kind,
                    DismissalKind::Bowled
                        | DismissalKind::Caught
                        | DismissalKind::Lbw
                        | DismissalKind::Stumped
                        | DismissalKind::HitWicket
                ) {
                    let bowl = inn.bowler_mut(bid)?;
                    bowl.wickets += 1;
                    bowl.balls += 1;
                } else if let Ok(bowl) = inn.bowler_mut(bid) {
                    bowl.balls += 1;
                }
            }
        }

        let score = inn.runs;
        let wickets = inn.wickets;
        let over_ball = MatchState::overs_balls_display(inn.legal_balls);
        inn.fall.push(FallOfWicket {
            score,
            wickets,
            batter_id,
            over_ball,
        });
        inn.deliveries.push(DeliveryRecord {
            over: inn.legal_balls.saturating_sub(1) / 6,
            ball_in_over: inn.balls_in_current_over,
            label: "WICKET".into(),
            runs: 0,
            is_legal,
            is_wicket: true,
        });

        if inn.wickets >= 10
            || inn.legal_balls >= (overs_limit as u16) * 6
        {
            inn.complete = true;
            return Ok(());
        }

        let new_id = new_batter_id
            .ok_or_else(|| DomainError::Validation("new batter required".into()))?;
        if !inn.batters.iter().any(|b| b.player_id == new_id) {
            inn.batters.push(BatterStats::new(new_id));
        }
        if inn.striker_id == Some(batter_id) {
            inn.striker_id = Some(new_id);
        } else {
            inn.non_striker_id = Some(new_id);
        }

        if inn.balls_in_current_over >= 6 {
            if let Some(bid) = bowler {
                if let Some(bowl) = inn.bowlers.iter_mut().find(|b| b.player_id == bid) {
                    if bowl.current_over_runs == 0 {
                        bowl.maidens += 1;
                    }
                    bowl.current_over_runs = 0;
                }
            }
            inn.balls_in_current_over = 0;
            inn.swap_strike();
        }
        Ok(())
    }

    fn complete_innings(&mut self) -> Result<()> {
        let inn = self
            .current_innings_mut()
            .ok_or_else(|| DomainError::Validation("no innings".into()))?;
        inn.complete = true;
        let idx = inn.index;
        let runs = inn.runs;
        if idx == 0 {
            self.target = Some(runs + 1);
            self.status = MatchStatus::InningsBreak;
        } else {
            self.status = MatchStatus::Complete;
            self.finish_result();
        }
        Ok(())
    }

    fn check_auto_complete(&mut self) -> Result<()> {
        let Some(inn) = self.current_innings() else {
            return Ok(());
        };
        if !inn.complete {
            // chase target
            if inn.index >= 1 {
                if let Some(target) = self.target {
                    if inn.runs >= target {
                        let inn = self.current_innings_mut().unwrap();
                        inn.complete = true;
                        self.status = MatchStatus::Complete;
                        self.finish_result();
                    }
                }
            }
            return Ok(());
        }
        if inn.index == 0 && self.status == MatchStatus::Live {
            self.target = Some(inn.runs + 1);
            self.status = MatchStatus::InningsBreak;
        }
        Ok(())
    }

    fn finish_result(&mut self) {
        if self.innings.len() < 2 {
            return;
        }
        let a = &self.innings[0];
        let b = &self.innings[1];
        if b.runs > a.runs {
            self.winner = Some(b.batting);
            let wkts = 10u8.saturating_sub(b.wickets);
            self.margin = Some(format!("won by {wkts} wickets"));
        } else if b.runs < a.runs {
            self.winner = Some(a.batting);
            let runs = a.runs - b.runs;
            self.margin = Some(format!("won by {runs} runs"));
        } else {
            self.winner = None;
            self.margin = Some("tied".into());
        }
    }
}

impl InningsState {
    fn swap_strike(&mut self) {
        std::mem::swap(&mut self.striker_id, &mut self.non_striker_id);
    }

    fn ensure_bowler(&mut self, id: Uuid) {
        if !self.bowlers.iter().any(|b| b.player_id == id) {
            self.bowlers.push(BowlerStats::new(id));
        }
    }

    fn batter_mut(&mut self, id: Uuid) -> Result<&mut BatterStats> {
        self.batters
            .iter_mut()
            .find(|b| b.player_id == id)
            .ok_or_else(|| DomainError::Validation("batter not in innings".into()))
    }

    fn bowler_mut(&mut self, id: Uuid) -> Result<&mut BowlerStats> {
        self.ensure_bowler(id);
        self.bowlers
            .iter_mut()
            .find(|b| b.player_id == id)
            .ok_or_else(|| DomainError::Validation("bowler missing".into()))
    }
}

/// Helper to build a sequenced event.
pub fn evt(seq: i64, kind: ScoringEventKind) -> ScoringEvent {
    ScoringEvent {
        client_event_id: Uuid::new_v4(),
        seq,
        kind,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn xi() -> Vec<Uuid> {
        (0..11).map(|_| Uuid::new_v4()).collect()
    }

    #[test]
    fn four_updates_score_and_batter() {
        let mut m = MatchState::default();
        let home = xi();
        let away = xi();
        m.apply(&evt(
            1,
            ScoringEventKind::MatchPrepared {
                overs_limit: 20,
                home_name: "A".into(),
                away_name: "B".into(),
            },
        ))
        .unwrap();
        m.apply(&evt(
            2,
            ScoringEventKind::TossRecorded {
                winner: MatchSide::Home,
                decision: TossDecision::Bat,
            },
        ))
        .unwrap();
        m.apply(&evt(
            3,
            ScoringEventKind::XiSelected {
                side: MatchSide::Home,
                player_ids: home.clone(),
                captain_id: Some(home[0]),
                keeper_id: Some(home[1]),
            },
        ))
        .unwrap();
        m.apply(&evt(
            4,
            ScoringEventKind::XiSelected {
                side: MatchSide::Away,
                player_ids: away.clone(),
                captain_id: Some(away[0]),
                keeper_id: None,
            },
        ))
        .unwrap();
        m.apply(&evt(
            5,
            ScoringEventKind::InningsStarted {
                innings_index: 0,
                batting: MatchSide::Home,
                striker_id: home[0],
                non_striker_id: home[1],
                bowler_id: away[0],
            },
        ))
        .unwrap();
        m.apply(&evt(
            6,
            ScoringEventKind::DeliveryRecorded {
                runs: 4,
                is_legal: true,
                is_boundary_four: true,
                is_boundary_six: false,
            },
        ))
        .unwrap();
        let inn = m.current_innings().unwrap();
        assert_eq!(inn.runs, 4);
        assert_eq!(inn.legal_balls, 1);
        let batter = inn.batters.iter().find(|b| b.player_id == home[0]).unwrap();
        assert_eq!(batter.runs, 4);
        assert_eq!(batter.fours, 1);
    }

    #[test]
    fn undo_reverts_last_delivery() {
        let mut m = MatchState::default();
        let home = xi();
        let away = xi();
        for (seq, kind) in [
            (
                1,
                ScoringEventKind::MatchPrepared {
                    overs_limit: 5,
                    home_name: "H".into(),
                    away_name: "A".into(),
                },
            ),
            (
                2,
                ScoringEventKind::TossRecorded {
                    winner: MatchSide::Home,
                    decision: TossDecision::Bat,
                },
            ),
            (
                3,
                ScoringEventKind::XiSelected {
                    side: MatchSide::Home,
                    player_ids: home.clone(),
                    captain_id: None,
                    keeper_id: None,
                },
            ),
            (
                4,
                ScoringEventKind::XiSelected {
                    side: MatchSide::Away,
                    player_ids: away.clone(),
                    captain_id: None,
                    keeper_id: None,
                },
            ),
            (
                5,
                ScoringEventKind::InningsStarted {
                    innings_index: 0,
                    batting: MatchSide::Home,
                    striker_id: home[0],
                    non_striker_id: home[1],
                    bowler_id: away[0],
                },
            ),
            (
                6,
                ScoringEventKind::DeliveryRecorded {
                    runs: 6,
                    is_legal: true,
                    is_boundary_four: false,
                    is_boundary_six: true,
                },
            ),
        ] {
            m.apply(&evt(seq, kind)).unwrap();
        }
        assert_eq!(m.current_innings().unwrap().runs, 6);
        m.apply(&evt(7, ScoringEventKind::UndoLast)).unwrap();
        assert_eq!(m.current_innings().unwrap().runs, 0);
    }

    #[test]
    fn odd_run_rotates_strike() {
        let mut m = MatchState::default();
        let home = xi();
        let away = xi();
        m.apply(&evt(
            1,
            ScoringEventKind::MatchPrepared {
                overs_limit: 20,
                home_name: "H".into(),
                away_name: "A".into(),
            },
        ))
        .unwrap();
        m.apply(&evt(
            2,
            ScoringEventKind::TossRecorded {
                winner: MatchSide::Home,
                decision: TossDecision::Bat,
            },
        ))
        .unwrap();
        m.apply(&evt(
            3,
            ScoringEventKind::XiSelected {
                side: MatchSide::Home,
                player_ids: home.clone(),
                captain_id: None,
                keeper_id: None,
            },
        ))
        .unwrap();
        m.apply(&evt(
            4,
            ScoringEventKind::XiSelected {
                side: MatchSide::Away,
                player_ids: away.clone(),
                captain_id: None,
                keeper_id: None,
            },
        ))
        .unwrap();
        m.apply(&evt(
            5,
            ScoringEventKind::InningsStarted {
                innings_index: 0,
                batting: MatchSide::Home,
                striker_id: home[0],
                non_striker_id: home[1],
                bowler_id: away[0],
            },
        ))
        .unwrap();
        m.apply(&evt(
            6,
            ScoringEventKind::DeliveryRecorded {
                runs: 1,
                is_legal: true,
                is_boundary_four: false,
                is_boundary_six: false,
            },
        ))
        .unwrap();
        assert_eq!(m.current_innings().unwrap().striker_id, Some(home[1]));
    }
}
