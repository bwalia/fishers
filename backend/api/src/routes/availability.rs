use axum::extract::{Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::{availability as avail_repo, clubs as clubs_repo};
use fishers_domain::{
    Availability, AvailabilityQuery, BulkAvailabilityRequest, UpsertAvailabilityRequest,
};
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/availability",
            get(list_availability).post(upsert_availability),
        )
        .route("/availability/bulk", post(bulk_availability))
}

/// Your own calendar, or a club-mate's — a captain picking a side needs to see
/// who is free. Anyone outside your clubs is none of your business.
async fn list_availability(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<AvailabilityQuery>,
) -> ApiResult<Json<Vec<Availability>>> {
    let user_id = q.user_id.unwrap_or(auth.user_id);
    if user_id != auth.user_id
        && !clubs_repo::shares_a_club(&state.pool, auth.user_id, user_id).await?
    {
        return Err(ApiError::forbidden(
            "you can only see the availability of people in your clubs",
        ));
    }
    if q.to < q.from {
        return Err(ApiError::bad_request("`to` must not be before `from`"));
    }
    if (q.to - q.from).num_days() > 400 {
        return Err(ApiError::bad_request("ask for at most a year at a time"));
    }
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
    if body.dates.len() > 366 {
        return Err(ApiError::bad_request("at most a year of dates at a time"));
    }
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
