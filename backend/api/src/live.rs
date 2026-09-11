//! Live updates: Postgres NOTIFY in, one broadcast channel out.
//!
//! The database announces every new message, notification and membership
//! change on `fishers_live` (see the live_events migration). This task holds one
//! LISTEN connection per API replica and rebroadcasts each event in-process;
//! every connected browser's stream subscribes and keeps only what that person
//! may see. Postgres rather than an in-memory channel alone because acc and
//! prod run more than one API replica: a message posted through one has to
//! reach people connected to the other.

use std::time::Duration;

use serde::Deserialize;
use sqlx::postgres::PgListener;
use sqlx::PgPool;
use tokio::sync::broadcast;
use tracing::{info, warn};
use uuid::Uuid;

const CHANNEL: &str = "fishers_live";

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum LiveEvent {
    Message {
        conversation_id: Uuid,
        id: Uuid,
    },
    Notification {
        user_id: Uuid,
    },
    Member {
        user_id: Uuid,
        conversation_id: Uuid,
        #[serde(default)]
        left: bool,
    },
    /// Anything about a match changed. `seq` is its event-log position, so a
    /// browser already showing that ball can skip the refetch.
    Match {
        id: Uuid,
        #[serde(default)]
        seq: i64,
    },
    /// Events may have been missed — the LISTEN connection dropped, or a slow
    /// browser fell behind the channel. Clients answer with a full reload.
    #[serde(skip)]
    Resync,
}

#[derive(Clone)]
pub struct Live {
    tx: broadcast::Sender<LiveEvent>,
}

impl Live {
    /// Starts the listener. It reconnects on its own for as long as the process
    /// lives, so a Postgres restart costs a resync, not a dead feature.
    pub fn spawn(pool: PgPool) -> Self {
        // Room for a burst: a busy thread plus everyone's notifications. A
        // browser that falls further behind than this gets a Resync.
        let (tx, _) = broadcast::channel(1024);
        tokio::spawn(listen(pool, tx.clone()));
        Self { tx }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<LiveEvent> {
        self.tx.subscribe()
    }
}

async fn listen(pool: PgPool, tx: broadcast::Sender<LiveEvent>) {
    loop {
        let mut listener = match PgListener::connect_with(&pool).await {
            Ok(l) => l,
            Err(e) => {
                warn!(error = %e, "live: could not connect the listener; retrying");
                tokio::time::sleep(Duration::from_secs(2)).await;
                continue;
            }
        };
        if let Err(e) = listener.listen(CHANNEL).await {
            warn!(error = %e, "live: LISTEN failed; retrying");
            tokio::time::sleep(Duration::from_secs(2)).await;
            continue;
        }
        info!("live: listening on {CHANNEL}");
        // Whatever happened while we were not listening is gone; tell the
        // browsers to fetch, rather than let them sit on a stale screen.
        let _ = tx.send(LiveEvent::Resync);

        loop {
            match listener.recv().await {
                Ok(n) => match serde_json::from_str::<LiveEvent>(n.payload()) {
                    // No receivers is normal — nobody has the app open.
                    Ok(event) => {
                        let _ = tx.send(event);
                    }
                    Err(e) => warn!(error = %e, payload = n.payload(), "live: unreadable event"),
                },
                Err(e) => {
                    warn!(error = %e, "live: listener dropped; reconnecting");
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    break;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::LiveEvent;

    /// The payloads are built in SQL (json_build_object in the migration); if
    /// the two ever disagree, every event is dropped as unreadable. These are
    /// the exact shapes the trigger produces.
    #[test]
    fn the_trigger_payloads_parse() {
        let m: LiveEvent = serde_json::from_str(
            r#"{"kind" : "message", "conversation_id" : "d439bcac-7ec8-4102-9048-6c449180dfac", "id" : "0f8b9d3e-7c1a-4a55-9f7a-3b2c1d0e9f8a"}"#,
        )
        .unwrap();
        assert!(matches!(m, LiveEvent::Message { .. }));

        let n: LiveEvent = serde_json::from_str(
            r#"{"kind" : "notification", "user_id" : "d439bcac-7ec8-4102-9048-6c449180dfac"}"#,
        )
        .unwrap();
        assert!(matches!(n, LiveEvent::Notification { .. }));

        let left: LiveEvent = serde_json::from_str(
            r#"{"kind" : "member", "user_id" : "d439bcac-7ec8-4102-9048-6c449180dfac", "conversation_id" : "0f8b9d3e-7c1a-4a55-9f7a-3b2c1d0e9f8a", "left" : true}"#,
        )
        .unwrap();
        assert!(matches!(left, LiveEvent::Member { left: true, .. }));

        let ball: LiveEvent = serde_json::from_str(
            r#"{"kind" : "match", "id" : "d439bcac-7ec8-4102-9048-6c449180dfac", "seq" : 42}"#,
        )
        .unwrap();
        assert!(matches!(ball, LiveEvent::Match { seq: 42, .. }));
    }
}
