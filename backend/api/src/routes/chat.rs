//! Chat threads and the agent that reads them.
//!
//! The agent proposes; humans apply via shared domain services. The LLM never
//! writes the database and uses the same RBAC matrix as the rest of Fishers.

use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use fishers_agent::AgentError;
use fishers_db::repos::{agent as agent_repo, chat as chat_repo, clubs as clubs_repo};
use fishers_domain::{
    AgentAnalysis, AgentProposal, ChatMessage, Conversation, ConversationSummary,
    CreateConversationRequest, MarkReadRequest, Permission, PostMessageRequest,
};
use serde::Deserialize;
use serde_json::json;
use tracing::warn;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::require_club_permission;
use crate::services::{agent_apply, club_briefing};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/conversations", get(list_conversations).post(create_conversation))
        .route("/conversations/{id}/messages", get(list_messages).post(post_message))
        .route("/conversations/{id}/read", post(mark_read))
        .route("/conversations/{id}/proposals", get(list_proposals))
        .route("/conversations/{id}/agent/analyse", post(analyse))
        .route("/agent/proposals/{id}/apply", post(apply_proposal))
        .route("/agent/proposals/{id}/dismiss", post(dismiss_proposal))
}

async fn list_conversations(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<Vec<ConversationSummary>>> {
    Ok(Json(
        chat_repo::list_for_user(&state.pool, auth.user_id).await?,
    ))
}

async fn create_conversation(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<CreateConversationRequest>,
) -> ApiResult<Json<Conversation>> {
    body.validate()?;
    if let Some(club_id) = body.club_id {
        require_club_member(&state, club_id, auth.user_id).await?;
    }
    Ok(Json(
        chat_repo::create_conversation(&state.pool, auth.user_id, &body).await?,
    ))
}

#[derive(Debug, Deserialize)]
struct MessagePage {
    before: Option<DateTime<Utc>>,
    limit: Option<i64>,
}

async fn list_messages(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Query(page): Query<MessagePage>,
) -> ApiResult<Json<Vec<ChatMessage>>> {
    require_thread_member(&state, id, auth.user_id).await?;
    Ok(Json(
        chat_repo::list_messages(&state.pool, id, page.before, page.limit.unwrap_or(50)).await?,
    ))
}

async fn post_message(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<PostMessageRequest>,
) -> ApiResult<Json<ChatMessage>> {
    body.validate()?;
    require_thread_member(&state, id, auth.user_id).await?;

    let message = chat_repo::post_message(
        &state.pool,
        id,
        Some(auth.user_id),
        "text",
        &body.body,
        json!({}),
    )
    .await?;

    // Everyone else in the thread gets a push; the sender does not.
    let recipients = chat_repo::member_ids(&state.pool, id).await?;
    let sender_name = message.sender_name.clone().unwrap_or_default();
    for recipient in recipients.into_iter().filter(|r| *r != auth.user_id) {
        if let Err(error) = state
            .push
            .send(
                recipient,
                "chat_message",
                &sender_name,
                &body.body,
                json!({ "conversation_id": id, "message_id": message.id }),
            )
            .await
        {
            warn!(%recipient, %error, "chat push failed");
        }
    }

    Ok(Json(message))
}

async fn mark_read(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<MarkReadRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    require_thread_member(&state, id, auth.user_id).await?;
    chat_repo::mark_read(
        &state.pool,
        id,
        auth.user_id,
        body.read_at.unwrap_or_else(Utc::now),
    )
    .await?;
    Ok(Json(json!({ "ok": true })))
}

async fn list_proposals(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<AgentProposal>>> {
    require_thread_member(&state, id, auth.user_id).await?;
    Ok(Json(
        agent_repo::list_proposals(&state.pool, id, false).await?,
    ))
}

/// Read the thread and propose what needs doing. Captains and club admins only:
/// the proposals are theirs to apply.
async fn analyse(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<AgentAnalysis>> {
    let conversation = require_thread_member(&state, id, auth.user_id).await?;
    let club_id = conversation
        .club_id
        .ok_or_else(|| ApiError::bad_request("this thread is not attached to a club"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::UseAdminAssistant).await?;

    let run =
        agent_repo::start_run(&state.pool, id, auth.user_id, state.agent.model()).await?;

    if !state.agent.is_enabled() {
        let run = agent_repo::finish_run(
            &state.pool,
            run.id,
            "disabled",
            None,
            None,
            Some("ANTHROPIC_API_KEY is not set"),
        )
        .await?;
        return Ok(Json(AgentAnalysis {
            run,
            proposals: Vec::new(),
            summary: Some(
                "The assistant is switched off on this server — set ANTHROPIC_API_KEY to enable it."
                    .into(),
            ),
        }));
    }

    let context = club_briefing::build_club_briefing(&state, &conversation, club_id).await?;

    let outcome = match state.agent.analyse(&context).await {
        Ok(outcome) => outcome,
        Err(error) => {
            let status = match error {
                AgentError::Refused => "refused",
                _ => "failed",
            };
            let message = error.to_string();
            agent_repo::finish_run(&state.pool, run.id, status, None, None, Some(&message)).await?;
            warn!(%message, "agent run failed");
            return Err(match error {
                AgentError::Disabled => ApiError::internal(message),
                _ => ApiError::internal(format!("the assistant could not read this thread: {message}")),
            });
        }
    };

    let mut proposals = Vec::new();
    for extracted in &outcome.result.proposals {
        let kind = serde_json::to_value(extracted.kind)
            .ok()
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_else(|| "announcement".into());
        let confidence = serde_json::to_value(extracted.confidence)
            .ok()
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_else(|| "medium".into());
        let payload = serde_json::to_value(&extracted.payload).unwrap_or_else(|_| json!({}));

        proposals.push(
            agent_repo::insert_proposal(
                &state.pool,
                run.id,
                id,
                &kind,
                extracted.subject_user_id,
                extracted.event_id,
                payload,
                &extracted.rationale,
                &confidence,
            )
            .await?,
        );
    }

    let run = agent_repo::finish_run(
        &state.pool,
        run.id,
        "succeeded",
        outcome.input_tokens,
        outcome.output_tokens,
        None,
    )
    .await?;

    Ok(Json(AgentAnalysis {
        run,
        proposals,
        summary: outcome.result.summary,
    }))
}

/// Carry out a proposal through shared services (same writes as the rest of Fishers).
async fn apply_proposal(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<AgentProposal>> {
    let proposal = agent_repo::get_proposal(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("proposal not found"))?;
    let conversation = require_thread_member(&state, proposal.conversation_id, auth.user_id).await?;
    if let Some(club_id) = conversation.club_id {
        require_club_permission(&state, club_id, auth.user_id, Permission::UseAdminAssistant)
            .await?;
        if proposal.kind == "squad" {
            require_club_permission(&state, club_id, auth.user_id, Permission::ManageSelection)
                .await?;
        }
    }

    let updated =
        agent_apply::apply_proposal(&state, &proposal, auth.user_id, conversation.club_id).await?;
    Ok(Json(updated))
}

async fn dismiss_proposal(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<AgentProposal>> {
    let proposal = agent_repo::get_proposal(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("proposal not found"))?;
    let conversation = require_thread_member(&state, proposal.conversation_id, auth.user_id).await?;
    if let Some(club_id) = conversation.club_id {
        require_club_permission(&state, club_id, auth.user_id, Permission::UseAdminAssistant)
            .await?;
    }
    agent_repo::decide_proposal(&state.pool, id, "dismissed", auth.user_id)
        .await?
        .ok_or_else(|| ApiError::conflict("proposal has already been decided"))
        .map(Json)
}

async fn require_thread_member(
    state: &AppState,
    conversation_id: Uuid,
    user_id: Uuid,
) -> ApiResult<Conversation> {
    let conversation = chat_repo::get_conversation(&state.pool, conversation_id)
        .await?
        .ok_or_else(|| ApiError::not_found("conversation not found"))?;
    if chat_repo::is_member(&state.pool, conversation_id, user_id).await? {
        Ok(conversation)
    } else {
        Err(ApiError::forbidden("not a member of this conversation"))
    }
}

async fn require_club_member(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<()> {
    if clubs_repo::is_club_member(&state.pool, club_id, user_id).await? {
        Ok(())
    } else {
        Err(ApiError::forbidden("not a club member"))
    }
}

