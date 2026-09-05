//! Core domain types for Fishers — clubs, events, availability, payments.

mod agent;
mod availability;
mod chat;
mod club;
/// Cricket scoring — event-sourced match engine.
pub mod cricket;
mod enums;
mod event;
mod invite;
mod order;
mod payment;
/// Cross-cutting club activity events (AI, stats, notifications).
pub mod platform;
mod profile;
mod rbac;
/// Season stats + Play-Cricket (ECB) profile links.
pub mod stats;
/// Tournament generation is namespaced: `tournament::round_robin` etc.
pub mod tournament;
/// Selection ranking is namespaced: `selection::rank` / `selection::suggest`.
pub mod selection;
/// Reliability scoring is namespaced: `reliability::score(counts)`.
pub mod reliability;
mod user;

pub use agent::*;
pub use availability::*;
pub use chat::*;
pub use club::*;
pub use cricket::{
    evt, BatterStats, BowlerStats, DeliveryRecord, DismissalKind, ExtraKind, FallOfWicket,
    InningsState, MatchSide, MatchState, MatchStatus, ScoringEvent, ScoringEventKind, TossDecision,
};
pub use enums::*;
pub use event::*;
pub use invite::*;
pub use order::*;
pub use payment::*;
pub use platform::{MatchStatsDelta, PlatformActor, PlatformEvent, PlatformEventKind};
pub use profile::*;
pub use rbac::*;
pub use stats::*;
pub use selection::*;
pub use tournament::*;
pub use reliability::{ReliabilityBand, ReliabilityCounts, ReliabilityScore};
pub use user::*;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum DomainError {
    #[error("{0}")]
    Validation(String),
    #[error("{0}")]
    NotFound(String),
    #[error("{0}")]
    Forbidden(String),
    #[error("{0}")]
    Conflict(String),
}
