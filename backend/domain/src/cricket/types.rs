//! Cricket scoring types and events.
//!
//! Player names travel inside the event log (`XiSelected`) and end up in
//! `MatchState::player_names`, so a scorecard read on any device — or months
//! later by someone who never had the scoring app open — shows names, not UUIDs.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MatchStatus {
    Scheduled,
    Preparing,
    Toss,
    SelectingXi,
    Ready,
    Live,
    InningsBreak,
    Complete,
    Published,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TossDecision {
    Bat,
    Bowl,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MatchSide {
    Home,
    Away,
}

impl MatchSide {
    pub fn opposite(self) -> Self {
        match self {
            Self::Home => Self::Away,
            Self::Away => Self::Home,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DismissalKind {
    Bowled,
    Caught,
    Lbw,
    RunOut,
    Stumped,
    HitWicket,
    /// Retired out — counts as a wicket. Retired hurt is not modelled yet.
    Retired,
    Other,
}

impl DismissalKind {
    /// Dismissals the bowler gets credit for.
    pub fn credits_bowler(self) -> bool {
        matches!(
            self,
            Self::Bowled | Self::Caught | Self::Lbw | Self::Stumped | Self::HitWicket
        )
    }

    /// Retiring does not use up a delivery.
    pub fn uses_a_ball(self) -> bool {
        !matches!(self, Self::Retired)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExtraKind {
    Wide,
    NoBall,
    Bye,
    LegBye,
    Penalty,
}

/// A player on a team sheet. `id` is the Fishers user id for members, or a
/// locally minted id for a guest / opposition player with no account.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MatchPlayer {
    pub id: Uuid,
    pub name: String,
    /// Left-handers mirror the field, so the wagon wheel has to know.
    #[serde(default)]
    pub bats_left: bool,
}

/// How the shot was played. Enough to write a line of commentary from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShotKind {
    Drive,
    Cut,
    Pull,
    Hook,
    Sweep,
    ReverseSweep,
    Glance,
    Flick,
    Loft,
    Defence,
    Edge,
    Leave,
    Other,
}

impl ShotKind {
    /// The verb a commentator would use.
    pub fn verb(self) -> &'static str {
        match self {
            Self::Drive => "driven",
            Self::Cut => "cut",
            Self::Pull => "pulled",
            Self::Hook => "hooked",
            Self::Sweep => "swept",
            Self::ReverseSweep => "reverse-swept",
            Self::Glance => "glanced",
            Self::Flick => "flicked",
            Self::Loft => "lofted",
            Self::Defence => "defended",
            Self::Edge => "edged",
            Self::Leave => "left alone",
            Self::Other => "worked away",
        }
    }
}

/// Where the ball went. `angle` is degrees clockwise from straight down the
/// ground past the bowler, as struck — so the wheel draws correctly for a
/// left-hander even though the region *names* are mirrored for them.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct ShotRecord {
    pub angle: u16,
    pub kind: ShotKind,
    /// 0.0 at the stumps, 1.0 at the rope. Boundaries are 1.0.
    #[serde(default = "default_shot_reach")]
    pub reach: f32,
}

fn default_shot_reach() -> f32 {
    0.6
}

/// The eight sectors of a wagon wheel, named as the batter's own field.
///
/// `angle` is 0 straight down the ground past the bowler, increasing towards a
/// right-hander's leg side. A left-hander's field is the mirror image, so the
/// same struck angle gets the opposite name — which is what makes "driven
/// through cover" read correctly for both.
pub fn region_for(angle: u16, bats_left: bool) -> &'static str {
    let angle = angle % 360;
    let angle = if bats_left { (360 - angle) % 360 } else { angle };
    match angle {
        0..=44 => "long on",
        45..=89 => "mid-wicket",
        90..=134 => "square leg",
        135..=179 => "fine leg",
        180..=224 => "third man",
        225..=269 => "point",
        270..=314 => "cover",
        _ => "long off",
    }
}

/// Append-only scoring event (client + server share this shape).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ScoringEventKind {
    MatchPrepared {
        overs_limit: u8,
        home_name: String,
        away_name: String,
    },
    TossRecorded {
        winner: MatchSide,
        decision: TossDecision,
    },
    XiSelected {
        side: MatchSide,
        /// The team sheet, batting order first. Any size from 2 to 15 — club
        /// cricket is not always eleven a side.
        players: Vec<MatchPlayer>,
        captain_id: Option<Uuid>,
        keeper_id: Option<Uuid>,
    },
    /// Rain, bad light, a late start: this innings now has fewer overs. Recorded
    /// as an event so the DLS par score moves with it.
    OversRevised {
        innings_index: u8,
        overs: u8,
    },
    InningsStarted {
        innings_index: u8,
        batting: MatchSide,
        striker_id: Uuid,
        non_striker_id: Uuid,
        bowler_id: Uuid,
    },
    DeliveryRecorded {
        runs: u8,
        /// Legal delivery if true (counts toward over).
        is_legal: bool,
        is_boundary_four: bool,
        is_boundary_six: bool,
        /// What the batter played and where it went, for the wagon wheel.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        shot: Option<ShotRecord>,
    },
    /// An extra, plus whatever came of the ball afterwards.
    ///
    /// `runs` is what the batters *ran* (or the boundary), on top of the one-run
    /// penalty a wide or no ball carries by itself. So a wide they ran a single
    /// off is `{ kind: wide, runs: 1 }` = 2 to the side; a no ball hit for four
    /// is `{ kind: no_ball, runs: 4, boundary: true, off_the_bat: true }` = 5.
    ExtrasRecorded {
        kind: ExtraKind,
        #[serde(default)]
        runs: u8,
        #[serde(default)]
        boundary: bool,
        /// No ball only: the runs came off the bat, so they belong to the batter
        /// rather than to the extras column.
        #[serde(default)]
        off_the_bat: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        shot: Option<ShotRecord>,
    },
    WicketRecorded {
        batter_id: Uuid,
        kind: DismissalKind,
        fielder_id: Option<Uuid>,
        /// New batter in (required unless the innings ends).
        new_batter_id: Option<Uuid>,
        /// Runs completed before the dismissal — run-outs are usually 1 or 2.
        #[serde(default)]
        runs: u8,
    },
    BowlerChanged {
        bowler_id: Uuid,
    },
    InningsCompleted,
    MatchCompleted {
        winner: Option<MatchSide>,
        margin: String,
    },
    UndoLast,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScoringEvent {
    pub client_event_id: Uuid,
    pub seq: i64,
    pub kind: ScoringEventKind,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatterStats {
    pub player_id: Uuid,
    pub runs: u16,
    pub balls: u16,
    pub fours: u16,
    pub sixes: u16,
    pub out: bool,
    pub dismissal: Option<DismissalKind>,
    /// Who bowled the dismissal, for "c Smith b Jones".
    #[serde(default)]
    pub bowler_id: Option<Uuid>,
    #[serde(default)]
    pub fielder_id: Option<Uuid>,
}

impl BatterStats {
    pub fn new(player_id: Uuid) -> Self {
        Self {
            player_id,
            runs: 0,
            balls: 0,
            fours: 0,
            sixes: 0,
            out: false,
            dismissal: None,
            bowler_id: None,
            fielder_id: None,
        }
    }

    pub fn strike_rate(&self) -> f64 {
        if self.balls == 0 {
            return 0.0;
        }
        (self.runs as f64) * 100.0 / (self.balls as f64)
    }

    /// True once the batter has faced a ball or been dismissed — used to leave
    /// the rest of the order off the card as "did not bat".
    pub fn has_batted(&self) -> bool {
        self.balls > 0 || self.runs > 0 || self.out
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BowlerStats {
    pub player_id: Uuid,
    pub balls: u16,
    pub runs: u16,
    pub wickets: u16,
    pub maidens: u16,
    pub current_over_runs: u16,
    #[serde(default)]
    pub wides: u16,
    #[serde(default)]
    pub no_balls: u16,
}

impl BowlerStats {
    pub fn new(player_id: Uuid) -> Self {
        Self {
            player_id,
            balls: 0,
            runs: 0,
            wickets: 0,
            maidens: 0,
            current_over_runs: 0,
            wides: 0,
            no_balls: 0,
        }
    }

    pub fn overs_display(&self) -> String {
        format!("{}.{}", self.balls / 6, self.balls % 6)
    }

    pub fn economy(&self) -> f64 {
        if self.balls == 0 {
            return 0.0;
        }
        (self.runs as f64) * 6.0 / (self.balls as f64)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FallOfWicket {
    pub score: u16,
    pub wickets: u8,
    pub batter_id: Uuid,
    pub over_ball: String,
    /// The stand that just ended.
    #[serde(default)]
    pub partnership_runs: u16,
    #[serde(default)]
    pub partnership_balls: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeliveryRecord {
    pub over: u16,
    pub ball_in_over: u8,
    pub label: String,
    pub runs: u8,
    pub is_legal: bool,
    pub is_wicket: bool,
    /// Who was on strike — the wagon wheel is drawn per batter.
    #[serde(default)]
    pub batter_id: Option<Uuid>,
    #[serde(default)]
    pub bowler_id: Option<Uuid>,
    #[serde(default)]
    pub shot: Option<ShotRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InningsState {
    pub index: u8,
    pub batting: MatchSide,
    pub bowling: MatchSide,
    pub runs: u16,
    pub wickets: u8,
    pub legal_balls: u16,
    pub extras: u16,
    pub batters: Vec<BatterStats>,
    pub bowlers: Vec<BowlerStats>,
    pub fall: Vec<FallOfWicket>,
    pub deliveries: Vec<DeliveryRecord>,
    pub striker_id: Option<Uuid>,
    pub non_striker_id: Option<Uuid>,
    pub bowler_id: Option<Uuid>,
    pub complete: bool,
    pub balls_in_current_over: u8,
    /// Extras broken down, as every scorecard shows them.
    #[serde(default)]
    pub wides: u16,
    #[serde(default)]
    pub no_balls: u16,
    #[serde(default)]
    pub byes: u16,
    #[serde(default)]
    pub leg_byes: u16,
    #[serde(default)]
    pub penalties: u16,
    #[serde(default)]
    pub partnership_runs: u16,
    #[serde(default)]
    pub partnership_balls: u16,
    /// All out at this many wickets — one fewer than the team sheet.
    #[serde(default = "default_wickets_allowed")]
    pub wickets_allowed: u8,
    /// Overs this innings actually gets, after any weather reduction.
    #[serde(default)]
    pub overs_available: u8,
}

fn default_wickets_allowed() -> u8 {
    10
}

impl Default for InningsState {
    fn default() -> Self {
        Self {
            index: 0,
            batting: MatchSide::Home,
            bowling: MatchSide::Away,
            runs: 0,
            wickets: 0,
            legal_balls: 0,
            extras: 0,
            batters: vec![],
            bowlers: vec![],
            fall: vec![],
            deliveries: vec![],
            striker_id: None,
            non_striker_id: None,
            bowler_id: None,
            complete: false,
            balls_in_current_over: 0,
            wides: 0,
            no_balls: 0,
            byes: 0,
            leg_byes: 0,
            penalties: 0,
            partnership_runs: 0,
            partnership_balls: 0,
            wickets_allowed: 10,
            overs_available: 0,
        }
    }
}

impl InningsState {
    pub fn overs_display(&self) -> String {
        format!("{}.{}", self.legal_balls / 6, self.legal_balls % 6)
    }

    pub fn run_rate(&self) -> f64 {
        if self.legal_balls == 0 {
            return 0.0;
        }
        (self.runs as f64) * 6.0 / (self.legal_balls as f64)
    }

    pub fn is_all_out(&self) -> bool {
        self.wickets >= self.wickets_allowed
    }

    /// Balls left, given whatever overs this innings ended up with.
    pub fn balls_remaining(&self) -> u16 {
        ((self.overs_available as u16) * 6).saturating_sub(self.legal_balls)
    }

    /// Overs left as a fraction, which is what the DLS table is indexed by.
    pub fn overs_remaining(&self) -> f64 {
        (self.balls_remaining() as f64) / 6.0
    }

    /// Every recorded shot, optionally for one batter — the wagon wheel.
    pub fn shots(&self, batter: Option<Uuid>) -> Vec<&DeliveryRecord> {
        self.deliveries
            .iter()
            .filter(|d| d.shot.is_some())
            .filter(|d| batter.is_none() || d.batter_id == batter)
            .collect()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchState {
    pub status: MatchStatus,
    pub overs_limit: u8,
    pub home_name: String,
    pub away_name: String,
    pub toss_winner: Option<MatchSide>,
    pub toss_decision: Option<TossDecision>,
    pub home_xi: Vec<Uuid>,
    pub away_xi: Vec<Uuid>,
    pub home_captain: Option<Uuid>,
    pub away_captain: Option<Uuid>,
    pub home_keeper: Option<Uuid>,
    pub away_keeper: Option<Uuid>,
    pub innings: Vec<InningsState>,
    pub target: Option<u16>,
    pub winner: Option<MatchSide>,
    pub margin: Option<String>,
    pub last_seq: i64,
    /// Every player named on either sheet, so the card reads as names.
    #[serde(default)]
    pub player_names: BTreeMap<Uuid, String>,
    /// Who bats left-handed — the wagon wheel mirrors the field for them.
    #[serde(default)]
    pub left_handers: BTreeSet<Uuid>,
    /// Undo stack. Rebuilt by replaying the log, never persisted.
    #[serde(skip)]
    pub history: Vec<MatchStateSnapshot>,
}

/// Lightweight snapshot for undo (clone of innings + status fields).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchStateSnapshot {
    pub status: MatchStatus,
    pub innings: Vec<InningsState>,
    pub target: Option<u16>,
    pub winner: Option<MatchSide>,
    pub margin: Option<String>,
}

impl Default for MatchState {
    fn default() -> Self {
        Self {
            status: MatchStatus::Scheduled,
            overs_limit: 20,
            home_name: "Home".into(),
            away_name: "Away".into(),
            toss_winner: None,
            toss_decision: None,
            home_xi: vec![],
            away_xi: vec![],
            home_captain: None,
            away_captain: None,
            home_keeper: None,
            away_keeper: None,
            innings: vec![],
            target: None,
            winner: None,
            margin: None,
            last_seq: 0,
            player_names: BTreeMap::new(),
            left_handers: BTreeSet::new(),
            history: vec![],
        }
    }
}

impl MatchState {
    pub fn current_innings(&self) -> Option<&InningsState> {
        self.innings.last()
    }

    pub fn current_innings_mut(&mut self) -> Option<&mut InningsState> {
        self.innings.last_mut()
    }

    pub fn overs_balls_display(legal_balls: u16) -> String {
        format!("{}.{}", legal_balls / 6, legal_balls % 6)
    }

    pub fn name_for(&self, id: Uuid) -> String {
        self.player_names
            .get(&id)
            .cloned()
            .unwrap_or_else(|| id.to_string()[..8].to_string())
    }

    pub fn bats_left(&self, id: Uuid) -> bool {
        self.left_handers.contains(&id)
    }

    /// Where a shot went, named the way the batter's own field is laid out.
    pub fn shot_region(&self, delivery: &DeliveryRecord) -> Option<&'static str> {
        let shot = delivery.shot.as_ref()?;
        let left = delivery.batter_id.is_some_and(|id| self.bats_left(id));
        Some(region_for(shot.angle, left))
    }

    pub fn side_name(&self, side: MatchSide) -> &str {
        match side {
            MatchSide::Home => &self.home_name,
            MatchSide::Away => &self.away_name,
        }
    }

    pub fn xi(&self, side: MatchSide) -> &[Uuid] {
        match side {
            MatchSide::Home => &self.home_xi,
            MatchSide::Away => &self.away_xi,
        }
    }

    /// "c Smith b Jones", "run out (Patel)", "not out" — the scorecard line.
    pub fn dismissal_text(&self, batter: &BatterStats) -> String {
        if !batter.out {
            return "not out".into();
        }
        let bowler = batter.bowler_id.map(|id| self.name_for(id));
        let fielder = batter.fielder_id.map(|id| self.name_for(id));
        match batter.dismissal {
            Some(DismissalKind::Bowled) => match bowler {
                Some(b) => format!("b {b}"),
                None => "bowled".into(),
            },
            Some(DismissalKind::Caught) => match (fielder, bowler) {
                (Some(f), Some(b)) => format!("c {f} b {b}"),
                (None, Some(b)) => format!("c & b {b}"),
                _ => "caught".into(),
            },
            Some(DismissalKind::Lbw) => match bowler {
                Some(b) => format!("lbw b {b}"),
                None => "lbw".into(),
            },
            Some(DismissalKind::Stumped) => match (fielder, bowler) {
                (Some(f), Some(b)) => format!("st {f} b {b}"),
                (_, Some(b)) => format!("st b {b}"),
                _ => "stumped".into(),
            },
            Some(DismissalKind::HitWicket) => match bowler {
                Some(b) => format!("hit wicket b {b}"),
                None => "hit wicket".into(),
            },
            Some(DismissalKind::RunOut) => match fielder {
                Some(f) => format!("run out ({f})"),
                None => "run out".into(),
            },
            Some(DismissalKind::Retired) => "retired out".into(),
            Some(DismissalKind::Other) | None => "out".into(),
        }
    }

    pub fn current_run_rate(&self) -> f64 {
        self.current_innings().map(InningsState::run_rate).unwrap_or(0.0)
    }

    /// Balls left in the current innings, after any weather reduction.
    pub fn balls_remaining(&self) -> Option<u16> {
        Some(self.current_innings()?.balls_remaining())
    }

    /// Runs the chasing side still needs.
    pub fn runs_needed(&self) -> Option<u16> {
        let target = self.target?;
        let inn = self.current_innings()?;
        if inn.index == 0 {
            return None;
        }
        Some(target.saturating_sub(inn.runs))
    }

    pub fn required_run_rate(&self) -> Option<f64> {
        let needed = self.runs_needed()?;
        let remaining = self.balls_remaining()?;
        if remaining == 0 {
            return Some(0.0);
        }
        Some((needed as f64) * 6.0 / (remaining as f64))
    }

    /// "Lords need 42 from 30" — the line every scoreboard carries.
    /// Where the chase stands on Duckworth–Lewis–Stern, from the first ball of
    /// the second innings — so an abandoned match always has a result.
    pub fn dls_par(&self, table: &super::dls::ResourceTable, g50: f64) -> Option<super::dls::DlsPar> {
        let first = self.innings.first()?;
        let second = self.innings.get(1)?;
        super::dls::par_score(
            table,
            g50,
            first.runs,
            super::dls::InningsResources {
                overs_available: first.overs_available as f64,
                overs_remaining: first.overs_remaining(),
                wickets_lost: first.wickets,
            },
            super::dls::InningsResources {
                overs_available: second.overs_available as f64,
                overs_remaining: second.overs_remaining(),
                wickets_lost: second.wickets,
            },
            second.runs,
        )
    }

    pub fn chase_line(&self) -> Option<String> {
        let inn = self.current_innings()?;
        if inn.index == 0 || inn.complete {
            return None;
        }
        let needed = self.runs_needed()?;
        let remaining = self.balls_remaining()?;
        Some(format!(
            "{} need {needed} from {remaining} ball{}",
            self.side_name(inn.batting),
            if remaining == 1 { "" } else { "s" }
        ))
    }
}
