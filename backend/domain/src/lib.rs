//! Core domain types for Fishers — clubs, events, availability, payments.

mod agent;
mod availability;
mod chat;
mod club;
/// Cricket scoring — event-sourced match engine.
pub mod admin;
/// The engine is its own crate now: it has to compile for a browser, and this
/// one depends on sqlx. Re-exported so `fishers_domain::cricket::…` still
/// names it, which is how the rest of the workspace refers to it.
pub use fishers_cricket as cricket;
mod enums;
mod event;
mod invite;
/// Man of the match, voted for by the club after the game.
mod motm;
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
pub mod umpire;
/// Selection ranking is namespaced: `selection::rank` / `selection::suggest`.
pub mod selection;
/// Reliability scoring is namespaced: `reliability::score(counts)`.
pub mod reliability;
mod user;
mod venue_hire;
/// Live scores from an outside feed, as opposed to matches scored in this app.
pub mod world_cricket;
/// One outside match in full — the scorecard.
pub mod world_cricket_detail;

pub use admin::*;
pub use agent::*;
pub use availability::*;
pub use chat::*;
pub use club::*;
pub use cricket::{
    dls, evt, BallType, BatterStats, BowlerStats, DeliveryRecord, DismissalKind, DlsMethod, DlsPar,
    ExtraKind, FallOfWicket, GroundType, InningsResources, InningsState, MatchConditions,
    MatchInsights, MatchPlayer, MatchSide, MatchState, MatchStatus, PhaseScore, PlayerImpact,
    ResourceTable, ScoringEvent, ScoringEventKind, SideInsights, region_for, ShotKind, ShotRecord,
    TossDecision,
};
pub use enums::*;
pub use event::*;
pub use invite::*;
pub use motm::*;
pub use order::*;
pub use payment::*;
pub use platform::{MatchStatsDelta, PlatformActor, PlatformEvent, PlatformEventKind};
pub use profile::*;
pub use rbac::*;
pub use stats::*;
pub use selection::*;
pub use tournament::*;
pub use umpire::*;
pub use reliability::{ReliabilityBand, ReliabilityCounts, ReliabilityScore};
pub use user::*;
pub use venue_hire::*;
pub use world_cricket::{phase_for, WorldMatch, WorldScores, PHASE_DONE, PHASE_LIVE, PHASE_PENDING};
// Only the three that do not collide with our own scoring types — this
// crate already has a `FallOfWicket`, and an outside feed's is a different
// thing. The rest are reached through `world_cricket_detail::`.
pub use world_cricket_detail::{dismissal_line, WorldMatchDetail, WorldMatchDetailView};

// Moved with the engine, which was its only user.
pub use fishers_cricket::DomainError;
