use axum::extract::{Query, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::notifications as notifications_repo;
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/notifications/register-device", post(register_device))
        .route("/notifications/unregister-device", post(unregister_device))
        .route("/notifications/web-push-key", get(web_push_key))
        .route("/notifications", get(list))
        .route("/notifications/read", post(mark_read))
}

#[derive(Debug, Deserialize)]
struct ListQuery {
    /// One `notifications_log.type`.
    kind: Option<String>,
    #[serde(default)]
    unread: bool,
    /// Matched against the payload's title and body.
    q: Option<String>,
    page: Option<i64>,
    per_page: Option<i64>,
}

/// What is waiting for you — newest first, filtered, counted and paged.
///
/// The bell asks for a handful; the notifications page asks for a page at a
/// time with whatever filter is set. Both go through here, because two
/// endpoints returning "your notifications" is how a bell badge and a list end
/// up disagreeing.
async fn list(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(q): Query<ListQuery>,
) -> ApiResult<Json<notifications_repo::NotificationPage>> {
    if let Some(term) = q.q.as_deref() {
        // One character matches most of the table and reads as a hang.
        if term.trim().chars().count() < 2 {
            return Err(ApiError::bad_request("search for at least two characters"));
        }
    }
    let filter = notifications_repo::NotificationFilter {
        kind: q.kind.filter(|k| !k.is_empty()),
        unread_only: q.unread,
        search: q.q.map(|s| s.trim().to_string()).filter(|s| !s.is_empty()),
        page: q.page.unwrap_or(1),
        per_page: q.per_page.unwrap_or(20),
    };
    if filter.page < 1 {
        return Err(ApiError::bad_request("page starts at 1"));
    }
    if filter.per_page < 1 || filter.per_page > 100 {
        return Err(ApiError::bad_request("per_page is between 1 and 100"));
    }
    Ok(Json(
        notifications_repo::page_for(&state.pool, auth.user_id, &filter).await?,
    ))
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

/// The public half of the VAPID pair, and whether push is configured at all.
///
/// A browser needs this before it can subscribe — it is a *public* key, so
/// this needs no auth. When push is not configured the app simply never
/// offers it, rather than asking for permission it cannot then use.
async fn web_push_key(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(json!({
        "enabled": state.push.web.is_configured(),
        "public_key": state.push.web.public_key,
    }))
}

#[derive(Deserialize)]
struct RegisterDevice {
    device_token: String,
    platform: Option<String>,
}

#[derive(Deserialize)]
struct UnregisterDevice {
    device_token: String,
}

/// Turning push off on this browser or phone.
///
/// Scoped to the caller: a token can only ever be removed by the account it
/// belongs to, so knowing somebody else's endpoint buys nothing.
async fn unregister_device(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<UnregisterDevice>,
) -> ApiResult<Json<serde_json::Value>> {
    let done = sqlx::query(
        "DELETE FROM device_tokens WHERE user_id = $1 AND device_token = $2",
    )
    .bind(auth.user_id)
    .bind(&body.device_token)
    .execute(&state.pool)
    .await?;
    Ok(Json(json!({ "removed": done.rows_affected() })))
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
        ON CONFLICT (user_id, device_token) DO UPDATE SET platform = EXCLUDED.platform
        "#,
    )
    .bind(auth.user_id)
    .bind(&body.device_token)
    .bind(&platform)
    .execute(&state.pool)
    .await?;
    Ok(Json(json!({ "registered": true })))
}
