//! Firebase Cloud Messaging, over the HTTP v1 API.
//!
//! The third transport: browsers have Web Push, iPhones have APNs, and
//! Android phones have this. All three are reached the same way from
//! `PushService::send` — one row in `device_tokens` per device, with
//! `platform` saying which.
//!
//! The legacy `fcm.googleapis.com/fcm/send` endpoint with a static server key
//! is gone; v1 wants a short OAuth2 access token minted from a **service
//! account**, which is a different kind of credential from the one older
//! guides describe. The flow is: sign an RS256 JWT with the service account's
//! private key, exchange it at Google's token endpoint for an access token
//! good for an hour, and send that as the bearer.
//!
//! Configuration, all from the environment:
//!
//!   FCM_PROJECT_ID            the Firebase project id, as in the console URL
//!   FCM_SERVICE_ACCOUNT       the service account JSON, whole
//!   FCM_SERVICE_ACCOUNT_PATH  …or a path to it, for a mounted secret
//!
//! Unconfigured is a normal state, exactly as for the other two: the bell
//! still fills up and the phone stays quiet.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::RwLock;
use tracing::{info, warn};

use crate::webpush::PushOutcome;

const TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";

/// Google issues these for an hour. Reminted well inside that, so a clock a
/// little out of step never sends an expired one.
const TOKEN_LIFETIME_SECS: u64 = 45 * 60;

/// The half of a service account JSON that matters here.
#[derive(Debug, Deserialize)]
struct ServiceAccount {
    client_email: String,
    private_key: String,
    #[serde(default)]
    project_id: String,
}

#[derive(Serialize)]
struct Claims {
    iss: String,
    scope: String,
    aud: String,
    iat: u64,
    exp: u64,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
}

#[derive(Clone)]
struct CachedToken {
    token: String,
    issued_at: u64,
}

#[derive(Clone)]
pub struct FcmService {
    project_id: String,
    client_email: String,
    /// `None` when FCM is not configured, which is the usual state locally.
    key: Option<Arc<EncodingKey>>,
    token: Arc<RwLock<Option<CachedToken>>>,
    client: reqwest::Client,
}

impl std::fmt::Debug for FcmService {
    // The signing key must never reach a log line.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FcmService")
            .field("project_id", &self.project_id)
            .field("configured", &self.key.is_some())
            .finish()
    }
}

impl FcmService {
    pub fn from_env() -> Self {
        let var = |k: &str| std::env::var(k).ok().filter(|v| !v.trim().is_empty());

        let raw = var("FCM_SERVICE_ACCOUNT").or_else(|| {
            var("FCM_SERVICE_ACCOUNT_PATH").and_then(|path| match std::fs::read_to_string(&path) {
                Ok(json) => Some(json),
                Err(error) => {
                    warn!(%path, %error, "FCM_SERVICE_ACCOUNT_PATH could not be read — Android push is off");
                    None
                }
            })
        });

        let Some(raw) = raw else {
            info!("FCM_SERVICE_ACCOUNT not set: Android push is off");
            return Self::unconfigured();
        };

        let account: ServiceAccount = match serde_json::from_str(&raw) {
            Ok(account) => account,
            Err(error) => {
                warn!(%error, "FCM_SERVICE_ACCOUNT is not a service account JSON — Android push is off");
                return Self::unconfigured();
            }
        };

        // The project id is in the JSON; the variable is there to override it
        // for a project whose messaging lives apart from its credentials.
        let project_id = var("FCM_PROJECT_ID").unwrap_or_else(|| account.project_id.clone());
        if project_id.is_empty() {
            warn!("neither FCM_PROJECT_ID nor the service account names a project — Android push is off");
            return Self::unconfigured();
        }

        // Parsed once, at boot: a malformed key should fail here, where
        // somebody is watching, rather than on the first notification of a
        // Saturday afternoon. A service account key is RSA, not the EC key
        // APNs uses — the two are not interchangeable.
        let key = match EncodingKey::from_rsa_pem(account.private_key.replace("\\n", "\n").as_bytes())
        {
            Ok(key) => Some(Arc::new(key)),
            Err(error) => {
                warn!(%error, "the service account's private_key is not a usable RSA key — Android push is off");
                None
            }
        };
        if key.is_some() {
            info!(project_id, "Android push on");
        }

        Self {
            project_id,
            client_email: account.client_email,
            key,
            token: Arc::new(RwLock::new(None)),
            client: reqwest::Client::new(),
        }
    }

    fn unconfigured() -> Self {
        Self {
            project_id: String::new(),
            client_email: String::new(),
            key: None,
            token: Arc::new(RwLock::new(None)),
            client: reqwest::Client::new(),
        }
    }

