mod auth;
mod error;
mod rbac;
mod routes;
mod state;

use std::net::SocketAddr;

use anyhow::Context;
use axum::Router;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

use crate::state::AppState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("fishers_api=debug".parse()?))
        .init();

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://fishers:fishers@localhost:5433/fishers".into());
    let jwt_secret = std::env::var("JWT_SECRET")
        .unwrap_or_else(|_| "dev-only-change-me-fishers-jwt-secret".into());
    let host = std::env::var("API_HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port: u16 = std::env::var("API_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);

    let pool = fishers_db::connect(&database_url).await?;
    fishers_db::migrate(&pool).await?;

    let push = fishers_notifications::PushService::from_env();
    fishers_jobs::spawn_scheduler(pool.clone(), push.clone());

    let state = AppState::new(pool, jwt_secret, push);

    let app = Router::new()
        .merge(routes::router())
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr: SocketAddr = format!("{host}:{port}").parse()?;
    tracing::info!(%addr, "Fishers API listening");
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .context("bind failed")?;
    axum::serve(listener, app).await.context("server failed")?;
    Ok(())
}
