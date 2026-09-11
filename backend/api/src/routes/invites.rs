use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::clubs as clubs_repo;
use fishers_db::repos::events as events_repo;
use fishers_db::repos::invites as invites_repo;
use fishers_db::repos::users as users_repo;
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

    let (invite, fresh) = invites_repo::create_invite(&state.pool, auth.user_id, &body).await?;

    // Tell the person being invited — once, and never the person inviting.
    // An invite to an email reaches its owner if they already have an account;
    // otherwise the link itself is how it arrives. (This used to fall back to
    // notifying the inviter, who got told they had been invited.)
    let invitee = match body.invited_user_id {
        Some(id) => Some(id),
        None => match body.invited_email.as_deref() {
            Some(email) => users_repo::find_by_email(&state.pool, email).await?.map(|u| u.id),
            None => None,
        },
    };
    if let (true, Some(invitee)) = (fresh, invitee) {
        let what = describe(&state, &body).await?;
        let inviter = users_repo::find_by_id(&state.pool, auth.user_id)
            .await?
            .map(|u| u.name)
            .unwrap_or_else(|| "Someone".into());
        let (title, text) = what.headline(&inviter);
        state
            .notify(
                invitee,
                "invite",
                &title,
                &text,
                serde_json::json!({
                    "invite_id": invite.id,
                    "target_type": body.target_type,
                    "club_name": what.club,
                    "team_name": what.team,
                    "event_title": what.event,
                    "inviter": inviter,
                    // Where a tap on the push lands: the dashboard lists it to accept.
                    "url": "/",
                    // Its own, so two invites both stay on the lock screen.
                    "tag": format!("invite:{}", invite.id),
                }),
            )
            .await;
    }
    Ok(Json(invite))
}

/// Names for what an invite is to, for the words people actually read.
struct InviteTo {
    club: Option<String>,
    team: Option<String>,
    event: Option<String>,
}

impl InviteTo {
    /// The push notification. The bell builds its own line from the same
    /// facts, carried in the payload.
    fn headline(&self, inviter: &str) -> (String, String) {
        let club = self.club.as_deref().unwrap_or("A club");
        match (&self.team, &self.event) {
            (Some(team), _) => (
                format!("{club} wants you in their {team}"),
                format!("{inviter} invited you to join {team} at {club}. Open Fishers to accept."),
            ),
            (_, Some(event)) => (
                format!("You're invited: {event}"),
                format!("{inviter} invited you to {event}. Open Fishers to answer."),
            ),
            _ => (
                format!("{club} wants you in the club"),
                format!("{inviter} invited you to join {club}. Open Fishers to accept."),
            ),
        }
    }
}

async fn describe(state: &AppState, body: &CreateInviteRequest) -> ApiResult<InviteTo> {
    let club_name = |id| async move {
        Ok::<_, ApiError>(clubs_repo::get_club(&state.pool, id).await?.map(|c| c.name))
    };
    Ok(match body.target_type {
        InviteTarget::Club => InviteTo { club: club_name(body.target_id).await?, team: None, event: None },
        InviteTarget::Team => {
            let team = clubs_repo::get_team(&state.pool, body.target_id).await?;
            InviteTo {
                club: match &team {
                    Some(t) => club_name(t.club_id).await?,
                    None => None,
                },
                team: team.map(|t| t.name),
                event: None,
            }
        }
        InviteTarget::Event => {
            let event = events_repo::get_event(&state.pool, body.target_id).await?;
            InviteTo {
                club: match &event {
                    Some(e) => club_name(e.club_id).await?,
                    None => None,
                },
                team: None,
                event: event.map(|e| e.title),
            }
        }
    })
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
    super::verification::require_verified(&state, auth.user_id).await?;
    let invite = invites_repo::accept_invite(&state.pool, &token, auth.user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("invite not found or already used"))?;

    // Close the loop for whoever sent it: they asked, and this is the answer.
    if invite.invited_by != auth.user_id {
        let what = describe(
            &state,
            &CreateInviteRequest {
                target_type: invite.target_type,
                target_id: invite.target_id,
                invited_user_id: None,
                invited_email: None,
            },
        )
        .await?;
        let player = users_repo::find_by_id(&state.pool, auth.user_id)
            .await?
            .map(|u| u.name)
            .unwrap_or_else(|| "A player".into());
        let into = what.team.clone().or(what.event.clone()).or(what.club.clone()).unwrap_or_default();
        let club_id = match invite.target_type {
            InviteTarget::Club => Some(invite.target_id),
            InviteTarget::Team => clubs_repo::get_team(&state.pool, invite.target_id).await?.map(|t| t.club_id),
            InviteTarget::Event => None,
        };
        state
            .notify(
                invite.invited_by,
                "invite_accepted",
                &format!("{player} accepted"),
                &format!("{player} is in {into}."),
                serde_json::json!({
                    "player": player,
                    "target_type": invite.target_type,
                    "club_name": what.club,
                    "team_name": what.team,
                    "event_title": what.event,
                    "club_id": club_id,
                    "url": club_id.map(|c| format!("/clubs/{c}#members")),
                    "tag": format!("accepted:{}", invite.id),
                }),
            )
            .await;
    }
    Ok(Json(invite))
}
