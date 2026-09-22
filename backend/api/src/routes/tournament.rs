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
    clubs as clubs_repo, events as events_repo, payments as payments_repo,
    tournament as tournament_repo,
};
use fishers_domain::tournament::{self, TournamentFormat};
use fishers_domain::{
    AddEntrantsRequest, BookTicketRequest, EntryInvitation, EntryStatus, EventTicket, FixtureBlock,
    GenerateKnockoutRequest, GenerateScheduleRequest, GenerateSlotsRequest, InviteEntrantRequest,
    Permission, RecordResultRequest, RespondToEntryRequest, ScheduleRow, Standing, TicketSummary,
    TournamentEntrant, UpdateBlockRequest,
};
use serde_json::json;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::require_permission;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/fixture-blocks/{id}", patch(update_block))
        .route("/fixture-blocks/{id}/entrants", get(list_entrants).post(add_entrants))
        .route("/fixture-blocks/{id}/invite", post(invite_entrant))
        .route("/entrants/{id}/withdraw", post(withdraw_entrant))
        .route("/entrants/{id}/respond", post(respond_to_entry))
        .route("/clubs/{id}/tournament-invites", get(club_invitations))
        // Unauthenticated, like the shared scoreboard: the side being asked has
        // no Fishers account, and the unguessable token is what stands in for
        // one. Answering is all it can do.
        .route("/public/entry/{token}", get(public_entry))
        .route("/public/entry/{token}/respond", post(public_respond))
        .route("/fixture-blocks/{id}/slots", get(list_slots).post(generate_slots))
        .route("/fixture-blocks/{id}/schedule", get(schedule).post(generate_schedule))
        .route("/fixture-blocks/{id}/knockout", post(generate_knockout))
        .route("/fixture-blocks/{id}/standings", get(standings))
        .route("/events/{id}/result", post(record_result))
        .route("/events/{id}/tickets", get(list_tickets).post(book_ticket))
        .route("/tickets/{id}/cancel", post(cancel_ticket))
        .route("/tickets/{id}/pay", post(pay_ticket))
        .route("/tickets/{id}/mark-paid", post(mark_ticket_paid))
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

// MARK: entries

/// Ask a club into a tournament.
///
/// Two kinds of side end up in a draw, and they are not the same thing. A name
/// an organiser types in is an entry — [`add_entrants`] — and it is in the draw
/// straight away. A real club is *asked*, and answers for itself; until it
/// does, it is not scheduled against anybody.
async fn invite_entrant(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<InviteEntrantRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    let settings = tournament_repo::block_settings(&state.pool, id).await?;
    require_organiser(&state, settings.club_id, auth.user_id).await?;

    // What the side is called in the draw. A club's own name unless the
    // organiser gave one — "Hemel 2nd XI" rather than "Hemel CC".
    let invited_club = match body.club_id {
        Some(club_id) => Some(
            clubs_repo::get_club(&state.pool, club_id)
                .await?
                .ok_or_else(|| ApiError::not_found("no such club"))?,
        ),
        None => None,
    };
    let name = body
        .name
        .as_deref()
        .map(str::trim)
        .filter(|n| !n.is_empty())
        .map(str::to_string)
        .or_else(|| invited_club.as_ref().map(|c| c.name.clone()))
        .ok_or_else(|| ApiError::bad_request("name the side, or pick a club"))?;

    if body.club_id == Some(settings.club_id) {
        return Err(ApiError::bad_request(
            "you are running this one — add your own side rather than inviting it",
        ));
    }
    if body.club_id.is_none() && body.contact_email.is_none() {
        return Err(ApiError::bad_request(
            "a side that is not on Fishers needs an email to be asked at",
        ));
    }

    // A side with no Fishers club answers by following a link, so it needs one.
    let token = body.club_id.is_none().then(entry_token);
    let entrant = match tournament_repo::invite_entrant(
        &state.pool,
        id,
        auth.user_id,
        &body,
        &name,
        token.as_deref(),
    )
    .await?
    {
        Ok(entrant) => entrant,
        Err(reason) => return Err(ApiError::conflict(reason)),
    };

    // Tell whoever can answer for them. A club nobody told is a club that
    // never enters.
    if let Some(club) = &invited_club {
        let host = clubs_repo::get_club(&state.pool, settings.club_id)
            .await?
            .map(|c| c.name)
            .unwrap_or_else(|| "A club".into());
        let title = format!("{host} invited you to {}", settings.name);
        let text = format!(
            "{host} asked {} into {}. Open Fishers to accept or decline.",
            club.name, settings.name
        );
        for officer in clubs_repo::event_managers(&state.pool, club.id).await? {
            state
                .notify(
                    officer,
                    "tournament_invite",
                    &title,
                    &text,
                    json!({
                        "entrant_id": entrant.id,
                        "block_id": id,
                        "block_name": settings.name,
                        "host_club": host,
                        "club_id": club.id,
                        "url": format!("/clubs/{}?invites=1", club.id),
                        "tag": format!("entry:{}", entrant.id),
                    }),
                )
                .await;
        }
    }

    // A side off-platform gets the link by email. Best effort: a bounced
    // invitation must not fail the organiser's request, which has already
    // written the entry they can see on their own screen.
    if let (Some(token), Some(email)) = (&token, body.contact_email.as_deref()) {
        let link = entry_link(token);
        let subject = format!("{} — invitation to enter", settings.name);
        let text = format!(
            "You have been invited to enter {} as {name}.\n\nAccept or decline here:\n{link}\n",
            settings.name
        );
        if let Err(error) = state.email.send(email, &subject, &text).await {
            tracing::warn!(%error, "could not email a tournament invitation");
        }
    }

    Ok(Json(json!({
        "entrant": entrant,
        // Only ever handed back to the organiser who created it, so they can
        // pass the link on themselves if the email does not arrive.
        "invite_link": token.as_deref().map(entry_link),
    })))
}

