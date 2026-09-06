//! Cricket match scoring API — offline-first event sync.

use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::{cricket as cricket_repo, events as events_repo};
use fishers_domain::{
    DlsPar, MatchState, MatchStatus, Permission, ScoringEvent, ScoringEventKind, UserRole,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_club_member, require_event_permission, require_permission};
use crate::services::platform_bus;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/events/{id}/cricket-match",
            post(create_or_get_match).get(get_match_for_event),
        )
        .route("/cricket/matches/{id}", get(get_match))
        .route("/cricket/matches/{id}/claim-scorer", post(claim_scorer))
        .route(
            "/cricket/matches/{id}/events",
            post(post_events).get(list_events),
        )
        .route("/cricket/matches/{id}/scorecard", get(scorecard))
        .route("/cricket/matches/{id}/officials", post(add_official))
}

#[derive(Deserialize)]
struct CreateMatchBody {
    /// The device may choose the id, so a match started with no signal can be
    /// scored locally and registered under the same id when it reconnects.
    #[serde(default)]
    match_id: Option<Uuid>,
    #[serde(default = "default_overs")]
    overs_limit: i32,
    #[serde(default = "default_home")]
    home_name: String,
    #[serde(default = "default_away")]
    away_name: String,
}

fn default_overs() -> i32 {
    20
}
fn default_home() -> String {
    "Home".into()
}
fn default_away() -> String {
    "Away".into()
}

#[derive(Serialize)]
struct MatchResponse {
    id: Uuid,
    event_id: Uuid,
    club_id: Uuid,
    status: String,
    overs_limit: i32,
    home_name: String,
    away_name: String,
    last_seq: i64,
    active_scorer_user_id: Option<Uuid>,
    active_scorer_device_id: Option<String>,
    /// True when the caller is allowed to score this match.
    can_score: bool,
    /// Where the chase stands on DLS, from the first ball of the second innings.
    #[serde(skip_serializing_if = "Option::is_none")]
    dls: Option<DlsPar>,
    state: MatchState,
}

fn to_response(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    can_score: bool,
) -> MatchResponse {
    let projection = cricket_repo::parse_state(row);
    let dls = projection.dls_par(&state.dls, state.g50);
    MatchResponse {
        id: row.id,
        event_id: row.event_id,
        club_id: row.club_id,
        status: row.status.clone(),
        overs_limit: row.overs_limit,
        home_name: row.home_name.clone(),
        away_name: row.away_name.clone(),
        last_seq: row.last_seq,
        active_scorer_user_id: row.active_scorer_user_id,
        active_scorer_device_id: row.active_scorer_device_id.clone(),
        can_score,
        dls,
        state: projection,
    }
}

async fn create_or_get_match(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
    Json(body): Json<CreateMatchBody>,
) -> ApiResult<Json<MatchResponse>> {
    let (event, _) =
        require_event_permission(&state, event_id, auth.user_id, Permission::ScoreMatch).await?;
    if event.sport != fishers_domain::SportType::Cricket {
        return Err(ApiError::bad_request("only cricket fixtures can be scored"));
    }
    if !(1..=100).contains(&body.overs_limit) {
        return Err(ApiError::bad_request("overs must be between 1 and 100"));
    }
    let row = cricket_repo::create_match(
        &state.pool,
        body.match_id,
        event_id,
        event.club_id,
        auth.user_id,
        &body.home_name,
        &body.away_name,
        body.overs_limit,
    )
    .await?;
    Ok(Json(to_response(&state, &row, true)))
}

async fn get_match_for_event(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
) -> ApiResult<Json<MatchResponse>> {
    let event = events_repo::get_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    require_club_member(&state, event.club_id, auth.user_id).await?;
    let row = cricket_repo::get_match_by_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("cricket match not started"))?;
    let can_score = may_score(&state, &row, auth.user_id).await;
    Ok(Json(to_response(&state, &row, can_score)))
}

async fn get_match(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_club_member(&state, row.club_id, auth.user_id).await?;
    let can_score = may_score(&state, &row, auth.user_id).await;
    Ok(Json(to_response(&state, &row, can_score)))
}

#[derive(Deserialize)]
struct ClaimBody {
    device_id: String,
    /// Take the match off a scorer whose phone has died mid-innings.
    #[serde(default)]
    force: bool,
}

