//! Apple Push Notification service, token-based.
//!
//! Until now the iOS half of `PushService::send` was a log line: notifications
//! were stored, so the bell filled up, but nothing ever reached a phone. This
//! is the other half.
//!
//! Token-based rather than certificate-based authentication, which is what
//! Apple recommends and what a Kubernetes secret can actually hold: one .p8
//! elliptic-curve key, a key id and a team id, from which this signs a short
//! ES256 JWT and sends it as the bearer on every push. Certificates expire
//! annually and have to be renewed by hand; a .p8 key does not expire.
//!
//! Configuration, all from the environment:
//!
//!   APNS_KEY_ID       the ten-character Key ID of the .p8 key
//!   APNS_TEAM_ID      the ten-character Apple Developer Team ID
//!   APNS_PRIVATE_KEY  the .p8 file's contents (PEM, with the BEGIN/END lines)
//!   APNS_PRIVATE_KEY_PATH  …or a path to it, for a mounted secret
//!   APNS_BUNDLE_ID    the app's bundle id; defaults to com.fishers.app
//!   APNS_ENVIRONMENT  "production" or "sandbox" (default: sandbox)
//!
//! Unconfigured is a normal state, exactly as it is for web push: a developer
//! without an Apple key gets an app whose bell works and whose phone stays
//! quiet, rather than a stream of errors.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::Serialize;
use serde_json::{json, Value};
use tokio::sync::RwLock;
use tracing::{info, warn};

use crate::webpush::PushOutcome;

const PRODUCTION: &str = "https://api.push.apple.com";
const SANDBOX: &str = "https://api.sandbox.push.apple.com";

/// Apple rejects a provider token older than an hour and rate-limits new ones
/// to roughly one every twenty minutes, so the token is cached and reminted
/// well inside both limits.
const TOKEN_LIFETIME_SECS: u64 = 45 * 60;

#[derive(Serialize)]
struct Claims {
    /// Team id.
    iss: String,
    /// Issued at, seconds since the epoch.
    iat: u64,
}

#[derive(Clone)]
struct CachedToken {
    jwt: String,
    issued_at: u64,
}

#[derive(Clone)]
pub struct ApnsService {
    key_id: String,
    team_id: String,
    bundle_id: String,
    host: &'static str,
    /// `None` when APNs is not configured, which is the usual state locally.
    /// Behind an `Arc` because `EncodingKey` is not `Clone` and this service
    /// is cloned into every request handler.
    key: Option<Arc<EncodingKey>>,
    token: Arc<RwLock<Option<CachedToken>>>,
    client: reqwest::Client,
}

impl std::fmt::Debug for ApnsService {
    // The signing key must never reach a log line.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ApnsService")
            .field("bundle_id", &self.bundle_id)
            .field("host", &self.host)
            .field("configured", &self.key.is_some())
            .finish()
    }
}

impl ApnsService {
    pub fn from_env() -> Self {
        let var = |k: &str| std::env::var(k).ok().filter(|v| !v.trim().is_empty());

        let bundle_id = var("APNS_BUNDLE_ID").unwrap_or_else(|| "com.fishers.app".into());
        // Sandbox by default. A development build's token is only ever valid
        // against the sandbox host, and getting this the wrong way round is
        // the single most common reason a correctly configured push is
        // rejected with BadDeviceToken.
        let host = match var("APNS_ENVIRONMENT").as_deref() {
            Some("production" | "prod") => PRODUCTION,
            _ => SANDBOX,
        };

        // HTTP/2 is not optional here: APNs speaks nothing else. reqwest is
        // built with default features off in this workspace, so the `http2`
        // feature is named explicitly in Cargo.toml — without it every push
        // fails at the protocol, not at the credentials.
        let client = reqwest::Client::builder()
            .http2_prior_knowledge()
            .build()
            .unwrap_or_default();

        let pem = var("APNS_PRIVATE_KEY").or_else(|| {
            var("APNS_PRIVATE_KEY_PATH").and_then(|path| match std::fs::read_to_string(&path) {
                Ok(pem) => Some(pem),
                Err(error) => {
                    warn!(%path, %error, "APNS_PRIVATE_KEY_PATH could not be read — iOS push is off");
                    None
                }
            })
        });

        let (Some(key_id), Some(team_id), Some(pem)) =
            (var("APNS_KEY_ID"), var("APNS_TEAM_ID"), pem)
        else {
            info!("APNS_KEY_ID / APNS_TEAM_ID / APNS_PRIVATE_KEY not all set: iOS push is off");
            return Self {
                key_id: String::new(),
                team_id: String::new(),
                bundle_id,
                host,
                key: None,
                token: Arc::new(RwLock::new(None)),
                client,
            };
        };

        // Parsed once, at boot: a malformed key should fail here, where
        // somebody is watching the log, rather than on the first notification
        // of a Saturday afternoon.
        let pem = normalise_key(&pem);
        let key = match EncodingKey::from_ec_pem(pem.as_bytes()) {
            Ok(key) => Some(Arc::new(key)),
            Err(error) => {
                warn!(%error, "APNS_PRIVATE_KEY is not a usable .p8 EC key — iOS push is off");
                None
            }
        };
        if key.is_some() {
            info!(bundle_id, host, "iOS push on");
        }

        Self {
            key_id,
            team_id,
            bundle_id,
            host,
            key,
            token: Arc::new(RwLock::new(None)),
            client,
        }
    }

