use axum::extract::State;
use axum::routing::post;
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::json;

use crate::auth::AuthUser;
use crate::error::ApiResult;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route("/notifications/register-device", post(register_device))
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
