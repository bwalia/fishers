//! Application services shared by HTTP routes, agent apply, and jobs.
//!
//! Keeps the LLM and UI on the same write paths — the model never owns data.

pub mod agent_apply;
pub mod club_briefing;
pub mod platform_bus;
pub mod play_cricket;
