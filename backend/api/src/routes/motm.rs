//! The club's man-of-the-match vote.
//!
//! A poll opens on its own when a match finishes (see `services::motm`); this
//! is how it is read, voted in and closed. Voting is open to every active
//! member of either club — the point of the feature is the people who watched
//! rather than played — while the ballot is only the players who were named
//! on a team sheet.

use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::{
    clubs as clubs_repo, cricket as cricket_repo, events as events_repo, motm as motm_repo,
};
use fishers_domain::{
    CastMotmVoteRequest, MotmCandidate, MotmPoll, MotmPollView, Permission,
};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::require_permission;
use crate::services::motm as motm_service;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/events/{id}/motm", get(poll_for_event))
        .route("/motm/polls/{id}", get(get_poll))
        .route(
            "/motm/polls/{id}/vote",
            post(cast_vote).delete(withdraw_vote),
        )
        .route("/motm/polls/{id}/close", post(close_poll))
}

/// The vote for a fixture, or 404 when it has none — a game still being
/// played, or one that finished before anybody was named on a sheet.
async fn poll_for_event(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
) -> ApiResult<Json<MotmPollView>> {
    let poll = motm_repo::poll_for_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("no man-of-the-match vote for this fixture"))?;
    view_for(&state, &poll, auth.user_id).await.map(Json)
}

async fn get_poll(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MotmPollView>> {
    let poll = load(&state, id).await?;
    view_for(&state, &poll, auth.user_id).await.map(Json)
}

async fn cast_vote(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CastMotmVoteRequest>,
) -> ApiResult<Json<MotmPollView>> {
    let poll = load(&state, id).await?;
    require_voter(&state, &poll, auth.user_id).await?;
    if !poll.is_open() {
        return Err(ApiError::conflict("voting has closed"));
    }
    if !motm_repo::cast_vote(&state.pool, poll.id, auth.user_id, body.candidate_user_id).await? {
        return Err(ApiError::bad_request(
            "that player was not named on either team sheet",
        ));
    }
    view_for(&state, &poll, auth.user_id).await.map(Json)
}

/// Take a vote back — which leaves you able to vote again, not abstaining
/// permanently. Only while the poll is open: a closed poll is a record.
async fn withdraw_vote(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MotmPollView>> {
    let poll = load(&state, id).await?;
    require_voter(&state, &poll, auth.user_id).await?;
    if !poll.is_open() {
        return Err(ApiError::conflict("voting has closed"));
    }
    motm_repo::withdraw_vote(&state.pool, poll.id, auth.user_id).await?;
    view_for(&state, &poll, auth.user_id).await.map(Json)
}

/// End the vote now and announce the winner. A captain or secretary of the
/// club whose fixture it is — the poll closes itself when its time is up, so
/// this is only for calling it early.
async fn close_poll(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MotmPollView>> {
    let poll = load(&state, id).await?;
    let team_id = events_repo::get_event(&state.pool, poll.event_id)
        .await?
        .and_then(|event| event.team_id);
    require_permission(
        &state,
        poll.club_id,
        auth.user_id,
        team_id,
        Permission::ManageEvents,
    )
    .await?;

    let closed = motm_service::close_and_announce(&state, &poll, Some(auth.user_id))
        .await
        .ok_or_else(|| ApiError::conflict("this vote has already been closed"))?;
    view_for(&state, &closed, auth.user_id).await.map(Json)
}

async fn load(state: &AppState, id: Uuid) -> ApiResult<MotmPoll> {
    motm_repo::get_poll(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("vote not found"))
}

/// Who may vote: any active member of either club in the fixture.
///
/// Deliberately wider than "who played". Somebody watching from the boundary
/// has the clearest view of the game and no reason to be shut out of it.
async fn require_voter(state: &AppState, poll: &MotmPoll, user_id: Uuid) -> ApiResult<()> {
    if clubs_repo::is_club_member(&state.pool, poll.club_id, user_id).await? {
        return Ok(());
    }
    let opponent = events_repo::get_event(&state.pool, poll.event_id)
        .await?
        .and_then(|event| event.opponent_club_id);
    if let Some(opponent) = opponent {
        if clubs_repo::is_club_member(&state.pool, opponent, user_id).await? {
            return Ok(());
        }
    }
    Err(ApiError::forbidden(
        "only the clubs who played this fixture can vote",
    ))
}

/// The poll as this person is allowed to see it.
///
/// The tally is withheld until they have voted or the poll has closed:
/// showing a running total to somebody still making their mind up is a nudge
/// towards whoever is already winning, and a club vote does not need one.
async fn view_for(state: &AppState, poll: &MotmPoll, user_id: Uuid) -> ApiResult<MotmPollView> {
    let my_vote = motm_repo::my_vote(&state.pool, poll.id, user_id).await?;
    let total_votes = motm_repo::total_votes(&state.pool, poll.id).await?;
    let is_open = poll.is_open();
    let tally_visible = my_vote.is_some() || !is_open;

    let mut candidates = motm_repo::candidates(&state.pool, poll.id).await?;
    if !tally_visible {
        // Zeroed rather than omitted: the ballot still has to be drawn, and
        // sorting it by a count nobody may see leaks the count.
        candidates.sort_by(|a, b| a.side.cmp(&b.side).then(a.display_name.cmp(&b.display_name)));
        candidates = candidates
            .into_iter()
            .map(|c| MotmCandidate { votes: 0, ..c })
            .collect();
    }

    let can_vote = is_open && require_voter(state, poll, user_id).await.is_ok();

    // The scorer's own award, so the app can show the two side by side rather
    // than letting a club vote look like it overruled the person scoring.
    let scorer_award_user_id = match poll.match_id {
        Some(match_id) => cricket_repo::get_match(&state.pool, match_id)
            .await?
            .map(|row| cricket_repo::parse_state(&row))
            .and_then(|state| state.player_of_the_match),
        None => None,
    };

    Ok(MotmPollView {
        poll: poll.clone(),
        candidates,
        my_vote,
        total_votes,
        tally_visible,
        can_vote,
        scorer_award_user_id,
    })
}
