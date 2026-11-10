use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::stats as stats_repo;
use fishers_domain::{AchievementDef, ClubSeasonBoard, MeStatsResponse, PlayerSeasonStatsView};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_club_member, require_club_permission, require_secretary};
use fishers_domain::Permission;
use crate::services::play_cricket;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/stats", get(me_stats))
        .route("/users/{id}", get(teammate))
        .route("/users/{id}/stats", get(user_stats))
        .route("/users/{id}/achievements", get(user_achievements))
        .route("/clubs/{id}/stats", get(club_stats))
        .route("/clubs/{id}/stats/sync", post(sync_club_stats))
        .route("/achievements", get(list_achievements))
        .route("/me/game", get(my_game))
        .route("/users/{id}/game", get(their_game))
        .route("/clubs/{id}/season", get(club_season))
        .route(
            "/clubs/{id}/seasons/{year}/close",
            get(close_preview).post(close_season),
        )
        .route("/email/season/off", post(season_emails_off))
        .route("/email/season/on", post(season_emails_on))
}

/// A year somebody could actually be closing.
/// A season that can be closed: plausible, and already started.
fn closable_season(year: i32) -> ApiResult<i32> {
    let year = plausible_season(year)?;
    if fishers_domain::season::can_close_season(year, chrono::Utc::now()) {
        Ok(year)
    } else {
        Err(ApiError::bad_request(format!("the {year} season hasn't started yet")))
    }
}

fn plausible_season(year: i32) -> ApiResult<i32> {
    let now = fishers_domain::season::season_of(chrono::Utc::now());
    if (2000..=now + 1).contains(&year) {
        Ok(year)
    } else {
        Err(ApiError::bad_request("that is not a season this club could have played"))
    }
}

/// Who closing the season would email — shown before the secretary confirms,
/// because it cannot be taken back.
async fn close_preview(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((id, year)): Path<(Uuid, i32)>,
) -> ApiResult<Json<fishers_domain::season::ClosePreview>> {
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;
    let year = closable_season(year)?;
    let mut preview = fishers_db::repos::season::close_preview(&state.pool, id, year).await?;
    // With no mail server, "33 emails on their way" would be untrue: nobody
    // gets one until mail is switched on. The in-app notice still goes.
    preview.email_on = state.email.enabled();
    if !preview.email_on {
        preview.will_email = 0;
    }
    Ok(Json(preview))
}

#[derive(Debug, Serialize)]
struct Closed {
    season: i32,
    /// Emails that will go — an address on file, not opted out — over the
    /// next few minutes. Zero while this server cannot send mail.
    queued: i64,
    /// False when this server cannot send mail: the emails wait until it can.
    email_on: bool,
}

/// Close the season: every active member gets their season by email. Once a
/// year; a second close is a 409 and emails nobody.
async fn close_season(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((id, year)): Path<(Uuid, i32)>,
) -> ApiResult<Json<Closed>> {
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;
    let year = closable_season(year)?;
    match fishers_db::repos::season::close_season(&state.pool, id, year, auth.user_id).await? {
        Some(queued) => {
            let email_on = state.email.enabled();
            Ok(Json(Closed { season: year, queued: if email_on { queued } else { 0 }, email_on }))
        }
        None => Err(ApiError::conflict("this season is already closed")),
    }
}

#[derive(Debug, Deserialize)]
struct PrefsToken {
    token: String,
}

/// From the link in a season email, signed in or not: the token is the
/// whole of the permission, and all it can do is this.
async fn season_emails_off(
    State(state): State<AppState>,
    Json(body): Json<PrefsToken>,
) -> ApiResult<Json<serde_json::Value>> {
    set_season_emails(&state, &body.token, true).await
}

async fn season_emails_on(
    State(state): State<AppState>,
    Json(body): Json<PrefsToken>,
) -> ApiResult<Json<serde_json::Value>> {
    set_season_emails(&state, &body.token, false).await
}

async fn set_season_emails(state: &AppState, token: &str, off: bool) -> ApiResult<Json<serde_json::Value>> {
    if token.len() < 32 || !fishers_db::repos::season::set_season_emails_off(&state.pool, token, off).await? {
        return Err(ApiError::not_found("that link is not recognised"));
    }
    Ok(Json(serde_json::json!({ "season_emails_off": off })))
}

#[derive(Debug, Deserialize)]
struct GameQuery {
    season: Option<i32>,
    /// Which club to rank them in. Defaults to the one they played most for.
    club_id: Option<Uuid>,
}

/// "My game": the season, its form, bests, milestones and the good news in it.
async fn my_game(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<GameQuery>,
) -> ApiResult<Json<fishers_domain::season::PlayerGame>> {
    fishers_db::repos::season::player_game(&state.pool, auth.user_id, q.season, q.club_id)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("no such player"))
}