    pub fn is_configured(&self) -> bool {
        self.key.is_some()
    }

    /// The provider token, minted on demand and reused until it ages out.
    async fn bearer(&self) -> Option<String> {
        let key = self.key.as_ref()?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .ok()?
            .as_secs();

        if let Some(cached) = self.token.read().await.as_ref() {
            if now.saturating_sub(cached.issued_at) < TOKEN_LIFETIME_SECS {
                return Some(cached.jwt.clone());
            }
        }

        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(self.key_id.clone());
        let claims = Claims {
            iss: self.team_id.clone(),
            iat: now,
        };
        let jwt = match jsonwebtoken::encode(&header, &claims, key) {
            Ok(jwt) => jwt,
            Err(error) => {
                warn!(%error, "could not sign an APNs provider token");
                return None;
            }
        };

        *self.token.write().await = Some(CachedToken {
            jwt: jwt.clone(),
            issued_at: now,
        });
        Some(jwt)
    }

    /// Send one alert to one device.
    ///
    /// `payload` is the app's own data, merged in alongside the `aps`
    /// dictionary so a tap can be routed — the conversation to open, the poll
    /// to show. `collapse` (APNs calls it `apns-collapse-id`) replaces an
    /// earlier unread notification with the same id rather than stacking a
    /// second one: five people voting is one notification, not five.
    pub async fn send(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        payload: &Value,
        collapse: Option<&str>,
    ) -> PushOutcome {
        let Some(bearer) = self.bearer().await else {
            return PushOutcome::Failed("APNs is not configured".into());
        };

        let message = alert_payload(title, body, payload, collapse);

        let url = format!("{}/3/device/{device_token}", self.host);
        let mut request = self
            .client
            .post(&url)
            .bearer_auth(bearer)
            .header("apns-topic", &self.bundle_id)
            .header("apns-push-type", "alert")
            // Alerts that arrive after the poll has closed are worse than no
            // alert, so APNs is told to stop trying after the voting window.
            .header("apns-expiration", expiry_in(48 * 3600).to_string())
            .header("apns-priority", "10")
            .json(&message);
        if let Some(collapse) = collapse_id(collapse) {
            request = request.header("apns-collapse-id", collapse);
        }

        let response = match request.send().await {
            Ok(response) => response,
            Err(error) => return PushOutcome::Failed(error.to_string()),
        };

        let status = response.status().as_u16();
        if (200..300).contains(&status) {
            return PushOutcome::Delivered;
        }
        classify(status, &reason_from(response.text().await.ok()))
    }
}

/// The body APNs is sent: the `aps` dictionary, and the app's own keys beside
/// it — never inside it, which is the one way to get a payload silently
/// ignored by iOS.
fn alert_payload(title: &str, body: &str, payload: &Value, collapse: Option<&str>) -> Value {
    let mut message = json!({
        "aps": {
            "alert": { "title": title, "body": body },
            "sound": "default",
            // Lets iOS group them; the app re-reads the real unread count
            // from /notifications when it opens.
            "thread-id": collapse.unwrap_or("fishers"),
        }
    });
    if let (Some(object), Some(extra)) = (message.as_object_mut(), payload.as_object()) {
        for (key, value) in extra {
            if key != "aps" {
                object.insert(key.clone(), value.clone());
            }
        }
    }
    message
}

/// Apple caps `apns-collapse-id` at 64 *bytes* and rejects anything longer.
///
/// Truncated on a character boundary, not at byte 64: slicing a `&str` mid
/// character panics, and these ids come from notification payloads rather
/// than from a fixed list, so a club with an emoji in its name would have
/// taken the whole push thread down with it.
fn collapse_id(raw: Option<&str>) -> Option<&str> {
    let raw = raw?;
    if raw.is_empty() {
        return None;
    }
    if raw.len() <= 64 {
        return Some(raw);
    }
    let mut end = 64;
    while end > 0 && !raw.is_char_boundary(end) {
        end -= 1;
    }
    (end > 0).then(|| &raw[..end])
}

