//! Reporting something, and blocking somebody.
//!
//! Both are a condition of shipping an app that carries other people's words
//! and pictures: somebody has to be able to say "this is wrong", and somebody
//! has to be able to stop another person reaching them without waiting for us
//! to agree. The block takes effect immediately; the report is a queue.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::moderation as moderation_repo;
use fishers_domain::{
    BlockedUser, ContentReport, CreateReportRequest, ReportVerdict,
};
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::require_platform_admin;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/blocks", get(list_blocks).post(add_block))
        .route("/me/blocks/{user_id}", axum::routing::delete(remove_block))
        .route("/reports", post(file_report))
        .route("/admin/reports", get(open_reports))
        .route("/admin/reports/{id}/resolve", post(resolve))
}

#[derive(Deserialize)]
struct BlockRequest {
    user_id: Uuid,
}

async fn list_blocks(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<Vec<BlockedUser>>> {
    let blocked = moderation_repo::list_blocks(&state.pool, auth.user_id).await?;
    Ok(Json(blocked))
}

async fn add_block(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<BlockRequest>,
) -> ApiResult<StatusCode> {
    if req.user_id == auth.user_id {
        return Err(ApiError::bad_request("You cannot block yourself."));
    }
    moderation_repo::block(&state.pool, auth.user_id, req.user_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn remove_block(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(user_id): Path<Uuid>,
) -> ApiResult<StatusCode> {
    moderation_repo::unblock(&state.pool, auth.user_id, user_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn file_report(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateReportRequest>,
) -> ApiResult<Json<ContentReport>> {
    req.validate()?;
    let report = moderation_repo::create_report(&state.pool, auth.user_id, &req).await?;
    Ok(Json(report))
}

async fn open_reports(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<Vec<ContentReport>>> {
    require_platform_admin(&state, auth.user_id).await?;
    let reports = moderation_repo::list_open_reports(&state.pool, 100).await?;
    Ok(Json(reports))
}

#[derive(Deserialize)]
struct Resolution {
    verdict: ReportVerdict,
}

async fn resolve(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<Resolution>,
) -> ApiResult<Json<ContentReport>> {
    require_platform_admin(&state, auth.user_id).await?;
    moderation_repo::resolve_report(&state.pool, id, auth.user_id, body.verdict)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("That report has already been dealt with."))
}
