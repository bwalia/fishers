//! Ball-by-ball commentary from a local (or self-hosted) Ollama model.
//!
//! The app already writes a line for every ball from the log — deterministic,
//! instant, and correct. This adds colour on top of it, and is deliberately
//! never in the way: a model on the other end of a network takes seconds, and a
//! scorer will not wait seconds to record a ball. So commentary is asked for
//! separately, after the ball is already in, and if the model is unset, slow or
//! down the written line simply stands.
//!
//! The facts are assembled here from the server's own match state, never from
//! the caller, so the model cannot be fed a score that did not happen.

use std::time::Duration;

use serde::Deserialize;
use tracing::warn;

const DEFAULT_MODEL: &str = "llama3.1:8b";

/// What a commentator is allowed to do, and what they must not.
const SYSTEM: &str = "You are a cricket commentator on live radio. \
Given the facts of one delivery, reply with ONE line of commentary of 8 to 20 words, \
present tense, in a natural broadcast voice. \
Reply with the line only: no preamble, no quotation marks, no emoji, no bullet points. \
Use only the facts given — never invent runs, wickets, players or fielders. \
When a direction is given, name that fielding position and no other.";

#[derive(Clone)]
pub struct Ollama {
    url: String,
    model: String,
    http: reqwest::Client,
}

#[derive(Deserialize)]
struct GenerateResponse {
    #[serde(default)]
    response: String,
}

impl Ollama {
    /// `None` when OLLAMA_URL is unset — commentary then stays as written.
    pub fn from_env() -> Option<Self> {
        let url = std::env::var("OLLAMA_URL").ok().filter(|u| !u.is_empty())?;
        Some(Self {
            url: url.trim_end_matches('/').to_string(),
            model: std::env::var("OLLAMA_MODEL").unwrap_or_else(|_| DEFAULT_MODEL.into()),
            http: reqwest::Client::builder()
                // Well beyond a good response, well short of holding a request open.
                .timeout(Duration::from_secs(30))
                .build()
                .ok()?,
        })
    }

    pub fn model(&self) -> &str {
        &self.model
    }

    /// One line for one ball, or `None` if the model could not oblige.
    ///
    /// `ball` is what actually happened. A small model asked for colour will
    /// cheerfully invent a wicket, and a scoreboard that announces wickets
    /// that did not fall is worse than one with no colour at all — so the
    /// answer is checked against the ball and dropped if it disagrees.
    pub async fn commentate(&self, facts: &str, ball: BallFacts) -> Option<String> {
        let body = serde_json::json!({
            "model": self.model,
            "system": SYSTEM,
            "prompt": facts,
            "stream": false,
            "options": { "temperature": 0.8, "num_predict": 80 },
        });

        let response = match self
            .http
            .post(format!("{}/api/generate", self.url))
            .json(&body)
            .send()
            .await
        {
            Ok(r) => r,
            Err(e) => {
                warn!("ollama unreachable: {e}");
                return None;
            }
        };
        if !response.status().is_success() {
            warn!("ollama returned {}", response.status());
            return None;
        }
        let payload: GenerateResponse = match response.json().await {
            Ok(p) => p,
            Err(e) => {
                warn!("ollama sent something unreadable: {e}");
                return None;
            }
        };
        let line = clean(&payload.response)?;
        if contradicts(&line, ball) {
            warn!("ollama contradicted the ball, dropping its line: {line}");
            return None;
        }
        Some(line)
    }
}

/// What the ball actually was, for checking the model against.
#[derive(Clone, Copy)]
pub struct BallFacts {
    pub is_wicket: bool,
    pub runs: u8,
    pub is_legal: bool,
}

