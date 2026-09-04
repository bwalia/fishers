//! In-app chat. Threads hang off a club, team or fixture, and the agent reads
//! them to work out availability, squads and announcements.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::types::JsonValue;
use uuid::Uuid;
use validator::Validate;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Conversation {
    pub id: Uuid,
    pub club_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub event_id: Option<Uuid>,
    /// `club` | `team` | `event` | `direct`
    pub kind: String,
    pub title: String,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// A thread plus the bits the app needs to render a list row.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ConversationSummary {
    pub id: Uuid,
    pub club_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub event_id: Option<Uuid>,
    pub kind: String,
    pub title: String,
    pub updated_at: DateTime<Utc>,
    pub last_message_body: Option<String>,
    pub last_message_at: Option<DateTime<Utc>>,
    pub unread_count: i64,
    pub pending_proposals: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ChatMessage {
    pub id: Uuid,
    pub conversation_id: Uuid,
    /// `None` when the agent wrote it.
    pub sender_id: Option<Uuid>,
    pub sender_name: Option<String>,
    /// `text` | `system` | `agent`
    pub kind: String,
    pub body: String,
    pub metadata: JsonValue,
    pub created_at: DateTime<Utc>,
    pub edited_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateConversationRequest {
    #[validate(length(min = 1, max = 120))]
    pub title: String,
    pub club_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub event_id: Option<Uuid>,
    /// Defaults to `club`, or `event` when an `event_id` is given.
    pub kind: Option<String>,
    /// Members to add alongside the creator; a club thread defaults to the roster.
    #[serde(default)]
    pub member_ids: Vec<Uuid>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct PostMessageRequest {
    #[validate(length(min = 1, max = 4000))]
    pub body: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MarkReadRequest {
    /// Defaults to now when omitted.
    pub read_at: Option<DateTime<Utc>>,
}
