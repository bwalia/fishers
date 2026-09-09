//! Cricket match scoring API — offline-first event sync.

use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::{
    clubs as clubs_repo, cricket as cricket_repo, events as events_repo,
    selection as selection_repo, users as users_repo,
};
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
        .route("/cricket/matches/{id}/squad", get(squad))
        .route("/cricket/matches/{id}/xi", post(submit_xi))
        .route("/cricket/matches/{id}/propose", post(propose_terms))
        .route("/cricket/matches/{id}/agree", post(agree_terms))
        .route(
            "/cricket/matches/{id}",
            get(get_match).delete(delete_match),
        )
        .route("/cricket/matches/{id}/abandon", post(abandon_match))
        .route("/cricket/fixtures", get(list_fixtures))
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
    /// The other side, when they were matched to a Fishers club by QR or by
    /// name. Without this their captain has no way in and no squad to pick
    /// from, which is why the column existed but nothing ever filled it.
    #[serde(default)]
    opponent_club_id: Option<Uuid>,
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
    /// The visiting club, when they are on Fishers. The setup screen needs it
    /// to offer the away captain from the right roster rather than the home
    /// club's.
    opponent_club_id: Option<Uuid>,
    status: String,
    overs_limit: i32,
    home_name: String,
    away_name: String,
    last_seq: i64,
    active_scorer_user_id: Option<Uuid>,
    active_scorer_device_id: Option<String>,
    /// True when the caller is allowed to score this match.
    can_score: bool,
    /// When the fixture is. A club plays the same opposition several times a
    /// season, so the sides alone do not say which match you have opened.
    #[serde(skip_serializing_if = "Option::is_none")]
    start_at: Option<chrono::DateTime<chrono::Utc>>,
    /// The side this caller actually plays for, when they are in one of the
    /// clubs. Distinct from `my_sides`: a scorer may act for both, but they
    /// only belong to one, and proposing terms on behalf of the opposition is
    /// something you do because their captain is standing next to you — never
    /// by accident.
    my_club_side: Option<fishers_domain::MatchSide>,
    /// Which sides this caller may propose or agree terms for.
    ///
    /// The scorer at the ground gets both, because they record the
    /// conversation both captains are having in front of them. A captain on
    /// their own phone gets their own side only — showing them the other
    /// club's agreement form asks for something the server will always refuse.
    my_sides: Vec<fishers_domain::MatchSide>,
    /// Where the chase stands on DLS, from the first ball of the second innings.
    #[serde(skip_serializing_if = "Option::is_none")]
    dls: Option<DlsPar>,
    state: MatchState,
}

fn to_response(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    can_score: bool,
    my_sides: Vec<fishers_domain::MatchSide>,
    my_club_side: Option<fishers_domain::MatchSide>,
    start_at: Option<chrono::DateTime<chrono::Utc>>,
) -> MatchResponse {
    let projection = cricket_repo::parse_state(row);
    let dls = projection.dls_par(&state.dls, state.g50);
    MatchResponse {
        id: row.id,
        event_id: row.event_id,
        club_id: row.club_id,
        opponent_club_id: row.opponent_club_id,
        status: row.status.clone(),
        overs_limit: row.overs_limit,
        home_name: row.home_name.clone(),
        away_name: row.away_name.clone(),
        last_seq: row.last_seq,
        active_scorer_user_id: row.active_scorer_user_id,
        active_scorer_device_id: row.active_scorer_device_id.clone(),
        can_score,
        start_at,
        my_club_side,
        my_sides,
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
        body.opponent_club_id,
        auth.user_id,
        &body.home_name,
        &body.away_name,
        body.overs_limit,
    )
    .await?;
    let sides = sides_for(&state, &row, auth.user_id).await;
    let mine = club_side_for(&state, &row, auth.user_id).await;
    let when = fixture_time(&state, &row).await;
    Ok(Json(to_response(&state, &row, true, sides, mine, when)))
}

