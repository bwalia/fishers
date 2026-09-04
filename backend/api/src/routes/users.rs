use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use fishers_db::repos::users as users_repo;
use fishers_domain::{reliability, PublicUser, UpdateProfileRequest};
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
    Ok(Json(with_reliability(&state, user).await?))
}

async fn update_me(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<UpdateProfileRequest>,
) -> ApiResult<Json<PublicUser>> {
    body.validate()?;
    let user = users_repo::update_profile(&state.pool, auth.user_id, &body).await?;
    Ok(Json(with_reliability(&state, user).await?))
}

/// Reliability is earned, not submitted: it is computed from attendance and
/// payment history on every read rather than stored on the user.
async fn with_reliability(
    state: &AppState,
    user: fishers_domain::User,
) -> Result<PublicUser, ApiError> {
    let counts = users_repo::reliability_counts(&state.pool, user.id).await?;
    Ok(PublicUser::from(user).with_reliability(reliability::score(counts)))
}
