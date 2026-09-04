//! Core domain types for Fishers — clubs, events, availability, payments.

mod agent;
mod availability;
mod chat;
mod club;
mod enums;
mod event;
mod invite;
mod order;
mod payment;
mod rbac;
mod user;

pub use agent::*;
pub use availability::*;
pub use chat::*;
pub use club::*;
pub use enums::*;
pub use event::*;
pub use invite::*;
pub use order::*;
pub use payment::*;
pub use rbac::*;
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
