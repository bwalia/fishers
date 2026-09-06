//! Platform-level domain events — shared club activity, not sport-specific scoring.
//!
//! These events are the single vocabulary for fan-out (stats, chat context,
//! notifications, AI briefing). Sport engines (e.g. cricket) emit them when
//! something club-meaningful happens; they never become a second database.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Who / what caused a platform event (audit trail for AI and jobs).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PlatformActor {
    User { user_id: Uuid },
    Agent { proposal_id: Uuid },
    System { job: String },
}

/// Club-scoped activity that should drive downstream behaviour.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum PlatformEventKind {
    /// A member's availability day changed.
    AvailabilityChanged {
        user_id: Uuid,
        date: String,
        status: String,
    },
    /// Players invited / squad set for a fixture.
    SquadChanged {
        event_id: Uuid,
        user_ids: Vec<Uuid>,
    },
    /// Selection board published or autonomy auto-published.
    SquadPublished { event_id: Uuid },
    /// Live cricket (or future sport) match claimed / started scoring.
    MatchStarted {
        event_id: Uuid,
        match_id: Uuid,
        sport: String,
    },
    /// Authoritative match finished (sport engine → club).
    MatchCompleted {
        event_id: Uuid,
        match_id: Uuid,
        sport: String,
        summary: Option<String>,
    },
    /// Agent proposal applied through Fishers services (not a side channel).
    AgentProposalApplied {
        proposal_id: Uuid,
        kind: String,
        conversation_id: Uuid,
    },
    /// Fee chase or payment reminder issued.
    PaymentChaseIssued {
        club_id: Uuid,
        outstanding_user_ids: Vec<Uuid>,
    },
    /// Generic recognition (MOTM later); keeps awards on match + member.
    RecognitionRecorded {
        event_id: Uuid,
        user_id: Uuid,
        kind: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlatformEvent {
    pub id: Uuid,
    pub club_id: Uuid,
    pub occurred_at: DateTime<Utc>,
    pub actor: PlatformActor,
    pub kind: PlatformEventKind,
}

impl PlatformEvent {
    pub fn new(club_id: Uuid, actor: PlatformActor, kind: PlatformEventKind) -> Self {
        Self {
            id: Uuid::new_v4(),
            club_id,
            occurred_at: Utc::now(),
            actor,
            kind,
        }
    }

    pub fn type_name(&self) -> &'static str {
        match &self.kind {
            PlatformEventKind::AvailabilityChanged { .. } => "availability_changed",
            PlatformEventKind::SquadChanged { .. } => "squad_changed",
            PlatformEventKind::SquadPublished { .. } => "squad_published",
            PlatformEventKind::MatchStarted { .. } => "match_started",
            PlatformEventKind::MatchCompleted { .. } => "match_completed",
            PlatformEventKind::AgentProposalApplied { .. } => "agent_proposal_applied",
            PlatformEventKind::PaymentChaseIssued { .. } => "payment_chase_issued",
            PlatformEventKind::RecognitionRecorded { .. } => "recognition_recorded",
        }
    }
}

/// Sport-agnostic delta that cricket (and later football, etc.) can contribute
/// into club statistics without owning the platform stats store.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MatchStatsDelta {
    pub event_id: Uuid,
    pub match_id: Uuid,
    pub sport: String,
    pub player_id: Uuid,
    pub runs: Option<u16>,
    pub wickets: Option<u16>,
    pub balls_faced: Option<u16>,
    pub overs_bowled_balls: Option<u16>,
    pub extras: Option<u16>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn match_completed_serialises_type() {
        let kind = PlatformEventKind::MatchCompleted {
            event_id: Uuid::nil(),
            match_id: Uuid::nil(),
            sport: "cricket".into(),
            summary: Some("won by 3 wickets".into()),
        };
        let ev = PlatformEvent::new(
            Uuid::nil(),
            PlatformActor::User {
                user_id: Uuid::nil(),
            },
            kind,
        );
        assert_eq!(ev.type_name(), "match_completed");
        let json = serde_json::to_value(&ev.kind).unwrap();
        assert_eq!(json["type"], "match_completed");
    }
}
