//! The chat agent: it reads a thread and proposes the admin a captain would
//! otherwise do by hand. Proposals are always applied by a human — the agent
//! has no write access to availability, squads or money.

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::types::JsonValue;
use uuid::Uuid;

use crate::enums::AvailabilityStatus;

/// What the agent is allowed to suggest. Extend the CHECK constraint in
/// `20260904000002_chat_and_agent.sql` alongside this list.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProposalKind {
    /// "I can't make Saturday" → set that player's availability for a date.
    Availability,
    /// Invite a named list of players to a fixture.
    Squad,
    /// Post a message to the thread (squad announcement, meet time, reminder).
    Announcement,
    /// Name who still owes a match fee.
    PaymentChase,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Confidence {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AgentRun {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub requested_by: Uuid,
    pub model: String,
    /// `running` | `succeeded` | `failed` | `refused` | `disabled`
    pub status: String,
    pub input_tokens: Option<i32>,
    pub output_tokens: Option<i32>,
    pub error: Option<String>,
    pub created_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AgentProposal {
    pub id: Uuid,
    pub agent_run_id: Uuid,
    pub conversation_id: Uuid,
    pub kind: String,
    pub subject_user_id: Option<Uuid>,
    pub event_id: Option<Uuid>,
    pub payload: JsonValue,
    pub rationale: String,
    pub confidence: String,
    /// `pending` | `applied` | `dismissed` | `failed`
    pub status: String,
    pub decided_by: Option<Uuid>,
    pub decided_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

/// One flat payload shape covers every kind: structured outputs can't express
/// "these fields are required for this kind", so `apply` validates instead.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProposalPayload {
    /// `availability`: the day being set.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub date: Option<NaiveDate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub availability_status: Option<AvailabilityStatus>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// `squad`: players to invite, in the order the agent ranked them.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub user_ids: Vec<Uuid>,
    /// `announcement` / `payment_chase`: the text to post.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

/// What the model returns, before it becomes rows.
#[derive(Debug, Clone, Deserialize)]
pub struct ExtractedProposal {
    pub kind: ProposalKind,
    pub confidence: Confidence,
    pub rationale: String,
    pub subject_user_id: Option<Uuid>,
    pub event_id: Option<Uuid>,
    #[serde(default)]
    pub payload: ProposalPayload,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ExtractionResult {
    #[serde(default)]
    pub proposals: Vec<ExtractedProposal>,
    /// Free text for the captain when the agent found nothing to do.
    #[serde(default)]
    pub summary: Option<String>,
}

/// A run plus what it produced — the response to "read this thread".
#[derive(Debug, Clone, Serialize)]
pub struct AgentAnalysis {
    pub run: AgentRun,
    pub proposals: Vec<AgentProposal>,
    pub summary: Option<String>,
}
