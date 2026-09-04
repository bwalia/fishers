//! Cricket match scoring API — offline-first event sync.

use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::{cricket as cricket_repo, events as events_repo};
use fishers_domain::{
    permissions_for, MatchState, Permission, ScoringEvent, ScoringEventKind, UserRole,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_event_permission, require_permission};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/events/{id}/cricket-match", post(create_or_get_match).get(get_match_for_event))
        .route("/cricket/matches/{id}", get(get_match))
        .route("/cricket/matches/{id}/claim-scorer", post(claim_scorer))
        .route("/cricket/matches/{id}/events", post(post_events).get(list_events))
        .route("/cricket/matches/{id}/scorecard", get(scorecard))
        .route("/cricket/matches/{id}/officials", post(add_official))
}

#[derive(Deserialize)]
struct CreateMatchBody {
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
    state: MatchState,
}

fn to_response(row: &cricket_repo::CricketMatchRow) -> MatchResponse {
    let state = cricket_repo::parse_state(row);
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
        state,
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
    let row = cricket_repo::create_match(
        &state.pool,
        event_id,
        event.club_id,
        auth.user_id,
        &body.home_name,
        &body.away_name,
        body.overs_limit,
    )
    .await?;
    Ok(Json(to_response(&row)))
}

async fn get_match_for_event(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
) -> ApiResult<Json<MatchResponse>> {
    let event = events_repo::get_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    crate::rbac::require_club_member(&state, event.club_id, auth.user_id).await?;
    let row = cricket_repo::get_match_by_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("cricket match not started"))?;
    Ok(Json(to_response(&row)))
}

async fn get_match(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    crate::rbac::require_club_member(&state, row.club_id, auth.user_id).await?;
    Ok(Json(to_response(&row)))
}

#[derive(Deserialize)]
struct ClaimBody {
    device_id: String,
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
    let updated = cricket_repo::claim_scorer(&state.pool, id, auth.user_id, &body.device_id)
        .await
        .map_err(|_| ApiError::conflict("another scorer holds this match"))?;
    Ok(Json(to_response(&updated)))
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
            return Err(ApiError::forbidden("not the active scorer for this match"));
        }
    }
    let state_out = cricket_repo::apply_event_batch(
        &state.pool,
        id,
        &body.events,
        auth.user_id,
        body.device_id.as_deref(),
    )
    .await
    .map_err(|e| ApiError::bad_request(e.to_string()))?;

    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    let mut resp = to_response(&row);
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
    crate::rbac::require_club_member(&state, row.club_id, auth.user_id).await?;
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

async fn scorecard(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MatchState>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    crate::rbac::require_club_member(&state, row.club_id, auth.user_id).await?;
    Ok(Json(cricket_repo::parse_state(&row)))
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

async fn require_can_score(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    user_id: Uuid,
) -> ApiResult<UserRole> {
    if cricket_repo::is_official(&state.pool, row.id, user_id).await? {
        return Ok(UserRole::Member); // granted via officials list
    }
    let role = require_permission(
        state,
        row.club_id,
        user_id,
        None,
        Permission::ScoreMatch,
    )
    .await?;
    let _ = permissions_for(role);
    Ok(role)
}
