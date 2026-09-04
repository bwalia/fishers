//! The chat agent. Reads a thread plus club context and asks Claude what admin
//! needs doing, returning proposals a captain can apply with one tap.
//!
//! Rust has no official Anthropic SDK, so this calls the Messages API over
//! plain HTTP. Structured outputs (`output_config.format`) guarantee the reply
//! parses into `ExtractionResult`, and the model never touches the database —
//! the API layer applies proposals after a human approves them.

use std::time::Duration;

use chrono::{DateTime, NaiveDate, Utc};
use fishers_domain::ExtractionResult;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use thiserror::Error;
use tracing::{debug, warn};
use uuid::Uuid;

const DEFAULT_API_URL: &str = "https://api.anthropic.com/v1/messages";
const API_VERSION: &str = "2023-06-01";
/// Routes a policy decline to a fallback model inside the same call.
const FALLBACK_BETA: &str = "server-side-fallback-2026-07-01";
const DEFAULT_MODEL: &str = "claude-opus-5";

#[derive(Debug, Error)]
pub enum AgentError {
    #[error("agent is disabled: set ANTHROPIC_API_KEY to enable it")]
    Disabled,
    #[error("claude request failed: {0}")]
    Transport(#[from] reqwest::Error),
    #[error("claude returned {status}: {body}")]
    Api { status: u16, body: String },
    #[error("claude declined the request")]
    Refused,
    #[error("could not read claude's reply: {0}")]
    Decode(String),
}

/// One person the agent may reason about. Reliability and level come from the
/// profile so the agent can rank a squad the way a captain would.
#[derive(Debug, Clone, Serialize)]
pub struct RosterEntry {
    pub user_id: Uuid,
    pub name: String,
    pub role: String,
    pub position: Option<String>,
    pub skill_level: Option<String>,
    pub reliability_score: i64,
    pub reliability_band: String,
    /// Fixtures they were left out of since they last played, so rotation is fair.
    pub games_missed_out: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct FixtureEntry {
    pub event_id: Uuid,
    pub title: String,
    pub sport: String,
    pub subtype: String,
    pub starts_at: DateTime<Utc>,
    pub date: NaiveDate,
    pub capacity: Option<i32>,
    pub fee_amount_cents: Option<i32>,
    /// Members already invited or confirmed, so the agent doesn't re-invite them.
    pub already_invited: Vec<Uuid>,
    pub confirmed: Vec<Uuid>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AvailabilityEntry {
    pub user_id: Uuid,
    pub date: NaiveDate,
    pub status: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct TranscriptLine {
    pub author: String,
    pub author_id: Option<Uuid>,
    pub sent_at: DateTime<Utc>,
    pub body: String,
}

/// Everything the agent is allowed to see for one run.
#[derive(Debug, Clone, Serialize)]
pub struct AgentContext {
    pub conversation_title: String,
    pub conversation_kind: String,
    pub club_name: Option<String>,
    pub today: NaiveDate,
    pub roster: Vec<RosterEntry>,
    pub fixtures: Vec<FixtureEntry>,
    pub availability: Vec<AvailabilityEntry>,
    pub unpaid_fees: Vec<Uuid>,
    pub transcript: Vec<TranscriptLine>,
}

/// A candidate as the deterministic ranking scored them. Handed to the model as
/// its starting point, so its decision is anchored to explainable numbers.
#[derive(Debug, Clone, Serialize)]
pub struct RankedEntry {
    pub user_id: Uuid,
    pub name: String,
    pub rank: usize,
    pub score: i64,
    pub reasons: Vec<String>,
    pub position: Option<String>,
    pub availability: Option<String>,
    pub state: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct SquadBrief {
    pub size: usize,
    pub reserves: usize,
    pub position_quotas: Vec<(String, usize)>,
    pub unmet_quotas: Vec<String>,
}

/// Everything needed to pick one side.
#[derive(Debug, Clone, Serialize)]
pub struct SelectionContext {
    pub club_name: Option<String>,
    pub fixture: FixtureEntry,
    pub brief: SquadBrief,
    pub ranked: Vec<RankedEntry>,
    /// Recent chat, so injuries and "I can only do the second half" are seen.
    pub transcript: Vec<TranscriptLine>,
    pub today: NaiveDate,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PlayerNote {
    pub user_id: Uuid,
    pub reason: String,
}

/// The model's decision. `selected` and `reserves` are the squad; `announcement`
/// is what gets posted to the thread when a captain publishes it.
#[derive(Debug, Clone, Deserialize)]
pub struct SquadDecision {
    #[serde(default)]
    pub selected: Vec<Uuid>,
    #[serde(default)]
    pub reserves: Vec<Uuid>,
    pub announcement: String,
    #[serde(default)]
    pub notes: Vec<PlayerNote>,
    /// Anything the captain should know — short of a keeper, someone injured.
    #[serde(default)]
    pub concerns: Option<String>,
    pub confidence: String,
}

#[derive(Debug, Clone)]
pub struct SquadOutcome {
    pub decision: SquadDecision,
    pub model: String,
    pub input_tokens: Option<i32>,
    pub output_tokens: Option<i32>,
}

#[derive(Debug, Clone)]
pub struct AgentOutcome {
    pub result: ExtractionResult,
    pub model: String,
    pub input_tokens: Option<i32>,
    pub output_tokens: Option<i32>,
}

#[derive(Clone)]
pub struct AgentService {
    api_key: Option<String>,
    model: String,
    /// Overridable via ANTHROPIC_BASE_URL for gateways, proxies and tests.
    api_url: String,
    http: reqwest::Client,
}

impl AgentService {
    pub fn from_env() -> Self {
        let api_key = std::env::var("ANTHROPIC_API_KEY").ok().filter(|k| !k.is_empty());
        if api_key.is_none() {
            warn!("ANTHROPIC_API_KEY unset — chat agent will return 'disabled' until it is set");
        }
        Self {
            api_key,
            model: std::env::var("FISHERS_AGENT_MODEL").unwrap_or_else(|_| DEFAULT_MODEL.into()),
            api_url: std::env::var("ANTHROPIC_BASE_URL").unwrap_or_else(|_| DEFAULT_API_URL.into()),
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(120))
                .build()
                .unwrap_or_default(),
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.api_key.is_some()
    }

    pub fn model(&self) -> &str {
        &self.model
    }

    /// One place for the HTTP call, headers and refusal handling.
    async fn post(&self, api_key: &str, body: &Value) -> Result<Value, AgentError> {
        let response = self
            .http
            .post(&self.api_url)
            .header("x-api-key", api_key)
            .header("anthropic-version", API_VERSION)
            .header("anthropic-beta", FALLBACK_BETA)
            .json(body)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(AgentError::Api {
                status: status.as_u16(),
                body,
            });
        }
        let payload: Value = response.json().await?;
        if payload["stop_reason"].as_str() == Some("refusal") {
            return Err(AgentError::Refused);
        }
        Ok(payload)
    }

    /// Ask Claude what admin this thread implies. Returns proposals only —
    /// applying them is a separate, human-approved step.
    pub async fn analyse(&self, context: &AgentContext) -> Result<AgentOutcome, AgentError> {
        let api_key = self.api_key.as_deref().ok_or(AgentError::Disabled)?;

        let body = json!({
            "model": self.model,
            "max_tokens": 16000,
            // Adaptive thinking is on by default for this tier; stated for clarity.
            "thinking": { "type": "adaptive" },
            "output_config": {
                // Reading a thread is closer to extraction than open-ended
                // reasoning, so medium effort is the cost/quality sweet spot.
                "effort": "medium",
                "format": { "type": "json_schema", "schema": extraction_schema() }
            },
            "fallbacks": "default",
            "system": [{
                "type": "text",
                "text": SYSTEM_PROMPT,
                // Stable prefix: the volatile club context goes in the user turn.
                "cache_control": { "type": "ephemeral" }
            }],
            "messages": [{
                "role": "user",
                "content": serde_json::to_string_pretty(context)
                    .map_err(|e| AgentError::Decode(e.to_string()))?
            }]
        });

        let payload = self.post(api_key, &body).await?;
        let text = first_text_block(&payload)?;
        debug!(%text, "agent reply");
        let result: ExtractionResult =
            serde_json::from_str(text).map_err(|e| AgentError::Decode(e.to_string()))?;

        Ok(AgentOutcome {
            result,
            model: payload["model"]
                .as_str()
                .unwrap_or(&self.model)
                .to_string(),
            input_tokens: payload["usage"]["input_tokens"].as_i64().map(|v| v as i32),
            output_tokens: payload["usage"]["output_tokens"].as_i64().map(|v| v as i32),
        })
    }
}

impl AgentService {
    /// Pick a side. The deterministic ranking is the starting point; the model
    /// may depart from it when the thread justifies it, and must say why.
    pub async fn pick_squad(
        &self,
        context: &SelectionContext,
    ) -> Result<SquadOutcome, AgentError> {
        let api_key = self.api_key.as_deref().ok_or(AgentError::Disabled)?;

        let body = json!({
            "model": self.model,
            "max_tokens": 16000,
            "thinking": { "type": "adaptive" },
            "output_config": {
                "effort": "medium",
                "format": { "type": "json_schema", "schema": squad_schema() }
            },
            "fallbacks": "default",
            "system": [{
                "type": "text",
                "text": SELECTION_PROMPT,
                "cache_control": { "type": "ephemeral" }
            }],
            "messages": [{
                "role": "user",
                "content": serde_json::to_string_pretty(context)
                    .map_err(|e| AgentError::Decode(e.to_string()))?
            }]
        });

        let payload = self.post(api_key, &body).await?;
        let text = first_text_block(&payload)?;
        debug!(%text, "squad decision");
        let decision: SquadDecision =
            serde_json::from_str(text).map_err(|e| AgentError::Decode(e.to_string()))?;

        Ok(SquadOutcome {
            decision,
            model: payload["model"].as_str().unwrap_or(&self.model).to_string(),
            input_tokens: payload["usage"]["input_tokens"].as_i64().map(|v| v as i32),
            output_tokens: payload["usage"]["output_tokens"].as_i64().map(|v| v as i32),
        })
    }
}

const SELECTION_PROMPT: &str = r#"You pick amateur club sides in England — cricket, football, badminton, padel, rugby, netball, hockey.

You are given one fixture, what the side needs, and every eligible player already ranked by a deterministic model: availability first, then reliability (do they turn up and pay), then rotation debt (how many fixtures they were available for and left out of). You also get the recent chat for that club.

Your job is to name the squad and the reserves, and write the announcement.

Rules:
- Start from the ranking. Depart from it only for a reason visible in the context — an injury mentioned in chat, someone saying they can only make half of it, a position the ranking could not fill — and record that reason in notes.
- Never select a player the ranking excluded for saying they are unavailable.
- Select exactly the number of places asked for, unless the available pool is smaller; then select everyone available and say so in concerns.
- Fill the position quotas. If you cannot, say which and by how many in concerns.
- Rotation matters: if two players are otherwise level, pick the one who has missed out more. Amateur clubs lose players who are never picked.
- The announcement is what the squad reads: British English, short, concrete, with the meet time if the context has one. No emoji unless the chat uses them.
- Use only user_ids from the ranked list.
- Set confidence to low when the pool is thin or the chat is ambiguous, high when availability is clear and the side picks itself."#;

/// Squad decision schema. Numeric constraints are unsupported, so the size is
/// stated in the brief and the prompt instead.
fn squad_schema() -> Value {
    json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["selected", "reserves", "announcement", "confidence"],
        "properties": {
            "selected": {
                "type": "array",
                "items": { "type": "string", "format": "uuid" },
                "description": "The squad, best pick first."
            },
            "reserves": {
                "type": "array",
                "items": { "type": "string", "format": "uuid" },
                "description": "Standby players, in the order they should be called up."
            },
            "announcement": {
                "type": "string",
                "description": "What gets posted to the thread when a captain publishes this."
            },
            "notes": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["user_id", "reason"],
                    "properties": {
                        "user_id": { "type": "string", "format": "uuid" },
                        "reason": { "type": "string" }
                    }
                },
                "description": "Only where you departed from the ranking, or a player needs context."
            },
            "concerns": {
                "anyOf": [{ "type": "string" }, { "type": "null" }],
                "description": "Short of a position, thin pool, anything the captain must know."
            },
            "confidence": { "enum": ["low", "medium", "high"] }
        }
    })
}

const SYSTEM_PROMPT: &str = r#"You are the team admin assistant inside Fishers, a club management app used by amateur clubs in England — cricket, football, badminton, padel, rugby, netball, hockey, tennis, basketball.

You read one chat thread plus the club's context and work out what admin the conversation implies, so the captain doesn't have to do it by hand. You never act: you return proposals that a captain or club admin approves.

You receive JSON with: the thread transcript (oldest first), the roster (with each member's position, standard, reliability score and how many fixtures they have missed out on), upcoming fixtures, availability already recorded, and who still owes a match fee.

Rules:
- Only propose an availability change when a member states their own availability in the thread ("can't make Saturday", "I'm free Wednesday"). Use their user_id from the roster, and the date of the fixture they are talking about.
- Never invent a person, fixture or date. Every user_id and event_id must come from the context. If you cannot resolve who or when, skip it.
- Propose a squad only when the captain asks for one, or when a fixture is within 7 days and fewer players are invited than its capacity. Rank by: recorded availability first, then reliability, then who has missed out most, then a sensible balance of positions for that sport.
- Announcements should read like a captain wrote them: British English, short, concrete. "Squad for Sat vs Hemel — meet 12:30 at the ground." Do not use emoji unless the thread already does.
- Propose payment_chase only when the context lists unpaid fees, and name only those members.
- Prefer fewer, higher-confidence proposals over many speculative ones. Mark confidence low when the thread is ambiguous.
- If nothing needs doing, return an empty proposals array and one line in summary saying so.

Terminology, per sport: a competitive game is a fixture (cricket, football, hockey, netball, rugby); cricket practice is nets; badminton social sessions are club nights; padel social sessions are Americanos. Match the thread's own wording where it differs."#;

/// Structured-output schema. Numeric and string constraints are unsupported, so
/// ranges are described in the prompt instead.
fn extraction_schema() -> Value {
    let uuid_or_null = json!({
        "anyOf": [{ "type": "string", "format": "uuid" }, { "type": "null" }]
    });

    json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["proposals"],
        "properties": {
            "summary": {
                "anyOf": [{ "type": "string" }, { "type": "null" }],
                "description": "One line for the captain when there is nothing to propose."
            },
            "proposals": {
                "type": "array",
                "description": "Admin actions implied by the thread. Empty when nothing needs doing.",
                "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["kind", "confidence", "rationale", "payload"],
                    "properties": {
                        "kind": {
                            "enum": ["availability", "squad", "announcement", "payment_chase"]
                        },
                        "confidence": { "enum": ["low", "medium", "high"] },
                        "rationale": {
                            "type": "string",
                            "description": "Why, quoting the thread where possible. Shown to the captain."
                        },
                        "subject_user_id": uuid_or_null,
                        "event_id": uuid_or_null,
                        "payload": {
                            "type": "object",
                            "additionalProperties": false,
                            "properties": {
                                "date": {
                                    "anyOf": [{ "type": "string", "format": "date" }, { "type": "null" }],
                                    "description": "availability: the day being set (YYYY-MM-DD)."
                                },
                                "availability_status": {
                                    "anyOf": [
                                        { "enum": ["available", "unavailable", "maybe"] },
                                        { "type": "null" }
                                    ]
                                },
                                "note": {
                                    "anyOf": [{ "type": "string" }, { "type": "null" }],
                                    "description": "availability: the member's own words, trimmed."
                                },
                                "user_ids": {
                                    "type": "array",
                                    "items": { "type": "string", "format": "uuid" },
                                    "description": "squad: players to invite, best pick first."
                                },
                                "message": {
                                    "anyOf": [{ "type": "string" }, { "type": "null" }],
                                    "description": "announcement / payment_chase: the text to post."
                                }
                            }
                        }
                    }
                }
            }
        }
    })
}

fn first_text_block(payload: &Value) -> Result<&str, AgentError> {
    payload["content"]
        .as_array()
        .and_then(|blocks| {
            blocks
                .iter()
                .find(|b| b["type"] == "text")
                .and_then(|b| b["text"].as_str())
        })
        .ok_or_else(|| AgentError::Decode("no text block in reply".into()))
}
