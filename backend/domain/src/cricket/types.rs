//! Cricket scoring types and events.

use serde::{Deserialize, Serialize};
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DismissalKind {
    Bowled,
    Caught,
    Lbw,
    RunOut,
    Stumped,
    HitWicket,
    Retired,
    Other,
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
        player_ids: Vec<Uuid>,
        captain_id: Option<Uuid>,
        keeper_id: Option<Uuid>,
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
    },
    ExtrasRecorded {
        kind: ExtraKind,
        runs: u8,
    },
    WicketRecorded {
        batter_id: Uuid,
        kind: DismissalKind,
        fielder_id: Option<Uuid>,
        /// New batter in (required unless innings ends).
        new_batter_id: Option<Uuid>,
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
        }
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
        }
    }

    pub fn overs_display(&self) -> String {
        format!("{}.{}", self.balls / 6, self.balls % 6)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FallOfWicket {
    pub score: u16,
    pub wickets: u8,
    pub batter_id: Uuid,
    pub over_ball: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeliveryRecord {
    pub over: u16,
    pub ball_in_over: u8,
    pub label: String,
    pub runs: u8,
    pub is_legal: bool,
    pub is_wicket: bool,
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
        }
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
    /// Snapshot of last applied event for undo.
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

    pub fn current_run_rate(&self) -> f64 {
        let Some(inn) = self.current_innings() else {
            return 0.0;
        };
        if inn.legal_balls == 0 {
            return 0.0;
        }
        (inn.runs as f64) * 6.0 / (inn.legal_balls as f64)
    }

    pub fn required_run_rate(&self) -> Option<f64> {
        let target = self.target?;
        let inn = self.current_innings()?;
        if inn.index == 0 {
            return None;
        }
        let remaining_runs = target.saturating_sub(inn.runs);
        let total_balls = (self.overs_limit as u16) * 6;
        let remaining_balls = total_balls.saturating_sub(inn.legal_balls);
        if remaining_balls == 0 {
            return Some(0.0);
        }
        Some((remaining_runs as f64) * 6.0 / (remaining_balls as f64))
    }
}