/// Does the line claim something the ball did not do?
///
/// Deliberately blunt and biased towards rejection: the written line is always
/// correct, so throwing away a good sentence costs nothing while keeping a
/// wrong one puts a fictional wicket on a live scoreboard.
fn contradicts(line: &str, ball: BallFacts) -> bool {
    let lower = line.to_lowercase();
    // "mid-wicket" is a fielding position, not a dismissal.
    let text = lower.replace("mid-wicket", " ").replace("midwicket", " ");
    let words: Vec<&str> = text
        .split(|c: char| !c.is_ascii_alphabetic())
        .filter(|w| !w.is_empty())
        .collect();
    let says = |needle: &str| words.iter().any(|w| *w == needle);

    if !ball.is_wicket
        && (says("wicket")
            || says("wickets")
            || says("out")
            || says("bowled")
            || says("caught")
            || says("stumped")
            || says("lbw")
            || says("dismissed")
            || says("dismissal"))
    {
        return true;
    }
    if ball.runs != 4 && (says("four") || says("boundary")) {
        return true;
    }
    if ball.runs != 6 && (says("six") || says("maximum")) {
        return true;
    }
    // A dot ball is not a scoring shot.
    if ball.runs == 0 && ball.is_legal && (says("runs") || says("scores")) {
        return true;
    }
    // Small models like to name a number that is not the one they were given —
    // "taps it for a single, four runs scored" was a real answer.
    if ball.runs != 1 && (says("single") || says("one")) {
        return true;
    }
    if ball.runs != 2 && (says("two") || says("couple") || says("brace")) {
        return true;
    }
    if ball.runs != 3 && says("three") {
        return true;
    }
    false
}

/// Models like to wrap a line in quotes, add a label, or run on for a
/// paragraph. Take the first sentence-ish line and strip the decoration.
fn clean(raw: &str) -> Option<String> {
    let line = raw
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())?
        .trim_matches(|c| c == '"' || c == '\'' || c == '*')
        .trim();
    // A model that ignored the brief and wrote an essay is not usable as a
    // one-line call.
    if line.is_empty() || line.chars().count() > 300 {
        return None;
    }
    Some(line.to_string())
}

#[cfg(test)]
mod tests {
    use super::{clean, contradicts, BallFacts};

    const FOUR: BallFacts = BallFacts { is_wicket: false, runs: 4, is_legal: true };
    const DOT: BallFacts = BallFacts { is_wicket: false, runs: 0, is_legal: true };
    const WICKET: BallFacts = BallFacts { is_wicket: true, runs: 0, is_legal: true };

    /// The one that started this: a four described as a wicket.
    #[test]
    fn a_wicket_that_did_not_fall_is_rejected() {
        assert!(contradicts(
            "Lords edges a short delivery, picked up at point as Hemel celebrates a wicket.",
            FOUR
        ));
    }

    #[test]
    fn mid_wicket_is_a_fielding_position_not_a_dismissal() {
        assert!(!contradicts("Pulled away through mid-wicket for four.", FOUR));
    }

    #[test]
    fn boundaries_are_not_invented() {
        assert!(contradicts("Smashed away for four.", DOT));
        assert!(contradicts("That is a maximum, six over long on.", FOUR));
        assert!(!contradicts("Driven through the covers for four.", FOUR));
    }

    #[test]
    fn a_real_wicket_may_be_called_a_wicket() {
        assert!(!contradicts("Bowled him! The off stump is out of the ground.", WICKET));
    }

    /// The other real answer: a four called a single in the same sentence.
    #[test]
    fn a_number_that_is_not_the_ball_is_rejected() {
        assert!(contradicts("Taps it softly for a single, four runs scored.", FOUR));
        assert!(contradicts("Pushed away for a couple.", FOUR));
        assert!(!contradicts("Driven hard through the covers for four.", FOUR));
    }

    #[test]
    fn a_dot_is_not_described_as_scoring() {
        assert!(contradicts("He scores comfortably off the back foot.", DOT));
        assert!(!contradicts("Solid defence, nothing on offer there.", DOT));
    }

    #[test]
    fn strips_the_quotes_models_like_to_add() {
        assert_eq!(
            clean("\"Driven sweetly through the covers for four.\"").as_deref(),
            Some("Driven sweetly through the covers for four.")
        );
    }

    #[test]
    fn takes_the_first_line_and_drops_the_rest() {
        assert_eq!(
            clean("\n\nPulled away for four.\nHere is some more waffle.").as_deref(),
            Some("Pulled away for four.")
        );
    }

    #[test]
    fn refuses_an_essay_and_an_empty_answer() {
        assert!(clean("").is_none());
        assert!(clean(&"word ".repeat(200)).is_none());
    }
}
