use axum::extract::{Path, State};
use axum::routing::{get, patch, post};
use axum::{Json, Router};
use fishers_db::repos::clubs as clubs_repo;
use fishers_db::repos::clubs::{ClubMemberDetail, ClubSettings, UpdateClubSettings};
use fishers_domain::{
    parse_role, permissions_for, AddMemberRequest, Club, ClubMember, CreateClubRequest,
    CreateTeamRequest, CreateVenueRequest, Permission, Team, TeamMember, UserRole, Venue,
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
        .route(
            "/clubs/{id}/members/{user_id}",
            patch(update_member_role).delete(remove_member),
        )
        .route("/clubs/{id}/settings", get(get_settings).patch(update_settings))
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
    can_score_match: bool,
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
            UserRole::TeamCaptain
                | UserRole::TeamViceCaptain
                | UserRole::ClubAdmin
                | UserRole::SuperAdmin
        ),
        can_invite_to_play: role.can_invite_to_play(),
        can_score_match: role.can_score_match(),
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
) -> ApiResult<Json<Vec<ClubMemberDetail>>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::list_member_details(&state.pool, id).await?))
}

#[derive(serde::Deserialize)]
struct AddMemberBody {
    #[serde(flatten)]
    inner: AddMemberRequest,
    /// Add by email when the secretary does not know the user id.
    email: Option<String>,
}

async fn add_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AddMemberBody>,
) -> ApiResult<Json<ClubMember>> {
    // Only a secretary adds members, and only a secretary appoints captains.
    require_secretary(&state, id, auth.user_id).await?;

    let user_id = match body.email.as_deref() {
        Some(email) if !email.is_empty() => {
            clubs_repo::find_user_by_email(&state.pool, email)
                .await?
                .map(|(id, _, _)| id)
                .ok_or_else(|| {
                    ApiError::not_found("nobody with that email has a Fishers account yet")
                })?
        }
        _ => body.inner.user_id,
    };

    let request = AddMemberRequest {
        user_id,
        role: body.inner.role,
    };
    Ok(Json(clubs_repo::add_member(&state.pool, id, &request).await?))
}

#[derive(serde::Deserialize)]
struct RoleBody {
    /// Accepts the product words too: `secretary`, `captain`, `vice_captain`.
    role: String,
}

/// Appoint a captain, a vice captain, or stand someone down.
async fn update_member_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, user_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<RoleBody>,
) -> ApiResult<Json<ClubMember>> {
    require_secretary(&state, club_id, auth.user_id).await?;
    let role = parse_role(&body.role)
        .ok_or_else(|| ApiError::bad_request(format!("unknown role: {}", body.role)))?;
    if role == UserRole::SuperAdmin {
        return Err(ApiError::forbidden(
            "platform administrators are not appointed from inside a club",
        ));
    }

    // A club without a secretary cannot appoint one, so never remove the last.
    let current = clubs_repo::club_role(&state.pool, club_id, user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("that person is not in this club"))?;
    let losing_a_secretary = matches!(current, UserRole::ClubAdmin | UserRole::SuperAdmin)
        && !matches!(role, UserRole::ClubAdmin | UserRole::SuperAdmin);
    if losing_a_secretary && clubs_repo::count_secretaries(&state.pool, club_id).await? <= 1 {
        return Err(ApiError::conflict(
            "this is the club's last secretary — appoint another one first",
        ));
    }

    clubs_repo::update_member_role(&state.pool, club_id, user_id, role)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("that person is not in this club"))
}

async fn remove_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, user_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<serde_json::Value>> {
    require_secretary(&state, club_id, auth.user_id).await?;
    let current = clubs_repo::club_role(&state.pool, club_id, user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("that person is not in this club"))?;
    if matches!(current, UserRole::ClubAdmin | UserRole::SuperAdmin)
        && clubs_repo::count_secretaries(&state.pool, club_id).await? <= 1
    {
        return Err(ApiError::conflict(
            "this is the club's last secretary — appoint another one first",
        ));
    }
    let removed = clubs_repo::remove_member(&state.pool, club_id, user_id).await?;
    Ok(Json(serde_json::json!({ "removed": removed })))
}

/// Club policy: how much the assistant may do, when players are chased for a
/// reconfirmation, and how hard match fees are pursued.
async fn get_settings(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<ClubSettings>> {
    require_club_member(&state, id, auth.user_id).await?;
    Ok(Json(clubs_repo::get_settings(&state.pool, id).await?))
}

async fn update_settings(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<UpdateClubSettings>,
) -> ApiResult<Json<ClubSettings>> {
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;

    if let Some(autonomy) = body.selection_autonomy.as_deref() {
        if !matches!(autonomy, "off" | "suggest" | "auto_publish") {
            return Err(ApiError::bad_request(
                "autonomy must be off, suggest or auto_publish",
            ));
        }
    }
    for (label, value) in [
        ("confirm_lead_hours", body.confirm_lead_hours),
        ("drop_lead_hours", body.drop_lead_hours),
        ("fee_chase_after_hours", body.fee_chase_after_hours),
    ] {
        if let Some(hours) = value {
            if !(0..=336).contains(&hours) {
                return Err(ApiError::bad_request(format!(
                    "{label} must be between 0 and 336 hours"
                )));
            }
        }
    }
    if let Some(max) = body.fee_chase_max_reminders {
        if !(0..=10).contains(&max) {
            return Err(ApiError::bad_request("at most ten reminders"));
        }
    }

    Ok(Json(
        clubs_repo::update_settings(&state.pool, id, &body).await?,
    ))
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
