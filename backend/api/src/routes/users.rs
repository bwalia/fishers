use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use fishers_db::repos::users as users_repo;
use fishers_domain::{PublicUser, UpdateProfileRequest};
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me", get(me).patch(update_me))
}

async fn me(State(state): State<AppState>, auth: AuthUser) -> ApiResult<Json<PublicUser>> {
    let user = users_repo::find_by_id(&state.pool, auth.user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("user not found"))?;
    Ok(Json(user.into()))
}

async fn update_me(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<UpdateProfileRequest>,
) -> ApiResult<Json<PublicUser>> {
    body.validate()?;
    let user = users_repo::update_profile(&state.pool, auth.user_id, &body).await?;
    Ok(Json(user.into()))
}
