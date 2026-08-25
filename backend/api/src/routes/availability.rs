use axum::extract::{Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::availability as avail_repo;
use fishers_domain::{
    Availability, AvailabilityQuery, BulkAvailabilityRequest, UpsertAvailabilityRequest,
};
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::ApiResult;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/availability",
            get(list_availability).post(upsert_availability),
        )
        .route("/availability/bulk", post(bulk_availability))
}

async fn list_availability(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<AvailabilityQuery>,
) -> ApiResult<Json<Vec<Availability>>> {
    let user_id = q.user_id.unwrap_or(auth.user_id);
    Ok(Json(
        avail_repo::list_range(&state.pool, user_id, q.from, q.to).await?,
    ))
}

async fn upsert_availability(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<UpsertAvailabilityRequest>,
) -> ApiResult<Json<Availability>> {
    body.validate()?;
    Ok(Json(
        avail_repo::upsert(&state.pool, auth.user_id, &body).await?,
    ))
}

async fn bulk_availability(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<BulkAvailabilityRequest>,
) -> ApiResult<Json<Vec<Availability>>> {
    body.validate()?;
    Ok(Json(
        avail_repo::bulk_set(
            &state.pool,
            auth.user_id,
            &body.dates,
            body.status,
            body.note.as_deref(),
        )
        .await?,
    ))
}
