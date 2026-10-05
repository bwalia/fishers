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

use jsonwebtoken::{encode, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use tracing::warn;

const DEFAULT_MODEL: &str = "llama3.1:8b";

/// What a commentator is allowed to do, and what they must not.
const SYSTEM: &str = "You are a cricket commentator on live radio. \
Given the facts of one delivery, reply with ONE line of commentary of 8 to 20 words, \
present tense, in a natural broadcast voice. \
Reply with the line only: no preamble, no quotation marks, no emoji, no bullet points. \
Use only the facts given — never invent runs, wickets, players or fielders. \
When a direction is given, name that fielding position and no other.";

/// The same brief, plus a translation — and the English kept alongside it.
///
/// The English is not a courtesy: `contradicts` below is what stops a small
/// model putting a wicket that never fell onto a live scoreboard, and it works
/// by reading English words. Asking for the line straight in Punjabi would
/// silently switch that check off, which is the one thing not worth trading
/// for a translation. So the model writes English, the English is checked, and
/// only a line that passed is shown — in the reader's language.
///
/// A model that cannot translate leaves `translated` empty, and the English
/// stands. A wrong translation of a correct line is a bad sentence; a
/// fabricated wicket is a wrong scoreboard, and only one of those is allowed.
const SYSTEM_BILINGUAL: &str = "You are a cricket commentator on live radio. \
Given the facts of one delivery, write ONE line of commentary of 8 to 20 words, \
present tense, in a natural broadcast voice. \
Use only the facts given — never invent runs, wickets, players or fielders. \
When a direction is given, name that fielding position and no other. \
Reply with JSON only, exactly {\"en\": \"...\", \"translated\": \"...\"}: \
\"en\" is that line in English, and \"translated\" is the same line in the \
language named in the prompt, as a commentator on that language's broadcast \
would say it — not a word-for-word rendering of the English. \
Keep player names as they are written. \
If you cannot write the other language, set \"translated\" to an empty string.";

#[derive(Clone)]
pub struct Ollama {
    url: String,
    model: String,
    /// The passphrase a request is signed with, when the endpoint wants one.
    ///
    /// Not sent as itself: it is the HMAC key for a short-lived JWT, minted per
    /// request and put in `x-api-key`. A bare Ollama on localhost wants
    /// nothing, but one published on a hostname normally sits behind a gateway
    /// that does — and such a gateway answering 403 looks from here exactly
    /// like a model with nothing to say, which is a bad way to spend an
    /// afternoon.
    api_key: Option<String>,
    http: reqwest::Client,
}

#[derive(Deserialize)]
struct GenerateResponse {
    #[serde(default)]
    response: String,
    /// `"stop"` when the model finished, `"length"` when it ran out of budget
    /// mid-sentence. Only used to explain an empty answer.
    #[serde(default)]
    done_reason: Option<String>,
}

/// The bilingual answer. Both fields default, so a model that sent only one of
/// them is handled rather than dropped.
#[derive(Deserialize, Default)]
struct Bilingual {
    #[serde(default)]
    en: String,
    #[serde(default)]
    translated: String,
}

/// The claims the gateway's JWT check wants. It verifies the signature and,
/// because they are present, the lifetime — so nothing here identifies a user.
/// The token says only "this request came from something holding the
/// passphrase", which is all the gateway is asking.
#[derive(Serialize)]
struct GatewayClaims<'a> {
    sub: &'a str,
    iat: u64,
    exp: u64,
}

impl Ollama {
    /// `None` when OLLAMA_URL is unset — commentary then stays as written.
    pub fn from_env() -> Option<Self> {
        let url = std::env::var("OLLAMA_URL").ok().filter(|u| !u.is_empty())?;
        Some(Self {
            url: url.trim_end_matches('/').to_string(),
            model: std::env::var("OLLAMA_MODEL").unwrap_or_else(|_| DEFAULT_MODEL.into()),
            api_key: std::env::var("OLLAMA_API_KEY")
                .ok()
                .map(|k| k.trim().to_string())
                .filter(|k| !k.is_empty()),
            http: reqwest::Client::builder()
                // A line is only worth having while its ball is the latest:
                // by the next one it is stale, and the browser has already
                // dropped the request. Long enough for a model that has to
                // load first, short enough not to hold a connection open
                // through the rest of the over.
                //
                // Configurable because the right number is a property of the
                // host, not of this code: a 3B model on a machine with a GPU
                // answers in a second, and an 8B one on a shared box can take
                // the better part of a minute. Fifteen is the default it has
                // always had.
                .timeout(Duration::from_secs(
                    std::env::var("OLLAMA_TIMEOUT_SECS")
                        .ok()
                        .and_then(|v| v.trim().parse().ok())
                        .filter(|secs| *secs > 0)
                        .unwrap_or(15),
                ))
                .build()
                .ok()?,
        })
    }

