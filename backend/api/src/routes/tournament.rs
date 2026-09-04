//! Running a tournament, and club events people buy a ticket for.
//!
//! A tournament is a fixture block with structure: entrants, a grid of pitches
//! and time slots, generated fixtures, results and a table. Squad selection
//! then works inside it exactly as it does for a league fixture.

use axum::extract::{Path, State};
use axum::routing::{get, patch, post};
use axum::{Json, Router};
use chrono::Duration;
use fishers_db::repos::{
    clubs as clubs_repo, events as events_repo, tournament as tournament_repo,
};
use fishers_domain::tournament::{self, TournamentFormat};
use fishers_domain::{
    AddEntrantsRequest, BookTicketRequest, EventTicket, FixtureBlock, GenerateKnockoutRequest,
    GenerateScheduleRequest, GenerateSlotsRequest, RecordResultRequest, ScheduleRow, Standing,
    TicketSummary, TournamentEntrant, UpdateBlockRequest,
};
use serde_json::json;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/fixture-blocks/{id}", patch(update_block))
        .route("/fixture-blocks/{id}/entrants", get(list_entrants).post(add_entrants))
        .route("/entrants/{id}/withdraw", post(withdraw_entrant))
        .route("/fixture-blocks/{id}/slots", get(list_slots).post(generate_slots))
        .route("/fixture-blocks/{id}/schedule", get(schedule).post(generate_schedule))
        .route("/fixture-blocks/{id}/knockout", post(generate_knockout))
        .route("/fixture-blocks/{id}/standings", get(standings))
        .route("/events/{id}/result", post(record_result))
        .route("/events/{id}/tickets", get(list_tickets).post(book_ticket))
        .route("/tickets/{id}/cancel", post(cancel_ticket))
        .route("/tickets/{id}/pay", post(pay_ticket))
}

async fn update_block(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateBlockRequest>,
) -> ApiResult<Json<FixtureBlock>> {
    let club_id = block_club(&state, id).await?;
    require_organiser(&state, club_id, auth.user_id).await?;
    Ok(Json(tournament_repo::update_block(&state.pool, id, &body).await?))
}

async fn add_entrants(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AddEntrantsRequest>,
) -> ApiResult<Json<Vec<TournamentEntrant>>> {
    let club_id = block_club(&state, id).await?;
    require_organiser(&state, club_id, auth.user_id).await?;
    if body.entrants.is_empty() {
        return Err(ApiError::bad_request("no entrants given"));
    }
    Ok(Json(
        tournament_repo::add_entrants(&state.pool, id, &body).await?,
    ))
}

