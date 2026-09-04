//! Chat threads and the agent that reads them.
//!
//! The agent proposes; a captain or club admin applies. Nothing the model says
//! reaches availability, squads or money without that approval step.

use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use fishers_agent::{
    AgentContext, AgentError, AvailabilityEntry, FixtureEntry, RosterEntry, TranscriptLine,
};
use fishers_db::repos::{
    agent as agent_repo, availability as availability_repo, chat as chat_repo, clubs as clubs_repo,
    invites as invites_repo, users as users_repo,
};
use fishers_domain::{
    reliability, AgentAnalysis, AgentProposal, ChatMessage, Conversation, ConversationSummary,
    CreateConversationRequest, MarkReadRequest, PostMessageRequest, ProposalPayload,
    UpsertAvailabilityRequest,
};
use serde::Deserialize;
use serde_json::json;
use tracing::warn;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

/// How far ahead the agent looks, and how much of the thread it reads.
const CONTEXT_DAYS_AHEAD: i32 = 21;
const TRANSCRIPT_LIMIT: i64 = 60;

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
    require_captain_or_admin(&state, club_id, auth.user_id).await?;

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

    let context = build_context(&state, &conversation, club_id).await?;

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

/// Carry out a proposal and record who approved it.
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
        require_captain_or_admin(&state, club_id, auth.user_id).await?;
    }

    let payload: ProposalPayload = serde_json::from_value(proposal.payload.clone())
        .map_err(|e| ApiError::bad_request(format!("unreadable proposal payload: {e}")))?;

    match proposal.kind.as_str() {
        "availability" => {
            let user_id = proposal
                .subject_user_id
                .ok_or_else(|| ApiError::bad_request("proposal has no subject member"))?;
            let date = payload
                .date
                .ok_or_else(|| ApiError::bad_request("proposal has no date"))?;
            let status = payload
                .availability_status
                .ok_or_else(|| ApiError::bad_request("proposal has no availability status"))?;

            availability_repo::upsert(
                &state.pool,
                user_id,
                &UpsertAvailabilityRequest {
                    date,
                    status,
                    note: payload.note.clone(),
                    recurrence_rule: None,
                },
            )
            .await?;

            let who = users_repo::names_for(&state.pool, &[user_id]).await?;
            let name = who
                .first()
                .map(|(_, n)| n.clone())
                .unwrap_or_else(|| "A member".into());
            let status_word = serde_json::to_value(status)
                .ok()
                .and_then(|v| v.as_str().map(str::to_owned))
                .unwrap_or_else(|| "updated".into());
            post_agent_note(
                &state,
                proposal.conversation_id,
                &format!("Marked {name} {status_word} for {date}."),
                proposal.id,
                &proposal.kind,
            )
            .await?;
        }
        "squad" => {
            let event_id = proposal
                .event_id
                .ok_or_else(|| ApiError::bad_request("proposal has no fixture"))?;
            if payload.user_ids.is_empty() {
                return Err(ApiError::bad_request("proposal names no players"));
            }
            for user_id in &payload.user_ids {
                invites_repo::invite_to_event(&state.pool, event_id, *user_id, auth.user_id)
                    .await?;
            }
            let names = users_repo::names_for(&state.pool, &payload.user_ids).await?;
            let listed = names
                .iter()
                .map(|(_, name)| name.as_str())
                .collect::<Vec<_>>()
                .join(", ");
            let body = payload.message.clone().unwrap_or_else(|| {
                format!("Squad invited ({}): {listed}", payload.user_ids.len())
            });
            post_agent_note(
                &state,
                proposal.conversation_id,
                &body,
                proposal.id,
                &proposal.kind,
            )
            .await?;
        }
        "announcement" | "payment_chase" => {
            let body = payload
                .message
                .clone()
                .ok_or_else(|| ApiError::bad_request("proposal has no message to post"))?;
            post_agent_note(
                &state,
                proposal.conversation_id,
                &body,
                proposal.id,
                &proposal.kind,
            )
            .await?;
        }
        other => return Err(ApiError::bad_request(format!("unknown proposal kind: {other}"))),
    }

    agent_repo::decide_proposal(&state.pool, id, "applied", auth.user_id)
        .await?
        .ok_or_else(|| ApiError::conflict("proposal has already been decided"))
        .map(Json)
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
        require_captain_or_admin(&state, club_id, auth.user_id).await?;
    }
    agent_repo::decide_proposal(&state.pool, id, "dismissed", auth.user_id)
        .await?
        .ok_or_else(|| ApiError::conflict("proposal has already been decided"))
        .map(Json)
}

