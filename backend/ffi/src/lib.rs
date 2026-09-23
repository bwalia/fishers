//! The cricket engine, for the phones.
//!
//! The Laws were written three times — Rust here, Swift in `CricketTypes.swift`
//! and `CricketEngine.swift`, and a partial Dart port — and the three only
//! agreed because their wire strings matched. They drifted twice in one week:
//! once when an enum variant was renamed, once when a `typeName` switch went
//! unnoticed. Every copy is a place for the rules to differ from the server's,
//! and a scorer who disagrees with the server about who won has no way to tell
//! which of them is wrong.
//!
//! So the rules run once, here, and the phones call this.
//!
//! # Why JSON across the boundary
//!
//! The types are not what was duplicated — the *logic* was. Mirroring every
//! struct into UniFFI would be a third hand-written copy of the data model to
//! keep in step, which is the problem rather than the fix. The platforms
//! already agree on the wire format; it is what the server speaks and what
//! every existing test pins. So that is the boundary: JSON in, JSON out, and
//! each platform keeps its own types for rendering, where a mistake is visible
//! rather than silent.

use fishers_domain::{MatchState, ScoringEvent};

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum EngineError {
    /// The JSON handed in was not an event log, or not a match state.
    #[error("could not read that as {what}: {detail}")]
    Malformed { what: String, detail: String },
    /// The engine refused it: a bowler who may not bowl, a free hit dismissal
    /// that is not a run out, an innings already closed. The message is the
    /// one a scorer should see.
    #[error("{detail}")]
    Refused { detail: String },
}

fn malformed(what: &str, e: serde_json::Error) -> EngineError {
    EngineError::Malformed { what: what.to_string(), detail: e.to_string() }
}

/// Build a match from its whole event log.
///
/// What a scorer's app does on opening a match: the log is the lasting record,
/// and the state is only ever a fold over it.
#[uniffi::export]
pub fn replay_match(events_json: String) -> Result<String, EngineError> {
    let events: Vec<ScoringEvent> =
        serde_json::from_str(&events_json).map_err(|e| malformed("an event log", e))?;
    let state = MatchState::replay(&events)
        .map_err(|e| EngineError::Refused { detail: e.to_string() })?;
    serde_json::to_string(&state).map_err(|e| malformed("the resulting state", e))
}

/// Apply one event to a state and hand back the new one.
///
/// This is the call that matters at the ground: the scorer taps, the app shows
/// the result immediately, and it is the *server's* rules that decided it — so
/// the phone and the server cannot disagree about whether that was a wicket.
#[uniffi::export]
pub fn apply_event(state_json: String, event_json: String) -> Result<String, EngineError> {
    let mut state: MatchState =
        serde_json::from_str(&state_json).map_err(|e| malformed("a match state", e))?;
    let event: ScoringEvent =
        serde_json::from_str(&event_json).map_err(|e| malformed("an event", e))?;
    state
        .apply(&event)
        .map_err(|e| EngineError::Refused { detail: e.to_string() })?;
    serde_json::to_string(&state).map_err(|e| malformed("the resulting state", e))
}

/// Whether the engine would accept this event, without keeping the result.
///
/// For disabling a button rather than letting someone tap it and be told no.
#[uniffi::export]
pub fn would_accept(state_json: String, event_json: String) -> bool {
    apply_event(state_json, event_json).is_ok()
}

/// The version of the rules this build carries, so a phone can say what it is
/// running when it disagrees with somebody.
#[uniffi::export]
pub fn engine_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The boundary is JSON both ways, so the test that matters is that a log
    /// goes in and a readable state comes out — not that Rust can call Rust.
    #[test]
    fn a_log_replays_into_a_state() {
        let log = r#"[
            {"client_event_id":"3f2504e0-4f89-41d3-9a0c-0305e82c3301","seq":1,
             "kind":{"type":"match_prepared","overs_limit":20,
                     "home_name":"Lords","away_name":"Hemel"}}
        ]"#;
        let state = replay_match(log.to_string()).expect("a one-event log replays");
        let parsed: serde_json::Value = serde_json::from_str(&state).unwrap();
        assert_eq!(parsed["home_name"], "Lords");
        assert_eq!(parsed["overs_limit"], 20);
    }

    #[test]
    fn rubbish_in_is_named_as_rubbish() {
        let err = replay_match("not json".into()).unwrap_err();
        assert!(
            matches!(err, EngineError::Malformed { ref what, .. } if what == "an event log"),
            "{err}"
        );
    }

    /// A refusal has to carry the engine's own words, because they are what the
    /// scorer reads — "nobody bowls two in a row", not "error 3".
    #[test]
    fn a_refusal_keeps_the_reason() {
        let state = replay_match("[]".into()).expect("an empty log is a fresh match");
        let event = r#"{"client_event_id":"3f2504e0-4f89-41d3-9a0c-0305e82c3302","seq":1,
                        "kind":{"type":"innings_completed"}}"#;
        let err = apply_event(state, event.to_string()).unwrap_err();
        match err {
            EngineError::Refused { detail } => assert!(!detail.is_empty(), "it says why"),
            other => panic!("expected a refusal, got {other:?}"),
        }
    }

    #[test]
    fn would_accept_agrees_with_apply() {
        let state = replay_match("[]".into()).unwrap();
        let bad = r#"{"client_event_id":"3f2504e0-4f89-41d3-9a0c-0305e82c3303","seq":1,
                      "kind":{"type":"innings_completed"}}"#;
        assert!(!would_accept(state.clone(), bad.to_string()));
        assert!(apply_event(state, bad.to_string()).is_err());
    }
}
