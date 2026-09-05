use axum::extract::{Path, Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::stats as stats_repo;
use fishers_domain::{AchievementDef, ClubSeasonBoard, MeStatsResponse, PlayerSeasonStatsView};
use serde::Deserialize;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_club_member, require_secretary};
use crate::services::play_cricket;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/stats", get(me_stats))
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
    // Members can view teammates' season boards; self always allowed.
    if id != auth.user_id {
        // Soft gate: must share at least one club.
        let my_clubs = fishers_db::repos::clubs::list_clubs_for_user(&state.pool, auth.user_id).await?;
        let their = fishers_db::repos::clubs::list_clubs_for_user(&state.pool, id).await?;
        let overlap = my_clubs.iter().any(|c| their.iter().any(|t| t.id == c.id));
        if !overlap {
            return Err(ApiError::forbidden("not in a shared club"));
        }
    }
    Ok(Json(
        stats_repo::player_season_views(&state.pool, id, q.season).await?,
    ))
}

async fn user_achievements(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<fishers_domain::UserAchievementView>>> {
    if id != auth.user_id {
        let my_clubs = fishers_db::repos::clubs::list_clubs_for_user(&state.pool, auth.user_id).await?;
        let their = fishers_db::repos::clubs::list_clubs_for_user(&state.pool, id).await?;
        let overlap = my_clubs.iter().any(|c| their.iter().any(|t| t.id == c.id));
        if !overlap {
            return Err(ApiError::forbidden("not in a shared club"));
        }
    }
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
