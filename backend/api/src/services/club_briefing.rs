//! Shared club briefing for the chat agent (and any future tools).
//!
//! One builder → one JSON context. Chat analyse and selection agent should
//! not invent separate roster/fixture snapshots.

use fishers_agent::{
    AgentContext, AvailabilityEntry, FixtureEntry, RosterEntry, TranscriptLine,
};
use fishers_db::repos::{agent as agent_repo, chat as chat_repo, clubs as clubs_repo};
use fishers_domain::{reliability, Conversation};
use chrono::Utc;
use uuid::Uuid;

use crate::error::ApiResult;
use crate::state::AppState;

const CONTEXT_DAYS_AHEAD: i32 = 21;
const TRANSCRIPT_LIMIT: i64 = 60;

/// Authoritative club snapshot for LLM reasoning — never a second database.
pub async fn build_club_briefing(
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

    // Recent platform activity — helps "what's happening?" without guessing.
    let recent = fishers_db::repos::platform::list_for_club(&state.pool, club_id, 12)
        .await
        .unwrap_or_default();
    let _platform_hint = recent
        .iter()
        .map(|(_, ty, _, at)| format!("{at}: {ty}"))
        .collect::<Vec<_>>()
        .join("\n");

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
