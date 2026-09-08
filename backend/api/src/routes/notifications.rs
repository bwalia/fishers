use axum::extract::State;
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::notifications as notifications_repo;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::ApiResult;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/notifications/register-device", post(register_device))
        .route("/notifications", get(list))
        .route("/notifications/read", post(mark_read))
}

/// What is waiting for you, newest first, with the unread count the bell shows.
async fn list(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<serde_json::Value>> {
    let items = notifications_repo::list_for(&state.pool, auth.user_id, 50).await?;
    let unread = notifications_repo::unread_count(&state.pool, auth.user_id).await?;
    Ok(Json(json!({ "unread": unread, "items": items })))
}

#[derive(Deserialize)]
struct MarkRead {
    /// One notification, or all of them when absent.
    id: Option<Uuid>,
}

async fn mark_read(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<MarkRead>,
) -> ApiResult<Json<serde_json::Value>> {
    let changed = notifications_repo::mark_read(&state.pool, auth.user_id, body.id).await?;
    Ok(Json(json!({ "marked": changed })))
}

#[derive(Deserialize)]
struct RegisterDevice {
    device_token: String,
    platform: Option<String>,
}

async fn register_device(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<RegisterDevice>,
) -> ApiResult<Json<serde_json::Value>> {
    let platform = body.platform.unwrap_or_else(|| "ios".into());
    sqlx::query(
        r#"
        INSERT INTO device_tokens (user_id, device_token, platform)
        VALUES ($1, $2, $3)
        ON CONFLICT (user_id, device_token) DO NOTHING
        "#,
    )
    .bind(auth.user_id)
    .bind(&body.device_token)
    .bind(&platform)
    .execute(&state.pool)
    .await?;
    Ok(Json(json!({ "registered": true })))
}
