mod auth;
mod docs;
mod error;
mod live;
mod rbac;
mod routes;
mod services;
mod state;

use std::net::SocketAddr;

use anyhow::Context;
use axum::http::{HeaderValue, Method};
use axum::Router;
use rand::Rng;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::timeout::TimeoutLayer;
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
        .unwrap_or_else(|_| "postgres://fishers:fishers@localhost:7313/fishers".into());
    let jwt_secret = resolve_jwt_secret();
    let host = std::env::var("API_HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port: u16 = std::env::var("API_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(7312);

    let pool = fishers_db::connect(&database_url).await?;
    fishers_db::migrate(&pool).await?;

    let push = fishers_notifications::PushService::from_env();
    let email = fishers_notifications::EmailService::from_env();
    fishers_jobs::spawn_scheduler(pool.clone(), push.clone(), email);

    let state = AppState::new(pool, jwt_secret, push);

    // A layer wraps only the routes already added when it is applied, so the
    // live stream is merged after the timeout: 30 seconds is right for a
    // request and would cut every live connection half a minute in.
    let app = Router::new()
        .merge(docs::router())
        .merge(routes::router())
        // A scoring batch is the largest legitimate body; nothing needs a megabyte.
        .layer(RequestBodyLimitLayer::new(1024 * 1024))
        .layer(TimeoutLayer::with_status_code(
            axum::http::StatusCode::GATEWAY_TIMEOUT,
            std::time::Duration::from_secs(30),
        ))
        .merge(routes::live_router())
        .layer(cors_layer())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Named, because the bare AddrParseError says only "invalid socket address"
    // and never mentions which variable to go and look at.
    let addr: SocketAddr = format!("{host}:{port}")
        .parse()
        .with_context(|| format!("invalid API_HOST/API_PORT: {host}:{port}"))?;
    tracing::info!(%addr, "Fishers API listening");
    tracing::info!("Swagger UI http://{addr}/swagger-ui");
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .context("bind failed")?;
    axum::serve(listener, app).await.context("server failed")?;
    Ok(())
}

/// The signing key for every token this API issues.
///
/// There is no shipped default: a known constant in the binary is the same as
/// no authentication at all. Without `JWT_SECRET` we mint a random one, which
/// keeps `cargo run` working and logs every session out on restart — annoying
/// in development, harmless in production, and never a forgeable key.
fn resolve_jwt_secret() -> String {
    match std::env::var("JWT_SECRET") {
        Ok(secret) if secret.len() >= 32 => secret,
        Ok(secret) if !secret.is_empty() => {
            tracing::warn!(
                length = secret.len(),
                "JWT_SECRET is shorter than 32 characters — use a long random string"
            );
            secret
        }
        _ => {
            let random: String = (0..48)
                .map(|_| rand::thread_rng().sample(rand::distributions::Alphanumeric) as char)
                .collect();
            tracing::warn!(
                "JWT_SECRET is not set — generated a random one. \
                 Everyone will be signed out when this process restarts."
            );
            random
        }
    }
}

/// The iOS app does not use CORS at all, so nothing is allowed cross-origin
/// unless a web front end is named in `CORS_ALLOWED_ORIGINS`.
fn cors_layer() -> CorsLayer {
    let layer = CorsLayer::new()
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PATCH,
            Method::DELETE,
            Method::OPTIONS,
        ])
        .allow_headers([
            axum::http::header::AUTHORIZATION,
            axum::http::header::CONTENT_TYPE,
        ]);

    let configured: Vec<HeaderValue> = std::env::var("CORS_ALLOWED_ORIGINS")
        .unwrap_or_default()
        .split(',')
        .map(str::trim)
        .filter(|origin| !origin.is_empty())
        .filter_map(|origin| origin.parse().ok())
        .collect();

    if configured.is_empty() {
        tracing::info!("CORS_ALLOWED_ORIGINS unset — no cross-origin browser access");
        layer.allow_origin(AllowOrigin::list([]))
    } else {
        tracing::info!(count = configured.len(), "CORS origins allowed");
        layer.allow_origin(AllowOrigin::list(configured))
    }
}
