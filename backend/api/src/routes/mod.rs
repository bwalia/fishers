mod auth;
mod availability;
mod chat;
mod clubs;
mod cricket;
mod events;
mod invites;
mod notifications;
mod orders;
mod payments;
mod scoreboard_share;
mod selection;
mod stats;
mod tournament;
mod users;

use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};
use serde_json::json;

use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/health/ready", get(ready))
        .nest("/api/v1", api_v1())
}

fn api_v1() -> Router<AppState> {
    Router::new()
        .merge(auth::router())
        .merge(users::router())
        .merge(clubs::router())
        .merge(events::router())
        .merge(availability::router())
        .merge(chat::router())
        .merge(invites::router())
        .merge(payments::router())
        .merge(selection::router())
        .merge(tournament::router())
        .merge(cricket::router())
        .merge(scoreboard_share::router())
        .merge(stats::router())
        .merge(orders::router())
        .merge(notifications::router())
}

/// Liveness says the process answers; readiness says it can serve a request.
///
/// `/health` is a constant, so it keeps returning "ok" after Postgres goes away
/// underneath a running API — every real endpoint then hangs on the pool while
/// the health check insists all is well. Startup scripts wait on this instead.
async fn ready(
    axum::extract::State(state): axum::extract::State<AppState>,
) -> (StatusCode, Json<serde_json::Value>) {
    match sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&state.pool)
        .await
    {
        Ok(_) => (StatusCode::OK, Json(json!({ "status": "ready" }))),
        Err(e) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({ "status": "degraded", "database": e.to_string() })),
        ),
    }
}
