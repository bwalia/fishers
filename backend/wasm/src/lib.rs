//! The cricket engine in the browser.
//!
//! Four functions, string in and string out, mirroring `backend/ffi` exactly —
//! the phones reach the engine through UniFFI and the web reaches it through
//! this. Neither is a port: both call the same `fishers-domain`, which is the
//! same code the API replays with.
//!
//! That is what lets a scorer at a ground with no signal be told "nobody bowls
//! two overs in a row" at the moment they tap, rather than when the network
//! comes back and the server rejects a batch they finished an hour ago.

use fishers_cricket::{MatchState, ScoringEvent};
use wasm_bindgen::prelude::*;

/// Errors cross into JavaScript as exceptions carrying the engine's own words,
/// so the screen can print the reason a ball was refused rather than "failed".
fn js_err(what: &str, detail: impl std::fmt::Display) -> JsValue {
    JsValue::from_str(&format!("{what}: {detail}"))
}

/// Build a match from its whole event log.
///
/// What the scorer's screen does on opening a match: the log is the lasting
/// record, and the state is only ever a fold over it.
#[wasm_bindgen]
pub fn replay_match(events_json: &str) -> Result<String, JsValue> {
    let events: Vec<ScoringEvent> =
        serde_json::from_str(events_json).map_err(|e| js_err("an event log is malformed", e))?;
    let state = MatchState::replay(&events).map_err(|e| js_err("refused", e))?;
    serde_json::to_string(&state).map_err(|e| js_err("the resulting state", e))
}

/// Apply one event to a state and hand back the new one.
#[wasm_bindgen]
pub fn apply_event(state_json: &str, event_json: &str) -> Result<String, JsValue> {
    let mut state: MatchState =
        serde_json::from_str(state_json).map_err(|e| js_err("a match state is malformed", e))?;
    let event: ScoringEvent =
        serde_json::from_str(event_json).map_err(|e| js_err("an event is malformed", e))?;
    state.apply(&event).map_err(|e| js_err("refused", e))?;
    serde_json::to_string(&state).map_err(|e| js_err("the resulting state", e))
}

/// Whether the engine would accept this event, without keeping the result.
///
/// For disabling a button rather than letting somebody tap it and be told no.
#[wasm_bindgen]
pub fn would_accept(state_json: &str, event_json: &str) -> bool {
    apply_event(state_json, event_json).is_ok()
}

/// The version of the rules this build carries, so a browser can say what it is
/// running when it disagrees with somebody.
#[wasm_bindgen]
pub fn engine_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}