async fn claim_scorer(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<ClaimBody>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_can_score(&state, &row, auth.user_id).await?;
    let updated = cricket_repo::claim_scorer(
        &state.pool,
        id,
        auth.user_id,
        &body.device_id,
        body.force,
    )
    .await?
    .ok_or_else(|| {
        ApiError::conflict(
            "another device is scoring this match — take over to score from here instead",
        )
    })?;
    platform_bus::match_started(
        &state,
        updated.club_id,
        updated.event_id,
        updated.id,
        auth.user_id,
        "cricket",
    )
    .await;
    Ok(Json(to_response(&state, &updated, true)))
}

#[derive(Deserialize)]
struct EventsBatch {
    device_id: Option<String>,
    events: Vec<ScoringEvent>,
}

async fn post_events(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<EventsBatch>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_can_score(&state, &row, auth.user_id).await?;
    if let Some(active) = row.active_scorer_user_id {
        if active != auth.user_id {
            return Err(ApiError::conflict(
                "someone else is the active scorer for this match",
            ));
        }
    }
    if body.events.len() > 500 {
        return Err(ApiError::bad_request("send at most 500 events per batch"));
    }
    // Whether the match was already over decides if this batch is the one that
    // finished it, and so whether the club hears about it.
    let prev_complete = cricket_repo::parse_state(&row).status == MatchStatus::Complete;

    let state_out = cricket_repo::apply_event_batch(
        &state.pool,
        id,
        &body.events,
        auth.user_id,
        body.device_id.as_deref(),
    )
    .await
    .map_err(|e| ApiError::conflict(e.to_string()))?;

    if !prev_complete && state_out.status == fishers_domain::MatchStatus::Complete {
        platform_bus::match_completed(
            &state,
            row.club_id,
            row.event_id,
            id,
            auth.user_id,
            "cricket",
            state_out.margin.clone(),
        )
        .await;
    }

    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    let mut resp = to_response(&state, &row, true);
    resp.dls = state_out.dls_par(&state.dls, state.g50);
    resp.state = state_out;
    Ok(Json(resp))
}

#[derive(Deserialize)]
struct EventsQuery {
    after_seq: Option<i64>,
}

#[derive(Serialize)]
struct EventListItem {
    seq: i64,
    client_event_id: Uuid,
    kind: ScoringEventKind,
}

async fn list_events(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Query(q): Query<EventsQuery>,
) -> ApiResult<Json<Vec<EventListItem>>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_club_member(&state, row.club_id, auth.user_id).await?;
    let after = q.after_seq.unwrap_or(0);
    let rows = cricket_repo::list_events_after(&state.pool, id, after).await?;
    let mut out = Vec::new();
    for (seq, client_event_id, payload) in rows {
        if let Ok(kind) = serde_json::from_value::<ScoringEventKind>(payload) {
            out.push(EventListItem {
                seq,
                client_event_id,
                kind,
            });
        }
    }
    Ok(Json(out))
}

#[derive(Serialize)]
struct ScorecardResponse {
    #[serde(flatten)]
    state: MatchState,
    #[serde(skip_serializing_if = "Option::is_none")]
    dls: Option<DlsPar>,
}

async fn scorecard(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<ScorecardResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_club_member(&state, row.club_id, auth.user_id).await?;
    let projection = cricket_repo::parse_state(&row);
    let dls = projection.dls_par(&state.dls, state.g50);
    Ok(Json(ScorecardResponse {
        state: projection,
        dls,
    }))
}

#[derive(Deserialize)]
struct OfficialBody {
    user_id: Uuid,
}

async fn add_official(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<OfficialBody>,
) -> ApiResult<Json<serde_json::Value>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_permission(
        &state,
        row.club_id,
        auth.user_id,
        None,
        Permission::ManageEvents,
    )
    .await?;
    cricket_repo::add_official(&state.pool, id, body.user_id).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

/// Scoring is for club officers with `score_match`, plus anyone named on the
/// match as a scorer — a club's regular scorer needn't be a captain.
async fn require_can_score(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    user_id: Uuid,
) -> ApiResult<UserRole> {
    if cricket_repo::is_official(&state.pool, row.id, user_id).await? {
        return Ok(UserRole::Member); // granted via the officials list
    }
    require_permission(
        state,
        row.club_id,
        user_id,
        None,
        Permission::ScoreMatch,
    )
    .await
}

/// Same question, as a flag for the UI rather than a rejection.
async fn may_score(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    user_id: Uuid,
) -> bool {
    require_can_score(state, row, user_id).await.is_ok()
}
