//! Squad selection, reconfirmation, reserves, fixture changes and fee chasing.
//!
//! Availability comes first, then a squad is decided — by a captain, by the
//! deterministic ranking, or by the assistant — then players reconfirm a couple
//! of days out and reserves fill any gaps. Announcements go to the fixture's
//! chat thread so nobody has to copy anything into WhatsApp.

use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::Utc;
use fishers_agent::{
    AgentError, FixtureEntry, RankedEntry, SelectionContext, SquadBrief, TranscriptLine,
};
use fishers_db::repos::{
    agent as agent_repo, chat as chat_repo, clubs as clubs_repo, events as events_repo,
    selection as selection_repo,
};
use fishers_domain::{
    selection, CreateFixtureBlockRequest, EventStatus, FixtureBlock, FixtureStatusRequest,
    RespondToSelectionRequest, SelectionBoard, SetSquadRequest, SquadProposalView, UserRole,
};
use serde_json::json;
use tracing::warn;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

/// How much chat the assistant reads when picking a side.
const TRANSCRIPT_LIMIT: i64 = 40;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/events/{id}/selection", get(board).post(set_squad))
        .route("/events/{id}/selection/suggest", post(suggest_squad))
        .route("/events/{id}/selection/agent", post(agent_squad))
        .route("/events/{id}/selection/publish", post(publish))
        .route("/events/{id}/selection/respond", post(respond))
        .route("/events/{id}/selection/promote", post(promote))
        .route("/events/{id}/status", post(update_status))
        .route("/clubs/{id}/fees/outstanding", get(outstanding_fees))
        .route("/clubs/{id}/fees/chase", post(chase_fees))
        .route("/clubs/{id}/fixture-blocks", get(list_blocks))
        .route("/fixture-blocks", post(create_block))
        .route("/fixture-blocks/{id}/selection", post(plan_block))
}

