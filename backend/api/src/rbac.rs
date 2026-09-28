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

/// Whether somebody may look at the whole system rather than their own clubs.
///
/// Two conditions, and the second is the one that matters: the address has to
/// be on `PLATFORM_ADMIN_EMAILS` **and** verified. Without the verification
/// check, anybody could sign up with the operator's address and be an admin
/// until they were asked to confirm it — the allowlist would be a list of
/// usernames to impersonate rather than a grant.
pub async fn is_platform_admin(state: &AppState, user_id: Uuid) -> Result<bool, sqlx::Error> {
    if state.platform_admins.is_empty() {
        return Ok(false);
    }
    let row: Option<(Option<String>, Option<chrono::DateTime<chrono::Utc>>)> = sqlx::query_as(
        "SELECT email, email_verified_at FROM users WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await?;

    Ok(match row {
        Some((email, verified)) => admits(
            &state.platform_admins,
            email.as_deref(),
            verified.is_some(),
        ),
        None => false,
    })
}

/// The decision itself, with no database in the way.
///
/// Split out so the rule can be tested: "the address is on the list **and**
/// confirmed" is a security property, and a property nothing checks is one
/// somebody simplifies away on a tired afternoon.
fn admits(
    admins: &std::collections::HashSet<String>,
    email: Option<&str>,
    verified: bool,
) -> bool {
    let Some(email) = email else { return false };
    verified && admins.contains(&email.to_ascii_lowercase())
}

/// The gate on every admin endpoint.
///
/// 404 rather than 403 when refused: a 403 confirms the panel is there and
/// that this account is not on the list, which is a fact worth nothing to the
/// person asking and something to an attacker enumerating.
pub async fn require_platform_admin(state: &AppState, user_id: Uuid) -> ApiResult<()> {
    if is_platform_admin(state, user_id).await? {
        return Ok(());
    }
    Err(ApiError::not_found("no such endpoint"))
}

#[cfg(test)]
mod platform_admin_tests {
    use super::admits;
    use std::collections::HashSet;

    fn list(entries: &[&str]) -> HashSet<String> {
        entries.iter().map(|e| e.to_string()).collect()
    }

    #[test]
    fn nobody_is_an_admin_when_the_list_is_empty() {
        assert!(!admits(&list(&[]), Some("someone@example.com"), true));
    }

    #[test]
    fn an_address_on_the_list_and_confirmed_is_admitted() {
        assert!(admits(&list(&["someone@example.com"]), Some("someone@example.com"), true));
    }

    /// The one that matters. Without it the list is a set of usernames to
    /// impersonate: register with the operator's address, be an admin until
    /// somebody notices.
    #[test]
    fn an_unconfirmed_address_is_refused_even_when_it_is_on_the_list() {
        assert!(!admits(&list(&["someone@example.com"]), Some("someone@example.com"), false));
    }

    #[test]
    fn an_address_not_on_the_list_is_refused() {
        assert!(!admits(&list(&["someone@example.com"]), Some("else@example.com"), true));
    }

    /// Addresses are not case-sensitive, and the list is lower-cased when it
    /// is read. Somebody who signed up with a capital would otherwise be
    /// locked out of their own panel by their own shift key.
    #[test]
    fn case_does_not_decide_it() {
        assert!(admits(&list(&["someone@example.com"]), Some("SomeOne@Example.COM"), true));
    }

    #[test]
    fn an_account_with_no_email_is_refused() {
        assert!(!admits(&list(&["someone@example.com"]), None, true));
    }
}