/// A club-mate's game, on the same terms as their season stats.
async fn their_game(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Query(q): Query<GameQuery>,
) -> ApiResult<Json<fishers_domain::season::PlayerGame>> {
    shared_clubs(&state, auth.user_id, id).await?;
    fishers_db::repos::season::player_game(&state.pool, id, q.season, q.club_id)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("no such player"))
}

/// The club's season from its players' match lines: the record and the boards.
async fn club_season(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Query(q): Query<SeasonQuery>,
) -> ApiResult<Json<fishers_domain::season::ClubSeason>> {
    require_club_member(&state, id, auth.user_id).await?;
    fishers_db::repos::season::club_season(&state.pool, id, q.season)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("no such club"))
}

#[derive(Debug, Deserialize)]
struct SeasonQuery {
    season: Option<i32>,
}

/// Another player, as their club-mates may see them.
///
/// Deliberately not `PublicUser`: that carries an email address, a phone
/// number, an emergency contact and a home location. Being in the same club as
/// somebody is not consent to hand their mobile number to anyone who can guess
/// a uuid. This is what goes on a team sheet — a name, a face, what they play.
#[derive(Debug, Serialize)]
struct TeammateProfile {
    id: Uuid,
    name: String,
    avatar_url: Option<String>,
    position_role: Option<String>,
    skill_level: Option<String>,
    primary_sport: Option<String>,
    sport_profiles: Vec<fishers_domain::SportProfile>,
    reliability: Option<fishers_domain::ReliabilityScore>,
    /// Clubs you and they are both in — the reason you can see this at all,
    /// and the useful thing to know about a name you do not recognise.
    shared_clubs: Vec<String>,
}

/// Both clubs' rosters, and what they have in common.
///
/// The gate on every one of these endpoints: you may look at somebody you play
/// with, and nobody else. Extracted because three handlers had the same eight
/// lines and a fourth was about to.
async fn shared_clubs(
    state: &AppState,
    me: Uuid,
    them: Uuid,
) -> ApiResult<Vec<String>> {
    if me == them {
        return Ok(Vec::new());
    }
    let mine = fishers_db::repos::clubs::list_clubs_for_user(&state.pool, me).await?;
    let theirs = fishers_db::repos::clubs::list_clubs_for_user(&state.pool, them).await?;
    let shared: Vec<String> = mine
        .iter()
        .filter(|c| theirs.iter().any(|t| t.club.id == c.club.id))
        .map(|c| c.club.name.clone())
        .collect();
    if shared.is_empty() {
        return Err(ApiError::forbidden("not in a shared club"));
    }
    Ok(shared)
}

async fn teammate(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<TeammateProfile>> {
    let shared = shared_clubs(&state, auth.user_id, id).await?;
    let user = fishers_db::repos::users::find_by_id(&state.pool, id)
        .await?
        .ok_or_else(|| ApiError::not_found("no such player"))?;
    let public: fishers_domain::PublicUser = user.into();
    Ok(Json(TeammateProfile {
        id: public.id,
        name: public.name,
        avatar_url: public.avatar_url,
        position_role: public.position_role,
        skill_level: public.skill_level,
        primary_sport: public.primary_sport,
        sport_profiles: public.sport_profiles,
        reliability: public.reliability,
        shared_clubs: shared,
    }))
}

async fn me_stats(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<SeasonQuery>,
) -> ApiResult<Json<MeStatsResponse>> {
    Ok(Json(
        stats_repo::me_stats(&state.pool, auth.user_id, q.season).await?,
    ))
}

async fn user_stats(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Query(q): Query<SeasonQuery>,
) -> ApiResult<Json<Vec<PlayerSeasonStatsView>>> {
    // Club-mates may read each other's season boards; self always allowed.
    shared_clubs(&state, auth.user_id, id).await?;
    Ok(Json(
        stats_repo::player_season_views(&state.pool, id, q.season).await?,
    ))
}

async fn user_achievements(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<fishers_domain::UserAchievementView>>> {
    shared_clubs(&state, auth.user_id, id).await?;
    Ok(Json(
        stats_repo::achievements_for_user(&state.pool, id).await?,
    ))
}

async fn club_stats(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Query(q): Query<SeasonQuery>,
) -> ApiResult<Json<ClubSeasonBoard>> {
    require_club_member(&state, id, auth.user_id).await?;
    let season = q
        .season
        .unwrap_or_else(|| fishers_domain::season::season_of(chrono::Utc::now()));
    let board = stats_repo::club_board(&state.pool, id, season)
        .await?
        .ok_or_else(|| ApiError::not_found("no season stats for this club"))?;
    Ok(Json(board))
}

async fn sync_club_stats(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<play_cricket::SyncResult>> {
    require_secretary(&state, id, auth.user_id).await?;
    let result = play_cricket::sync_club(&state.pool, id)
        .await
        .map_err(ApiError::bad_request)?;
    Ok(Json(result))
}

async fn list_achievements(
    State(state): State<AppState>,
    _auth: AuthUser,
) -> ApiResult<Json<Vec<AchievementDef>>> {
    Ok(Json(stats_repo::list_achievement_defs(&state.pool).await?))
}
