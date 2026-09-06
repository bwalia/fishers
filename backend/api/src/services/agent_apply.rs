//! Apply agent proposals through the same domain write paths as the rest of Fishers.

use fishers_db::repos::{
    agent as agent_repo, availability as availability_repo, chat as chat_repo,
    invites as invites_repo, platform as platform_repo, users as users_repo,
};
use fishers_domain::{
    AgentProposal, ChatMessage, PlatformEvent, PlatformEventKind, ProposalPayload,
    UpsertAvailabilityRequest,
};
use serde_json::json;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub async fn apply_proposal(
    state: &AppState,
    proposal: &AgentProposal,
    decided_by: Uuid,
    club_id: Option<Uuid>,
) -> ApiResult<AgentProposal> {
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

            if let Some(club_id) = club_id {
                let status_word = serde_json::to_value(status)
                    .ok()
                    .and_then(|v| v.as_str().map(str::to_owned))
                    .unwrap_or_else(|| "updated".into());
                platform_repo::emit_best_effort(
                    &state.pool,
                    PlatformEvent::new(
                        club_id,
                        platform_repo::agent_actor(proposal.id),
                        PlatformEventKind::AvailabilityChanged {
                            user_id,
                            date: date.to_string(),
                            status: status_word.clone(),
                        },
                    ),
                )
                .await;
            }

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
                state,
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
            // Same invite path captains use from the selection / invite APIs.
            for user_id in &payload.user_ids {
                invites_repo::invite_to_event(&state.pool, event_id, *user_id, decided_by)
                    .await?;
            }
            if let Some(club_id) = club_id {
                platform_repo::emit_best_effort(
                    &state.pool,
                    PlatformEvent::new(
                        club_id,
                        platform_repo::agent_actor(proposal.id),
                        PlatformEventKind::SquadChanged {
                            event_id,
                            user_ids: payload.user_ids.clone(),
                        },
                    ),
                )
                .await;
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
                state,
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
            if proposal.kind == "payment_chase" {
                if let Some(club_id) = club_id {
                    let unpaid =
                        agent_repo::unpaid_fee_users(&state.pool, club_id).await.unwrap_or_default();
                    platform_repo::emit_best_effort(
                        &state.pool,
                        PlatformEvent::new(
                            club_id,
                            platform_repo::agent_actor(proposal.id),
                            PlatformEventKind::PaymentChaseIssued {
                                club_id,
                                outstanding_user_ids: unpaid,
                            },
                        ),
                    )
                    .await;
                }
            }
            post_agent_note(
                state,
                proposal.conversation_id,
                &body,
                proposal.id,
                &proposal.kind,
            )
            .await?;
        }
        other => {
            return Err(ApiError::bad_request(format!("unknown proposal kind: {other}")));
        }
    }

    if let Some(club_id) = club_id {
        platform_repo::emit_best_effort(
            &state.pool,
            PlatformEvent::new(
                club_id,
                platform_repo::user_actor(decided_by),
                PlatformEventKind::AgentProposalApplied {
                    proposal_id: proposal.id,
                    kind: proposal.kind.clone(),
                    conversation_id: proposal.conversation_id,
                },
            ),
        )
        .await;
    }

    agent_repo::decide_proposal(&state.pool, proposal.id, "applied", decided_by)
        .await?
        .ok_or_else(|| ApiError::conflict("proposal has already been decided"))
}

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
