//! HTTP-layer RBAC helpers — resolve club/team role then check [`Permission`].

use fishers_db::repos::clubs as clubs_repo;
use fishers_db::repos::events as events_repo;
use fishers_domain::{Permission, UserRole};
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub async fn role_in_club(
    state: &AppState,
    club_id: Uuid,
    user_id: Uuid,
) -> ApiResult<UserRole> {
    clubs_repo::club_role(&state.pool, club_id, user_id)
        .await?
        .ok_or_else(|| ApiError::forbidden("not a club member"))
}

pub async fn require_club_member(
    state: &AppState,
    club_id: Uuid,
    user_id: Uuid,
) -> ApiResult<UserRole> {
    let role = role_in_club(state, club_id, user_id).await?;
    if role.can(Permission::ViewClub) {
        Ok(role)
    } else {
        Err(ApiError::forbidden("not allowed to view this club"))
    }
}

pub async fn require_club_permission(
    state: &AppState,
    club_id: Uuid,
    user_id: Uuid,
    permission: Permission,
) -> ApiResult<UserRole> {
    let role = role_in_club(state, club_id, user_id).await?;
    if role.can(permission) {
        Ok(role)
    } else {
        Err(ApiError::forbidden(format!(
            "{} cannot {} — needs club secretary or captain",
            role.display_name(),
            permission.as_str()
        )))
    }
}

/// Club role, raised by team captaincy when `team_id` is set.
pub async fn require_permission(
    state: &AppState,
    club_id: Uuid,
    user_id: Uuid,
    team_id: Option<Uuid>,
    permission: Permission,
) -> ApiResult<UserRole> {
    let role = clubs_repo::effective_membership_role(&state.pool, club_id, user_id, team_id)
        .await?
        .ok_or_else(|| ApiError::forbidden("not a club member"))?;
    if role.can(permission) {
        Ok(role)
    } else {
        Err(ApiError::forbidden(format!(
            "{} cannot {} — ask a club secretary or captain",
            role.display_name(),
            permission.as_str()
        )))
    }
}

pub async fn require_event_permission(
    state: &AppState,
    event_id: Uuid,
    user_id: Uuid,
    permission: Permission,
) -> ApiResult<(fishers_domain::Event, UserRole)> {
    let event = events_repo::get_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    let role = require_permission(
        state,
        event.club_id,
        user_id,
        event.team_id,
        permission,
    )
    .await?;
    Ok((event, role))
}

/// Secretary-only actions (manage members / assign captain).
pub async fn require_secretary(
    state: &AppState,
    club_id: Uuid,
    user_id: Uuid,
) -> ApiResult<UserRole> {
    require_club_permission(state, club_id, user_id, Permission::ManageMembers).await
}

/// Captain or secretary — invite to play / selection.
pub async fn require_captain_or_secretary(
    state: &AppState,
    club_id: Uuid,
    user_id: Uuid,
    team_id: Option<Uuid>,
) -> ApiResult<UserRole> {
    require_permission(
        state,
        club_id,
        user_id,
        team_id,
        Permission::InviteToEvent,
    )
    .await
}