/// APNs answers a refusal as `{"reason": "BadDeviceToken"}`. Anything else it
/// sends is kept whole rather than thrown away — an unrecognised body is the
/// thing worth reading in a log.
fn reason_from(body: Option<String>) -> String {
    let Some(body) = body else {
        return String::new();
    };
    serde_json::from_str::<Value>(&body)
        .ok()
        .and_then(|v| v.get("reason").and_then(Value::as_str).map(str::to_owned))
        .unwrap_or(body)
}

/// Whether this token is worth keeping.
///
/// 410 Gone, and 400 BadDeviceToken, both mean it will never work again — the
/// app was deleted, or the build moved between the sandbox and production
/// environments. Deleting the row is right. Everything else is this attempt
/// failing, not the token: APNs being down must not quietly unsubscribe a
/// club from its own notifications.
fn classify(status: u16, reason: &str) -> PushOutcome {
    let dead = status == 410
        || reason.contains("BadDeviceToken")
        || reason.contains("Unregistered")
        || reason.contains("DeviceTokenNotForTopic");
    if dead {
        PushOutcome::Gone
    } else {
        PushOutcome::Failed(format!("APNs {status}: {reason}"))
    }
}

/// The .p8 as PEM, however it was stored.
///
/// Three shapes reach this, and all three are somebody doing the sensible
/// thing with the tool in front of them:
///
///   - the PEM itself, which is what `cat AuthKey_XXX.p8` gives;
///   - the PEM with literal `\n` in it, because a .env file cannot hold a
///     newline and pasting one in is the obvious move;
///   - base64 of the whole file, which is how this repo already stores the
///     App Store Connect key (`ASC_PRIVATE_KEY_B64`) — secret UIs mangle
///     multi-line values, and the iOS release scripts have the scar tissue
///     to prove it.
///
/// Anything unrecognised is handed back unchanged, so the parse fails with
/// the key's own error rather than one invented here.
fn normalise_key(raw: &str) -> String {
    let text = raw.trim().trim_matches('"').trim_matches('\'').trim();
    if text.contains("BEGIN") {
        return text.replace("\\n", "\n");
    }
    let compact: String = text.chars().filter(|c| !c.is_whitespace()).collect();
    match base64::engine::general_purpose::STANDARD.decode(&compact) {
        Ok(bytes) => match String::from_utf8(bytes) {
            Ok(decoded) if decoded.contains("BEGIN") => decoded,
            _ => text.to_string(),
        },
        Err(_) => text.to_string(),
    }
}