    pub fn is_configured(&self) -> bool {
        self.key.is_some()
    }

    /// An access token, minted on demand and reused until it ages out.
    async fn bearer(&self) -> Option<String> {
        let key = self.key.as_ref()?;
        let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();

        if let Some(cached) = self.token.read().await.as_ref() {
            if now.saturating_sub(cached.issued_at) < TOKEN_LIFETIME_SECS {
                return Some(cached.token.clone());
            }
        }

        let claims = Claims {
            iss: self.client_email.clone(),
            scope: SCOPE.to_string(),
            aud: TOKEN_URL.to_string(),
            iat: now,
            exp: now + 3600,
        };
        let assertion = match jsonwebtoken::encode(&Header::new(Algorithm::RS256), &claims, key) {
            Ok(jwt) => jwt,
            Err(error) => {
                warn!(%error, "could not sign the FCM assertion");
                return None;
            }
        };

        let response = self
            .client
            .post(TOKEN_URL)
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", &assertion),
            ])
            .send()
            .await;
        let token = match response {
            Ok(response) if response.status().is_success() => {
                match response.json::<TokenResponse>().await {
                    Ok(body) => body.access_token,
                    Err(error) => {
                        warn!(%error, "Google's token response was not readable");
                        return None;
                    }
                }
            }
            Ok(response) => {
                let status = response.status();
                let body = response.text().await.unwrap_or_default();
                warn!(%status, %body, "Google refused the FCM assertion");
                return None;
            }
            Err(error) => {
                warn!(%error, "could not reach Google's token endpoint");
                return None;
            }
        };

        *self.token.write().await = Some(CachedToken {
            token: token.clone(),
            issued_at: now,
        });
        Some(token)
    }

    /// Send one notification to one device.
    pub async fn send(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        payload: &Value,
        collapse: Option<&str>,
    ) -> PushOutcome {
        // Two different failures, and saying the wrong one sends whoever is
        // reading the log to the wrong place. "Not configured" is a server
        // with no service account; everything else is a server that has one
        // and could not turn it into an access token — a revoked key, a
        // clock out of step, Google unreachable.
        let Some(bearer) = self.bearer().await else {
            return PushOutcome::Failed(
                if self.is_configured() {
                    "FCM is configured but Google would not issue an access token — see the \
                     warning above for what it said"
                } else {
                    "FCM is not configured"
                }
                .into(),
            );
        };

        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            self.project_id
        );
        let message = json!({ "message": message_for(device_token, title, body, payload, collapse) });

        let response = match self
            .client
            .post(&url)
            .bearer_auth(bearer)
            .json(&message)
            .send()
            .await
        {
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

/// The `message` FCM is sent.
///
/// `data` is where the app's own keys go, and FCM only carries strings there
/// — a number or a null in the payload would be refused as INVALID_ARGUMENT,
/// taking the whole notification with it. Everything is stringified rather
/// than dropped, so a tap still has the ids it needs to route.
fn message_for(
    device_token: &str,
    title: &str,
    body: &str,
    payload: &Value,
    collapse: Option<&str>,
) -> Value {
    let mut data = serde_json::Map::new();
    if let Some(object) = payload.as_object() {
        for (key, value) in object {
            let text = match value {
                Value::String(s) => s.clone(),
                Value::Null => continue,
                other => other.to_string(),
            };
            data.insert(key.clone(), Value::String(text));
        }
    }

    let mut message = json!({
        "token": device_token,
        "notification": { "title": title, "body": body },
        "data": Value::Object(data),
        "android": {
            // The club cares about the match that just finished, not about
            // one that finished an hour ago: a notification that arrives
            // after the vote has closed is worse than none.
            "ttl": "172800s",
            "priority": "high",
            "notification": { "default_sound": true },
        }
    });

    // FCM replaces an earlier unread notification with the same collapse key
    // rather than stacking a second: five people voting is one notification.
    if let (Some(collapse), Some(android)) = (
        collapse.filter(|c| !c.is_empty()),
        message["android"].as_object_mut(),
    ) {
        android.insert("collapse_key".into(), Value::String(collapse.to_string()));
    }
    message
}

/// FCM answers a refusal as `{"error": {"status": "...", "message": "..."}}`.
/// Anything else it sends is kept whole — an unrecognised body is the thing
/// worth reading in a log.
fn reason_from(body: Option<String>) -> String {
    let Some(body) = body else {
        return String::new();
    };
    let Ok(parsed) = serde_json::from_str::<Value>(&body) else {
        return body;
    };
    let error = &parsed["error"];
    match (error["status"].as_str(), error["message"].as_str()) {
        (Some(status), Some(message)) => format!("{status}: {message}"),
        (Some(status), None) => status.to_string(),
        (None, Some(message)) => message.to_string(),
        _ => body,
    }
}

/// Whether this token is worth keeping.
///
/// `UNREGISTERED` and `NOT_FOUND` mean the app was uninstalled or the token
/// rotated — the row should go. `INVALID_ARGUMENT` is ambiguous in FCM: it is
/// both "that token is nonsense" and "your payload is wrong", and the second
/// is our bug. It is treated as a failure rather than a dead token, because
/// deleting every row on a malformed payload would unsubscribe a whole club
/// for a mistake on this side.
fn classify(status: u16, reason: &str) -> PushOutcome {
    let dead = reason.contains("UNREGISTERED")
        || reason.contains("NOT_FOUND")
        || status == 404;
    if dead {
        PushOutcome::Gone
    } else {
        PushOutcome::Failed(format!("FCM {status}: {reason}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_app_keys_ride_in_data_as_strings() {
        let payload = json!({
            "conversation_id": "abc",
            "motm_poll_id": "def",
            "url": "/chat/abc",
        });
        let message = message_for("tok", "Man of the match", "Vote now", &payload, None);

        assert_eq!(message["token"], "tok");
        assert_eq!(message["notification"]["title"], "Man of the match");
        assert_eq!(message["data"]["conversation_id"], "abc");
        assert_eq!(message["data"]["url"], "/chat/abc");
    }

    /// FCM's `data` carries strings and nothing else. A number left as a
    /// number is INVALID_ARGUMENT, which fails the whole notification.
    #[test]
    fn a_number_in_the_payload_is_stringified_rather_than_sent_raw() {
        let payload = json!({ "votes": 3, "winner_user_id": null, "ok": true });
        let message = message_for("tok", "T", "B", &payload, None);

        assert_eq!(message["data"]["votes"], "3");
        assert_eq!(message["data"]["ok"], "true");
        // A null has nothing to say and is left out rather than sent as "null".
        assert!(message["data"].get("winner_user_id").is_none());
        for (_, value) in message["data"].as_object().unwrap() {
            assert!(value.is_string(), "every data value must be a string");
        }
    }

    #[test]
    fn a_collapse_key_is_set_only_when_there_is_one() {
        let with = message_for("tok", "T", "B", &json!({}), Some("motm_vote_open"));
        assert_eq!(with["android"]["collapse_key"], "motm_vote_open");

        let without = message_for("tok", "T", "B", &json!({}), None);
        assert!(without["android"].get("collapse_key").is_none());
        // An empty tag is not a collapse key.
        let empty = message_for("tok", "T", "B", &json!({}), Some(""));
        assert!(empty["android"].get("collapse_key").is_none());
    }

    /// A token FCM says is gone gets deleted. Anything else is this attempt
    /// failing — including INVALID_ARGUMENT, which is usually our payload.
    #[test]
    fn only_a_dead_token_is_thrown_away() {
        assert!(matches!(
            classify(404, "NOT_FOUND: Requested entity was not found."),
            PushOutcome::Gone
        ));
        assert!(matches!(
            classify(400, "UNREGISTERED: the token is no longer valid"),
            PushOutcome::Gone
        ));

        assert!(matches!(classify(503, "UNAVAILABLE"), PushOutcome::Failed(_)));
        assert!(matches!(classify(429, "QUOTA_EXCEEDED"), PushOutcome::Failed(_)));
        // Our payload, not their device — deleting every row would be bad.
        assert!(matches!(
            classify(400, "INVALID_ARGUMENT: Invalid value at 'message.data'"),
            PushOutcome::Failed(_)
        ));
        // Our credentials, not their device.
        assert!(matches!(classify(401, "UNAUTHENTICATED"), PushOutcome::Failed(_)));
    }

    #[test]
    fn a_reason_is_read_out_of_fcms_json_or_kept_whole() {
        assert_eq!(
            reason_from(Some(
                r#"{"error":{"status":"UNREGISTERED","message":"token expired"}}"#.into()
            )),
            "UNREGISTERED: token expired"
        );
        assert_eq!(reason_from(Some("502 Bad Gateway".into())), "502 Bad Gateway");
        assert_eq!(reason_from(None), "");
    }

    /// Unconfigured is a normal state, and never leaks the key material.
    #[test]
    fn an_unconfigured_service_is_quiet_rather_than_broken() {
        let service = FcmService::unconfigured();
        assert!(!service.is_configured());
        assert!(!format!("{service:?}").contains("private_key"));
    }
}