async fn board(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<SelectionBoard>> {
    let event = load_event(&state, id).await?;
    require_club_member(&state, event.club_id, auth.user_id).await?;
    Ok(Json(build_board(&state, id).await?))
}

/// Commit a squad. Optionally announce it in the same call.
async fn set_squad(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<SetSquadRequest>,
) -> ApiResult<Json<SelectionBoard>> {
    let event = load_event(&state, id).await?;
    require_captain_or_admin(&state, event.club_id, auth.user_id).await?;
    let policy = selection_repo::policy_for_club(&state.pool, event.club_id).await?;

    selection_repo::set_squad(
        &state.pool,
        id,
        auth.user_id,
        &body.selected,
        &body.reserves,
        false,
        policy.confirm_lead_hours,
    )
    .await?;

    if body.publish {
        let announcement = body.announcement.clone().unwrap_or_else(|| {
            default_announcement(&event.title, body.selected.len(), policy.confirm_lead_hours)
        });
        announce(&state, event.club_id, Some(id), &announcement).await;
        notify_squad(&state, id, "squad_published", &event.title, &announcement).await;
    }

    Ok(Json(build_board(&state, id).await?))
}

/// The deterministic pick — no model involved, works with no API key.
async fn suggest_squad(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<SquadProposalView>> {
    let event = load_event(&state, id).await?;
    require_captain_or_admin(&state, event.club_id, auth.user_id).await?;

    let candidates = selection_repo::candidates(&state.pool, id).await?;
    let requirements = selection_repo::requirements_for(&state.pool, id).await?;
    let suggestion = selection::suggest(&candidates, &requirements);

    Ok(Json(SquadProposalView {
        source: "ranking".into(),
        announcement: Some(default_announcement(
            &event.title,
            suggestion.selected.len(),
            selection_repo::policy_for_club(&state.pool, event.club_id)
                .await?
                .confirm_lead_hours,
        )),
        concerns: (!suggestion.unmet_quotas.is_empty())
            .then(|| suggestion.unmet_quotas.join("; ")),
        confidence: None,
        selected: suggestion.selected,
        reserves: suggestion.reserves,
        unmet_quotas: suggestion.unmet_quotas,
        published: false,
    }))
}

/// Let the assistant decide the side. It starts from the ranking and may depart
/// from it when the thread justifies it. Published immediately only when the
/// club has set `selection_autonomy = 'auto_publish'`.
async fn agent_squad(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<SquadProposalView>> {
    let event = load_event(&state, id).await?;
    require_captain_or_admin(&state, event.club_id, auth.user_id).await?;
    let policy = selection_repo::policy_for_club(&state.pool, event.club_id).await?;
    if policy.selection_autonomy == "off" {
        return Err(ApiError::forbidden(
            "this club has the assistant switched off for selection",
        ));
    }

    let candidates = selection_repo::candidates(&state.pool, id).await?;
    let requirements = selection_repo::requirements_for(&state.pool, id).await?;
    let fallback = selection::suggest(&candidates, &requirements);

    // No key, no model: hand back the deterministic pick rather than nothing.
    if !state.agent.is_enabled() {
        return Ok(Json(SquadProposalView {
            source: "ranking".into(),
            announcement: Some(default_announcement(
                &event.title,
                fallback.selected.len(),
                policy.confirm_lead_hours,
            )),
            concerns: Some(
                "The assistant is switched off on this server, so this is the ranking's pick."
                    .into(),
            ),
            confidence: None,
            selected: fallback.selected,
            reserves: fallback.reserves,
            unmet_quotas: fallback.unmet_quotas,
            published: false,
        }));
    }

    let ranked = selection::rank(&candidates);
    let context = SelectionContext {
        club_name: clubs_repo::get_club(&state.pool, event.club_id)
            .await?
            .map(|c| c.name),
        fixture: FixtureEntry {
            event_id: event.id,
            title: event.title.clone(),
            sport: serde_json::to_value(event.sport)
                .ok()
                .and_then(|v| v.as_str().map(str::to_owned))
                .unwrap_or_default(),
            subtype: serde_json::to_value(event.event_subtype)
                .ok()
                .and_then(|v| v.as_str().map(str::to_owned))
                .unwrap_or_default(),
            starts_at: event.start_at,
            date: event.start_at.date_naive(),
            capacity: event.capacity,
            fee_amount_cents: event.fee_amount_cents,
            already_invited: candidates
                .iter()
                .filter(|c| c.state.is_in_squad())
                .map(|c| c.user_id)
                .collect(),
            confirmed: candidates
                .iter()
                .filter(|c| c.is_confirmed)
                .map(|c| c.user_id)
                .collect(),
        },
        brief: SquadBrief {
            size: requirements.size,
            reserves: requirements.reserves,
            position_quotas: requirements
                .position_quotas
                .iter()
                .map(|q| (q.position.clone(), q.minimum))
                .collect(),
            unmet_quotas: fallback.unmet_quotas.clone(),
        },
        ranked: ranked
            .iter()
            .enumerate()
            .map(|(index, r)| {
                let candidate = candidates.iter().find(|c| c.user_id == r.user_id);
                RankedEntry {
                    user_id: r.user_id,
                    name: r.name.clone(),
                    rank: index + 1,
                    score: r.score,
                    reasons: r.reasons.clone(),
                    position: candidate.and_then(|c| c.position.clone()),
                    availability: candidate.and_then(|c| {
                        serde_json::to_value(c.availability)
                            .ok()
                            .and_then(|v| v.as_str().map(str::to_owned))
                    }),
                    state: candidate
                        .map(|c| c.state.as_str().to_string())
                        .unwrap_or_else(|| "pool".into()),
                }
            })
            .collect(),
        transcript: recent_transcript(&state, event.club_id, event.id).await?,
        today: Utc::now().date_naive(),
    };

    let run = agent_repo::start_run(
        &state.pool,
        // Selection runs are logged against the announcement thread when there
        // is one, so a captain can see them next to the chat.
        match chat_repo::conversation_for_announcement(&state.pool, event.club_id, Some(id)).await? {
            Some(conversation_id) => conversation_id,
            None => {
                return Err(ApiError::bad_request(
                    "create a chat thread for this club first — the assistant announces there",
                ))
            }
        },
        auth.user_id,
        state.agent.model(),
    )
    .await?;

    let outcome = match state.agent.pick_squad(&context).await {
        Ok(outcome) => outcome,
        Err(error) => {
            let status = if matches!(error, AgentError::Refused) { "refused" } else { "failed" };
            let message = error.to_string();
            agent_repo::finish_run(&state.pool, run.id, status, None, None, Some(&message)).await?;
            warn!(%message, "squad selection failed");
            return Err(ApiError::internal(format!(
                "the assistant could not pick this side: {message}"
            )));
        }
    };

    agent_repo::finish_run(
        &state.pool,
        run.id,
        "succeeded",
        outcome.input_tokens,
        outcome.output_tokens,
        None,
    )
    .await?;

    let decision = outcome.decision;
    let publish = policy.selection_autonomy == "auto_publish";
    if publish {
        selection_repo::set_squad(
            &state.pool,
            id,
            auth.user_id,
            &decision.selected,
            &decision.reserves,
            true,
            policy.confirm_lead_hours,
        )
        .await?;
        announce(&state, event.club_id, Some(id), &decision.announcement).await;
        notify_squad(&state, id, "squad_published", &event.title, &decision.announcement).await;
    }

    // Keep the ranking's numbers alongside the model's picks, so the captain
    // sees why each player is there.
    let pick = |ids: &[Uuid]| -> Vec<selection::RankedCandidate> {
        ids.iter()
            .filter_map(|id| {
                let mut ranked = ranked.iter().find(|r| r.user_id == *id).cloned()?;
                if let Some(note) = decision.notes.iter().find(|n| n.user_id == *id) {
                    ranked.reasons.push(note.reason.clone());
                }
                Some(ranked)
            })
            .collect()
    };

    Ok(Json(SquadProposalView {
        source: "assistant".into(),
        selected: pick(&decision.selected),
        reserves: pick(&decision.reserves),
        unmet_quotas: fallback.unmet_quotas,
        announcement: Some(decision.announcement),
        concerns: decision.concerns,
        confidence: Some(decision.confidence),
        published: publish,
    }))
}

/// Announce the squad as it stands.
async fn publish(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let event = load_event(&state, id).await?;
    require_captain_or_admin(&state, event.club_id, auth.user_id).await?;
    let policy = selection_repo::policy_for_club(&state.pool, event.club_id).await?;
    let candidates = selection_repo::candidates(&state.pool, id).await?;
    let squad: Vec<&fishers_domain::Candidate> =
        candidates.iter().filter(|c| c.state.is_in_squad()).collect();

    if squad.is_empty() {
        return Err(ApiError::bad_request("no squad has been picked yet"));
    }

    let names = squad.iter().map(|c| c.name.as_str()).collect::<Vec<_>>().join(", ");
    let announcement = format!(
        "{}\n\n{names}\n\nConfirm in the app by {} hours before start.",
        event.title, policy.confirm_lead_hours
    );
    announce(&state, event.club_id, Some(id), &announcement).await;
    notify_squad(&state, id, "squad_published", &event.title, &announcement).await;
    Ok(Json(json!({ "announced_to": squad.len() })))
}

/// The player's own reconfirmation, a couple of days out rather than at the last
/// minute. Declining inside the drop window counts as a late drop-out.
async fn respond(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<RespondToSelectionRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let event = load_event(&state, id).await?;
    require_club_member(&state, event.club_id, auth.user_id).await?;
    let policy = selection_repo::policy_for_club(&state.pool, event.club_id).await?;

    selection_repo::respond(
        &state.pool,
        id,
        auth.user_id,
        body.confirming,
        policy.drop_lead_hours,
    )
    .await?;

    // A drop-out opens a place: pull up the next reserve straight away.
    let promoted = if body.confirming {
        Vec::new()
    } else {
        selection_repo::promote_reserves(&state.pool, id, policy.confirm_lead_hours).await?
    };

    for player in &promoted {
        let body = format!("You're in for {} — a place opened up.", event.title);
        if let Err(error) = state
            .push
            .send(player.user_id, "squad_promoted", &event.title, &body, json!({ "event_id": id }))
            .await
        {
            warn!(%error, "promotion push failed");
        }
    }
    if !promoted.is_empty() {
        let names = promoted.iter().map(|p| p.name.as_str()).collect::<Vec<_>>().join(", ");
        announce(
            &state,
            event.club_id,
            Some(id),
            &format!("{names} called up for {}.", event.title),
        )
        .await;
    }

    Ok(Json(json!({
        "confirmed": body.confirming,
        "promoted": promoted.iter().map(|p| p.name.clone()).collect::<Vec<_>>()
    })))
}

async fn promote(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let event = load_event(&state, id).await?;
    require_captain_or_admin(&state, event.club_id, auth.user_id).await?;
    let policy = selection_repo::policy_for_club(&state.pool, event.club_id).await?;
    let promoted =
        selection_repo::promote_reserves(&state.pool, id, policy.confirm_lead_hours).await?;
    Ok(Json(json!({
        "promoted": promoted.iter().map(|p| p.name.clone()).collect::<Vec<_>>()
    })))
}

/// Rain stops play. Changes the fixture and tells the squad — the announcement
/// that otherwise gets typed into three different group chats.
async fn update_status(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<FixtureStatusRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let event = load_event(&state, id).await?;
    require_captain_or_admin(&state, event.club_id, auth.user_id).await?;

    let status = match body.status.as_str() {
        "scheduled" => EventStatus::Scheduled,
        "postponed" => EventStatus::Postponed,
        "cancelled" => EventStatus::Cancelled,
        "completed" => EventStatus::Completed,
        other => return Err(ApiError::bad_request(format!("unknown status: {other}"))),
    };

    selection_repo::update_fixture_status(
        &state.pool,
        id,
        status,
        body.note.as_deref(),
        body.rescheduled_to,
    )
    .await?;

    let headline = match status {
        EventStatus::Postponed => format!("{} is off for now.", event.title),
        EventStatus::Cancelled => format!("{} is cancelled.", event.title),
        EventStatus::Scheduled => format!("{} is back on.", event.title),
        EventStatus::Completed => format!("{} is done.", event.title),
        EventStatus::Draft => format!("{} moved to draft.", event.title),
    };
    let mut announcement = headline;
    if let Some(note) = &body.note {
        announcement.push_str(&format!(" {note}"));
    }
    if let Some(when) = body.rescheduled_to {
        announcement.push_str(&format!(
            " New date: {}.",
            when.format("%a %-d %b, %H:%M")
        ));
    }

    announce(&state, event.club_id, Some(id), &announcement).await;
    notify_squad(&state, id, "fixture_update", &event.title, &announcement).await;

    Ok(Json(json!({ "status": body.status, "announced": announcement })))
}

// MARK: match fees

async fn outstanding_fees(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    require_captain_or_admin(&state, id, auth.user_id).await?;
    let rows = selection_repo::outstanding_fees(&state.pool, id).await?;
    let total: i64 = rows
        .iter()
        .map(|r| r.fee_amount_cents.unwrap_or(0) as i64)
        .sum();
    Ok(Json(json!({
        "total_cents": total,
        "count": rows.len(),
        "owed": rows.iter().map(|r| json!({
            "user_id": r.user_id,
            "name": r.name,
            "event_id": r.event_id,
            "fixture": r.title,
            "start_at": r.start_at,
            "amount_cents": r.fee_amount_cents,
            "currency": r.fee_currency,
            "reminders_sent": r.fee_reminders_sent,
        })).collect::<Vec<_>>()
    })))
}

/// Chase everyone who owes, now. The scheduler does this on its own; this is
/// the "do it now" button for a credit controller.
async fn chase_fees(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    require_captain_or_admin(&state, id, auth.user_id).await?;
    let rows = selection_repo::outstanding_fees(&state.pool, id).await?;

    for row in &rows {
        let amount = row.fee_amount_cents.unwrap_or(0) as f64 / 100.0;
        let body = format!(
            "{} — £{amount:.2} for {} on {}. You can pay in the app.",
            row.name,
            row.title,
            row.start_at.format("%-d %b")
        );
        if let Err(error) = state
            .email
            .send(&row.email, &format!("Match fee for {}", row.title), &body)
            .await
        {
            warn!(%error, "fee email failed");
        }
        if let Err(error) = state
            .push
            .send(
                row.user_id,
                "fee_reminder",
                "Match fee due",
                &body,
                json!({ "event_id": row.event_id }),
            )
            .await
        {
            warn!(%error, "fee push failed");
        }
        selection_repo::mark_fee_reminded(&state.pool, row.event_id, row.user_id).await?;
    }

    Ok(Json(json!({ "chased": rows.len() })))
}

// MARK: fixture blocks (tours, tournaments, the next few weeks)

async fn create_block(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<CreateFixtureBlockRequest>,
) -> ApiResult<Json<FixtureBlock>> {
    body.validate()?;
    require_captain_or_admin(&state, body.club_id, auth.user_id).await?;
    Ok(Json(
        events_repo::create_fixture_block(&state.pool, auth.user_id, &body).await?,
    ))
}

async fn list_blocks(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<FixtureBlock>>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(events_repo::list_fixture_blocks(&state.pool, id).await?))
}

/// Squads for a whole block — a tour, a tournament, or the next few weeks —
/// with the games spread so nobody sits out the lot. `commit` writes them.
async fn plan_block(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<PlanBlockRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let fixtures = events_repo::list_block_events(&state.pool, id).await?;
    let Some(first) = fixtures.first() else {
        return Err(ApiError::bad_request("this block has no fixtures yet"));
    };
    require_captain_or_admin(&state, first.club_id, auth.user_id).await?;
    let policy = selection_repo::policy_for_club(&state.pool, first.club_id).await?;

    let mut block_fixtures = Vec::with_capacity(fixtures.len());
    for fixture in &fixtures {
        block_fixtures.push(selection::BlockFixture {
            event_id: fixture.id,
            candidates: selection_repo::candidates(&state.pool, fixture.id).await?,
            requirements: selection_repo::requirements_for(&state.pool, fixture.id).await?,
        });
    }

    let plan = selection::suggest_block(&block_fixtures);

    if body.commit {
        for squad in &plan {
            selection_repo::set_squad(
                &state.pool,
                squad.event_id,
                auth.user_id,
                &squad.selected.iter().map(|s| s.user_id).collect::<Vec<_>>(),
                &squad.reserves.iter().map(|s| s.user_id).collect::<Vec<_>>(),
                false,
                policy.confirm_lead_hours,
            )
            .await?;
        }
        let titles = fixtures
            .iter()
            .map(|f| f.title.as_str())
            .collect::<Vec<_>>()
            .join(", ");
        announce(
            &state,
            first.club_id,
            None,
            &format!(
                "Squads named for {} fixture{}: {titles}. Please confirm in the app.",
                plan.len(),
                if plan.len() == 1 { "" } else { "s" }
            ),
        )
        .await;
        for squad in &plan {
            notify_squad(
                &state,
                squad.event_id,
                "squad_published",
                "You're picked",
                "Squads are up for the block — confirm in the app.",
            )
            .await;
        }
    }

    Ok(Json(json!({
        "committed": body.commit,
        "fixtures": plan.iter().map(|squad| {
            let fixture = fixtures.iter().find(|f| f.id == squad.event_id);
            json!({
                "event_id": squad.event_id,
                "title": fixture.map(|f| f.title.clone()),
                "starts_at": fixture.map(|f| f.start_at),
                "selected": squad.selected,
                "reserves": squad.reserves,
                "unmet_quotas": squad.unmet_quotas,
            })
        }).collect::<Vec<_>>()
    })))
}

#[derive(Debug, Default, serde::Deserialize)]
struct PlanBlockRequest {
    /// Write the squads rather than just previewing them.
    #[serde(default)]
    commit: bool,
}

// MARK: helpers

async fn build_board(state: &AppState, event_id: Uuid) -> ApiResult<SelectionBoard> {
    let event = load_event(state, event_id).await?;
    let policy = selection_repo::policy_for_club(&state.pool, event.club_id).await?;
    let candidates = selection_repo::candidates(&state.pool, event_id).await?;
    let requirements = selection_repo::requirements_for(&state.pool, event_id).await?;
    let ranked = selection::rank(&candidates);

    Ok(SelectionBoard {
        event_id,
        title: event.title.clone(),
        sport: serde_json::to_value(event.sport)
            .ok()
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_default(),
        starts_at: event.start_at,
        status: serde_json::to_value(event.status)
            .ok()
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_default(),
        status_note: None,
        selected_count: candidates.iter().filter(|c| c.state.is_in_squad()).count(),
        confirmed_count: candidates.iter().filter(|c| c.is_confirmed).count(),
        requirements,
        autonomy: policy.selection_autonomy,
        confirm_lead_hours: policy.confirm_lead_hours,
        drop_lead_hours: policy.drop_lead_hours,
        candidates,
        ranked,
    })
}

fn default_announcement(title: &str, size: usize, confirm_lead_hours: i32) -> String {
    format!(
        "Squad for {title} — {size} named. Please confirm in the app at least {confirm_lead_hours} hours before start."
    )
}

/// Post to the club's thread. Announcements are best-effort: a missing thread
/// must not fail the selection itself.
async fn announce(state: &AppState, club_id: Uuid, event_id: Option<Uuid>, body: &str) {
    match chat_repo::conversation_for_announcement(&state.pool, club_id, event_id).await {
        Ok(Some(conversation_id)) => {
            if let Err(error) = chat_repo::post_message(
                &state.pool,
                conversation_id,
                None,
                "agent",
                body,
                json!({ "kind": "announcement", "event_id": event_id }),
            )
            .await
            {
                warn!(%error, "announcement post failed");
            }
        }
        Ok(None) => warn!(%club_id, "no thread to announce in"),
        Err(error) => warn!(%error, "could not find a thread to announce in"),
    }
}

async fn notify_squad(state: &AppState, event_id: Uuid, kind: &str, title: &str, body: &str) {
    let recipients = match selection_repo::squad_user_ids(&state.pool, event_id).await {
        Ok(recipients) => recipients,
        Err(error) => {
            warn!(%error, "could not load squad to notify");
            return;
        }
    };
    for user_id in recipients {
        if let Err(error) = state
            .push
            .send(user_id, kind, title, body, json!({ "event_id": event_id }))
            .await
        {
            warn!(%error, "squad push failed");
        }
    }
}

async fn load_event(state: &AppState, event_id: Uuid) -> ApiResult<fishers_domain::Event> {
    events_repo::get_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("fixture not found"))
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
    match clubs_repo::club_role(&state.pool, club_id, user_id).await? {
        Some(UserRole::ClubAdmin | UserRole::TeamCaptain | UserRole::SuperAdmin) => Ok(()),
        Some(_) => Err(ApiError::forbidden("only a captain or club admin can do that")),
        None => Err(ApiError::forbidden("not a club member")),
    }
}

async fn recent_transcript(
    state: &AppState,
    club_id: Uuid,
    event_id: Uuid,
) -> ApiResult<Vec<TranscriptLine>> {
    let Some(conversation_id) =
        chat_repo::conversation_for_announcement(&state.pool, club_id, Some(event_id)).await?
    else {
        return Ok(Vec::new());
    };
    let mut lines: Vec<TranscriptLine> =
        chat_repo::list_messages(&state.pool, conversation_id, None, TRANSCRIPT_LIMIT)
            .await?
            .into_iter()
            .map(|m| TranscriptLine {
                author: m.sender_name.clone().unwrap_or_else(|| "Assistant".into()),
                author_id: m.sender_id,
                sent_at: m.created_at,
                body: m.body,
            })
            .collect();
    lines.reverse();
    Ok(lines)
}
