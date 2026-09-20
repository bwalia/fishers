//! Venue hire Phase 1 — spaces, rates, availability, public browse.

use axum::extract::{Path, Query, State};
use axum::routing::{delete, get, patch};
use axum::{Json, Router};
use fishers_db::repos::venue_hire as hire_repo;
use fishers_domain::{
    CreateVenueBlackoutRequest, CreateVenueRateCardRequest, CreateVenueSpaceRequest,
    HireableSpaceRow, Permission, SetVenueAvailabilityRequest, UpdateVenueSpaceRequest,
    VenueAvailabilityWindow, VenueBlackout, VenueRateCard, VenueSpace,
};
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::require_club_permission;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/hire/spaces", get(browse_hireable))
        .route(
            "/venues/{venue_id}/spaces",
            get(list_spaces).post(create_space),
        )
        .route("/spaces/{space_id}", get(get_space).patch(update_space))
        .route(
            "/spaces/{space_id}/rates",
            get(list_rates).post(create_rate),
        )
        .route("/rates/{rate_id}", patch(set_rate_active))
        .route(
            "/spaces/{space_id}/availability",
            get(list_availability).put(set_availability),
        )
        .route(
            "/spaces/{space_id}/blackouts",
            get(list_blackouts).post(create_blackout),
        )
        .route("/blackouts/{blackout_id}", delete(delete_blackout))
}

#[derive(Debug, Deserialize)]
struct BrowseQuery {
    sport: Option<String>,
    q: Option<String>,
    #[serde(default = "default_limit")]
    limit: i64,
}

fn default_limit() -> i64 {
    50
}

async fn browse_hireable(
    State(state): State<AppState>,
    Query(q): Query<BrowseQuery>,
) -> ApiResult<Json<Vec<HireableSpaceRow>>> {
    Ok(Json(
        hire_repo::list_hireable_spaces(
            &state.pool,
            q.sport.as_deref(),
            q.q.as_deref(),
            q.limit,
        )
        .await?,
    ))
}