async fn get_match_for_event(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(event_id): Path<Uuid>,
) -> ApiResult<Json<MatchResponse>> {
    events_repo::get_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("event not found"))?;
    let row = cricket_repo::get_match_by_event(&state.pool, event_id)
        .await?
        .ok_or_else(|| ApiError::not_found("cricket match not started"))?;
    // Checked against the match, not the event: the visiting club is on the
    // match, and the fixture belongs to the host.
    require_either_side(&state, &row, auth.user_id).await?;
    let can_score = may_score(&state, &row, auth.user_id).await;
    let sides = sides_for(&state, &row, auth.user_id).await;
    let mine = club_side_for(&state, &row, auth.user_id).await;
    let when = fixture_time(&state, &row).await;
    Ok(Json(to_response(&state, &row, can_score, sides, mine, when)))
}

async fn get_match(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_either_side(&state, &row, auth.user_id).await?;
    let can_score = may_score(&state, &row, auth.user_id).await;
    let sides = sides_for(&state, &row, auth.user_id).await;
    let mine = club_side_for(&state, &row, auth.user_id).await;
    let when = fixture_time(&state, &row).await;
    Ok(Json(to_response(&state, &row, can_score, sides, mine, when)))
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
    let sides = sides_for(&state, &updated, auth.user_id).await;
    let mine = club_side_for(&state, &updated, auth.user_id).await;
    let when = fixture_time(&state, &updated).await;
    Ok(Json(to_response(&state, &updated, true, sides, mine, when)))
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

    // The other captain has to be told the terms are on the table, or the match
    // waits on somebody who does not know they are being waited on.
    if body
        .events
        .iter()
        .any(|e| matches!(e.kind, ScoringEventKind::ConditionsProposed { .. }))
    {
        notify_opposition_of_terms(&state, &row, &state_out, auth.user_id).await;
    }

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
    let sides = sides_for(&state, &row, auth.user_id).await;
    let mine = club_side_for(&state, &row, auth.user_id).await;
    let when = fixture_time(&state, &row).await;
    let mut resp = to_response(&state, &row, true, sides, mine, when);
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
    require_either_side(&state, &row, auth.user_id).await?;
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
    require_either_side(&state, &row, auth.user_id).await?;
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
    require_either_side(&state, &row, auth.user_id).await?;
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
    let sides = sides_for(&state, &updated, auth.user_id).await;
    let mine = club_side_for(&state, &updated, auth.user_id).await;
    let when = fixture_time(&state, &updated).await;
    Ok(Json(to_response(&state, &updated, false, sides, mine, when)))
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
    require_either_side(&state, &row, auth.user_id).await?;
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

/// When the fixture behind this match is.
async fn fixture_time(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
) -> Option<chrono::DateTime<chrono::Utc>> {
    events_repo::get_event(&state.pool, row.event_id)
        .await
        .ok()
        .flatten()
        .map(|e| e.start_at)
}

/// The side this user actually plays for.
async fn club_side_for(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    user_id: Uuid,
) -> Option<fishers_domain::MatchSide> {
    use fishers_domain::MatchSide;
    if require_club_member(state, row.club_id, user_id).await.is_ok() {
        return Some(MatchSide::Home);
    }
    if let Some(club) = row.opponent_club_id {
        if require_club_member(state, club, user_id).await.is_ok() {
            return Some(MatchSide::Away);
        }
    }
    None
}

/// The sides this user may speak for.
///
/// Deliberately the same test `agree_terms` and `submit_xi` apply, so the app
/// can never put a form in front of somebody the server will then refuse.
async fn sides_for(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    user_id: Uuid,
) -> Vec<fishers_domain::MatchSide> {
    use fishers_domain::MatchSide;
    if may_score(state, row, user_id).await {
        return vec![MatchSide::Home, MatchSide::Away];
    }
    let mut sides = Vec::new();
    if may_manage_selection(state, Some(row.club_id), user_id).await {
        sides.push(MatchSide::Home);
    }
    if may_manage_selection(state, row.opponent_club_id, user_id).await {
        sides.push(MatchSide::Away);
    }
    sides
}

/// A match belongs to both sides.
///
/// Checking only the home club locked the visiting captain out of the fixture
/// they are playing in — they could not open it, so they could not agree the
/// terms they were being asked to agree.
async fn require_either_side(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    user_id: Uuid,
) -> ApiResult<()> {
    if require_club_member(state, row.club_id, user_id).await.is_ok() {
        return Ok(());
    }
    if let Some(club) = row.opponent_club_id {
        if require_club_member(state, club, user_id).await.is_ok() {
            return Ok(());
        }
    }
    Err(ApiError::forbidden("you are not in either side"))
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
    require_either_side(&state, &row, auth.user_id).await?;

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


// MARK: Squads and team sheets

#[derive(Serialize)]
struct SquadPlayer {
    id: Uuid,
    name: String,
    /// "selected", "reserve", "available", "unavailable" or "member" — enough
    /// for a captain to see who was picked for this fixture and who was not.
    standing: String,
    bats_left: bool,
}

#[derive(Serialize)]
struct SideSquad {
    side: &'static str,
    team_name: String,
    /// Null when this side is not a club in Fishers — the scorer names them.
    club_id: Option<Uuid>,
    /// Whether the caller may submit this side's sheet.
    can_pick: bool,
    /// Already named, if the captain has been.
    submitted: bool,
    players: Vec<SquadPlayer>,
}

#[derive(Serialize)]
struct SquadResponse {
    home: SideSquad,
    away: SideSquad,
}

/// Who each captain has to pick from.
///
/// The home side comes from the fixture's own selection board — the squad that
/// was picked, with availability already worked out — because that is what a
/// squad for this game means. The away side comes from the opposing club's
/// members when the opposition was matched by QR; a club that is not in Fishers
/// has no pool, and the scorer names them as before.
async fn squad(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<SquadResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_either_side(&state, &row, auth.user_id).await?;
    let projection = cricket_repo::parse_state(&row);

    let scorer = may_score(&state, &row, auth.user_id).await;
    let home_pick = scorer
        || may_manage_selection(&state, Some(row.club_id), auth.user_id).await;
    let away_pick = scorer
        || may_manage_selection(&state, row.opponent_club_id, auth.user_id).await;

    // The fixture's board: who was picked, who is a reserve, who said no.
    let mut home_players: Vec<SquadPlayer> = selection_repo::candidates(&state.pool, row.event_id)
        .await
        .unwrap_or_default()
        .into_iter()
        .map(|c| SquadPlayer {
            id: c.user_id,
            standing: standing_of(&c),
            bats_left: projection.left_handers.contains(&c.user_id),
            name: c.name,
        })
        .collect();
    home_players.sort_by(|a, b| standing_rank(&a.standing).cmp(&standing_rank(&b.standing)));

    // Members carry no name of their own, so look them up as the scoreboard does.
    let away_players = match row.opponent_club_id {
        Some(club) => {
            let members = clubs_repo::list_members(&state.pool, club)
                .await
                .unwrap_or_default();
            let ids: Vec<Uuid> = members.iter().map(|m| m.user_id).collect();
            let names: std::collections::HashMap<Uuid, String> =
                users_repo::names_for(&state.pool, &ids)
                    .await
                    .unwrap_or_default()
                    .into_iter()
                    .collect();
            members
                .into_iter()
                .map(|m| SquadPlayer {
                    id: m.user_id,
                    name: names.get(&m.user_id).cloned().unwrap_or_else(|| "Player".into()),
                    standing: "member".into(),
                    bats_left: projection.left_handers.contains(&m.user_id),
                })
                .collect()
        }
        None => Vec::new(),
    };

    Ok(Json(SquadResponse {
        home: SideSquad {
            side: "home",
            team_name: projection.home_name.clone(),
            club_id: Some(row.club_id),
            can_pick: home_pick,
            submitted: !projection.home_xi.is_empty(),
            players: home_players,
        },
        away: SideSquad {
            side: "away",
            team_name: projection.away_name.clone(),
            club_id: row.opponent_club_id,
            can_pick: away_pick,
            submitted: !projection.away_xi.is_empty(),
            players: away_players,
        },
    }))
}

fn side_name(projection: &fishers_domain::MatchState, side: fishers_domain::MatchSide) -> String {
    match side {
        fishers_domain::MatchSide::Home => projection.home_name.clone(),
        fishers_domain::MatchSide::Away => projection.away_name.clone(),
    }
}

/// What a notification needs to say *which* match it is about.
///
/// A club with several fixtures against the same opposition gets several
/// identical-looking notifications, and following an old one lands you in a
/// different match than the one you are scoring. The kick-off time is what
/// tells them apart.
async fn match_payload(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    projection: &fishers_domain::MatchState,
) -> serde_json::Value {
    let start_at = events_repo::get_event(&state.pool, row.event_id)
        .await
        .ok()
        .flatten()
        .map(|e| e.start_at);
    serde_json::json!({
        "match_id": row.id,
        "event_id": row.event_id,
        "home_name": projection.home_name,
        "away_name": projection.away_name,
        "start_at": start_at,
    })
}

/// Tell everyone in both clubs who is involved in running the match.
async fn notify_both_sides(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    projection: &fishers_domain::MatchState,
    kind: &str,
    body: String,
    except: Uuid,
) {
    let title = format!("{} v {}", projection.home_name, projection.away_name);
    let payload = match_payload(state, row, projection).await;
    for club in [Some(row.club_id), row.opponent_club_id].into_iter().flatten() {
        for member in clubs_repo::list_members(&state.pool, club)
            .await
            .unwrap_or_default()
        {
            if member.user_id == except || !member.role.can_score_match() {
                continue;
            }
            state
                .notify(member.user_id, kind, &title, &body, payload.clone())
                .await;
        }
    }
}

/// Tell the other side's captains it is their turn.
///
/// Without this the flow stalls on somebody who does not know they are being
/// waited on: the match cannot start until both sides are named, and nothing
/// told them.
async fn notify_side_to_pick(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    projection: &fishers_domain::MatchState,
    side: fishers_domain::MatchSide,
    except: Uuid,
) {
    let club = match side {
        fishers_domain::MatchSide::Home => Some(row.club_id),
        fishers_domain::MatchSide::Away => row.opponent_club_id,
    };
    let Some(club) = club else { return };

    let title = format!("{} v {}", projection.home_name, projection.away_name);
    let body = match (projection.toss_winner, projection.toss_decision) {
        (Some(winner), Some(decision)) => format!(
            "{} won the toss and chose to {}. Pick your side to get the match started.",
            side_name(projection, winner),
            format!("{decision:?}").to_lowercase(),
        ),
        _ => "The other side is named. Pick yours to get the match started.".into(),
    };
    let payload = match_payload(state, row, projection).await;

    for member in clubs_repo::list_members(&state.pool, club)
        .await
        .unwrap_or_default()
    {
        if member.user_id == except || !member.role.can_score_match() {
            continue;
        }
        state
            .notify(member.user_id, "match_pick_your_xi", &title, &body, payload.clone())
            .await;
    }
}

/// Tell whoever can agree for the other side that terms are waiting on them.
///
/// Goes to the side that has *not* agreed: proposing counts as the proposer
/// agreeing, so it is the other club's captains and secretary who need to act.
async fn notify_opposition_of_terms(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    projection: &fishers_domain::MatchState,
    proposer: Uuid,
) {
    // Whichever side is still outstanding decides which club hears about it.
    let waiting_home = projection.agreed_home.is_none();
    let club = if waiting_home {
        Some(row.club_id)
    } else {
        row.opponent_club_id
    };
    let Some(club) = club else { return };

    let members = clubs_repo::list_members(&state.pool, club)
        .await
        .unwrap_or_default();
    let title = format!("{} v {}", projection.home_name, projection.away_name);
    let body = format!(
        "{} overs, {:?} ball. Open the match to agree the terms.",
        projection.conditions.overs_limit,
        projection.conditions.ball
    )
    .to_lowercase();
    let payload = match_payload(state, row, projection).await;

    for member in members {
        // The proposer already knows; anyone who cannot agree cannot act on it.
        if member.user_id == proposer || !member.role.can_score_match() {
            continue;
        }
        state
            .notify(member.user_id, "match_terms_proposed", &title, &body, payload.clone())
            .await;
    }
}

fn standing_of(c: &fishers_domain::Candidate) -> String {
    use fishers_domain::{AvailabilityStatus, SelectionState};
    match c.state {
        SelectionState::Selected => "selected".into(),
        SelectionState::Reserve => "reserve".into(),
        _ => match c.availability {
            Some(AvailabilityStatus::Available) => "available".into(),
            Some(AvailabilityStatus::Unavailable) => "unavailable".into(),
            _ => "member".into(),
        },
    }
}

fn standing_rank(standing: &str) -> u8 {
    match standing {
        "selected" => 0,
        "reserve" => 1,
        "available" => 2,
        "member" => 3,
        _ => 4,
    }
}

async fn may_manage_selection(state: &AppState, club: Option<Uuid>, user_id: Uuid) -> bool {
    let Some(club) = club else { return false };
    require_permission(state, club, user_id, None, Permission::ManageSelection)
        .await
        .is_ok()
}

#[derive(Deserialize)]
struct XiRequest {
    side: fishers_domain::MatchSide,
    players: Vec<fishers_domain::MatchPlayer>,
    #[serde(default)]
    captain_id: Option<Uuid>,
    #[serde(default)]
    keeper_id: Option<Uuid>,
}

/// A captain names their own side.
///
/// Separate from the scoring log's usual door because the two captains are not
/// the scorer: each names their own eleven, from their own device, and neither
/// has to hold the book to do it. The sequence number is worked out here rather
/// than sent, so two captains submitting at once cannot collide on one.
///
/// Players do not have to be club members. A side short on the morning can be
/// made up by whoever turns up, and that player is recorded on the sheet by
/// name like any other.
#[derive(Deserialize)]
struct FixtureQuery {
    club_id: Option<Uuid>,
    /// `live`, `upcoming` or `finished`.
    state: Option<String>,
    q: Option<String>,
    /// `asc` (default, next fixture first) or `desc`.
    order: Option<String>,
    page: Option<i64>,
    per_page: Option<i64>,
}

#[derive(Serialize)]
struct FixtureSummary {
    event_id: Uuid,
    club_id: Uuid,
    title: String,
    start_at: chrono::DateTime<chrono::Utc>,
    event_status: String,
    match_id: Option<Uuid>,
    match_status: Option<String>,
    home_name: Option<String>,
    away_name: Option<String>,
    /// Whoever is holding the book, so the list can say so without asking.
    has_scorer: bool,
    /// The live score, when there is one — "128/4 (14.2 ov)".
    score: Option<String>,
    result: Option<String>,
}

/// Cricket fixtures for the scoring list: one query, paged and filtered.
///
/// This replaces fetching every event and then asking about each one — a
/// round trip per fixture, and no paging at all, which is a hundred requests
/// for a club with a season behind it.
async fn list_fixtures(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<FixtureQuery>,
) -> ApiResult<Json<serde_json::Value>> {
    if let Some(club_id) = q.club_id {
        require_club_member(&state, club_id, auth.user_id).await?;
    }
    let order = q.order.as_deref().unwrap_or("asc");
    if !matches!(order, "asc" | "desc") {
        return Err(ApiError::bad_request("order must be asc or desc"));
    }
    if let Some(s) = q.state.as_deref() {
        if !matches!(s, "live" | "upcoming" | "finished") {
            return Err(ApiError::bad_request(
                "state must be live, upcoming or finished",
            ));
        }
    }
    if let Some(page) = q.page {
        if page < 1 {
            return Err(ApiError::bad_request("page starts at 1"));
        }
    }
    if let Some(per_page) = q.per_page {
        if !(1..=100).contains(&per_page) {
            return Err(ApiError::bad_request("per_page must be between 1 and 100"));
        }
    }
    let search = q
        .q
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);
    if search.as_deref().is_some_and(|s| s.chars().count() < 2) {
        return Err(ApiError::bad_request("give at least two letters to search on"));
    }

    let filter = cricket_repo::FixtureFilter {
        club_id: q.club_id,
        state: q.state.clone(),
        search,
        descending: order == "desc",
        page: q.page.unwrap_or(1),
        per_page: q.per_page.unwrap_or(20),
    };
    let found = cricket_repo::list_cricket_fixtures(&state.pool, auth.user_id, &filter).await?;

    let items: Vec<FixtureSummary> = found
        .items
        .iter()
        .map(|row| {
            // The projection is already stored; parsing it here costs nothing
            // and saves the list a request per fixture.
            let projection: Option<fishers_domain::MatchState> = row
                .state_json
                .clone()
                .and_then(|v| serde_json::from_value(v).ok());
            let score = projection.as_ref().and_then(|p| {
                p.innings.last().map(|inn| {
                    format!(
                        "{}/{} ({}.{} ov)",
                        inn.runs,
                        inn.wickets,
                        inn.legal_balls / 6,
                        inn.legal_balls % 6
                    )
                })
            });
            FixtureSummary {
                event_id: row.event_id,
                club_id: row.club_id,
                title: row.title.clone(),
                start_at: row.start_at,
                event_status: row.event_status.clone(),
                match_id: row.match_id,
                match_status: row.match_status.clone(),
                home_name: row.home_name.clone(),
                away_name: row.away_name.clone(),
                has_scorer: row.active_scorer_user_id.is_some(),
                score,
                result: projection.as_ref().and_then(|p| p.margin.clone()),
            }
        })
        .collect();

    Ok(Json(serde_json::json!({
        "items": items,
        "total": found.total,
        "page": found.page,
        "per_page": found.per_page,
        "has_more": found.has_more,
    })))
}

#[derive(Deserialize)]
struct AbandonRequest {
    /// "rain", "bad light", "ground unfit" — whatever goes in the book.
    #[serde(default)]
    reason: String,
}

/// Call the match off with no result.
///
/// Recorded as an event, not a deletion: an innings that was played happened,
/// the averages count, and a scorecard has to be able to say why it stopped.
/// Only a captain or secretary — abandoning is a decision about the fixture,
/// not a scoring action, so holding the book is not enough.
async fn abandon_match(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AbandonRequest>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_match_manager(&state, &row, auth.user_id).await?;

    let projection = cricket_repo::parse_state(&row);
    if projection.status == MatchStatus::Complete {
        return Err(ApiError::conflict("this match already has a result"));
    }

    let event = ScoringEvent {
        client_event_id: Uuid::new_v4(),
        seq: projection.last_seq + 1,
        kind: ScoringEventKind::MatchAbandoned {
            reason: body.reason.trim().to_string(),
        },
        at: Some(chrono::Utc::now()),
    };
    let state_out =
        cricket_repo::apply_event_batch(&state.pool, id, &[event], auth.user_id, None)
            .await
            .map_err(|e| ApiError::conflict(e.to_string()))?;

    notify_both_sides(
        &state,
        &row,
        &state_out,
        "match_abandoned",
        state_out
            .margin
            .clone()
            .unwrap_or_else(|| "Abandoned — no result".into()),
        auth.user_id,
    )
    .await;

    let refreshed = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    let can_score = may_score(&state, &refreshed, auth.user_id).await;
    let sides = sides_for(&state, &refreshed, auth.user_id).await;
    let mine = club_side_for(&state, &refreshed, auth.user_id).await;
    let when = fixture_time(&state, &refreshed).await;
    Ok(Json(to_response(&state, &refreshed, can_score, sides, mine, when)))
}

/// Remove a match set up by mistake.
///
/// Only while nothing has been scored. Once a ball has been bowled the log is
/// a record of something that happened to real people, and the way to end it
/// is to abandon it — which keeps the scorecard — not to delete it.
async fn delete_match(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    require_match_manager(&state, &row, auth.user_id).await?;

    let projection = cricket_repo::parse_state(&row);
    if projection.innings.iter().any(|i| i.legal_balls > 0 || i.runs > 0) {
        return Err(ApiError::conflict(
            "balls have been bowled — abandon the match instead, so the scorecard survives",
        ));
    }

    let removed = cricket_repo::delete_match(&state.pool, id).await?;
    Ok(Json(serde_json::json!({ "deleted": removed })))
}

/// Calling a match off is the club's decision, not the scorer's.
async fn require_match_manager(
    state: &AppState,
    row: &cricket_repo::CricketMatchRow,
    user_id: Uuid,
) -> ApiResult<()> {
    for club in [Some(row.club_id), row.opponent_club_id].into_iter().flatten() {
        if require_permission(state, club, user_id, None, Permission::ManageEvents)
            .await
            .is_ok()
        {
            return Ok(());
        }
    }
    Err(ApiError::forbidden(
        "only a captain or club secretary can call a match off",
    ))
}

#[derive(Deserialize)]
struct ProposeRequest {
    conditions: fishers_domain::MatchConditions,
    by: fishers_domain::MatchSide,
    by_name: String,
}

/// A captain puts terms on the table.
///
/// The same separate door as agreeing, for the same reason: going through the
/// scoring log meant only whoever held the book could propose, so a captain
/// opening the match on their own phone was shown a form they could not
/// submit.
async fn propose_terms(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<ProposeRequest>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;

    // You propose for your own side. Proposing counts as that side agreeing, so
    // letting a scorer propose "on behalf of" the opposition signed for a club
    // that had not seen the terms and left them nothing to accept. Recording
    // the other captain's agreement is a separate act — `agree_terms` — and
    // that one still allows it, because at a ground both captains are present.
    match club_side_for(&state, &row, auth.user_id).await {
        Some(mine) if mine != body.by => {
            return Err(ApiError::forbidden(
                "propose for your own side — the opposition is asked to accept",
            ));
        }
        // Somebody in neither club, an appointed neutral scorer, may propose
        // for whichever side asked them to.
        None if !sides_for(&state, &row, auth.user_id).await.contains(&body.by) => {
            return Err(ApiError::forbidden(
                "only this side's captain or the scorer can propose for them",
            ));
        }
        _ => {}
    }

    let name = body.by_name.trim();
    if name.is_empty() {
        return Err(ApiError::bad_request("put a name against the proposal"));
    }

    let projection = cricket_repo::parse_state(&row);
    let event = ScoringEvent {
        client_event_id: Uuid::new_v4(),
        seq: projection.last_seq + 1,
        kind: ScoringEventKind::ConditionsProposed {
            conditions: body.conditions,
            by: body.by,
            by_name: name.to_string(),
        },
        at: Some(chrono::Utc::now()),
    };
    let state_out =
        cricket_repo::apply_event_batch(&state.pool, id, &[event], auth.user_id, None)
            .await
            .map_err(|e| ApiError::conflict(e.to_string()))?;

    notify_opposition_of_terms(&state, &row, &state_out, auth.user_id).await;

    let refreshed = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;
    let can_score = may_score(&state, &refreshed, auth.user_id).await;
    let sides = sides_for(&state, &refreshed, auth.user_id).await;
    let mine = club_side_for(&state, &refreshed, auth.user_id).await;
    let when = fixture_time(&state, &refreshed).await;
    Ok(Json(to_response(&state, &refreshed, can_score, sides, mine, when)))
}

#[derive(Deserialize)]
struct AgreeRequest {
    side: fishers_domain::MatchSide,
    captain_name: String,
}

/// A captain accepts the terms on the table.
///
/// A separate door from the scoring log, for the same reason naming an XI is:
/// agreeing is not scoring. Going through `post_events` meant the visiting
/// captain needed scoring rights in the *home* club, which they will never
/// have, so the one thing they were being asked to do was the one thing they
/// could not.
async fn agree_terms(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<AgreeRequest>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;

    let owning_club = match body.side {
        fishers_domain::MatchSide::Home => Some(row.club_id),
        fishers_domain::MatchSide::Away => row.opponent_club_id,
    };
    // The scorer at the ground records both agreements on one device; a captain
    // on their own phone agrees for their own side only.
    let allowed = may_score(&state, &row, auth.user_id).await
        || may_manage_selection(&state, owning_club, auth.user_id).await;
    if !allowed {
        return Err(ApiError::forbidden(
            "only this side's captain or the scorer can agree these terms",
        ));
    }

    let name = body.captain_name.trim();
    if name.is_empty() {
        return Err(ApiError::bad_request("put a name against the agreement"));
    }

    let projection = cricket_repo::parse_state(&row);
    let event = ScoringEvent {
        client_event_id: Uuid::new_v4(),
        seq: projection.last_seq + 1,
        kind: ScoringEventKind::ConditionsAgreed {
            side: body.side,
            captain_name: name.to_string(),
        },
        at: Some(chrono::Utc::now()),
    };
    cricket_repo::apply_event_batch(&state.pool, id, &[event], auth.user_id, None)
        .await
        .map_err(|e| ApiError::conflict(e.to_string()))?;

    let refreshed = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;

    // Both in: whoever is holding the book can get on with the toss.
    let settled = cricket_repo::parse_state(&refreshed);
    if settled.agreed_home.is_some() && settled.agreed_away.is_some() {
        if let Some(scorer) = refreshed.active_scorer_user_id {
            if scorer != auth.user_id {
                let payload = match_payload(&state, &refreshed, &settled).await;
                state
                    .notify(
                        scorer,
                        "match_terms_agreed",
                        &format!("{} v {}", settled.home_name, settled.away_name),
                        "Both captains have agreed. You can do the toss.",
                        payload,
                    )
                    .await;
            }
        }
    }

    let can_score = may_score(&state, &refreshed, auth.user_id).await;
    let sides = sides_for(&state, &refreshed, auth.user_id).await;
    let mine = club_side_for(&state, &refreshed, auth.user_id).await;
    let when = fixture_time(&state, &refreshed).await;
    Ok(Json(to_response(&state, &refreshed, can_score, sides, mine, when)))
}

async fn submit_xi(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<XiRequest>,
) -> ApiResult<Json<MatchResponse>> {
    let row = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;

    let owning_club = match body.side {
        fishers_domain::MatchSide::Home => Some(row.club_id),
        fishers_domain::MatchSide::Away => row.opponent_club_id,
    };
    let allowed = may_score(&state, &row, auth.user_id).await
        || may_manage_selection(&state, owning_club, auth.user_id).await;
    if !allowed {
        return Err(ApiError::forbidden(
            "only this side's captain or the scorer can name this team sheet",
        ));
    }

    let projection = cricket_repo::parse_state(&row);
    let event = ScoringEvent {
        client_event_id: Uuid::new_v4(),
        seq: projection.last_seq + 1,
        kind: ScoringEventKind::XiSelected {
            side: body.side,
            players: body.players,
            captain_id: body.captain_id,
            keeper_id: body.keeper_id,
        },
        at: Some(chrono::Utc::now()),
    };
    let state_out =
        cricket_repo::apply_event_batch(&state.pool, id, &[event], auth.user_id, None)
            .await
            .map_err(|e| ApiError::conflict(e.to_string()))?;

    let refreshed = cricket_repo::get_match(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("match not found"))?;

    // One side named: the other has a job to do, and nothing else would tell
    // them. The match cannot start until both are in.
    let waiting = body.side.opposite();
    if state_out.xi(waiting).is_empty() {
        notify_side_to_pick(&state, &refreshed, &state_out, waiting, auth.user_id).await;
    }

    let can_score = may_score(&state, &refreshed, auth.user_id).await;
    let sides = sides_for(&state, &refreshed, auth.user_id).await;
    let mine = club_side_for(&state, &refreshed, auth.user_id).await;
    let when = fixture_time(&state, &refreshed).await;
    Ok(Json(to_response(&state, &refreshed, can_score, sides, mine, when)))
}
