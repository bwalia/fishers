use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::clubs as clubs_repo;
use fishers_domain::{
    AddMemberRequest, Club, ClubMember, CreateClubRequest, CreateTeamRequest, CreateVenueRequest,
    Team, TeamMember, UserRole, Venue,
};
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/clubs", get(list_clubs).post(create_club))
        .route("/clubs/{id}", get(get_club))
        .route("/clubs/{id}/members", get(list_members).post(add_member))
        .route("/clubs/{id}/teams", get(list_teams).post(create_team))
        .route("/clubs/{id}/venues", get(list_venues).post(create_venue))
        .route("/teams/{id}/members", post(add_team_member))
}

async fn create_club(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<CreateClubRequest>,
) -> ApiResult<Json<Club>> {
    body.validate()?;
    let club = clubs_repo::create_club(&state.pool, auth.user_id, &body).await?;
    Ok(Json(club))
}

async fn list_clubs(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<Vec<Club>>> {
    Ok(Json(
        clubs_repo::list_clubs_for_user(&state.pool, auth.user_id).await?,
    ))
}

async fn get_club(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Club>> {
    require_member(&state, id, auth.user_id).await?;
    let club = clubs_repo::get_club(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("club not found"))?;
    Ok(Json(club))
}

async fn list_members(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<ClubMember>>> {
    require_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_members(&state.pool, id).await?))
}

async fn add_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AddMemberRequest>,
) -> ApiResult<Json<ClubMember>> {
    require_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::add_member(&state.pool, id, &body).await?))
}

async fn create_team(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateTeamRequest>,
) -> ApiResult<Json<Team>> {
    body.validate()?;
    require_member(&state, id, auth.user_id).await?;
    Ok(Json(
        clubs_repo::create_team(&state.pool, id, &body).await?,
    ))
}

async fn list_teams(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<Team>>> {
    require_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_teams(&state.pool, id).await?))
}

async fn create_venue(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateVenueRequest>,
) -> ApiResult<Json<Venue>> {
    body.validate()?;
    require_member(&state, id, auth.user_id).await?;
    Ok(Json(
        clubs_repo::create_venue(&state.pool, id, &body).await?,
    ))
}

async fn list_venues(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<Venue>>> {
    require_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_venues(&state.pool, id).await?))
}

#[derive(serde::Deserialize)]
struct TeamMemberBody {
    user_id: Uuid,
    role: Option<UserRole>,
}

async fn add_team_member(
    State(state): State<AppState>,
    _auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<TeamMemberBody>,
) -> ApiResult<Json<TeamMember>> {
    let role = body.role.unwrap_or(UserRole::Member);
    Ok(Json(
        clubs_repo::add_team_member(&state.pool, id, body.user_id, role).await?,
    ))
}

async fn require_member(state: &AppState, club_id: Uuid, user_id: Uuid) -> ApiResult<()> {
    if clubs_repo::is_club_member(&state.pool, club_id, user_id).await? {
        Ok(())
    } else {
        Err(ApiError::forbidden("not a club member"))
    }
}
