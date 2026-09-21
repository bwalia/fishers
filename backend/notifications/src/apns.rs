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

        let mut message = json!({
            "aps": {
                "alert": { "title": title, "body": body },
                "sound": "default",
                // Lets iOS badge and group them; the app re-reads the real
                // unread count from /notifications when it opens.
                "thread-id": collapse.unwrap_or("fishers"),
            }
        });
        // Custom keys sit beside `aps`, never inside it.
        if let (Some(object), Some(extra)) = (message.as_object_mut(), payload.as_object()) {
            for (key, value) in extra {
                if key != "aps" {
                    object.insert(key.clone(), value.clone());
                }
            }
        }

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
        if let Some(collapse) = collapse {
            // Apple caps this at 64 bytes and rejects anything longer.
            request = request.header("apns-collapse-id", &collapse[..collapse.len().min(64)]);
        }

        let response = match request.send().await {
            Ok(response) => response,
            Err(error) => return PushOutcome::Failed(error.to_string()),
        };

        let status = response.status();
        if status.is_success() {
            return PushOutcome::Delivered;
        }

        let reason = response
            .text()
            .await
            .ok()
            .and_then(|body| {
                serde_json::from_str::<Value>(&body)
                    .ok()
                    .and_then(|v| v.get("reason").and_then(Value::as_str).map(str::to_owned))
                    .or(Some(body))
            })
            .unwrap_or_default();

        // 410 Gone, and 400 BadDeviceToken, both mean this token will never
        // work again — the app was deleted, or the build moved between the
        // sandbox and production environments. Deleting the row is right;
        // retrying it forever is what fills a log with noise.
        let dead = status.as_u16() == 410
            || reason.contains("BadDeviceToken")
            || reason.contains("Unregistered");
        if dead {
            PushOutcome::Gone
        } else {
            PushOutcome::Failed(format!("APNs {status}: {reason}"))
        }
    }
}

fn expiry_in(seconds: u64) -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() + seconds)
        .unwrap_or(0)
}