// MARK: helpers

async fn post_agent_note(
    state: &AppState,
    conversation_id: Uuid,
    body: &str,
    proposal_id: Uuid,
    kind: &str,
) -> ApiResult<ChatMessage> {
    Ok(chat_repo::post_message(
        &state.pool,
        conversation_id,
        None,
        "agent",
        body,
        json!({ "proposal_id": proposal_id, "kind": kind }),
    )
    .await?)
}

async fn build_context(
    state: &AppState,
    conversation: &Conversation,
    club_id: Uuid,
) -> ApiResult<AgentContext> {
    let club = clubs_repo::get_club(&state.pool, club_id).await?;
    let roster_rows = agent_repo::roster_context(&state.pool, club_id).await?;
    let user_ids: Vec<Uuid> = roster_rows.iter().map(|r| r.user_id).collect();

    let roster = roster_rows
        .iter()
        .map(|row| {
            let score = reliability::score(reliability::ReliabilityCounts {
                invites_received: row.invites_received,
                responded: row.responded,
                said_going: row.said_going,
                turned_up: row.turned_up,
                late_cancellations: row.late_cancellations,
                fees_due: row.fees_due,
                fees_paid: row.fees_paid,
            });
            let band = serde_json::to_value(score.band)
                .ok()
                .and_then(|v| v.as_str().map(str::to_owned))
                .unwrap_or_else(|| "unproven".into());
            RosterEntry {
                user_id: row.user_id,
                name: row.name.clone(),
                role: row.role.clone(),
                position: row.position_role.clone(),
                skill_level: row.skill_level.clone(),
                reliability_score: score.score,
                reliability_band: band,
                games_missed_out: row.games_missed_out,
            }
        })
        .collect();

    let fixtures = agent_repo::fixture_context(
        &state.pool,
        club_id,
        conversation.team_id,
        CONTEXT_DAYS_AHEAD,
    )
    .await?
    .into_iter()
    .map(|row| FixtureEntry {
        event_id: row.event_id,
        title: row.title,
        sport: row.sport,
        subtype: row.subtype,
        starts_at: row.start_at,
        date: row.start_at.date_naive(),
        capacity: row.capacity,
        fee_amount_cents: row.fee_amount_cents,
        already_invited: row.already_invited,
        confirmed: row.confirmed,
    })
    .collect();

    let availability =
        agent_repo::availability_context(&state.pool, &user_ids, CONTEXT_DAYS_AHEAD)
            .await?
            .into_iter()
            .map(|row| AvailabilityEntry {
                user_id: row.user_id,
                date: row.date,
                status: row.status,
            })
            .collect();

    // Newest-first from the repo; the model reads oldest-first.
    let mut transcript: Vec<TranscriptLine> =
        chat_repo::list_messages(&state.pool, conversation.id, None, TRANSCRIPT_LIMIT)
            .await?
            .into_iter()
            .map(|m| TranscriptLine {
                author: m.sender_name.clone().unwrap_or_else(|| "Assistant".into()),
                author_id: m.sender_id,
                sent_at: m.created_at,
                body: m.body,
            })
            .collect();
    transcript.reverse();

    Ok(AgentContext {
        conversation_title: conversation.title.clone(),
        conversation_kind: conversation.kind.clone(),
        club_name: club.map(|c| c.name),
        today: Utc::now().date_naive(),
        roster,
        fixtures,
        availability,
        unpaid_fees: agent_repo::unpaid_fee_users(&state.pool, club_id).await?,
        transcript,
    })
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

async fn require_captain_or_admin(
    state: &AppState,
    club_id: Uuid,
    user_id: Uuid,
) -> ApiResult<()> {
    match clubs_repo::club_role(&state.pool, club_id, user_id).await?.as_deref() {
        Some("club_admin") | Some("team_captain") | Some("super_admin") => Ok(()),
        Some(_) => Err(ApiError::forbidden(
            "only a captain or club admin can decide the assistant's proposals",
        )),
        None => Err(ApiError::forbidden("not a club member")),
    }
}
