//! Core domain types for Fishers — clubs, events, availability, payments.

mod availability;
mod club;
mod enums;
mod event;
mod invite;
mod order;
mod payment;
mod profile;
/// Reliability scoring is namespaced: `reliability::score(counts)`.
pub mod reliability;
mod user;

pub use availability::*;
pub use club::*;
pub use enums::*;
pub use event::*;
pub use invite::*;
pub use order::*;
pub use payment::*;
pub use profile::*;
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
