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
mod selection;
mod stats;
mod tournament;
mod users;

use axum::routing::get;
use axum::Router;

use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/health", get(|| async { "ok" }))
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
        .merge(stats::router())
        .merge(orders::router())
        .merge(notifications::router())
}
