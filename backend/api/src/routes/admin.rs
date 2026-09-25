//! The whole system, for whoever runs it.
//!
//! Gated by `require_platform_admin`, which reads `PLATFORM_ADMIN_EMAILS` and
//! insists the address is verified. Refusal is a 404, not a 403: a 403 tells
//! somebody probing that the panel exists and that this account is not on the
//! list. Neither fact is worth anything to a person who should not be here.
//!
//! One brand's deployment is one system. Each has its own database, so there
//! is nothing here that could show another brand's users even by mistake.

use axum::extract::{Path, Query, State};
use axum::routing::get;
use axum::{Json, Router};
use fishers_db::repos::admin as admin_repo;
use fishers_domain::{AdminOverview, AdminUser};
use serde::Deserialize;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::require_platform_admin;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/admin/overview", get(overview))
        .route("/admin/users", get(users))
        .route("/admin/users/{id}", get(user))
}

async fn overview(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<AdminOverview>> {
    require_platform_admin(&state, auth.user_id).await?;
    Ok(Json(admin_repo::overview(&state.pool).await?))
}

#[derive(Debug, Deserialize)]
struct Search {
    q: Option<String>,
}

/// Find somebody who has written in.
///
/// Two characters minimum: a one-character search matches most of the table
/// and is never what anybody meant.
async fn users(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(search): Query<Search>,
) -> ApiResult<Json<Vec<AdminUser>>> {
    require_platform_admin(&state, auth.user_id).await?;
    let query = search.q.unwrap_or_default();
    let query = query.trim();
    if query.chars().count() < 2 {
        return Err(ApiError::bad_request(
            "search for at least two characters — a name, an email or a number",
        ));
    }
    Ok(Json(admin_repo::find_users(&state.pool, query, 50).await?))
}

async fn user(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<AdminUser>> {
    require_platform_admin(&state, auth.user_id).await?;
    admin_repo::find_user(&state.pool, id)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("no such person"))
}