    pub fn model(&self) -> &str {
        &self.model
    }

    /// A short-lived HS256 token for the gateway in front of the model.
    ///
    /// `x-api-key` rather than `Authorization`, and the gateway accepts the
    /// value bare or `Bearer`-prefixed; bare is what it documents. The
    /// lifetime only has to outlast one request, and the client gives up on
    /// those after fifteen seconds.
    fn gateway_token(passphrase: &str) -> Option<String> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .ok()?
            .as_secs();
        encode(
            &Header::default(),
            &GatewayClaims { sub: "fishers-api", iat: now, exp: now + 120 },
            &EncodingKey::from_secret(passphrase.as_bytes()),
        )
        .inspect_err(|e| warn!("could not sign the ollama gateway token: {e}"))
        .ok()
    }

    /// One line for one ball, or `None` if the model could not oblige.
    ///
    /// `ball` is what actually happened. A small model asked for colour will
    /// cheerfully invent a wicket, and a scoreboard that announces wickets
    /// that did not fall is worse than one with no colour at all — so the
    /// answer is checked against the ball and dropped if it disagrees.
    /// `language` is the language to say it in, as a name the model will
    /// recognise ("Punjabi"), or `None` for English — which needs no
    /// translation step and whose guard is therefore exact.
    pub async fn commentate(
        &self,
        facts: &str,
        ball: BallFacts,
        language: Option<&str>,
    ) -> Option<String> {
        let body = match language {
            None => serde_json::json!({
                "model": self.model,
                "system": SYSTEM,
                "prompt": facts,
                "stream": false,
                // A reasoning model spends its whole budget deliberating and
                // returns an empty answer with done_reason "length" — which
                // arrives here as a model that had nothing to say, with
                // nothing anywhere to suggest otherwise. We want the call, not
                // the deliberation. Models that cannot think accept this and
                // ignore it, so it is safe to send to all of them.
                "think": false,
                "options": { "temperature": 0.8, "num_predict": 80 },
            }),
            Some(name) => serde_json::json!({
                "model": self.model,
                "system": SYSTEM_BILINGUAL,
                "prompt": format!("{facts}\n\nThe other language is {name}."),
                "stream": false,
                // As above: deliberation would eat the budget both lines need.
                "think": false,
                // Ollama's JSON mode, so the answer parses rather than arriving
                // wrapped in an explanation of itself.
                "format": "json",
                // Room for two lines, and one of them in a script that costs
                // more tokens per word than English does.
                "options": { "temperature": 0.8, "num_predict": 220 },
            }),
        };

        let mut request = self.http.post(format!("{}/api/generate", self.url));
        if let Some(key) = &self.api_key {
            // Minted per request rather than cached: an HMAC over three short
            // claims costs less than the bookkeeping to keep one fresh, and a
            // token that cannot outlive the call it was made for is one fewer
            // thing to leak.
            match Self::gateway_token(key) {
                Some(token) => request = request.header("x-api-key", token),
                None => {
                    warn!("could not sign the gateway token; sending the request unauthenticated");
                }
            }
        }
        let response = match request.json(&body).send().await {
            Ok(r) => r,
            Err(e) => {
                warn!("ollama unreachable: {e}");
                return None;
            }
        };
        if !response.status().is_success() {
            let status = response.status();
            // 401 and 403 are almost always the gateway in front of the model
            // rather than the model, and almost always a missing or wrong
            // OLLAMA_API_KEY. Say so, because "returned 403" on its own sent
            // somebody looking at the model for an afternoon.
            if status == reqwest::StatusCode::UNAUTHORIZED
                || status == reqwest::StatusCode::FORBIDDEN
            {
                warn!(
                    "ollama returned {status} — the gateway rejected the request and \
                     OLLAMA_API_KEY is {}",
                    if self.api_key.is_some() {
                        "set, so the passphrase may be wrong"
                    } else {
                        "unset, so nothing was signed"
                    }
                );
            } else {
                warn!("ollama returned {status}");
            }
            return None;
        }
        let payload: GenerateResponse = match response.json().await {
            Ok(p) => p,
            Err(e) => {
                warn!("ollama sent something unreadable: {e}");
                return None;
            }
        };
        // An empty answer is the one failure with no error attached to it, and
        // it is what a thinking model does when it talks itself out of the
        // budget. Say so, because the alternative is a silent feature.
        if payload.response.trim().is_empty() {
            warn!(
                "ollama said nothing (done_reason {}) — if this is a reasoning model, \
                 it spent the whole num_predict budget thinking",
                payload.done_reason.as_deref().unwrap_or("unknown")
            );
            return None;
        }
        match language {
            None => {
                let line = clean(&payload.response)?;
                if contradicts(&line, ball) {
                    warn!("ollama contradicted the ball, dropping its line: {line}");
                    return None;
                }
                Some(line)
            }
            Some(name) => {
                let pair: Bilingual = serde_json::from_str(payload.response.trim())
                    .inspect_err(|e| warn!("ollama sent unparseable JSON for {name}: {e}"))
                    .ok()?;
                pick(&pair, ball)
            }
        }
    }
}

