//! Cricket match scoring — event-sourced engine for offline + server replay.

/// Duckworth–Lewis–Stern par scores for a rain-affected chase.
pub mod dls;
mod engine;
mod types;

pub use dls::{DlsMethod, DlsPar, InningsResources, ResourceTable};
pub use engine::*;
pub use types::*;
