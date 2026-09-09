use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use fishers_db::repos::clubs as clubs_repo;
use fishers_db::repos::events as events_repo;
use fishers_db::repos::events::EventSort;
use fishers_db::repos::invites as invites_repo;
use fishers_domain::{
    AttendeeSummary, CreateEventRequest, Event, EventInvite, Permission, RsvpRequest,
    UpdateEventRequest,
};
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{
    require_captain_or_secretary, require_club_member, require_event_permission, require_permission,
};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/events", get(list_events).post(create_event))
        .route("/events/{id}", get(get_event).patch(update_event))
        .route("/events/{id}/rsvp", post(rsvp))
        .route("/events/{id}/attendees", get(attendees))
        .route("/events/{id}/invite", post(invite_user))
}

#[derive(Debug, Deserialize)]
pub struct EventQuery {
    pub club_id: Option<Uuid>,
    pub from: Option<DateTime<Utc>>,
    pub to: Option<DateTime<Utc>>,
    /// When true, filter cricket nets + match subtypes (season view).
    pub cricket_season: Option<bool>,
    pub sport: Option<String>,
    pub subtype: Option<String>,
    pub status: Option<String>,
    /// Free text against the fixture title.
    pub q: Option<String>,
    /// `start_at` (default), `title` or `created_at`.
    pub sort: Option<EventSort>,
    /// `asc` (default) or `desc`.
    pub order: Option<String>,
    /// 1-based.
    pub page: Option<i64>,
    pub per_page: Option<i64>,
}

async fn create_event(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<CreateEventRequest>,
) -> ApiResult<Json<Event>> {
    body.validate()?;
    if body.end_at <= body.start_at {
        return Err(ApiError::bad_request("end_at must be after start_at"));
    }
    require_permission(
        &state,
        body.club_id,
        auth.user_id,
        body.team_id,
        Permission::ManageEvents,
    )
    .await?;
    // Scheduling against another club needs their permission in the sense
    // that it puts the fixture in their diary and asks their players — so it
    // has to be a real club, not an id somebody guessed.
    if let Some(opponent) = body.opponent_club_id {
        if opponent == body.club_id {
            return Err(ApiError::bad_request("a club cannot play itself"));
        }
        if clubs_repo::get_club(&state.pool, opponent).await?.is_none() {
            return Err(ApiError::not_found("that opposition club does not exist"));
        }
    }

    let event = events_repo::create_event(&state.pool, auth.user_id, &body).await?;
    ask_who_is_available(&state, &event, auth.user_id).await;
    Ok(Json(event))
}

/// Put the fixture in front of everyone who might play in it.
///
/// A fixture nobody is told about is a diary entry. Every active member of
/// each side gets an invite row — which is what the selection board reads —
/// and a notification asking whether they can play. Without this a captain
/// picks a side from people who were never asked.
async fn ask_who_is_available(state: &AppState, event: &Event, scheduler: Uuid) {
    let when = event.start_at.format("%a %-d %b, %H:%M");
    let body = format!("{when}. Can you play?");

    for club in [Some(event.club_id), event.opponent_club_id]
        .into_iter()
        .flatten()
    {
        for member in clubs_repo::list_members(&state.pool, club)
            .await
            .unwrap_or_default()
        {
            // The invite is what makes them a candidate for selection; the
            // notification is what makes them aware of it.
            if let Err(error) =
                invites_repo::invite_to_event(&state.pool, event.id, member.user_id, scheduler)
                    .await
            {
                tracing::warn!(%error, "could not invite a member to the fixture");
                continue;
            }
            if member.user_id == scheduler {
                continue; // they just made it
            }
            state
                .notify(
                    member.user_id,
                    "fixture_scheduled",
                    &event.title,
                    &body,
                    serde_json::json!({
                        "event_id": event.id,
                        "title": event.title,
                        "start_at": event.start_at,
                    }),
                )
                .await;
        }
    }
}