/// Which of a bilingual pair to show.
///
/// The English is what gets checked, because `contradicts` reads English. A
/// line that fails takes its translation down with it: they are the same claim
/// in two languages, so if one is a lie so is the other, and a Punjabi reader
/// is owed the same correct scoreboard as an English one.
///
/// A translation that came back empty — the model was asked to do that rather
/// than guess — or that arrived as a paragraph leaves the checked English
/// standing. An English line on a Punjabi page is a gap; a wicket that did not
/// fall is a wrong scoreboard.
fn pick(pair: &Bilingual, ball: BallFacts) -> Option<String> {
    let english = clean(&pair.en)?;
    if contradicts(&english, ball) {
        warn!("ollama contradicted the ball, dropping its line: {english}");
        return None;
    }
    Some(clean(&pair.translated).unwrap_or(english))
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
    let says = |needle: &str| words.contains(&needle);

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
    use super::{clean, contradicts, pick, BallFacts, Bilingual, Ollama};

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

    fn pair(en: &str, translated: &str) -> Bilingual {
        Bilingual { en: en.into(), translated: translated.into() }
    }

    /// The point of generating English alongside the translation: the check
    /// still runs, and a fabricated wicket is dropped in every language.
    #[test]
    fn a_translation_of_a_line_that_lied_is_dropped_too() {
        let lie = pair(
            "Lords edges a short delivery, caught at point for the wicket.",
            "ਲੌਰਡਜ਼ ਦਾ ਕਿਨਾਰਾ ਲੱਗਿਆ, ਪੌਇੰਟ 'ਤੇ ਕੈਚ।",
        );
        assert!(
            pick(&lie, FOUR).is_none(),
            "the English claimed a wicket off a four, so neither line may be shown"
        );
    }

    #[test]
    fn a_good_pair_shows_the_translation() {
        let good = pair(
            "Driven sweetly through the covers for four.",
            "ਕਵਰ ਵੱਲ ਸ਼ਾਨਦਾਰ ਡਰਾਈਵ — ਚੌਕਾ।",
        );
        assert_eq!(pick(&good, FOUR).as_deref(), Some("ਕਵਰ ਵੱਲ ਸ਼ਾਨਦਾਰ ਡਰਾਈਵ — ਚੌਕਾ।"));
    }

    /// A model that cannot write the language was told to say so. The English
    /// it did write is correct and checked, so it stands.
    #[test]
    fn an_empty_translation_falls_back_to_the_checked_english() {
        let only_english = pair("Driven through the covers for four.", "");
        assert_eq!(
            pick(&only_english, FOUR).as_deref(),
            Some("Driven through the covers for four.")
        );
    }

    /// Nothing usable at all is nothing shown — the written line already on
    /// the page is correct and stays.
    #[test]
    fn an_empty_pair_is_no_line() {
        assert!(pick(&pair("", ""), FOUR).is_none());
    }

    /// The gateway verifies the signature with the same passphrase and, since
    /// the token carries them, the lifetime. Verifying it here the way the
    /// gateway does is the only check that the thing we send is the thing it
    /// will accept — the alternative is finding out from a 403 in a log.
    #[test]
    fn the_gateway_token_verifies_with_the_passphrase() {
        use jsonwebtoken::{decode, DecodingKey, Validation};

        let token = Ollama::gateway_token("a-passphrase").expect("signs");
        let claims = decode::<serde_json::Value>(
            &token,
            &DecodingKey::from_secret(b"a-passphrase"),
            &Validation::default(),
        )
        .expect("the gateway can verify it");

        assert_eq!(claims.claims["sub"], "fishers-api");
        let iat = claims.claims["iat"].as_u64().unwrap();
        let exp = claims.claims["exp"].as_u64().unwrap();
        // Long enough to outlast a request the client gives up on at 15s,
        // short enough that a leaked one is worth little.
        assert_eq!(exp - iat, 120);
    }

    #[test]
    fn a_token_signed_with_another_passphrase_is_refused() {
        use jsonwebtoken::{decode, DecodingKey, Validation};

        let token = Ollama::gateway_token("the-right-one").expect("signs");
        assert!(decode::<serde_json::Value>(
            &token,
            &DecodingKey::from_secret(b"the-wrong-one"),
            &Validation::default(),
        )
        .is_err());
    }
}
