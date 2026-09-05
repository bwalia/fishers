//! Thin emit helpers used from routes after authoritative domain writes.

use fishers_db::repos::platform as platform_repo;
use fishers_domain::{PlatformEvent, PlatformEventKind};
use uuid::Uuid;

use crate::state::AppState;

pub async fn match_started(
    state: &AppState,
    club_id: Uuid,
    event_id: Uuid,
    match_id: Uuid,
    user_id: Uuid,
    sport: &str,
) {
    platform_repo::emit_best_effort(
        &state.pool,
        PlatformEvent::new(
            club_id,
            platform_repo::user_actor(user_id),
            PlatformEventKind::MatchStarted {
                event_id,
                match_id,
                sport: sport.to_string(),
            },
        ),
    )
    .await;
}

pub async fn match_completed(
    state: &AppState,
    club_id: Uuid,
    event_id: Uuid,
    match_id: Uuid,
    user_id: Uuid,
    sport: &str,
    summary: Option<String>,
) {
    platform_repo::emit_best_effort(
        &state.pool,
        PlatformEvent::new(
            club_id,
            platform_repo::user_actor(user_id),
            PlatformEventKind::MatchCompleted {
                event_id,
                match_id,
                sport: sport.to_string(),
                summary,
            },
        ),
    )
    .await;
}

pub async fn squad_published(state: &AppState, club_id: Uuid, event_id: Uuid, user_id: Uuid) {
    platform_repo::emit_best_effort(
        &state.pool,
        PlatformEvent::new(
            club_id,
            platform_repo::user_actor(user_id),
            PlatformEventKind::SquadPublished { event_id },
        ),
    )
    .await;
}