fn expiry_in(seconds: u64) -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() + seconds)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The app's own keys route a tap — which conversation, which poll. Put
    /// inside `aps` they are silently ignored by iOS, so this is the shape
    /// that matters.
    #[test]
    fn custom_keys_sit_beside_aps_not_inside_it() {
        let payload = json!({ "conversation_id": "abc", "url": "/chat/abc" });
        let message = alert_payload("Man of the match", "Vote now", &payload, None);

        assert_eq!(message["conversation_id"], "abc");
        assert_eq!(message["url"], "/chat/abc");
        assert!(message["aps"]["conversation_id"].is_null());
        assert_eq!(message["aps"]["alert"]["title"], "Man of the match");
        assert_eq!(message["aps"]["alert"]["body"], "Vote now");
    }

    /// A payload cannot smuggle its own `aps` in and overwrite the alert.
    #[test]
    fn a_payload_cannot_replace_the_aps_dictionary() {
        let payload = json!({ "aps": { "alert": "hijacked" }, "keep": 1 });
        let message = alert_payload("Real", "Body", &payload, None);
        assert_eq!(message["aps"]["alert"]["title"], "Real");
        assert_eq!(message["keep"], 1);
    }

    /// Apple caps the collapse id at 64 bytes. Truncating at byte 64 would
    /// panic when that byte falls inside a character — a club with an emoji
    /// in its name would have taken the whole push thread down.
    #[test]
    fn a_long_collapse_id_is_cut_on_a_character_boundary() {
        let emoji = "🏏".repeat(40); // 4 bytes each: 160
        let cut = collapse_id(Some(&emoji)).expect("something survives");
        assert!(cut.len() <= 64, "{} bytes", cut.len());
        assert!(emoji.starts_with(cut));
        // The proof it did not slice mid-character: it is still valid UTF-8
        // made of whole cricket balls.
        assert_eq!(cut.chars().count(), 16);
    }

    #[test]
    fn a_short_collapse_id_is_left_alone() {
        assert_eq!(collapse_id(Some("motm_vote_open")), Some("motm_vote_open"));
        assert_eq!(collapse_id(None), None);
        assert_eq!(collapse_id(Some("")), None);
    }

    /// A token APNs says is gone gets deleted. Anything else is this attempt
    /// failing — APNs being down must not unsubscribe a club from its own
    /// notifications.
    #[test]
    fn only_a_dead_token_is_thrown_away() {
        assert!(matches!(classify(410, "Unregistered"), PushOutcome::Gone));
        assert!(matches!(classify(400, "BadDeviceToken"), PushOutcome::Gone));
        assert!(matches!(
            classify(400, "DeviceTokenNotForTopic"),
            PushOutcome::Gone
        ));

        assert!(matches!(classify(503, "ServiceUnavailable"), PushOutcome::Failed(_)));
        assert!(matches!(classify(429, "TooManyRequests"), PushOutcome::Failed(_)));
        // A bad provider token is *our* problem, not the device's. Deleting
        // every row on a misconfigured key would be a very bad afternoon.
        assert!(matches!(classify(403, "InvalidProviderToken"), PushOutcome::Failed(_)));
    }

    /// The failure a human reads has to name the status and the reason.
    #[test]
    fn a_failure_says_what_apns_said() {
        let PushOutcome::Failed(message) = classify(403, "ExpiredProviderToken") else {
            panic!("a 403 is not a dead token");
        };
        assert!(message.contains("403"), "{message}");
        assert!(message.contains("ExpiredProviderToken"), "{message}");
    }

    #[test]
    fn a_reason_is_read_out_of_apnss_json_or_kept_whole() {
        assert_eq!(reason_from(Some(r#"{"reason":"BadDeviceToken"}"#.into())), "BadDeviceToken");
        // Not JSON — worth keeping verbatim rather than discarding.
        assert_eq!(reason_from(Some("502 Bad Gateway".into())), "502 Bad Gateway");
        assert_eq!(reason_from(None), "");
    }

    /// A key is a key however the secret store mangled it on the way in.
    #[test]
    fn a_p8_is_recognised_in_every_shape_it_arrives_in() {
        // Not a real key — the shape is what is under test, not the maths.
        let pem = "-----BEGIN PRIVATE KEY-----\nMIGHAgEA\n-----END PRIVATE KEY-----";

        // Straight from `cat AuthKey_XXX.p8`.
        assert_eq!(normalise_key(pem), pem);

        // Out of a .env file, which cannot hold a newline.
        let escaped = pem.replace('\n', "\\n");
        assert_eq!(normalise_key(&escaped), pem);

        // Base64 of the whole file — how this repo already stores the App
        // Store Connect key, because secret UIs mangle multi-line values.
        let encoded = base64::engine::general_purpose::STANDARD.encode(pem);
        assert_eq!(normalise_key(&encoded), pem);

        // Base64 that a text box wrapped, and one a UI quoted.
        let wrapped = encoded
            .as_bytes()
            .chunks(20)
            .map(|c| String::from_utf8_lossy(c).to_string())
            .collect::<Vec<_>>()
            .join("\n");
        assert_eq!(normalise_key(&wrapped), pem);
        assert_eq!(normalise_key(&format!("\"{encoded}\"")), pem);
    }

    /// Something that is not a key at all is handed back untouched, so the
    /// parse fails with the key's own error rather than one invented here.
    #[test]
    fn junk_is_left_for_the_parser_to_reject() {
        assert_eq!(normalise_key("not a key"), "not a key");
        // Valid base64 of something that is not a PEM.
        let noise = base64::engine::general_purpose::STANDARD.encode("hello");
        assert_eq!(normalise_key(&noise), noise);
    }

    /// Unconfigured is a normal state: the bell still fills up and the phone
    /// stays quiet, rather than the server erroring on every notification.
    #[test]
    fn an_unconfigured_service_is_quiet_rather_than_broken() {
        let service = ApnsService {
            key_id: String::new(),
            team_id: String::new(),
            bundle_id: "com.fishers.app".into(),
            host: SANDBOX,
            key: None,
            token: Arc::new(RwLock::new(None)),
            client: reqwest::Client::new(),
        };
        assert!(!service.is_configured());
        // And it never leaks the key material into a log line.
        assert!(!format!("{service:?}").contains("key_id"));
    }
}