/// Accept or decline on behalf of the invited club.
async fn respond_to_entry(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<RespondToEntryRequest>,
) -> ApiResult<Json<TournamentEntrant>> {
    if !matches!(
        body.status.as_str(),
        EntryStatus::ACCEPTED | EntryStatus::DECLINED | EntryStatus::WITHDRAWN
    ) {
        return Err(ApiError::bad_request(
            "answer with accepted, declined or withdrawn",
        ));
    }

    let entrant = tournament_repo::get_entrant(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("entrant not found"))?;

    // The invited club answers for itself. Only the *host* may answer for a
    // side with no club of its own — otherwise nobody could, and an emailed
    // invitation would strand the entry.
    let answering_club = match entrant.club_id {
        Some(club_id) => club_id,
        None => block_club(&state, entrant.block_id).await?,
    };
    require_organiser(&state, answering_club, auth.user_id).await?;

    let entrant = match tournament_repo::set_entry_status(&state.pool, id, &body.status).await? {
        Ok(entrant) => entrant,
        Err(reason) => return Err(ApiError::conflict(reason)),
    };

    // Close the loop for whoever asked: they are waiting on this answer to
    // know whether they can make the draw.
    if let Some(inviter) = entrant.invited_by {
        let settings = tournament_repo::block_settings(&state.pool, entrant.block_id).await?;
        let said = match body.status.as_str() {
            EntryStatus::ACCEPTED => "are in",
            EntryStatus::DECLINED => "cannot make it",
            _ => "have pulled out",
        };
        state
            .notify(
                inviter,
                "tournament_entry_answered",
                &format!("{} {said}", entrant.name),
                &format!("{} {said} for {}.", entrant.name, settings.name),
                json!({
                    "entrant_id": entrant.id,
                    "block_id": entrant.block_id,
                    "block_name": settings.name,
                    "status": entrant.status,
                    "url": format!("/tournaments/{}", entrant.block_id),
                    "tag": format!("entry-answer:{}", entrant.id),
                }),
            )
            .await;
    }

    Ok(Json(entrant))
}

/// Tournaments this club has been asked into. `?pending=1` for unanswered only.
async fn club_invitations(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    axum::extract::Query(query): axum::extract::Query<InvitesQuery>,
) -> ApiResult<Json<Vec<EntryInvitation>>> {
    require_member(&state, id, auth.user_id).await?;
    Ok(Json(
        tournament_repo::entry_invitations(&state.pool, id, query.pending()).await?,
    ))
}

#[derive(serde::Deserialize)]
struct InvitesQuery {
    /// A string rather than a bool: `?pending=1` is what a link and a fetch
    /// naturally send, and serde's bool rejects it with a 400 nobody can read.
    #[serde(default)]
    pending: Option<String>,
}

