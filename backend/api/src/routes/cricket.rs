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
        .route(
            "/cricket/matches/{id}/officials",
            get(list_officials).post(add_official),
        )
        .route(
            "/cricket/matches/{id}/officials/{user_id}",
            axum::routing::delete(remove_official),
        )
        .route("/cricket/matches/{id}/handover", post(handover))
        .route("/cricket/matches/{id}/scorer-trail", get(scorer_trail))
        .route("/cricket/matches/{id}/commentary", post(commentary))
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
    /// Break glass: take the book from a scorer whose phone has died. Needs
    /// `manage_events`, and is written to the handover trail.
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

    let updated = if body.force {
        // Only a captain or secretary may take the book off someone, and only
        // ever on the record.
        require_permission(
            &state,
            row.club_id,
            auth.user_id,
            None,
            Permission::ManageEvents,
        )
        .await?;
        cricket_repo::override_scorer(
            &state.pool,
            id,
            auth.user_id,
            auth.user_id,
            &body.device_id,
        )
        .await?
    } else {
        cricket_repo::claim_scorer(&state.pool, id, auth.user_id, &body.device_id).await?
    };

    let updated = updated.ok_or_else(|| {
        ApiError::conflict(
            "someone else is scoring this match — ask them to hand it over, \
             or a captain can take it on the record",
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
    /// `umpire` or `scorer`. Either may score the match.
    #[serde(default = "default_official_role")]
    role: String,
}

fn default_official_role() -> String {
    "scorer".into()
}

/// Appoint an umpire or a scorer. Umpires are named before the toss and may
/// control the scoring — at club level the square-leg umpire often keeps the
/// book.
async fn add_official(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<OfficialBody>,
) -> ApiResult<Json<Vec<cricket_repo::OfficialRow>>> {
    if !matches!(body.role.as_str(), "umpire" | "scorer") {
        return Err(ApiError::bad_request("a match official is an umpire or a scorer"));
    }
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
    cricket_repo::add_official(&state.pool, id, body.user_id, &body.role, auth.user_id).await?;
    Ok(Json(cricket_repo::list_officials(&state.pool, id).await?))
}

async fn list_officials(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<cricket_repo::OfficialRow>>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_club_member(&state, row.club_id, auth.user_id).await?;
    Ok(Json(cricket_repo::list_officials(&state.pool, id).await?))
}

async fn remove_official(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((id, user_id)): Path<(Uuid, Uuid)>,
) -> ApiResult<Json<Vec<cricket_repo::OfficialRow>>> {
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
    cricket_repo::remove_official(&state.pool, id, user_id).await?;
    Ok(Json(cricket_repo::list_officials(&state.pool, id).await?))
}

#[derive(Deserialize)]
struct HandoverBody {
    to_user_id: Uuid,
}

/// Pass the book on. Only the scorer currently holding it can do this — which
/// is what stops anyone else altering a match while it is being scored.
async fn handover(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<HandoverBody>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;

    if row.active_scorer_user_id != Some(auth.user_id) {
        return Err(ApiError::forbidden(
            "only the scorer holding the book can hand it over",
        ));
    }
    if body.to_user_id == auth.user_id {
        return Err(ApiError::bad_request("you already have it"));
    }
    // Whoever receives it has to be allowed to score.
    let recipient_may_score = cricket_repo::is_official(&state.pool, id, body.to_user_id).await?
        || require_permission(
            &state,
            row.club_id,
            body.to_user_id,
            None,
            Permission::ScoreMatch,
        )
        .await
        .is_ok();
    if !recipient_may_score {
        return Err(ApiError::bad_request(
            "that person cannot score this match — appoint them as an official first",
        ));
    }

    let updated = cricket_repo::handover(&state.pool, id, auth.user_id, body.to_user_id)
        .await?
        .ok_or_else(|| ApiError::conflict("the book has already moved on"))?;
    Ok(Json(to_response(&state, &updated, false)))
}

/// Who has held the book, and how it changed hands.
async fn scorer_trail(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<cricket_repo::HandoverRow>>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_club_member(&state, row.club_id, auth.user_id).await?;
    Ok(Json(cricket_repo::handover_trail(&state.pool, id).await?))
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

#[derive(Deserialize)]
struct CommentaryRequest {
    /// Which ball to call. Defaults to the last one bowled.
    over: Option<u16>,
    ball_in_over: Option<u8>,
}

#[derive(Serialize)]
struct CommentaryResponse {
    /// `None` when no model is configured or it could not oblige — the caller
    /// keeps the line it already has.
    line: Option<String>,
    model: Option<String>,
}

/// A line of colour for one ball.
///
/// The facts are built here from the stored state, never taken from the caller,
/// so the model cannot be handed a score that did not happen. Scoring never
/// waits on this: the ball is already recorded by the time anyone asks.
async fn commentary(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CommentaryRequest>,
) -> ApiResult<Json<CommentaryResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_club_member(&state, row.club_id, auth.user_id).await?;

    let Some(ollama) = state.ollama.clone() else {
        return Ok(Json(CommentaryResponse { line: None, model: None }));
    };

    let projection = cricket_repo::parse_state(&row);
    let Some(inn) = projection.innings.last() else {
        return Err(ApiError::bad_request("nothing has been bowled yet"));
    };
    let ball = match (body.over, body.ball_in_over) {
        (Some(o), Some(b)) => inn
            .deliveries
            .iter()
            .rev()
            .find(|d| d.over == o && d.ball_in_over == b),
        _ => inn.deliveries.last(),
    }
    .ok_or_else(|| ApiError::not_found("no such ball"))?;

    let name = |who: Option<Uuid>| {
        who.and_then(|w| projection.player_names.get(&w).cloned())
            .unwrap_or_else(|| "the batter".to_string())
    };
    let mut facts = format!(
        "Over {}.{}. {} bowls to {}. Result: {}.",
        ball.over,
        ball.ball_in_over,
        name(ball.bowler_id),
        name(ball.batter_id),
        ball.label
    );
    if let Some(shot) = ball.shot {
        let left = ball
            .batter_id
            .map(|b| projection.left_handers.contains(&b))
            .unwrap_or(false);
        facts.push_str(&format!(
            " Shot: {}, towards {}.",
            format!("{:?}", shot.kind).to_lowercase(),
            fishers_domain::region_for(shot.angle, left)
        ));
    }
    facts.push_str(&format!(
        " Score now {} for {} after {}.{} overs.",
        inn.runs,
        inn.wickets,
        inn.legal_balls / 6,
        inn.legal_balls % 6
    ));
    if let Some(target) = projection.target {
        facts.push_str(&format!(
            " Chasing {}, needing {} more.",
            target,
            target.saturating_sub(inn.runs)
        ));
    }

    let line = ollama
        .commentate(
            &facts,
            crate::services::ollama::BallFacts {
                is_wicket: ball.is_wicket,
                runs: ball.runs,
                is_legal: ball.is_legal,
            },
        )
        .await;
    Ok(Json(CommentaryResponse {
        line,
        model: Some(ollama.model().to_string()),
    }))
}
