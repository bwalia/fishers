//! Cricket match scoring — event-sourced engine for offline + server replay.
//!
//! A crate of its own rather than a module of `fishers-domain`, because this is
//! the one part of the system that runs in four places: the API, both phones
//! (through `fishers-ffi`) and the browser (through `fishers-wasm`). The domain
//! crate depends on sqlx so its row types can derive `FromRow`; a Postgres
//! driver does not compile to WebAssembly, and the rules should not need one.

use thiserror::Error;

/// What the engine says when it refuses something.
///
/// It lived in `fishers-domain` and was used by nothing but the engine, so it
/// came with it. `fishers_domain::DomainError` still names this type.
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

/// Duckworth–Lewis–Stern par scores for a rain-affected chase.
pub mod dls;
mod engine;
mod impact;
mod insights;
mod types;

pub use dls::{DlsMethod, DlsPar, InningsResources, ResourceTable};
pub use engine::*;
pub use impact::PlayerImpact;
pub use insights::{MatchInsights, PhaseScore, SideInsights};
pub use types::*;
