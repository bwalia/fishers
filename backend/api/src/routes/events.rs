use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
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
    let event = events_repo::create_event(&state.pool, auth.user_id, &body).await?;
    Ok(Json(event))
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
    Ok(Json(
        invites_repo::rsvp(&state.pool, id, auth.user_id, body.status).await?,
    ))
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
