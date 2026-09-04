use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::clubs as clubs_repo;
use fishers_domain::{
    permissions_for, AddMemberRequest, Club, ClubMember, CreateClubRequest, CreateTeamRequest,
    CreateVenueRequest, Permission, Team, TeamMember, UserRole, Venue,
};
use serde::Serialize;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_club_member, require_club_permission, require_secretary};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/clubs", get(list_clubs).post(create_club))
        .route("/clubs/{id}", get(get_club))
        .route("/clubs/{id}/my-role", get(my_role))
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
    require_club_member(&state, id, auth.user_id).await?;
    let club = clubs_repo::get_club(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("club not found"))?;
    Ok(Json(club))
}

#[derive(Serialize)]
struct MyRoleResponse {
    role: UserRole,
    display_name: &'static str,
    /// Product alias — club_admin is the club secretary.
    is_secretary: bool,
    is_captain: bool,
    can_invite_to_play: bool,
    permissions: Vec<&'static str>,
}

async fn my_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MyRoleResponse>> {
    let role = require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(MyRoleResponse {
        role,
        display_name: role.display_name(),
        is_secretary: matches!(role, UserRole::ClubAdmin | UserRole::SuperAdmin),
        is_captain: matches!(
            role,
            UserRole::TeamCaptain | UserRole::ClubAdmin | UserRole::SuperAdmin
        ),
        can_invite_to_play: role.can_invite_to_play(),
        permissions: permissions_for(role)
            .iter()
            .map(|p| p.as_str())
            .collect(),
    }))
}

async fn list_members(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<ClubMember>>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_members(&state.pool, id).await?))
}

async fn add_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AddMemberRequest>,
) -> ApiResult<Json<ClubMember>> {
    // Only secretary can add members / assign captain.
    require_secretary(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::add_member(&state.pool, id, &body).await?))
}

async fn create_team(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateTeamRequest>,
) -> ApiResult<Json<Team>> {
    body.validate()?;
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;
    Ok(Json(
        clubs_repo::create_team(&state.pool, id, &body).await?,
    ))
}

async fn list_teams(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<Team>>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_teams(&state.pool, id).await?))
}

async fn create_venue(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateVenueRequest>,
) -> ApiResult<Json<Venue>> {
    body.validate()?;
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;
    Ok(Json(
        clubs_repo::create_venue(&state.pool, id, &body).await?,
    ))
}

async fn list_venues(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<Venue>>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_venues(&state.pool, id).await?))
}

#[derive(serde::Deserialize)]
struct TeamMemberBody {
    user_id: Uuid,
    role: Option<UserRole>,
}

async fn add_team_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<TeamMemberBody>,
) -> ApiResult<Json<TeamMember>> {
    let team = clubs_repo::get_team(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("team not found"))?;
    // Secretary can always add; team captain can invite onto their team.
    require_club_permission(
        &state,
        team.club_id,
        auth.user_id,
        Permission::InviteToTeam,
    )
    .await?;
    // Only secretary may appoint another captain.
    if matches!(body.role, Some(UserRole::TeamCaptain | UserRole::ClubAdmin)) {
        require_secretary(&state, team.club_id, auth.user_id).await?;
    }
    let role = body.role.unwrap_or(UserRole::Member);
    Ok(Json(
        clubs_repo::add_team_member(&state.pool, id, body.user_id, role).await?,
    ))
}
