use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::clubs as clubs_repo;
use fishers_db::repos::events as events_repo;
use fishers_db::repos::invites as invites_repo;
use fishers_domain::{CreateInviteRequest, Invite, InviteTarget, Permission};
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::require_permission;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/invites", post(create_invite))
        .route("/invites/mine", get(my_invites))
        .route("/invites/{token}/accept", post(accept_invite))
}

async fn create_invite(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<CreateInviteRequest>,
) -> ApiResult<Json<Invite>> {
    body.validate()?;
    authorize_invite(&state, auth.user_id, &body).await?;

    let invite = invites_repo::create_invite(&state.pool, auth.user_id, &body).await?;
    let _ = state
        .push
        .send(
            body.invited_user_id.unwrap_or(auth.user_id),
            "invite",
            "You're invited",
            "You have a new Fishers invite",
            serde_json::json!({ "invite_id": invite.id, "token": invite.token }),
        )
        .await;
    Ok(Json(invite))
}

async fn authorize_invite(
    state: &AppState,
    user_id: uuid::Uuid,
    body: &CreateInviteRequest,
) -> ApiResult<()> {
    match body.target_type {
        InviteTarget::Club => {
            require_permission(
                state,
                body.target_id,
                user_id,
                None,
                Permission::InviteToClub,
            )
            .await?;
        }
        InviteTarget::Team => {
            let team = clubs_repo::get_team(&state.pool, body.target_id)
                .await?
                .ok_or_else(|| ApiError::not_found("team not found"))?;
            require_permission(
                state,
                team.club_id,
                user_id,
                Some(team.id),
                Permission::InviteToTeam,
            )
            .await?;
        }
        InviteTarget::Event => {
            let event = events_repo::get_event(&state.pool, body.target_id)
                .await?
                .ok_or_else(|| ApiError::not_found("event not found"))?;
            require_permission(
                state,
                event.club_id,
                user_id,
                event.team_id,
                Permission::InviteToEvent,
            )
            .await?;
        }
    }
    Ok(())
}

async fn my_invites(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<Vec<Invite>>> {
    Ok(Json(
        invites_repo::list_my_invites(&state.pool, auth.user_id).await?,
    ))
}

async fn accept_invite(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(token): Path<String>,
) -> ApiResult<Json<Invite>> {
    let invite = invites_repo::accept_invite(&state.pool, &token, auth.user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("invite not found or already used"))?;
    Ok(Json(invite))
}
