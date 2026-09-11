//! Live streams: one long-lived Server-Sent Events response per open tab,
//! carrying what changed for whoever is watching.
//!
//!   GET /api/v1/stream                            signed in: your threads,
//!                                                 notifications and matches
//!   GET /api/v1/public/scoreboard/{token}/stream  a shared scoreboard link:
//!                                                 that one match, no sign-in
//!
//! SSE rather than a WebSocket: traffic here only flows server-to-browser (a
//! message or a ball is still sent with a POST), SSE is plain HTTP so it
//! passes the wslproxy edge and Traefik with no Upgrade handling, and the
//! browser reads it with fetch — which, unlike WebSocket and EventSource, can
//! send the ordinary Authorization header, so no token ever goes in a URL for
//! the edge to log.
//!
//! Each event names what changed, never its content; the browser fetches that
//! through the normal endpoints, which do their own access checks.

use std::collections::{HashMap, HashSet};
use std::convert::Infallible;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::http::header;
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;
use fishers_db::repos::chat as chat_repo;
use fishers_db::repos::scoreboard_shares as share_repo;
use serde_json::json;
use tokio::sync::broadcast::{self, error::RecvError};
use tokio::time::Instant;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::live::LiveEvent;
use crate::state::AppState;

/// A stream ends after this and the browser reconnects at once with a fresh
/// token. That re-checks who may see what — someone removed from a club stops
/// hearing about its matches within ten minutes — without re-checking on
/// every ball.
const LIFETIME: Duration = Duration::from_secs(600);

/// Mounted outside the 30-second request timeout, which would otherwise cut
/// every stream half a minute in.
pub fn router() -> Router<AppState> {
    Router::new().route("/api/v1/stream", get(stream)).route(
        "/api/v1/public/scoreboard/{token}/stream",
        get(public_scoreboard_stream),
    )
}

async fn stream(State(state): State<AppState>, auth: AuthUser) -> ApiResult<impl IntoResponse> {
    let threads = chat_repo::conversation_ids_for(&state.pool, auth.user_id)
        .await?
        .into_iter()
        .collect();
    let rx = state.live.subscribe();
    Ok(sse(Watcher::new(
        state,
        rx,
        Viewer::Member {
            id: auth.user_id,
            threads,
        },
    )))
}

/// For whoever holds a shared scoreboard link: the link's one match, nothing
/// else — the same scope as the page it belongs to.
async fn public_scoreboard_stream(
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> ApiResult<impl IntoResponse> {
    let token = super::scoreboard_share::clean_token(&token);
    let share = share_repo::find_valid_by_token(&state.pool, &token)
        .await?
        .ok_or_else(|| ApiError::not_found("scoreboard link invalid or expired"))?;
    let rx = state.live.subscribe();
    Ok(sse(Watcher::new(
        state,
        rx,
        Viewer::Link {
            match_id: share.match_id,
        },
    )))
}

enum Viewer {
    Member { id: Uuid, threads: HashSet<Uuid> },
    Link { match_id: Uuid },
}

struct Watcher {
    state: AppState,
    rx: broadcast::Receiver<LiveEvent>,
    viewer: Viewer,
    /// Whether each match seen so far may be watched, asked once per match.
    matches: HashMap<Uuid, bool>,
    deadline: Instant,
    started: bool,
}

impl Watcher {
    fn new(state: AppState, rx: broadcast::Receiver<LiveEvent>, viewer: Viewer) -> Self {
        Self {
            state,
            rx,
            viewer,
            matches: HashMap::new(),
            deadline: Instant::now() + LIFETIME,
            started: false,
        }
    }

    async fn next(&mut self) -> Option<Event> {
        // "ready" first, so a reconnecting browser knows to catch up on
        // whatever happened while it was away.
        if !self.started {
            self.started = true;
            return Some(event("ready", json!({})));
        }
        loop {
            let got = tokio::select! {
                got = self.rx.recv() => got,
                _ = tokio::time::sleep_until(self.deadline) => return None,
            };
            match got {
                Ok(e) => {
                    if let Some(out) = self.forward(e).await {
                        return Some(out);
                    }
                }
                Err(RecvError::Lagged(_)) => return Some(event("resync", json!({}))),
                Err(RecvError::Closed) => return None,
            }
        }
    }

    /// Only what this viewer may see; everything else is dropped silently.
    async fn forward(&mut self, e: LiveEvent) -> Option<Event> {
        match (e, &mut self.viewer) {
            (LiveEvent::Resync, _) => Some(event("resync", json!({}))),

            (LiveEvent::Match { id, seq }, Viewer::Link { match_id }) => {
                (id == *match_id).then(|| event("match", json!({ "id": id, "seq": seq })))
            }
            (LiveEvent::Match { id, seq }, Viewer::Member { id: me, .. }) => {
                let me = *me;
                let visible = match self.matches.get(&id) {
                    Some(v) => *v,
                    None => {
                        let v = super::cricket::may_watch(&self.state, id, me).await;
                        self.matches.insert(id, v);
                        v
                    }
                };
                visible.then(|| event("match", json!({ "id": id, "seq": seq })))
            }

            (
                LiveEvent::Message {
                    conversation_id,
                    id,
                },
                Viewer::Member { threads, .. },
            ) => threads.contains(&conversation_id).then(|| {
                event(
                    "message",
                    json!({ "conversation_id": conversation_id, "id": id }),
                )
            }),

            (LiveEvent::Notification { user_id }, Viewer::Member { id: me, .. }) => {
                (user_id == *me).then(|| event("notification", json!({})))
            }

            (
                LiveEvent::Member {
                    user_id,
                    conversation_id,
                    left,
                },
                Viewer::Member { id: me, threads },
            ) => {
                if user_id != *me {
                    return None;
                }
                if left {
                    threads.remove(&conversation_id);
                } else {
                    threads.insert(conversation_id);
                }
                Some(event("conversations", json!({})))
            }

            // A scoreboard link hears about its match and nothing else.
            (_, Viewer::Link { .. }) => None,
        }
    }
}

fn sse(watcher: Watcher) -> impl IntoResponse {
    let events = futures_util::stream::unfold(watcher, |mut w| async move {
        w.next().await.map(|e| (Ok::<_, Infallible>(e), w))
    });
    (
        [
            // nginx (the wslproxy edge) buffers proxied responses by default,
            // which would hold every event until the buffer filled.
            (header::HeaderName::from_static("x-accel-buffering"), "no"),
            (header::CACHE_CONTROL, "no-cache"),
        ],
        // A comment every 20s keeps idle proxies (60s read timeouts are
        // common) from closing a quiet stream.
        Sse::new(events).keep_alive(KeepAlive::new().interval(Duration::from_secs(20))),
    )
}

fn event(name: &str, data: serde_json::Value) -> Event {
    Event::default().event(name).data(data.to_string())
}
