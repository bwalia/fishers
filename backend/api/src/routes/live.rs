//! `GET /api/v1/stream`: one long-lived Server-Sent Events response per open
//! tab, carrying what changed for this person.
//!
//! SSE rather than a WebSocket: traffic here only flows server-to-browser (a
//! message is still sent with a POST), SSE is plain HTTP so it passes the
//! wslproxy edge and Traefik with no Upgrade handling, and the browser reads it
//! with fetch — which, unlike WebSocket and EventSource, can send the ordinary
//! Authorization header, so no token ever goes in a URL for the edge to log.
//!
//! Each event names what changed, never its content; the browser fetches that
//! through the normal endpoints, which do their own access checks.

use std::collections::HashSet;
use std::convert::Infallible;
use std::time::Duration;

use axum::extract::State;
use axum::http::header;
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;
use fishers_db::repos::chat as chat_repo;
use serde_json::json;
use tokio::sync::broadcast::error::RecvError;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::ApiResult;
use crate::live::LiveEvent;
use crate::state::AppState;

/// Mounted outside the 30-second request timeout, which would otherwise cut
/// every stream half a minute in.
pub fn router() -> Router<AppState> {
    Router::new().route("/api/v1/stream", get(stream))
}

async fn stream(State(state): State<AppState>, auth: AuthUser) -> ApiResult<impl IntoResponse> {
    let me = auth.user_id;
    let threads: HashSet<Uuid> = chat_repo::conversation_ids_for(&state.pool, me)
        .await?
        .into_iter()
        .collect();
    let rx = state.live.subscribe();

    // "ready" first, so a reconnecting browser knows to catch up on whatever
    // happened while it was away.
    let events = futures_util::stream::unfold(
        (rx, threads, true),
        move |(mut rx, mut threads, first)| async move {
            if first {
                return Some((
                    Ok::<_, Infallible>(event("ready", json!({}))),
                    (rx, threads, false),
                ));
            }
            loop {
                let out = match rx.recv().await {
                    Ok(LiveEvent::Message {
                        conversation_id,
                        id,
                    }) if threads.contains(&conversation_id) => event(
                        "message",
                        json!({ "conversation_id": conversation_id, "id": id }),
                    ),
                    Ok(LiveEvent::Notification { user_id }) if user_id == me => {
                        event("notification", json!({}))
                    }
                    Ok(LiveEvent::Member {
                        user_id,
                        conversation_id,
                        left,
                    }) if user_id == me => {
                        if left {
                            threads.remove(&conversation_id);
                        } else {
                            threads.insert(conversation_id);
                        }
                        event("conversations", json!({}))
                    }
                    Ok(LiveEvent::Resync) | Err(RecvError::Lagged(_)) => event("resync", json!({})),
                    Ok(_) => continue, // somebody else's
                    Err(RecvError::Closed) => return None,
                };
                return Some((Ok(out), (rx, threads, false)));
            }
        },
    );

    Ok((
        [
            // nginx (the wslproxy edge) buffers proxied responses by default,
            // which would hold every event until the buffer filled.
            (header::HeaderName::from_static("x-accel-buffering"), "no"),
            (header::CACHE_CONTROL, "no-cache"),
        ],
        // A comment every 20s keeps idle proxies (60s read timeouts are
        // common) from closing a quiet stream.
        Sse::new(events).keep_alive(KeepAlive::new().interval(Duration::from_secs(20))),
    ))
}

fn event(name: &str, data: serde_json::Value) -> Event {
    Event::default().event(name).data(data.to_string())
}
