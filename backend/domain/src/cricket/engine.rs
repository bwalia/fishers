//! Pure cricket scoring engine — apply events, support undo.
//!
//! The engine is a fold over the event log: `MatchState::default()` plus every
//! event in order is the whole truth. `history` is the undo stack, rebuilt by
//! that replay, which is why the server replays rather than restoring a
//! serialised snapshot — a snapshot cannot undo events it never applied.

use uuid::Uuid;

use super::types::*;
use crate::DomainError;

type Result<T> = std::result::Result<T, DomainError>;

/// Smallest and largest team sheet the engine accepts. Club cricket is not
/// always eleven a side.
const MIN_TEAM: usize = 2;
const MAX_TEAM: usize = 15;

impl MatchState {
    /// Rebuild state from an ordered event log. This is how the server derives
    /// state, so undo works identically on the device and on the API.
    pub fn replay(events: &[ScoringEvent]) -> Result<Self> {
        let mut state = Self::default();
        for event in events {
            state.apply(event)?;
        }
        Ok(state)
    }

    fn push_history(&mut self) {
        self.history.push(MatchStateSnapshot {
            status: self.status,
            innings: self.innings.clone(),
            target: self.target,
            winner: self.winner,
            margin: self.margin.clone(),
            player_of_the_match: self.player_of_the_match,
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
        self.player_of_the_match = snap.player_of_the_match;
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
                let overs = (*overs_limit).max(1);
                self.overs_limit = overs;
                self.conditions = MatchConditions::standard(overs);
                self.home_name = home_name.clone();
                self.away_name = away_name.clone();
                self.status = MatchStatus::Preparing;
            }
            ScoringEventKind::ConditionsProposed {
                conditions,
                by,
                by_name,
            } => {
                if conditions.overs_limit == 0 {
                    return Err(DomainError::Validation(
                        "a match needs at least one over".into(),
                    ));
                }
                if conditions.overs_per_bowler > conditions.overs_limit {
                    return Err(DomainError::Validation(
                        "a bowler cannot be allowed more overs than the innings has".into(),
                    ));
                }
                self.conditions = *conditions;
                self.overs_limit = conditions.overs_limit;
                self.conditions_proposed_by = Some(*by);
                // New terms need agreeing again, by both sides.
                self.agreed_home = None;
                self.agreed_away = None;
                // The proposer has, by proposing, agreed to their own terms.
                match by {
                    MatchSide::Home => self.agreed_home = Some(by_name.clone()),
                    MatchSide::Away => self.agreed_away = Some(by_name.clone()),
                }
                self.status = MatchStatus::Preparing;
            }
            ScoringEventKind::ConditionsAgreed { side, captain_name } => {
                if self.conditions_proposed_by.is_none() {
                    return Err(DomainError::Validation(
                        "there are no terms on the table to agree to".into(),
                    ));
                }
                match side {
                    MatchSide::Home => self.agreed_home = Some(captain_name.clone()),
                    MatchSide::Away => self.agreed_away = Some(captain_name.clone()),
                }
                if self.conditions_agreed() {
                    self.status = MatchStatus::Toss;
                }
            }
            ScoringEventKind::OfficialsAppointed { officials } => {
                for official in officials.umpires.iter().chain(officials.scorers.iter()) {
                    self.player_names
                        .insert(official.id, official.name.clone());
                }
                self.officials = officials.clone();
            }
            ScoringEventKind::PlayerOfTheMatch { player_id } => {
                self.player_of_the_match = Some(*player_id);
            }
            ScoringEventKind::BatterResumed {
                batter_id,
                replacing_id,
            } => {
                let inn = self
                    .current_innings_mut()
                    .ok_or_else(|| DomainError::Validation("no innings".into()))?;
                {
                    let batter = inn.batter_mut(*batter_id)?;
                    if !batter.can_resume() {
                        return Err(DomainError::Validation(
                            "only a batter who retired hurt can come back".into(),
                        ));
                    }
                    batter.retired_hurt = false;
                }
                match replacing_id {
                    Some(out_id) if inn.striker_id == Some(*out_id) => {
                        inn.striker_id = Some(*batter_id)
                    }
                    Some(out_id) if inn.non_striker_id == Some(*out_id) => {
                        inn.non_striker_id = Some(*batter_id)
                    }
                    _ => {
                        // Nobody named: take whichever end is empty.
                        if inn.striker_id.is_none() {
                            inn.striker_id = Some(*batter_id);
                        } else if inn.non_striker_id.is_none() {
                            inn.non_striker_id = Some(*batter_id);
                        } else {
                            return Err(DomainError::Validation(
                                "say which batter they are coming in for".into(),
                            ));
                        }
                    }
                }
            }
            ScoringEventKind::TossRecorded { winner, decision } => {
                if !self.conditions_agreed() {
                    return Err(DomainError::Validation(
                        "both captains have to agree the overs, ground and ball first".into(),
                    ));
                }
                self.toss_winner = Some(*winner);
                self.toss_decision = Some(*decision);
                self.status = MatchStatus::SelectingXi;
            }
            ScoringEventKind::XiSelected {
                side,
                players,
                captain_id,
                keeper_id,
            } => {
                if players.len() < MIN_TEAM || players.len() > MAX_TEAM {
                    return Err(DomainError::Validation(format!(
                        "a team sheet is {MIN_TEAM}–{MAX_TEAM} players, got {}",
                        players.len()
                    )));
                }
                let ids: Vec<Uuid> = players.iter().map(|p| p.id).collect();
                for player in players {
                    self.player_names.insert(player.id, player.name.clone());
                    if player.bats_left {
                        self.left_handers.insert(player.id);
                    } else {
                        self.left_handers.remove(&player.id);
                    }
                }
                match side {
                    MatchSide::Home => {
                        self.home_xi = ids;
                        self.home_captain = *captain_id;
                        self.home_keeper = *keeper_id;
                    }
                    MatchSide::Away => {
                        self.away_xi = ids;
                        self.away_captain = *captain_id;
                        self.away_keeper = *keeper_id;
                    }
                }
                if self.home_xi.len() >= MIN_TEAM && self.away_xi.len() >= MIN_TEAM {
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
                if striker_id == non_striker_id {
                    return Err(DomainError::Validation(
                        "the two openers must be different players".into(),
                    ));
                }
                let bowling = batting.opposite();
                let batting_xi = self.xi(*batting).to_vec();
                let mut batters: Vec<BatterStats> =
                    batting_xi.iter().map(|id| BatterStats::new(*id)).collect();
                for id in [*striker_id, *non_striker_id] {
                    if !batters.iter().any(|b| b.player_id == id) {
                        batters.push(BatterStats::new(id));
                    }
                }
                let wickets_allowed = (batters.len().saturating_sub(1)).clamp(1, 10) as u8;
                let mut inn = InningsState {
                    index: *innings_index,
                    batting: *batting,
                    bowling,
                    batters,
                    striker_id: Some(*striker_id),
                    non_striker_id: Some(*non_striker_id),
                    bowler_id: Some(*bowler_id),
                    wickets_allowed,
                    overs_available: self.conditions.overs_limit.max(self.overs_limit),
                    ..Default::default()
                };
                inn.ensure_bowler(*bowler_id);
                self.innings.push(inn);
                self.status = MatchStatus::Live;
                // The opening bowler counts against the allocation like any other.
                self.check_bowler_available(*bowler_id)?;
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
                shot,
            } => {
                self.apply_delivery(*runs, *is_legal, *is_boundary_four, *is_boundary_six, *shot)?;
            }
            ScoringEventKind::ExtrasRecorded {
                kind,
                runs,
                boundary,
                off_the_bat,
                shot,
            } => {
                self.apply_extras(*kind, *runs, *boundary, *off_the_bat, *shot)?;
            }
            ScoringEventKind::WicketRecorded {
                batter_id,
                kind,
                fielder_id,
                new_batter_id,
                runs,
                on_extra,
            } => {
                self.apply_wicket(
                    *batter_id,
                    *kind,
                    *fielder_id,
                    *new_batter_id,
                    *runs,
                    *on_extra,
                )?;
            }
            ScoringEventKind::OversRevised {
                innings_index,
                overs,
            } => {
                let overs = (*overs).max(1);
                let index = *innings_index as usize;
                let innings = self
                    .innings
                    .get_mut(index)
                    .ok_or_else(|| DomainError::Validation("no such innings".into()))?;
                let bowled = innings.legal_balls.div_ceil(6) as u8;
                if overs < bowled {
                    return Err(DomainError::Validation(format!(
                        "{bowled} overs have already been bowled"
                    )));
                }
                innings.overs_available = overs;
                innings.close_if_finished(overs);
            }
            ScoringEventKind::BowlerChanged { bowler_id } => {
                self.check_bowler_available(*bowler_id)?;
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
        self.check_auto_complete();
        Ok(())
    }

    /// Two Laws and one agreement: nobody bowls consecutive overs, nobody
    /// exceeds the allocation the captains settled, and a side with a single
    /// bowler is excused the first of those.
    fn check_bowler_available(&self, bowler: Uuid) -> Result<()> {
        let Some(inn) = self.current_innings() else {
            return Ok(());
        };
        if inn.last_over_bowler == Some(bowler) && self.xi(inn.bowling).len() > 1 {
            return Err(DomainError::Validation(format!(
                "{} bowled the last over — nobody bowls two in a row",
                self.name_for(bowler)
            )));
        }
        if self.conditions.overs_per_bowler > 0 {
            let bowled = inn
                .bowlers
                .iter()
                .find(|b| b.player_id == bowler)
                .map(|b| (b.balls / 6) as u8)
                .unwrap_or(0);
            if bowled >= self.conditions.overs_per_bowler {
                return Err(DomainError::Validation(format!(
                    "{} has bowled their {} overs",
                    self.name_for(bowler),
                    self.conditions.overs_per_bowler
                )));
            }
        }
        Ok(())
    }

    fn apply_delivery(
        &mut self,
        runs: u8,
        is_legal: bool,
        four: bool,
        six: bool,
        shot: Option<ShotRecord>,
    ) -> Result<()> {
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
        inn.partnership_runs += runs as u16;
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
            "6".into()
        } else if four {
            "4".into()
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
            batter_id: Some(striker),
            bowler_id: Some(bowler),
            shot,
        });

        if is_legal {
            inn.legal_balls += 1;
            inn.balls_in_current_over += 1;
            inn.partnership_balls += 1;
            // A free hit lasts one legal delivery.
            inn.free_hit = false;
            if runs % 2 == 1 {
                inn.swap_strike();
            }
            inn.complete_over_if_due(Some(bowler));
        }

        let overs_available = inn.overs_available;
        inn.close_if_finished(overs_available);
        Ok(())
    }

    /// An extra, plus whatever the ball did afterwards.
    ///
    /// `runs` is what the batters ran (or the boundary), *on top of* the one-run
    /// penalty a wide or a no ball carries. The three things that have to come
    /// apart are: what the side scores, what the batter is credited with, and
    /// what the bowler is charged.
    fn apply_extras(
        &mut self,
        kind: ExtraKind,
        runs: u8,
        boundary: bool,
        off_the_bat: bool,
        shot: Option<ShotRecord>,
    ) -> Result<()> {
        let inn = self
            .current_innings_mut()
            .ok_or_else(|| DomainError::Validation("no live innings".into()))?;
        if inn.complete {
            return Err(DomainError::Validation("innings complete".into()));
        }
        let bowler = inn
            .bowler_id
            .ok_or_else(|| DomainError::Validation("no bowler".into()))?;
        let striker = inn
            .striker_id
            .ok_or_else(|| DomainError::Validation("no striker".into()))?;

        // A wide or a no ball is one run to the side before anyone runs.
        let penalty: u8 = match kind {
            ExtraKind::Wide | ExtraKind::NoBall => 1,
            _ => 0,
        };
        let legal = matches!(kind, ExtraKind::Bye | ExtraKind::LegBye);
        // Runs off the bat only happen off a no ball; everything else that is
        // run belongs to the extras column.
        let bat_runs = if kind == ExtraKind::NoBall && off_the_bat {
            runs
        } else {
            0
        };
        let team_runs = penalty + runs;
        let extra_runs = team_runs - bat_runs;
        // Byes off a no ball are not the bowler's fault; the no ball itself is.
        let bowler_runs = match kind {
            ExtraKind::Wide => penalty + runs,
            ExtraKind::NoBall => penalty + bat_runs,
            ExtraKind::Bye | ExtraKind::LegBye | ExtraKind::Penalty => 0,
        };

        inn.runs += team_runs as u16;
        inn.extras += extra_runs as u16;
        inn.partnership_runs += team_runs as u16;
        match kind {
            // A wide and the runs run off it are all wides in the book.
            ExtraKind::Wide => inn.wides += extra_runs as u16,
            // Only the no ball itself is a no ball; byes off it are byes.
            ExtraKind::NoBall => {
                inn.no_balls += penalty as u16;
                if !off_the_bat {
                    inn.byes += runs as u16;
                }
            }
            ExtraKind::Bye => inn.byes += extra_runs as u16,
            ExtraKind::LegBye => inn.leg_byes += extra_runs as u16,
            ExtraKind::Penalty => inn.penalties += extra_runs as u16,
        }

        // The batter faces a no ball, a bye and a leg bye; never a wide.
        let faced = !matches!(kind, ExtraKind::Wide | ExtraKind::Penalty);
        if faced {
            let b = inn.batter_mut(striker)?;
            b.balls += 1;
            if bat_runs > 0 {
                b.runs += bat_runs as u16;
                if boundary && bat_runs >= 6 {
                    b.sixes += 1;
                } else if boundary && bat_runs >= 4 {
                    b.fours += 1;
                }
            }
        }

        {
            let bowl = inn.bowler_mut(bowler)?;
            bowl.runs += bowler_runs as u16;
            bowl.current_over_runs += bowler_runs as u16;
            if legal {
                bowl.balls += 1;
            }
            match kind {
                ExtraKind::Wide => bowl.wides += 1,
                ExtraKind::NoBall => bowl.no_balls += 1,
                _ => {}
            }
        }

        let label = match kind {
            ExtraKind::Wide if runs > 0 => format!("wd+{runs}"),
            ExtraKind::Wide => "wd".into(),
            ExtraKind::NoBall if runs > 0 => format!("nb+{runs}"),
            ExtraKind::NoBall => "nb".into(),
            ExtraKind::Bye => format!("{runs}b"),
            ExtraKind::LegBye => format!("{runs}lb"),
            ExtraKind::Penalty => format!("{runs}p"),
        };
        let over = inn.legal_balls / 6;
        let ball_in = inn.balls_in_current_over + if legal { 1 } else { 0 };
        inn.deliveries.push(DeliveryRecord {
            over,
            ball_in_over: ball_in,
            label,
            runs: team_runs,
            is_legal: legal,
            is_wicket: false,
            batter_id: Some(striker),
            bowler_id: Some(bowler),
            shot,
        });

        if legal {
            inn.legal_balls += 1;
            inn.balls_in_current_over += 1;
            inn.partnership_balls += 1;
            inn.free_hit = false;
        }
        // A no ball buys the batter a free hit off the next legal delivery.
        if kind == ExtraKind::NoBall {
            inn.free_hit = true;
        }
        // Whatever they ran, an odd number puts the other batter on strike —
        // and a boundary is four or six, so it never does.
        if runs % 2 == 1 && !boundary {
            inn.swap_strike();
        }
        if legal {
            inn.complete_over_if_due(Some(bowler));
        }

        let overs_available = inn.overs_available;
        inn.close_if_finished(overs_available);
        Ok(())
    }

    fn apply_wicket(
        &mut self,
        batter_id: Uuid,
        kind: DismissalKind,
        fielder_id: Option<Uuid>,
        new_batter_id: Option<Uuid>,
        runs: u8,
        on_extra: bool,
    ) -> Result<()> {
        let inn = self
            .current_innings_mut()
            .ok_or_else(|| DomainError::Validation("no live innings".into()))?;
        if inn.complete {
            return Err(DomainError::Validation("innings complete".into()));
        }
        let overs_limit = inn.overs_available;
        let bowler = inn.bowler_id;
        let striker = inn.striker_id;
        if inn.free_hit && !kind.allowed_on_a_free_hit() {
            return Err(DomainError::Validation(
                "it is a free hit — only a run out can get them".into(),
            ));
        }
        // A dismissal on a delivery already booked as an extra must not count
        // the ball a second time.
        let is_legal = kind.uses_a_ball() && !on_extra;
        let counts_a_wicket = kind.costs_a_wicket();

        // Runs completed before the dismissal (a run-out is usually off the bat).
        if runs > 0 {
            if let Some(striker_id) = striker {
                inn.runs += runs as u16;
                inn.partnership_runs += runs as u16;
                let b = inn.batter_mut(striker_id)?;
                b.runs += runs as u16;
                if let Some(bid) = bowler {
                    let bowl = inn.bowler_mut(bid)?;
                    bowl.runs += runs as u16;
                    bowl.current_over_runs += runs as u16;
                }
            }
        }

        {
            let b = inn.batter_mut(batter_id)?;
            if counts_a_wicket {
                b.out = true;
            } else {
                // Retired hurt: off the field, but not out, and may resume.
                b.retired_hurt = true;
            }
            b.dismissal = Some(kind);
            b.fielder_id = fielder_id;
            b.bowler_id = if kind.credits_bowler() { bowler } else { None };
        }
        // The ball is faced by whoever was on strike, not necessarily the
        // batter given out — a non-striker can be run out.
        if is_legal {
            if let Some(striker_id) = striker {
                inn.batter_mut(striker_id)?.balls += 1;
            }
        }

        if counts_a_wicket {
            inn.wickets += 1;
        }
        if is_legal {
            inn.legal_balls += 1;
            inn.balls_in_current_over += 1;
            inn.partnership_balls += 1;
            inn.free_hit = false;
            if let Some(bid) = bowler {
                inn.bowler_mut(bid)?.balls += 1;
            }
        }
        // The wicket is the bowler's whether or not the delivery counted — a
        // stumping off a wide is still theirs.
        if kind.credits_bowler() {
            if let Some(bid) = bowler {
                inn.bowler_mut(bid)?.wickets += 1;
            }
        }

        if counts_a_wicket {
            let score = inn.runs;
            let wickets = inn.wickets;
            let over_ball = MatchState::overs_balls_display(inn.legal_balls);
            let partnership_runs = inn.partnership_runs;
            let partnership_balls = inn.partnership_balls;
            inn.fall.push(FallOfWicket {
                score,
                wickets,
                batter_id,
                over_ball,
                partnership_runs,
                partnership_balls,
            });
            inn.partnership_runs = 0;
            inn.partnership_balls = 0;
        }

        let over = inn.legal_balls.saturating_sub(1) / 6;
        let ball_in = inn.balls_in_current_over;
        inn.deliveries.push(DeliveryRecord {
            over,
            ball_in_over: ball_in,
            label: if !counts_a_wicket {
                "RH".into()
            } else if runs > 0 {
                format!("{runs}W")
            } else {
                "W".into()
            },
            runs,
            is_legal,
            is_wicket: counts_a_wicket,
            batter_id: striker,
            bowler_id: bowler,
            shot: None,
        });

        // Batters cross on odd completed runs, so work out where the dismissed
        // player ended up before the replacement takes their end.
        if is_legal && runs % 2 == 1 {
            inn.swap_strike();
        }

        if inn.is_all_out() || (overs_limit > 0 && inn.legal_balls >= (overs_limit as u16) * 6) {
            inn.complete = true;
            return Ok(());
        }

        let new_id = new_batter_id
            .ok_or_else(|| DomainError::Validation("new batter required".into()))?;
        if !inn.batters.iter().any(|b| b.player_id == new_id) {
            inn.batters.push(BatterStats::new(new_id));
        } else if let Ok(returning) = inn.batter_mut(new_id) {
            // Someone who retired hurt and is coming back in.
            returning.retired_hurt = false;
        }
        if inn.striker_id == Some(batter_id) {
            inn.striker_id = Some(new_id);
        } else if inn.non_striker_id == Some(batter_id) {
            inn.non_striker_id = Some(new_id);
        } else {
            inn.striker_id = Some(new_id);
        }

        inn.complete_over_if_due(bowler);
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

    /// A chase reaching its target, an innings running out of balls or wickets,
    /// and the end of the second innings all finish the match on their own.
    fn check_auto_complete(&mut self) {
        let Some(inn) = self.current_innings() else {
            return;
        };
        let index = inn.index;
        let complete = inn.complete;
        let runs = inn.runs;

        if !complete {
            if index >= 1 {
                if let Some(target) = self.target {
                    if runs >= target {
                        if let Some(inn) = self.current_innings_mut() {
                            inn.complete = true;
                        }
                        self.status = MatchStatus::Complete;
                        self.finish_result();
                    }
                }
            }
            return;
        }

        if index == 0 && self.status == MatchStatus::Live {
            self.target = Some(runs + 1);
            self.status = MatchStatus::InningsBreak;
        } else if index >= 1 && self.status != MatchStatus::Complete {
            self.status = MatchStatus::Complete;
            self.finish_result();
        }
    }

    fn finish_result(&mut self) {
        if self.innings.len() < 2 {
            return;
        }
        // Copy what the margin needs before touching `self` again.
        let (first_runs, first_batting) = {
            let first = &self.innings[0];
            (first.runs, first.batting)
        };
        let (second_runs, second_batting, second_wickets, wickets_allowed, second_balls, second_overs) = {
            let second = &self.innings[1];
            (
                second.runs,
                second.batting,
                second.wickets,
                second.wickets_allowed,
                second.legal_balls,
                second.overs_available,
            )
        };

        if second_runs > first_runs {
            // Chased it down: the margin is the wickets still standing.
            let wickets = wickets_allowed.saturating_sub(second_wickets);
            let balls_left = ((second_overs as u16) * 6).saturating_sub(second_balls);
            let mut margin = format!(
                "{} won by {wickets} wicket{}",
                self.side_name(second_batting),
                if wickets == 1 { "" } else { "s" }
            );
            if balls_left > 0 {
                margin.push_str(&format!(" ({balls_left} balls remaining)"));
            }
            self.winner = Some(second_batting);
            self.margin = Some(margin);
        } else if second_runs < first_runs {
            let runs = first_runs - second_runs;
            let margin = format!(
                "{} won by {runs} run{}",
                self.side_name(first_batting),
                if runs == 1 { "" } else { "s" }
            );
            self.winner = Some(first_batting);
            self.margin = Some(margin);
        } else {
            self.winner = None;
            self.margin = Some("Match tied".into());
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

    /// Six legal balls: bank the maiden, reset the count, change ends, and
    /// remember who bowled it so they cannot bowl the next one.
    fn complete_over_if_due(&mut self, bowler: Option<Uuid>) {
        if self.balls_in_current_over < 6 {
            return;
        }
        if let Some(id) = bowler {
            if let Some(bowl) = self.bowlers.iter_mut().find(|b| b.player_id == id) {
                if bowl.current_over_runs == 0 {
                    bowl.maidens += 1;
                }
                bowl.current_over_runs = 0;
            }
        }
        self.last_over_bowler = bowler;
        self.balls_in_current_over = 0;
        self.swap_strike();
    }

    fn close_if_finished(&mut self, overs_limit: u8) {
        let out_of_overs = overs_limit > 0 && self.legal_balls >= (overs_limit as u16) * 6;
        if out_of_overs || self.is_all_out() {
            self.complete = true;
        }
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

    fn team(prefix: &str, size: usize) -> Vec<MatchPlayer> {
        (0..size)
            .map(|i| MatchPlayer {
                id: Uuid::new_v4(),
                name: format!("{prefix} {i}"),
                bats_left: false,
            })
            .collect()
    }

    /// A match wound forward to the first ball of the innings.
    struct Fixture {
        state: MatchState,
        home: Vec<MatchPlayer>,
        away: Vec<MatchPlayer>,
        seq: i64,
    }

    impl Fixture {
        fn new(overs: u8) -> Self {
            let home = team("Home", 11);
            let away = team("Away", 11);
            let mut state = MatchState::default();
            let mut seq = 0;
            let push = |state: &mut MatchState, seq: &mut i64, kind| {
                *seq += 1;
                state.apply(&evt(*seq, kind)).unwrap();
            };
            push(
                &mut state,
                &mut seq,
                ScoringEventKind::MatchPrepared {
                    overs_limit: overs,
                    home_name: "Lords".into(),
                    away_name: "Hemel".into(),
                },
            );
            push(
                &mut state,
                &mut seq,
                ScoringEventKind::ConditionsProposed {
                    conditions: MatchConditions::standard(overs),
                    by: MatchSide::Home,
                    by_name: "Home captain".into(),
                },
            );
            push(
                &mut state,
                &mut seq,
                ScoringEventKind::ConditionsAgreed {
                    side: MatchSide::Away,
                    captain_name: "Away captain".into(),
                },
            );
            push(
                &mut state,
                &mut seq,
                ScoringEventKind::TossRecorded {
                    winner: MatchSide::Home,
                    decision: TossDecision::Bat,
                },
            );
            push(
                &mut state,
                &mut seq,
                ScoringEventKind::XiSelected {
                    side: MatchSide::Home,
                    players: home.clone(),
                    captain_id: Some(home[0].id),
                    keeper_id: Some(home[1].id),
                },
            );
            push(
                &mut state,
                &mut seq,
                ScoringEventKind::XiSelected {
                    side: MatchSide::Away,
                    players: away.clone(),
                    captain_id: Some(away[0].id),
                    keeper_id: Some(away[1].id),
                },
            );
            push(
                &mut state,
                &mut seq,
                ScoringEventKind::InningsStarted {
                    innings_index: 0,
                    batting: MatchSide::Home,
                    striker_id: home[0].id,
                    non_striker_id: home[1].id,
                    bowler_id: away[0].id,
                },
            );
            Self {
                state,
                home,
                away,
                seq,
            }
        }

        fn push(&mut self, kind: ScoringEventKind) {
            self.seq += 1;
            self.state.apply(&evt(self.seq, kind)).unwrap();
        }

        fn try_push(&mut self, kind: ScoringEventKind) -> Result<()> {
            self.seq += 1;
            self.state.apply(&evt(self.seq, kind))
        }

        fn runs(&mut self, runs: u8) {
            self.push(ScoringEventKind::DeliveryRecorded {
                runs,
                is_legal: true,
                is_boundary_four: runs == 4,
                is_boundary_six: runs == 6,
                shot: None,
            });
        }

        fn innings(&self) -> &InningsState {
            self.state.current_innings().unwrap()
        }
    }

    #[test]
    fn four_updates_score_and_batter() {
        let mut m = Fixture::new(20);
        m.runs(4);
        assert_eq!(m.innings().runs, 4);
        assert_eq!(m.innings().legal_balls, 1);
        let striker = m.home[0].id;
        let batter = m.innings().batters.iter().find(|b| b.player_id == striker).unwrap();
        assert_eq!(batter.runs, 4);
        assert_eq!(batter.fours, 1);
    }

    #[test]
    fn odd_run_rotates_strike() {
        let mut m = Fixture::new(20);
        m.runs(1);
        assert_eq!(m.innings().striker_id, Some(m.home[1].id));
    }

    #[test]
    fn over_completion_swaps_strike_and_banks_a_maiden() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        for _ in 0..6 {
            m.runs(0);
        }
        assert_eq!(m.innings().balls_in_current_over, 0);
        assert_eq!(m.innings().legal_balls, 6);
        assert_ne!(m.innings().striker_id, Some(striker));
        assert_eq!(m.innings().bowlers[0].maidens, 1);
    }

    #[test]
    fn undo_reverts_the_last_ball() {
        let mut m = Fixture::new(5);
        m.runs(6);
        assert_eq!(m.innings().runs, 6);
        m.push(ScoringEventKind::UndoLast);
        assert_eq!(m.innings().runs, 0);
    }

    #[test]
    fn undo_survives_a_replay_of_the_log() {
        // The bug this guards: the server used to restore state from a stored
        // snapshot whose undo stack was empty, so a synced undo always failed
        // and jammed the queue. Replaying the log rebuilds the stack.
        let home = team("Home", 11);
        let away = team("Away", 11);
        let log = vec![
            evt(
                1,
                ScoringEventKind::MatchPrepared {
                    overs_limit: 5,
                    home_name: "Lords".into(),
                    away_name: "Hemel".into(),
                },
            ),
            evt(
                2,
                ScoringEventKind::XiSelected {
                    side: MatchSide::Home,
                    players: home.clone(),
                    captain_id: None,
                    keeper_id: None,
                },
            ),
            evt(
                3,
                ScoringEventKind::XiSelected {
                    side: MatchSide::Away,
                    players: away.clone(),
                    captain_id: None,
                    keeper_id: None,
                },
            ),
            evt(
                4,
                ScoringEventKind::InningsStarted {
                    innings_index: 0,
                    batting: MatchSide::Home,
                    striker_id: home[0].id,
                    non_striker_id: home[1].id,
                    bowler_id: away[0].id,
                },
            ),
            evt(
                5,
                ScoringEventKind::DeliveryRecorded {
                    runs: 4,
                    is_legal: true,
                    is_boundary_four: true,
                    is_boundary_six: false,
                    shot: None,
                },
            ),
            evt(
                6,
                ScoringEventKind::DeliveryRecorded {
                    runs: 2,
                    is_legal: true,
                    is_boundary_four: false,
                    is_boundary_six: false,
                    shot: None,
                },
            ),
        ];

        let before = MatchState::replay(&log).unwrap();
        assert_eq!(before.current_innings().unwrap().runs, 6);

        // The undo arrives in a later batch, long after those balls were stored.
        let mut with_undo = log.clone();
        with_undo.push(evt(7, ScoringEventKind::UndoLast));
        let after = MatchState::replay(&with_undo).unwrap();
        assert_eq!(
            after.current_innings().unwrap().runs,
            4,
            "an undo arriving after a reload must still undo"
        );
        assert_eq!(after.last_seq, 7);
    }

    #[test]
    fn wide_costs_a_run_but_not_a_ball() {
        let mut m = Fixture::new(20);
        m.push(ScoringEventKind::ExtrasRecorded {
            kind: ExtraKind::Wide,
            runs: 0,
            boundary: false,
            off_the_bat: false,
            shot: None,
        });
        assert_eq!(m.innings().runs, 1);
        assert_eq!(m.innings().legal_balls, 0);
        assert_eq!(m.innings().wides, 1);
        assert_eq!(m.innings().extras, 1);
        assert_eq!(m.innings().bowlers[0].wides, 1);
    }

    #[test]
    fn no_ball_with_runs_off_the_bat_splits_the_credit() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        // 1 no-ball + 4 off the bat.
        m.push(ScoringEventKind::ExtrasRecorded {
            kind: ExtraKind::NoBall,
            runs: 4,
            boundary: true,
            off_the_bat: true,
            shot: None,
        });
        assert_eq!(m.innings().runs, 5);
        assert_eq!(m.innings().extras, 1, "only the no-ball itself is an extra");
        assert_eq!(m.innings().no_balls, 1);
        let batter = m.innings().batters.iter().find(|b| b.player_id == striker).unwrap();
        assert_eq!(batter.runs, 4);
    }

    #[test]
    fn byes_do_not_go_against_the_bowler() {
        let mut m = Fixture::new(20);
        m.push(ScoringEventKind::ExtrasRecorded {
            kind: ExtraKind::Bye,
            runs: 2,
            boundary: false,
            off_the_bat: false,
            shot: None,
        });
        assert_eq!(m.innings().runs, 2);
        assert_eq!(m.innings().byes, 2);
        assert_eq!(m.innings().legal_balls, 1);
        assert_eq!(m.innings().bowlers[0].runs, 0);
    }

    #[test]
    fn caught_credits_the_bowler_and_reads_as_a_scorecard_line() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        let fielder = m.away[3].id;
        m.push(ScoringEventKind::WicketRecorded {
            batter_id: striker,
            kind: DismissalKind::Caught,
            fielder_id: Some(fielder),
            new_batter_id: Some(m.home[2].id),
            runs: 0,
                    on_extra: false,
        });
        assert_eq!(m.innings().wickets, 1);
        assert_eq!(m.innings().bowlers[0].wickets, 1);
        let out = m.innings().batters.iter().find(|b| b.player_id == striker).unwrap().clone();
        assert_eq!(m.state.dismissal_text(&out), "c Away 3 b Away 0");
        assert_eq!(m.innings().striker_id, Some(m.home[2].id));
    }

    #[test]
    fn run_out_does_not_credit_the_bowler_and_can_take_the_non_striker() {
        let mut m = Fixture::new(20);
        let non_striker = m.innings().non_striker_id.unwrap();
        let replacement = m.home[2].id;
        m.push(ScoringEventKind::WicketRecorded {
            batter_id: non_striker,
            kind: DismissalKind::RunOut,
            fielder_id: Some(m.away[4].id),
            new_batter_id: Some(replacement),
            runs: 1,
                    on_extra: false,
        });
        assert_eq!(m.innings().wickets, 1);
        assert_eq!(m.innings().bowlers[0].wickets, 0, "run outs are not the bowler's");
        assert_eq!(m.innings().runs, 1, "the completed run still counts");
        // One run was completed, so the batters crossed: the survivor is on strike
        // and the new batter takes the non-striker's end.
        assert!(
            m.innings().striker_id == Some(replacement)
                || m.innings().non_striker_id == Some(replacement),
            "the replacement is at the crease"
        );
        let out = m.innings().batters.iter().find(|b| b.player_id == non_striker).unwrap().clone();
        assert_eq!(m.state.dismissal_text(&out), "run out (Away 4)");
    }

    #[test]
    fn fall_of_wicket_records_the_partnership() {
        let mut m = Fixture::new(20);
        m.runs(2);
        m.runs(4);
        let striker = m.innings().striker_id.unwrap();
        m.push(ScoringEventKind::WicketRecorded {
            batter_id: striker,
            kind: DismissalKind::Bowled,
            fielder_id: None,
            new_batter_id: Some(m.home[2].id),
            runs: 0,
                    on_extra: false,
        });
        let fall = &m.innings().fall[0];
        assert_eq!(fall.score, 6);
        assert_eq!(fall.wickets, 1);
        assert_eq!(fall.partnership_runs, 6);
        assert_eq!(fall.partnership_balls, 3);
        assert_eq!(m.innings().partnership_runs, 0, "a new stand starts at zero");
    }

    #[test]
    fn innings_ends_when_the_overs_run_out() {
        let mut m = Fixture::new(1);
        for _ in 0..6 {
            m.runs(1);
        }
        assert!(m.innings().complete);
        assert_eq!(m.state.status, MatchStatus::InningsBreak);
        assert_eq!(m.state.target, Some(7));
    }

    #[test]
    fn a_short_side_is_all_out_early() {
        let home = team("Home", 3);
        let away = team("Away", 3);
        let mut state = MatchState::default();
        let mut seq = 0;
        let push = |state: &mut MatchState, seq: &mut i64, kind| {
            *seq += 1;
            state.apply(&evt(*seq, kind)).unwrap();
        };
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::MatchPrepared {
                overs_limit: 20,
                home_name: "A".into(),
                away_name: "B".into(),
            },
        );
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::XiSelected {
                side: MatchSide::Home,
                players: home.clone(),
                captain_id: None,
                keeper_id: None,
            },
        );
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::XiSelected {
                side: MatchSide::Away,
                players: away.clone(),
                captain_id: None,
                keeper_id: None,
            },
        );
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::InningsStarted {
                innings_index: 0,
                batting: MatchSide::Home,
                striker_id: home[0].id,
                non_striker_id: home[1].id,
                bowler_id: away[0].id,
            },
        );
        assert_eq!(state.current_innings().unwrap().wickets_allowed, 2);
        for batter in [home[0].id, home[1].id].iter() {
            seq += 1;
            state
                .apply(&evt(
                    seq,
                    ScoringEventKind::WicketRecorded {
                        batter_id: *batter,
                        kind: DismissalKind::Bowled,
                        fielder_id: None,
                        new_batter_id: Some(home[2].id),
                        runs: 0,
                    on_extra: false,
                    },
                ))
                .unwrap();
        }
        assert!(state.current_innings().unwrap().complete, "three players, two wickets");
    }

    #[test]
    fn a_team_sheet_must_be_a_plausible_size() {
        let mut m = Fixture::new(20);
        let result = m.try_push(ScoringEventKind::XiSelected {
            side: MatchSide::Home,
            players: team("Too many", 16),
            captain_id: None,
            keeper_id: None,
        });
        assert!(result.is_err());
    }

    #[test]
    fn chasing_side_wins_by_wickets_with_balls_to_spare() {
        let mut m = Fixture::new(2);
        m.runs(4);
        m.push(ScoringEventKind::InningsCompleted);
        assert_eq!(m.state.target, Some(5));
        m.push(ScoringEventKind::InningsStarted {
            innings_index: 1,
            batting: MatchSide::Away,
            striker_id: m.away[0].id,
            non_striker_id: m.away[1].id,
            bowler_id: m.home[0].id,
        });
        m.runs(6);
        assert_eq!(m.state.status, MatchStatus::Complete);
        assert_eq!(m.state.winner, Some(MatchSide::Away));
        let margin = m.state.margin.clone().unwrap();
        assert!(margin.starts_with("Hemel won by 10 wickets"), "got {margin}");
        assert!(margin.contains("balls remaining"), "got {margin}");
    }

    #[test]
    fn defending_side_wins_by_runs() {
        let mut m = Fixture::new(1);
        for _ in 0..6 {
            m.runs(2);
        }
        m.push(ScoringEventKind::InningsStarted {
            innings_index: 1,
            batting: MatchSide::Away,
            striker_id: m.away[0].id,
            non_striker_id: m.away[1].id,
            bowler_id: m.home[0].id,
        });
        for _ in 0..6 {
            m.runs(1);
        }
        assert_eq!(m.state.status, MatchStatus::Complete);
        assert_eq!(m.state.winner, Some(MatchSide::Home));
        assert_eq!(m.state.margin.as_deref(), Some("Lords won by 6 runs"));
    }

    #[test]
    fn scores_level_is_a_tie() {
        let mut m = Fixture::new(1);
        for _ in 0..6 {
            m.runs(1);
        }
        m.push(ScoringEventKind::InningsStarted {
            innings_index: 1,
            batting: MatchSide::Away,
            striker_id: m.away[0].id,
            non_striker_id: m.away[1].id,
            bowler_id: m.home[0].id,
        });
        for _ in 0..6 {
            m.runs(1);
        }
        assert_eq!(m.state.margin.as_deref(), Some("Match tied"));
        assert_eq!(m.state.winner, None);
    }

    #[test]
    fn the_chase_line_reads_like_a_scoreboard() {
        let mut m = Fixture::new(2);
        m.runs(4);
        m.push(ScoringEventKind::InningsCompleted);
        m.push(ScoringEventKind::InningsStarted {
            innings_index: 1,
            batting: MatchSide::Away,
            striker_id: m.away[0].id,
            non_striker_id: m.away[1].id,
            bowler_id: m.home[0].id,
        });
        m.runs(2);
        assert_eq!(
            m.state.chase_line().as_deref(),
            Some("Hemel need 3 from 11 balls")
        );
    }

    /// The iOS client encodes UUIDs in upper case and omits fields it has no
    /// value for. Anything the phone can send, the API has to be able to read.
    #[test]
    fn the_wire_shape_the_client_sends_parses_here() {
        let team_sheet = r#"{
            "type": "xi_selected",
            "side": "home",
            "players": [
                { "id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301", "name": "Ravi Patel" },
                { "id": "3f2504e0-4f89-41d3-9a0c-0305e82c3302", "name": "Sam Cook" }
            ],
            "captain_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
        }"#;
        let kind: ScoringEventKind = serde_json::from_str(team_sheet).unwrap();
        match &kind {
            ScoringEventKind::XiSelected { players, keeper_id, .. } => {
                assert_eq!(players.len(), 2);
                assert_eq!(players[0].name, "Ravi Patel");
                assert!(keeper_id.is_none(), "an absent keeper is not an error");
            }
            other => panic!("expected a team sheet, got {other:?}"),
        }

        // A run out carries the fielder and the runs completed.
        let run_out = r#"{
            "type": "wicket_recorded",
            "batter_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301",
            "kind": "run_out",
            "fielder_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3302",
            "new_batter_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3303",
            "runs": 1
        }"#;
        match serde_json::from_str::<ScoringEventKind>(run_out).unwrap() {
            ScoringEventKind::WicketRecorded { kind, runs, fielder_id, .. } => {
                assert_eq!(kind, DismissalKind::RunOut);
                assert_eq!(runs, 1);
                assert!(fielder_id.is_some());
            }
            other => panic!("expected a wicket, got {other:?}"),
        }

        // An older client that never sends `runs` still parses.
        let bowled = r#"{
            "type": "wicket_recorded",
            "batter_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301",
            "kind": "bowled",
            "new_batter_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3303"
        }"#;
        match serde_json::from_str::<ScoringEventKind>(bowled).unwrap() {
            ScoringEventKind::WicketRecorded { runs, .. } => assert_eq!(runs, 0),
            other => panic!("expected a wicket, got {other:?}"),
        }
    }

    /// Names go out as a JSON object keyed by lower-case UUID, which is the one
    /// shape both ends read the same way.
    #[test]
    fn player_names_serialise_as_an_object_the_client_can_key_into() {
        let m = Fixture::new(20);
        let json = serde_json::to_value(&m.state).unwrap();
        let names = json["player_names"].as_object().expect("an object, not an array");
        let key = m.home[0].id.to_string();
        assert_eq!(key, key.to_lowercase(), "uuids serialise lower case");
        assert_eq!(names[&key], "Home 0");
    }

    #[test]
    fn an_innings_with_no_recorded_overs_does_not_close_itself() {
        // A projection restored without `overs_available` used to have a limit
        // of zero, which meant every ball ended the innings.
        let mut m = Fixture::new(20);
        m.state.innings[0].overs_available = 0;
        m.runs(1);
        assert!(!m.innings().complete, "zero means unknown, not finished");
        assert_eq!(m.innings().runs, 1);
        assert_eq!(m.innings().balls_allowed(), None);
    }

    // MARK: conditions the captains agree

    #[test]
    fn a_toss_needs_both_captains_to_have_agreed_the_terms() {
        let mut state = MatchState::default();
        let mut seq = 0;
        let push = |state: &mut MatchState, seq: &mut i64, kind| {
            *seq += 1;
            state.apply(&evt(*seq, kind))
        };
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::MatchPrepared {
                overs_limit: 20,
                home_name: "Lords".into(),
                away_name: "Hemel".into(),
            },
        )
        .unwrap();

        // Straight to the toss: refused, nothing has been agreed.
        assert!(push(
            &mut state,
            &mut seq,
            ScoringEventKind::TossRecorded {
                winner: MatchSide::Home,
                decision: TossDecision::Bat,
            },
        )
        .is_err());

        seq -= 1; // the refused event never happened
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::ConditionsProposed {
                conditions: MatchConditions {
                    overs_limit: 30,
                    overs_per_bowler: 6,
                    ground: GroundType::Boxed,
                    ball: BallType::Tennis,
                },
                by: MatchSide::Home,
                by_name: "Ravi".into(),
            },
        )
        .unwrap();

        // The proposing captain has agreed; the other has not.
        assert_eq!(state.agreed_home.as_deref(), Some("Ravi"));
        assert!(state.agreed_away.is_none());
        assert!(!state.conditions_agreed());
        assert_eq!(state.awaiting_agreement(), vec![MatchSide::Away]);
        assert!(push(
            &mut state,
            &mut seq,
            ScoringEventKind::TossRecorded {
                winner: MatchSide::Home,
                decision: TossDecision::Bat,
            },
        )
        .is_err());

        seq -= 1;
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::ConditionsAgreed {
                side: MatchSide::Away,
                captain_name: "Sam".into(),
            },
        )
        .unwrap();
        assert!(state.conditions_agreed());
        assert_eq!(state.status, MatchStatus::Toss);
        assert_eq!(state.conditions.overs_limit, 30);
        assert_eq!(state.conditions.ball, BallType::Tennis);
        assert_eq!(state.conditions.ground, GroundType::Boxed);

        push(
            &mut state,
            &mut seq,
            ScoringEventKind::TossRecorded {
                winner: MatchSide::Home,
                decision: TossDecision::Bat,
            },
        )
        .unwrap();
        assert_eq!(state.status, MatchStatus::SelectingXi);
    }

    #[test]
    fn changing_the_terms_needs_agreeing_all_over_again() {
        let mut m = Fixture::new(20);
        assert!(m.state.conditions_agreed());
        m.push(ScoringEventKind::ConditionsProposed {
            conditions: MatchConditions::standard(10),
            by: MatchSide::Away,
            by_name: "Sam".into(),
        });
        assert!(!m.state.conditions_agreed(), "the home side must agree the change");
        assert_eq!(m.state.awaiting_agreement(), vec![MatchSide::Home]);
    }

    #[test]
    fn the_standard_allocation_is_a_fifth_of_the_innings() {
        assert_eq!(MatchConditions::standard(20).overs_per_bowler, 4);
        assert_eq!(MatchConditions::standard(50).overs_per_bowler, 10);
        assert_eq!(MatchConditions::standard(40).overs_per_bowler, 8);
        // Rounded up, and never zero.
        assert_eq!(MatchConditions::standard(12).overs_per_bowler, 3);
        assert_eq!(MatchConditions::standard(1).overs_per_bowler, 1);
    }

    #[test]
    fn a_bowler_allocation_larger_than_the_innings_is_refused() {
        let mut m = Fixture::new(20);
        let result = m.try_push(ScoringEventKind::ConditionsProposed {
            conditions: MatchConditions {
                overs_limit: 20,
                overs_per_bowler: 21,
                ground: GroundType::Open,
                ball: BallType::White,
            },
            by: MatchSide::Home,
            by_name: "Ravi".into(),
        });
        assert!(result.is_err());
    }

    #[test]
    fn the_conditions_summary_reads_like_a_scorecard_header() {
        let conditions = MatchConditions {
            overs_limit: 20,
            overs_per_bowler: 4,
            ground: GroundType::Boxed,
            ball: BallType::Tape,
        };
        assert_eq!(
            conditions.summary(),
            "20 overs · 4 per bowler · tape ball · boxed / caged"
        );
    }

    // MARK: the bowling Laws

    #[test]
    fn nobody_bowls_two_overs_in_a_row() {
        let mut m = Fixture::new(20);
        let opener = m.innings().bowler_id.unwrap();
        for _ in 0..6 {
            m.runs(0);
        }
        assert_eq!(m.innings().last_over_bowler, Some(opener));
        let result = m.try_push(ScoringEventKind::BowlerChanged { bowler_id: opener });
        assert!(result.is_err(), "the same bowler cannot start the next over");

        // Someone else can, and then the opener is free again.
        let second = m.away[1].id;
        m.seq -= 1;
        m.push(ScoringEventKind::BowlerChanged { bowler_id: second });
        for _ in 0..6 {
            m.runs(0);
        }
        m.push(ScoringEventKind::BowlerChanged { bowler_id: opener });
        assert_eq!(m.innings().bowler_id, Some(opener));
    }

    #[test]
    fn a_bowler_cannot_exceed_the_agreed_allocation() {
        // Five overs, one per bowler.
        let mut m = Fixture::new(5);
        m.push(ScoringEventKind::ConditionsProposed {
            conditions: MatchConditions {
                overs_limit: 5,
                overs_per_bowler: 1,
                ground: GroundType::Open,
                ball: BallType::White,
            },
            by: MatchSide::Home,
            by_name: "Ravi".into(),
        });
        m.push(ScoringEventKind::ConditionsAgreed {
            side: MatchSide::Away,
            captain_name: "Sam".into(),
        });

        let opener = m.innings().bowler_id.unwrap();
        for _ in 0..6 {
            m.runs(0);
        }
        assert_eq!(m.state.overs_left_for_bowler(opener), Some(0));
        m.push(ScoringEventKind::BowlerChanged { bowler_id: m.away[1].id });
        for _ in 0..6 {
            m.runs(0);
        }
        // The opener is off consecutive-over duty now, but has no overs left.
        let result = m.try_push(ScoringEventKind::BowlerChanged { bowler_id: opener });
        assert!(result.is_err(), "their single over is gone");
        assert_eq!(
            m.state.bowler_unavailable_reason(opener).as_deref(),
            Some("has bowled their 1 overs")
        );
    }

    #[test]
    fn no_allocation_means_no_limit() {
        let mut m = Fixture::new(6);
        m.push(ScoringEventKind::ConditionsProposed {
            conditions: MatchConditions {
                overs_limit: 6,
                overs_per_bowler: 0,
                ground: GroundType::Boxed,
                ball: BallType::Tennis,
            },
            by: MatchSide::Home,
            by_name: "Ravi".into(),
        });
        m.push(ScoringEventKind::ConditionsAgreed {
            side: MatchSide::Away,
            captain_name: "Sam".into(),
        });
        let a = m.innings().bowler_id.unwrap();
        let b = m.away[1].id;
        assert_eq!(m.state.overs_left_for_bowler(a), None, "no limit to report");

        // Alternate for four overs; with no allocation neither runs out.
        for _ in 0..2 {
            for _ in 0..6 {
                m.runs(0);
            }
            m.push(ScoringEventKind::BowlerChanged { bowler_id: b });
            for _ in 0..6 {
                m.runs(0);
            }
            m.push(ScoringEventKind::BowlerChanged { bowler_id: a });
        }
        assert_eq!(m.innings().bowlers.len(), 2);
        assert_eq!(m.state.overs_left_for_bowler(b), None);
        // `a` is on now, so the only thing that could stop them is an allocation.
        assert!(m.state.bowler_unavailable_reason(a).is_none());
    }

    #[test]
    fn the_consecutive_over_rule_holds_even_two_a_side() {
        // A two-player side still has a second bowler, so the Law applies.
        let home = team("Home", 2);
        let away = team("Away", 2);
        let mut state = MatchState::default();
        let mut seq = 0;
        let push = |state: &mut MatchState, seq: &mut i64, kind| {
            *seq += 1;
            state.apply(&evt(*seq, kind)).unwrap();
        };
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::MatchPrepared {
                overs_limit: 4,
                home_name: "A".into(),
                away_name: "B".into(),
            },
        );
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::ConditionsProposed {
                conditions: MatchConditions {
                    overs_limit: 4,
                    overs_per_bowler: 0,
                    ground: GroundType::Boxed,
                    ball: BallType::Tennis,
                },
                by: MatchSide::Home,
                by_name: "A".into(),
            },
        );
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::ConditionsAgreed {
                side: MatchSide::Away,
                captain_name: "B".into(),
            },
        );
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::TossRecorded {
                winner: MatchSide::Home,
                decision: TossDecision::Bat,
            },
        );
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::XiSelected {
                side: MatchSide::Home,
                players: home.clone(),
                captain_id: None,
                keeper_id: None,
            },
        );
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::XiSelected {
                side: MatchSide::Away,
                players: away.clone(),
                captain_id: None,
                keeper_id: None,
            },
        );
        push(
            &mut state,
            &mut seq,
            ScoringEventKind::InningsStarted {
                innings_index: 0,
                batting: MatchSide::Home,
                striker_id: home[0].id,
                non_striker_id: home[1].id,
                bowler_id: away[0].id,
            },
        );
        for _ in 0..6 {
            seq += 1;
            state
                .apply(&evt(
                    seq,
                    ScoringEventKind::DeliveryRecorded {
                        runs: 0,
                        is_legal: true,
                        is_boundary_four: false,
                        is_boundary_six: false,
                        shot: None,
                    },
                ))
                .unwrap();
        }
        seq += 1;
        assert!(
            state
                .apply(&evt(
                    seq,
                    ScoringEventKind::BowlerChanged {
                        bowler_id: away[0].id
                    }
                ))
                .is_err(),
            "the other player has to bowl the next one"
        );
    }

    // MARK: extras that carry runs

    fn extras(kind: ExtraKind, runs: u8, boundary: bool, off_the_bat: bool) -> ScoringEventKind {
        ScoringEventKind::ExtrasRecorded {
            kind,
            runs,
            boundary,
            off_the_bat,
            shot: None,
        }
    }

    #[test]
    fn a_wide_they_ran_a_single_off_is_two() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        m.push(extras(ExtraKind::Wide, 1, false, false));
        assert_eq!(m.innings().runs, 2, "one for the wide, one run");
        assert_eq!(m.innings().wides, 2, "both go down as wides");
        assert_eq!(m.innings().legal_balls, 0, "and it is not a ball");
        assert_eq!(m.innings().bowlers[0].runs, 2);
        let batter = m.innings().batters.iter().find(|b| b.player_id == striker).unwrap();
        assert_eq!(batter.balls, 0, "nobody faces a wide");
        assert_ne!(m.innings().striker_id, Some(striker), "an odd run rotates strike");
    }

    #[test]
    fn a_wide_to_the_boundary_is_five() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        m.push(extras(ExtraKind::Wide, 4, true, false));
        assert_eq!(m.innings().runs, 5);
        assert_eq!(m.innings().wides, 5);
        assert_eq!(m.innings().extras, 5);
        assert_eq!(m.innings().striker_id, Some(striker), "a boundary does not rotate");
    }

    #[test]
    fn a_no_ball_hit_for_six_gives_the_batter_the_six() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        m.push(extras(ExtraKind::NoBall, 6, true, true));
        assert_eq!(m.innings().runs, 7, "one for the no ball, six off the bat");
        assert_eq!(m.innings().extras, 1, "only the no ball is an extra");
        assert_eq!(m.innings().no_balls, 1);
        let batter = m.innings().batters.iter().find(|b| b.player_id == striker).unwrap();
        assert_eq!(batter.runs, 6);
        assert_eq!(batter.sixes, 1);
        assert_eq!(batter.balls, 1, "a no ball is faced");
        assert_eq!(m.innings().bowlers[0].runs, 7, "and all of it is the bowler's");
    }

    #[test]
    fn byes_off_a_no_ball_are_not_the_bowlers_fault() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        m.push(extras(ExtraKind::NoBall, 2, false, false));
        assert_eq!(m.innings().runs, 3, "one no ball, two byes");
        assert_eq!(m.innings().no_balls, 1);
        assert_eq!(m.innings().byes, 2);
        assert_eq!(m.innings().extras, 3);
        assert_eq!(m.innings().bowlers[0].runs, 1, "only the no ball is charged");
        let batter = m.innings().batters.iter().find(|b| b.player_id == striker).unwrap();
        assert_eq!(batter.runs, 0, "byes are nobody's runs");
    }

    #[test]
    fn three_byes_rotate_the_strike_and_use_a_ball() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        m.push(extras(ExtraKind::Bye, 3, false, false));
        assert_eq!(m.innings().runs, 3);
        assert_eq!(m.innings().byes, 3);
        assert_eq!(m.innings().legal_balls, 1);
        assert_eq!(m.innings().bowlers[0].runs, 0);
        assert_ne!(m.innings().striker_id, Some(striker));
    }

    #[test]
    fn a_penalty_is_five_runs_and_no_delivery() {
        let mut m = Fixture::new(20);
        m.push(extras(ExtraKind::Penalty, 5, false, false));
        assert_eq!(m.innings().runs, 5);
        assert_eq!(m.innings().penalties, 5);
        assert_eq!(m.innings().legal_balls, 0);
        assert_eq!(m.innings().bowlers[0].runs, 0);
    }

    #[test]
    fn wides_do_not_end_the_over() {
        let mut m = Fixture::new(1);
        for _ in 0..5 {
            m.push(extras(ExtraKind::Wide, 0, false, false));
        }
        assert_eq!(m.innings().legal_balls, 0);
        assert!(!m.innings().complete, "five wides is not an over");
        assert_eq!(m.innings().runs, 5);
    }

    // MARK: free hit, retired hurt, and dismissals on an extra

    fn wicket(
        batter_id: Uuid,
        kind: DismissalKind,
        new_batter_id: Option<Uuid>,
    ) -> ScoringEventKind {
        ScoringEventKind::WicketRecorded {
            batter_id,
            kind,
            fielder_id: None,
            new_batter_id,
            runs: 0,
            on_extra: false,
        }
    }

    #[test]
    fn a_no_ball_buys_a_free_hit_off_the_next_delivery() {
        let mut m = Fixture::new(20);
        assert!(!m.innings().free_hit);
        m.push(extras(ExtraKind::NoBall, 0, false, false));
        assert!(m.innings().free_hit, "the next legal ball is a free hit");

        // Another no ball keeps it alive.
        m.push(extras(ExtraKind::NoBall, 0, false, false));
        assert!(m.innings().free_hit);

        m.runs(1);
        assert!(!m.innings().free_hit, "one legal delivery spends it");
    }

    #[test]
    fn only_a_run_out_gets_you_on_a_free_hit() {
        let mut m = Fixture::new(20);
        m.push(extras(ExtraKind::NoBall, 0, false, false));
        let striker = m.innings().striker_id.unwrap();

        for kind in [
            DismissalKind::Bowled,
            DismissalKind::Caught,
            DismissalKind::Lbw,
            DismissalKind::Stumped,
            DismissalKind::HitWicket,
        ] {
            let result = m.try_push(wicket(striker, kind, Some(m.home[2].id)));
            assert!(result.is_err(), "{kind:?} should not stand on a free hit");
            m.seq -= 1;
        }

        m.push(wicket(striker, DismissalKind::RunOut, Some(m.home[2].id)));
        assert_eq!(m.innings().wickets, 1);
    }

    #[test]
    fn retired_hurt_costs_a_batter_but_not_a_wicket() {
        let mut m = Fixture::new(20);
        m.runs(2);
        let striker = m.innings().striker_id.unwrap();
        m.push(wicket(striker, DismissalKind::RetiredHurt, Some(m.home[2].id)));

        assert_eq!(m.innings().wickets, 0, "retiring hurt is not a wicket");
        assert!(m.innings().fall.is_empty(), "and does not fall");
        let batter = m.innings().batters.iter().find(|b| b.player_id == striker).unwrap();
        assert!(batter.retired_hurt);
        assert!(!batter.out);
        assert!(batter.can_resume());
        assert_eq!(m.state.dismissal_text(batter), "retired hurt");
        assert_eq!(m.innings().striker_id, Some(m.home[2].id));
    }

    #[test]
    fn a_batter_who_retired_hurt_can_come_back() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        m.push(wicket(striker, DismissalKind::RetiredHurt, Some(m.home[2].id)));
        // The replacement is then out, and the injured batter resumes.
        m.push(wicket(m.home[2].id, DismissalKind::Bowled, Some(m.home[3].id)));
        m.push(ScoringEventKind::BatterResumed {
            batter_id: striker,
            replacing_id: Some(m.home[3].id),
        });

        let batter = m.innings().batters.iter().find(|b| b.player_id == striker).unwrap();
        assert!(!batter.retired_hurt, "back at the crease");
        assert!(
            m.innings().striker_id == Some(striker) || m.innings().non_striker_id == Some(striker)
        );
        assert_eq!(m.innings().wickets, 1, "only the bowled one counted");
    }

    #[test]
    fn only_someone_who_retired_hurt_can_resume() {
        let mut m = Fixture::new(20);
        let result = m.try_push(ScoringEventKind::BatterResumed {
            batter_id: m.home[5].id,
            replacing_id: None,
        });
        assert!(result.is_err());
    }

    #[test]
    fn a_stumping_off_a_wide_does_not_count_the_ball_twice() {
        let mut m = Fixture::new(20);
        m.push(extras(ExtraKind::Wide, 0, false, false));
        assert_eq!(m.innings().legal_balls, 0);
        let striker = m.innings().striker_id.unwrap();

        m.push(ScoringEventKind::WicketRecorded {
            batter_id: striker,
            kind: DismissalKind::Stumped,
            fielder_id: Some(m.away[1].id),
            new_batter_id: Some(m.home[2].id),
            runs: 0,
            on_extra: true,
        });

        assert_eq!(m.innings().wickets, 1);
        assert_eq!(
            m.innings().legal_balls,
            0,
            "a wide is not a ball, and the stumping does not make it one"
        );
        assert_eq!(m.innings().bowlers[0].wickets, 1, "the stumping is the bowler's");
    }

    #[test]
    fn the_player_of_the_match_is_recorded_and_undone_with_everything_else() {
        let mut m = Fixture::new(20);
        m.push(ScoringEventKind::PlayerOfTheMatch {
            player_id: m.home[0].id,
        });
        assert_eq!(m.state.player_of_the_match, Some(m.home[0].id));
        m.push(ScoringEventKind::UndoLast);
        assert_eq!(m.state.player_of_the_match, None);
    }

    #[test]
    fn umpires_are_named_before_the_toss_and_may_score() {
        let mut m = Fixture::new(20);
        let umpire = MatchPlayer {
            id: Uuid::new_v4(),
            name: "Alan Umpire".into(),
            bats_left: false,
        };
        let scorer = MatchPlayer {
            id: Uuid::new_v4(),
            name: "Book Keeper".into(),
            bats_left: false,
        };
        m.push(ScoringEventKind::OfficialsAppointed {
            officials: MatchOfficials {
                umpires: vec![umpire.clone()],
                scorers: vec![scorer.clone()],
            },
        });
        assert!(m.state.is_official(umpire.id));
        assert!(m.state.is_official(scorer.id));
        assert!(!m.state.is_official(m.home[0].id));
        // Names travel, so the scorecard can print who stood.
        assert_eq!(m.state.name_for(umpire.id), "Alan Umpire");
    }

    // MARK: the wagon wheel

    #[test]
    fn a_shot_is_kept_against_the_batter_who_played_it() {
        let mut m = Fixture::new(20);
        let striker = m.innings().striker_id.unwrap();
        m.push(ScoringEventKind::DeliveryRecorded {
            runs: 4,
            is_legal: true,
            is_boundary_four: true,
            is_boundary_six: false,
            shot: Some(ShotRecord {
                angle: 280,
                kind: ShotKind::Drive,
                reach: 1.0,
            }),
        });
        let shots = m.innings().shots(Some(striker));
        assert_eq!(shots.len(), 1);
        assert_eq!(shots[0].shot.unwrap().kind, ShotKind::Drive);
        assert_eq!(m.state.shot_region(shots[0]), Some("cover"));
    }

    #[test]
    fn the_field_mirrors_for_a_left_hander() {
        // 280 degrees is cover to a right-hander and mid-wicket to a lefty.
        assert_eq!(region_for(280, false), "cover");
        assert_eq!(region_for(280, true), "mid-wicket");
        assert_eq!(region_for(50, false), "mid-wicket");
        assert_eq!(region_for(50, true), "cover");
        // Straight is straight for everyone.
        assert_eq!(region_for(0, false), region_for(0, true));
    }

    #[test]
    fn every_angle_lands_in_a_region() {
        for angle in 0..360u16 {
            assert!(!region_for(angle, false).is_empty(), "no region for {angle}");
            assert!(!region_for(angle, true).is_empty(), "no mirrored region for {angle}");
        }
    }

    #[test]
    fn a_left_hander_on_the_sheet_is_remembered() {
        let mut m = Fixture::new(20);
        let lefty = MatchPlayer {
            id: Uuid::new_v4(),
            name: "Lefty".into(),
            bats_left: true,
        };
        let mut sheet = m.home.clone();
        sheet[10] = lefty.clone();
        m.push(ScoringEventKind::XiSelected {
            side: MatchSide::Home,
            players: sheet,
            captain_id: None,
            keeper_id: None,
        });
        assert!(m.state.bats_left(lefty.id));
        assert!(!m.state.bats_left(m.home[0].id));
    }

    // MARK: rain

    #[test]
    fn revised_overs_shorten_the_innings_and_the_chase() {
        let mut m = Fixture::new(20);
        m.runs(1);
        m.push(ScoringEventKind::OversRevised {
            innings_index: 0,
            overs: 10,
        });
        assert_eq!(m.innings().overs_available, 10);
        assert_eq!(m.innings().balls_remaining(), 59);
    }

    #[test]
    fn overs_cannot_be_cut_below_what_has_been_bowled() {
        let mut m = Fixture::new(20);
        for _ in 0..12 {
            m.runs(0);
        }
        let result = m.try_push(ScoringEventKind::OversRevised {
            innings_index: 0,
            overs: 1,
        });
        assert!(result.is_err(), "two overs are already gone");
    }

    #[test]
    fn cutting_the_overs_to_what_has_been_bowled_ends_the_innings() {
        let mut m = Fixture::new(20);
        for _ in 0..6 {
            m.runs(1);
        }
        m.push(ScoringEventKind::OversRevised {
            innings_index: 0,
            overs: 1,
        });
        assert!(m.innings().complete);
    }

    // MARK: DLS

    #[test]
    fn a_chase_has_a_par_score_from_the_first_ball() {
        let table = crate::cricket::dls::ResourceTable::default();
        let mut m = Fixture::new(20);
        for _ in 0..6 {
            m.runs(4);
        }
        m.push(ScoringEventKind::InningsCompleted);
        m.push(ScoringEventKind::InningsStarted {
            innings_index: 1,
            batting: MatchSide::Away,
            striker_id: m.away[0].id,
            non_striker_id: m.away[1].id,
            bowler_id: m.home[0].id,
        });

        let start = m.state.dls_par(&table, crate::cricket::dls::DEFAULT_G50).unwrap();
        assert_eq!(start.par, 0, "nothing used, nothing to be level with");

        m.runs(2);
        let after = m.state.dls_par(&table, crate::cricket::dls::DEFAULT_G50).unwrap();
        assert!(after.par >= 0);
        assert_eq!(after.ahead_by, 2 - after.par);
        assert!(after.summary().contains("DLS par"));
    }

    #[test]
    fn a_chase_cut_short_by_rain_needs_less() {
        let table = crate::cricket::dls::ResourceTable::default();
        let mut m = Fixture::new(20);
        for _ in 0..12 {
            m.runs(3);
        }
        m.push(ScoringEventKind::InningsCompleted);
        m.push(ScoringEventKind::InningsStarted {
            innings_index: 1,
            batting: MatchSide::Away,
            striker_id: m.away[0].id,
            non_striker_id: m.away[1].id,
            bowler_id: m.home[0].id,
        });
        let full = m.state.dls_par(&table, crate::cricket::dls::DEFAULT_G50).unwrap();

        m.push(ScoringEventKind::OversRevised {
            innings_index: 1,
            overs: 10,
        });
        let shortened = m.state.dls_par(&table, crate::cricket::dls::DEFAULT_G50).unwrap();
        assert!(
            shortened.target < full.target,
            "ten overs should chase less than twenty: {} vs {}",
            shortened.target,
            full.target
        );
    }

    #[test]
    fn names_travel_with_the_team_sheet() {
        let m = Fixture::new(20);
        assert_eq!(m.state.name_for(m.home[0].id), "Home 0");
        assert_eq!(m.state.name_for(m.away[5].id), "Away 5");
    }
}