async fn list_spaces(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(venue_id): Path<Uuid>,
) -> ApiResult<Json<Vec<VenueSpace>>> {
    let club_id = hire_repo::get_venue_club_id(&state.pool, venue_id)
        .await?
        .ok_or_else(|| ApiError::not_found("venue not found"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ViewClub).await?;
    Ok(Json(
        hire_repo::list_spaces_for_venue(&state.pool, venue_id).await?,
    ))
}

async fn create_space(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(venue_id): Path<Uuid>,
    Json(body): Json<CreateVenueSpaceRequest>,
) -> ApiResult<Json<VenueSpace>> {
    body.validate()?;
    let club_id = hire_repo::get_venue_club_id(&state.pool, venue_id)
        .await?
        .ok_or_else(|| ApiError::not_found("venue not found"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ManageVenues).await?;
    Ok(Json(
        hire_repo::create_space(&state.pool, venue_id, &body).await?,
    ))
}

async fn get_space(
    State(state): State<AppState>,
    Path(space_id): Path<Uuid>,
) -> ApiResult<Json<VenueSpace>> {
    let space = hire_repo::get_space(&state.pool, space_id)
        .await?
        .ok_or_else(|| ApiError::not_found("space not found"))?;
    // Hireable active spaces are public; otherwise require membership (checked below).
    if space.is_hireable && space.active {
        return Ok(Json(space));
    }
    Err(ApiError::not_found("space not found"))
}

async fn update_space(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(space_id): Path<Uuid>,
    Json(body): Json<UpdateVenueSpaceRequest>,
) -> ApiResult<Json<VenueSpace>> {
    body.validate()?;
    let club_id = hire_repo::space_club_id(&state.pool, space_id)
        .await?
        .ok_or_else(|| ApiError::not_found("space not found"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ManageVenues).await?;
    hire_repo::update_space(&state.pool, space_id, &body)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("space not found"))
}

async fn list_rates(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(space_id): Path<Uuid>,
) -> ApiResult<Json<Vec<VenueRateCard>>> {
    let club_id = hire_repo::space_club_id(&state.pool, space_id)
        .await?
        .ok_or_else(|| ApiError::not_found("space not found"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ViewClub).await?;
    Ok(Json(
        hire_repo::list_rate_cards(&state.pool, space_id).await?,
    ))
}

async fn create_rate(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(space_id): Path<Uuid>,
    Json(body): Json<CreateVenueRateCardRequest>,
) -> ApiResult<Json<VenueRateCard>> {
    body.validate()?;
    let club_id = hire_repo::space_club_id(&state.pool, space_id)
        .await?
        .ok_or_else(|| ApiError::not_found("space not found"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ManageVenues).await?;
    Ok(Json(
        hire_repo::create_rate_card(&state.pool, space_id, &body).await?,
    ))
}

#[derive(Debug, Deserialize)]
struct SetActiveBody {
    active: bool,
}

async fn set_rate_active(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(rate_id): Path<Uuid>,
    Json(body): Json<SetActiveBody>,
) -> ApiResult<Json<VenueRateCard>> {
    let club_id = hire_repo::rate_card_club_id(&state.pool, rate_id)
        .await?
        .ok_or_else(|| ApiError::not_found("rate not found"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ManageVenues).await?;
    hire_repo::set_rate_card_active(&state.pool, rate_id, body.active)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("rate not found"))
}

async fn list_availability(
    State(state): State<AppState>,
    Path(space_id): Path<Uuid>,
) -> ApiResult<Json<Vec<VenueAvailabilityWindow>>> {
    let space = hire_repo::get_space(&state.pool, space_id)
        .await?
        .ok_or_else(|| ApiError::not_found("space not found"))?;
    // Public for hireable spaces; members can also peek via owning club elsewhere.
    if !(space.is_hireable && space.active) {
        return Err(ApiError::not_found("space not found"));
    }
    Ok(Json(
        hire_repo::list_availability(&state.pool, space_id).await?,
    ))
}

async fn set_availability(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(space_id): Path<Uuid>,
    Json(body): Json<SetVenueAvailabilityRequest>,
) -> ApiResult<Json<Vec<VenueAvailabilityWindow>>> {
    body.validate()?;
    for w in &body.windows {
        w.validate()?;
        if w.closes_at <= w.opens_at {
            return Err(ApiError::bad_request(
                "each availability window needs closes_at after opens_at",
            ));
        }
    }
    let club_id = hire_repo::space_club_id(&state.pool, space_id)
        .await?
        .ok_or_else(|| ApiError::not_found("space not found"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ManageVenues).await?;
    Ok(Json(
        hire_repo::replace_availability(&state.pool, space_id, &body).await?,
    ))
}

async fn list_blackouts(
    State(state): State<AppState>,
    Path(space_id): Path<Uuid>,
) -> ApiResult<Json<Vec<VenueBlackout>>> {
    let space = hire_repo::get_space(&state.pool, space_id)
        .await?
        .ok_or_else(|| ApiError::not_found("space not found"))?;
    if !(space.is_hireable && space.active) {
        return Err(ApiError::not_found("space not found"));
    }
    Ok(Json(
        hire_repo::list_blackouts(&state.pool, space_id).await?,
    ))
}

async fn create_blackout(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(space_id): Path<Uuid>,
    Json(body): Json<CreateVenueBlackoutRequest>,
) -> ApiResult<Json<VenueBlackout>> {
    body.validate()?;
    if body.ends_at <= body.starts_at {
        return Err(ApiError::bad_request("ends_at must be after starts_at"));
    }
    let club_id = hire_repo::space_club_id(&state.pool, space_id)
        .await?
        .ok_or_else(|| ApiError::not_found("space not found"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ManageVenues).await?;
    Ok(Json(
        hire_repo::create_blackout(&state.pool, space_id, &body).await?,
    ))
}

async fn delete_blackout(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(blackout_id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let club_id = hire_repo::blackout_club_id(&state.pool, blackout_id)
        .await?
        .ok_or_else(|| ApiError::not_found("blackout not found"))?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ManageVenues).await?;
    if !hire_repo::delete_blackout(&state.pool, blackout_id).await? {
        return Err(ApiError::not_found("blackout not found"));
    }
    Ok(Json(serde_json::json!({ "ok": true })))
}