async fn list_events(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<EventQuery>,
) -> ApiResult<Json<events_repo::Page<Event>>> {
    if let Some(club_id) = q.club_id {
        require_club_member(&state, club_id, auth.user_id).await?;
    }

    let order = q.order.as_deref().unwrap_or("asc");
    if !matches!(order, "asc" | "desc") {
        return Err(ApiError::bad_request("order must be asc or desc"));
    }
    if let Some(page) = q.page {
        if page < 1 {
            return Err(ApiError::bad_request("page starts at 1"));
        }
    }
    if let Some(per_page) = q.per_page {
        if !(1..=200).contains(&per_page) {
            return Err(ApiError::bad_request("per_page must be between 1 and 200"));
        }
    }
    // A one-letter search matches most of the table and costs a scan for
    // nothing useful; the club search has the same floor.
    let search = q
        .q
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);
    if search.as_deref().is_some_and(|s| s.chars().count() < 2) {
        return Err(ApiError::bad_request("give at least two letters to search on"));
    }

    let filter = events_repo::EventFilter {
        club_id: q.club_id,
        from: q.from,
        to: q.to,
        cricket_season: q.cricket_season.unwrap_or(false),
        sport: q.sport.clone(),
        subtype: q.subtype.clone(),
        status: q.status.clone(),
        search,
        sort: q.sort.unwrap_or_default(),
        descending: order == "desc",
        page: q.page.unwrap_or(1),
        per_page: q.per_page.unwrap_or(20),
    };
    Ok(Json(
        events_repo::list_events(&state.pool, auth.user_id, &filter).await?,
    ))
}

async fn get_event(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Event>> {
    let event = events_repo::get_event(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    require_club_member(&state, event.club_id, auth.user_id).await?;
    Ok(Json(event))
}

async fn update_event(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateEventRequest>,
) -> ApiResult<Json<Event>> {
    body.validate()?;
    require_event_permission(&state, id, auth.user_id, Permission::ManageEvents).await?;
    Ok(Json(
        events_repo::update_event(&state.pool, id, &body).await?,
    ))
}

async fn rsvp(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<RsvpRequest>,
) -> ApiResult<Json<EventInvite>> {
    require_event_permission(&state, id, auth.user_id, Permission::RespondAsPlayer).await?;
    let invite = invites_repo::rsvp(&state.pool, id, auth.user_id, body.status).await?;
    tell_the_selectors(&state, id, auth.user_id, body.status).await;
    Ok(Json(invite))
}

/// A captain picking a side needs to know who put their hand up.
///
/// Only the side the player belongs to hears it, and only the people who
/// actually pick — everyone else does not need their evening interrupted by
/// somebody else's availability.
async fn tell_the_selectors(
    state: &AppState,
    event_id: Uuid,
    player: Uuid,
    status: fishers_domain::RsvpStatus,
) {
    let Ok(Some(event)) = events_repo::get_event(&state.pool, event_id).await else {
        return;
    };
    // Which side they are on decides who hears about it.
    let mut theirs = None;
    for club in [Some(event.club_id), event.opponent_club_id]
        .into_iter()
        .flatten()
    {
        if clubs_repo::club_role(&state.pool, club, player)
            .await
            .ok()
            .flatten()
            .is_some()
        {
            theirs = Some(club);
            break;
        }
    }
    let Some(club) = theirs else { return };

    let name = fishers_db::repos::users::find_by_id(&state.pool, player)
        .await
        .ok()
        .flatten()
        .map(|u| u.name)
        .unwrap_or_else(|| "A player".into());
    let answer = match status {
        fishers_domain::RsvpStatus::Going => "is available",
        fishers_domain::RsvpStatus::NotGoing => "cannot play",
        _ => "has not decided",
    };
    let body = format!("{name} {answer} for {}.", event.title);

    for member in clubs_repo::list_members(&state.pool, club)
        .await
        .unwrap_or_default()
    {
        if member.user_id == player
            || !fishers_domain::permissions_for(member.role)
                .contains(&Permission::ManageSelection)
        {
            continue;
        }
        state
            .notify(
                member.user_id,
                "player_responded",
                &event.title,
                &body,
                serde_json::json!({
                    "event_id": event.id,
                    "title": event.title,
                    "start_at": event.start_at,
                    "player": name,
                }),
            )
            .await;
    }
}

async fn attendees(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<AttendeeSummary>>> {
    let (event, _) =
        require_event_permission(&state, id, auth.user_id, Permission::ViewClub).await?;
    let _ = event;
    Ok(Json(
        invites_repo::list_attendees(&state.pool, id).await?,
    ))
}

#[derive(Deserialize)]
struct InviteUserBody {
    user_id: Uuid,
}

/// Captain or club secretary invites someone to play this fixture.
async fn invite_user(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<InviteUserBody>,
) -> ApiResult<Json<EventInvite>> {
    let (event, _) =
        require_event_permission(&state, id, auth.user_id, Permission::InviteToEvent).await?;
    let _ = require_captain_or_secretary(&state, event.club_id, auth.user_id, event.team_id)
        .await?;
    Ok(Json(
        invites_repo::invite_to_event(&state.pool, id, body.user_id, auth.user_id).await?,
    ))
}
