use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::stats as stats_repo;
use fishers_domain::{AchievementDef, ClubSeasonBoard, MeStatsResponse, PlayerSeasonStatsView};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_club_member, require_secretary};
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
    let season = q.season.unwrap_or(2026);
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