async fn list_entrants(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<TournamentEntrant>>> {
    let club_id = block_club(&state, id).await?;
    require_member(&state, club_id, auth.user_id).await?;
    Ok(Json(tournament_repo::list_entrants(&state.pool, id).await?))
}

async fn withdraw_entrant(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    // Withdrawals are rare and consequential: organisers only.
    let entrant = sqlx_entrant_block(&state, id).await?;
    let club_id = block_club(&state, entrant).await?;
    require_organiser(&state, club_id, auth.user_id).await?;
    tournament_repo::withdraw_entrant(&state.pool, id).await?;
    Ok(Json(json!({ "withdrawn": true })))
}

async fn generate_slots(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<GenerateSlotsRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let club_id = block_club(&state, id).await?;
    require_organiser(&state, club_id, auth.user_id).await?;
    if body.courts.is_empty() {
        return Err(ApiError::bad_request("name at least one pitch or court"));
    }
    let created = tournament_repo::generate_slots(&state.pool, id, &body).await?;
    Ok(Json(json!({
        "created": created.len(),
        "slots": created,
    })))
}

async fn list_slots(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let club_id = block_club(&state, id).await?;
    require_member(&state, club_id, auth.user_id).await?;
    Ok(Json(json!({
        "free": tournament_repo::list_free_slots(&state.pool, id).await?
    })))
}

/// Generate the fixture list. A preview by default; `commit` writes it.
async fn generate_schedule(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<GenerateScheduleRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let settings = tournament_repo::block_settings(&state.pool, id).await?;
    require_organiser(&state, settings.club_id, auth.user_id).await?;

    let entrants = tournament_repo::entrants_for_generation(&state.pool, id).await?;
    if entrants.len() < 2 {
        return Err(ApiError::bad_request("add at least two entrants first"));
    }

    let format = body
        .format
        .unwrap_or_else(|| tournament_repo::parse_format(&settings.format));
    let group_count = body
        .group_count
        .or_else(|| settings.group_count.map(|c| c.max(1) as usize))
        .unwrap_or(1);

    let fixtures = match format {
        TournamentFormat::Knockout => tournament::knockout(&entrants),
        TournamentFormat::GroupsKnockout | TournamentFormat::RoundRobin => {
            let groups = if matches!(format, TournamentFormat::GroupsKnockout) {
                group_count.max(2)
            } else {
                1
            };
            let allocation = if groups > 1 {
                tournament_repo::apply_groups(&state.pool, &entrants, groups).await?
            } else {
                entrants.iter().map(|e| (e.id, "A".to_string())).collect()
            };

            let mut all = Vec::new();
            let mut labels: Vec<String> =
                allocation.iter().map(|(_, label)| label.clone()).collect();
            labels.sort();
            labels.dedup();
            for label in labels {
                let ids: Vec<Uuid> = allocation
                    .iter()
                    .filter(|(_, group)| *group == label)
                    .map(|(id, _)| *id)
                    .collect();
                all.extend(tournament::round_robin(&ids, Some(label)));
            }
            all
        }
        TournamentFormat::Ladder | TournamentFormat::None => {
            return Err(ApiError::bad_request(
                "set a format of round_robin, groups_knockout or knockout first",
            ))
        }
    };

    let slots = tournament_repo::list_free_slots(&state.pool, id).await?;
    let schedule = tournament::build_schedule(
        &fixtures,
        &slots,
        Duration::minutes(body.min_rest_minutes.max(0)),
    );

    let mut committed = 0usize;
    if body.commit {
        let names: Vec<(Uuid, String)> = entrants
            .iter()
            .map(|e| (e.id, e.name.clone()))
            .collect();
        let pairs: Vec<_> = schedule
            .scheduled
            .iter()
            .map(|s| (s.fixture.clone(), s.slot.clone()))
            .collect();
        committed = tournament_repo::commit_schedule(
            &state.pool,
            id,
            auth.user_id,
            &pairs,
            &names,
            settings.sport.as_deref().unwrap_or("cricket"),
            "tournament",
        )
        .await?;
    }

    Ok(Json(json!({
        "format": format,
        "committed": committed,
        "scheduled": schedule.scheduled,
        "unscheduled": schedule.unscheduled,
        "byes": schedule.byes,
        "needs_more_slots": schedule.unscheduled.len(),
    })))
}

/// Build the knockout from the group table once the groups are done.
async fn generate_knockout(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<GenerateKnockoutRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let settings = tournament_repo::block_settings(&state.pool, id).await?;
    require_organiser(&state, settings.club_id, auth.user_id).await?;

    let table = tournament_repo::standings(&state.pool, id).await?;
    if table.is_empty() {
        return Err(ApiError::bad_request("no results recorded yet"));
    }
    let through = tournament::qualifiers(&table, body.per_group.max(1));
    let bracket = tournament::knockout(&through);

    let slots = tournament_repo::list_free_slots(&state.pool, id).await?;
    let schedule =
        tournament::build_schedule(&bracket, &slots, tournament_repo::default_rest());

    let mut committed = 0usize;
    if body.commit {
        let names: Vec<(Uuid, String)> =
            through.iter().map(|e| (e.id, e.name.clone())).collect();
        let pairs: Vec<_> = schedule
            .scheduled
            .iter()
            .map(|s| (s.fixture.clone(), s.slot.clone()))
            .collect();
        committed = tournament_repo::commit_schedule(
            &state.pool,
            id,
            auth.user_id,
            &pairs,
            &names,
            settings.sport.as_deref().unwrap_or("cricket"),
            "tournament",
        )
        .await?;
    }

    Ok(Json(json!({
        "qualifiers": through,
        "committed": committed,
        "scheduled": schedule.scheduled,
        "unscheduled": schedule.unscheduled,
        "byes": schedule.byes,
    })))
}

async fn schedule(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<ScheduleRow>>> {
    let club_id = block_club(&state, id).await?;
    require_member(&state, club_id, auth.user_id).await?;
    Ok(Json(tournament_repo::schedule_rows(&state.pool, id).await?))
}

async fn standings(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<Standing>>> {
    let club_id = block_club(&state, id).await?;
    require_member(&state, club_id, auth.user_id).await?;
    Ok(Json(tournament_repo::standings(&state.pool, id).await?))
}

async fn record_result(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<RecordResultRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let event = events_repo::get_event(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("fixture not found"))?;
    require_organiser(&state, event.club_id, auth.user_id).await?;

    let rules = match sqlx_event_block(&state, id).await? {
        Some(block_id) => tournament_repo::points_rules(&state.pool, block_id).await?,
        None => Default::default(),
    };
    tournament_repo::record_result(&state.pool, id, &body, rules).await?;
    Ok(Json(json!({ "recorded": body.entrants.len() })))
}

// MARK: ticketed club events

/// Book a place at a social, dinner or AGM, with guests where allowed.
async fn book_ticket(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<BookTicketRequest>,
) -> ApiResult<Json<EventTicket>> {
    let event = events_repo::get_event(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    require_member(&state, event.club_id, auth.user_id).await?;

    match tournament_repo::book_ticket(&state.pool, id, auth.user_id, &body).await? {
        Ok(ticket) => Ok(Json(ticket)),
        Err(reason) => Err(ApiError::conflict(reason)),
    }
}

async fn list_tickets(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let event = events_repo::get_event(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    require_member(&state, event.club_id, auth.user_id).await?;

    let summary: TicketSummary = tournament_repo::ticket_summary(&state.pool, id).await?;
    Ok(Json(json!({
        "summary": summary,
        "tickets": tournament_repo::list_tickets(&state.pool, id).await?,
    })))
}

async fn cancel_ticket(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<EventTicket>> {
    // A member may cancel their own; an organiser may cancel anyone's.
    let event_id = tournament_repo::ticket_event(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("ticket not found"))?;
    let event = events_repo::get_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    let is_organiser = clubs_repo::club_role(&state.pool, event.club_id, auth.user_id)
        .await?
        .as_deref()
        .is_some_and(|role| matches!(role, "club_admin" | "team_captain" | "super_admin"));

    tournament_repo::set_ticket_status(
        &state.pool,
        id,
        (!is_organiser).then_some(auth.user_id),
        "cancelled",
    )
    .await?
    .map(Json)
    .ok_or_else(|| ApiError::forbidden("that isn't your ticket"))
}

/// Mark a ticket paid. Stripe is stubbed, so this records the payment and
/// returns the ticket; wiring a real intent replaces the middle of it.
async fn pay_ticket(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<EventTicket>> {
    let event_id = tournament_repo::ticket_event(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("ticket not found"))?;
    let event = events_repo::get_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    require_member(&state, event.club_id, auth.user_id).await?;

    tournament_repo::set_ticket_status(&state.pool, id, Some(auth.user_id), "paid")
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::forbidden("that isn't your ticket"))
}

// MARK: helpers

async fn block_club(state: &AppState, block_id: Uuid) -> ApiResult<Uuid> {
    tournament_repo::get_block(&state.pool, block_id)
        .await?
        .map(|b| b.club_id)
        .ok_or_else(|| ApiError::not_found("block not found"))
}

async fn sqlx_entrant_block(state: &AppState, entrant_id: Uuid) -> ApiResult<Uuid> {
    let row: Option<(Uuid,)> =
        sqlx::query_as("SELECT block_id FROM tournament_entrants WHERE id = $1")
            .bind(entrant_id)
            .fetch_optional(&state.pool)
            .await?;
    row.map(|r| r.0)
        .ok_or_else(|| ApiError::not_found("entrant not found"))
}

async fn sqlx_event_block(state: &AppState, event_id: Uuid) -> ApiResult<Option<Uuid>> {
    let row: Option<(Option<Uuid>,)> =
        sqlx::query_as("SELECT fixture_block_id FROM events WHERE id = $1")
            .bind(event_id)
            .fetch_optional(&state.pool)
            .await?;
    Ok(row.and_then(|r| r.0))
}

async fn require_member(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<()> {
    if clubs_repo::is_club_member(&state.pool, club_id, user_id).await? {
        Ok(())
    } else {
        Err(ApiError::forbidden("not a club member"))
    }
}

async fn require_organiser(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<()> {
    match clubs_repo::club_role(&state.pool, club_id, user_id).await?.as_deref() {
        Some("club_admin") | Some("team_captain") | Some("super_admin") => Ok(()),
        Some(_) => Err(ApiError::forbidden(
            "only a captain or club admin can organise this",
        )),
        None => Err(ApiError::forbidden("not a club member")),
    }
}