impl InvitesQuery {
    fn pending(&self) -> bool {
        matches!(
            self.pending.as_deref(),
            Some("1" | "true" | "yes" | "on")
        )
    }
}

/// What an emailed invitation is for, for the page the link opens.
async fn public_entry(
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> ApiResult<Json<serde_json::Value>> {
    let entrant = tournament_repo::entrant_by_token(&state.pool, &token)
        .await?
        .ok_or_else(|| ApiError::not_found("that invitation link is not valid"))?;
    let settings = tournament_repo::block_settings(&state.pool, entrant.block_id).await?;
    let host = clubs_repo::get_club(&state.pool, settings.club_id)
        .await?
        .map(|c| c.name)
        .unwrap_or_else(|| "A club".into());

    // Deliberately narrow. This is served to anybody holding the link, so it
    // carries what the invitation says and nothing else about the club running
    // it — no contacts, no other entrants, no member list.
    Ok(Json(json!({
        "tournament": settings.name,
        "host_club": host,
        "side": entrant.name,
        "status": entrant.status,
    })))
}

/// Accept or decline from the emailed link.
async fn public_respond(
    State(state): State<AppState>,
    Path(token): Path<String>,
    Json(body): Json<RespondToEntryRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    if !matches!(
        body.status.as_str(),
        EntryStatus::ACCEPTED | EntryStatus::DECLINED
    ) {
        return Err(ApiError::bad_request("answer with accepted or declined"));
    }
    let entrant = tournament_repo::entrant_by_token(&state.pool, &token)
        .await?
        .ok_or_else(|| ApiError::not_found("that invitation link is not valid"))?;

    // The link is spent on the way through `set_entry_status`, so it answers
    // once. A second visit gets a 404 rather than the chance to change a draw
    // the organiser has already built.
    let entrant = match tournament_repo::set_entry_status(&state.pool, entrant.id, &body.status)
        .await?
    {
        Ok(entrant) => entrant,
        Err(reason) => return Err(ApiError::conflict(reason)),
    };

    if let Some(inviter) = entrant.invited_by {
        let settings = tournament_repo::block_settings(&state.pool, entrant.block_id).await?;
        let said = if body.status == EntryStatus::ACCEPTED { "are in" } else { "cannot make it" };
        state
            .notify(
                inviter,
                "tournament_entry_answered",
                &format!("{} {said}", entrant.name),
                &format!("{} {said} for {}.", entrant.name, settings.name),
                json!({
                    "entrant_id": entrant.id,
                    "block_id": entrant.block_id,
                    "block_name": settings.name,
                    "status": entrant.status,
                    "url": format!("/tournaments/{}", entrant.block_id),
                    "tag": format!("entry-answer:{}", entrant.id),
                }),
            )
            .await;
    }

    Ok(Json(json!({ "status": entrant.status, "side": entrant.name })))
}

fn entry_link(token: &str) -> String {
    format!("{}/entry/{token}", super::scoreboard_share::public_web_base())
}

/// The link an off-platform side follows. Unguessable rather than sequential:
/// it is the only thing standing between a stranger and somebody else's entry.
fn entry_token() -> String {
    use rand::Rng;
    let bytes: [u8; 16] = rand::thread_rng().gen();
    bytes.iter().map(|b| format!("{b:02x}")).collect()
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

/// Book a place at a social, dinner or AGM, with guests where allowed — or at
/// a tournament, where most of the people buying are not members of the club
/// running it.
async fn book_ticket(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<BookTicketRequest>,
) -> ApiResult<Json<EventTicket>> {
    let event = events_repo::get_event(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    require_buyer(&state, &event, auth.user_id).await?;

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
    require_buyer(&state, &event, auth.user_id).await?;

    // Who else is coming is club business. Opening ticket sales to the public
    // must not hand a stranger the guest list — names, dietary notes and all —
    // so an outsider sees the headcount and their own booking, nothing more.
    let member = clubs_repo::is_club_member(&state.pool, event.club_id, auth.user_id).await?;
    let mut tickets = tournament_repo::list_tickets(&state.pool, id).await?;
    if !member {
        tickets.retain(|t| t.user_id == auth.user_id);
    }

    let summary: TicketSummary = tournament_repo::ticket_summary(&state.pool, id).await?;
    Ok(Json(json!({
        "summary": summary,
        "tickets": tickets,
        "can_see_everyone": member,
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
    let is_organiser = require_organiser(&state, event.club_id, auth.user_id)
        .await
        .is_ok();

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

/// Start paying for a ticket. This creates the payment; the ticket only becomes
/// `paid` when the provider's webhook says the money arrived — a member cannot
/// mark their own ticket paid.
async fn pay_ticket(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let ticket = tournament_repo::get_ticket(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("ticket not found"))?;
    if ticket.user_id != auth.user_id {
        return Err(ApiError::forbidden("that isn't your ticket"));
    }
    let event = events_repo::get_event(&state.pool, ticket.event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    require_buyer(&state, &event, auth.user_id).await?;

    if ticket.status == "paid" {
        return Ok(Json(json!({ "already_paid": true })));
    }
    if ticket.amount_cents <= 0 {
        return Err(ApiError::bad_request("this event is free — nothing to pay"));
    }

    let request = fishers_domain::CreatePaymentIntentRequest {
        event_id: Some(ticket.event_id),
        order_id: None,
        amount_cents: ticket.amount_cents,
        currency: Some(ticket.currency.clone()),
    };

    // Tapping Pay twice, or coming back to a half-finished checkout, must not
    // open a second payment for the same ticket. Reusing the pending row also
    // reaches Stripe with the same idempotency key, so it hands back the
    // original intent rather than creating another.
    //
    // Reused only while the amount still matches: a member who added a guest
    // owes more than the intent was opened for, and that needs a new one.
    let payment = match payments_repo::pending_for_event(
        &state.pool,
        auth.user_id,
        ticket.event_id,
    )
    .await?
    {
        Some(open) if open.amount_cents == ticket.amount_cents => open,
        _ => payments_repo::create_pending(&state.pool, auth.user_id, &request, None).await?,
    };

    let intent = state
        .stripe
        .create_payment_intent(payment.id, &request)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    payments_repo::attach_intent(&state.pool, payment.id, &intent.intent_id).await?;

    Ok(Json(json!({
        "payment_id": intent.payment_id,
        "client_secret": intent.client_secret,
        "amount_cents": intent.amount_cents,
        "currency": intent.currency,
        "ticket_status": ticket.status,
    })))
}

#[derive(serde::Deserialize)]
struct MarkPaidBody {
    /// `cash` | `transfer` — how the money actually arrived.
    #[serde(default = "default_method")]
    method: String,
}

fn default_method() -> String {
    "cash".into()
}

/// Record a ticket paid outside the app — cash at the bar, a bank transfer.
/// Organisers only: this is the treasurer's button, not the buyer's.
async fn mark_ticket_paid(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<MarkPaidBody>,
) -> ApiResult<Json<EventTicket>> {
    if !matches!(body.method.as_str(), "cash" | "transfer") {
        return Err(ApiError::bad_request("method must be cash or transfer"));
    }
    let event_id = tournament_repo::ticket_event(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("ticket not found"))?;
    let event = events_repo::get_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    require_organiser(&state, event.club_id, auth.user_id).await?;

    tournament_repo::record_ticket_payment(&state.pool, id, auth.user_id, &body.method)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("ticket not found"))
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

/// Who may buy a ticket: a member of the hosting club, or — when the event
/// says its tickets are public — anybody signed in to Fishers.
///
/// `tickets_public` is off by default, so a members' AGM stays a members' AGM
/// unless somebody deliberately opens it.
async fn require_buyer(
    state: &AppState,
    event: &fishers_domain::Event,
    user_id: Uuid,
) -> ApiResult<()> {
    if event.tickets_public {
        return Ok(());
    }
    require_member(state, event.club_id, user_id).await
}

async fn require_member(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<()> {
    if clubs_repo::is_club_member(&state.pool, club_id, user_id).await? {
        Ok(())
    } else {
        Err(ApiError::forbidden("not a club member"))
    }
}

/// Running a tournament is `manage_events`, from the same matrix as everything
/// else — including a captaincy held on the team rather than the club.
async fn require_organiser(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<()> {
    require_permission(state, club_id, user_id, None, Permission::ManageEvents)
        .await
        .map(|_| ())
}
