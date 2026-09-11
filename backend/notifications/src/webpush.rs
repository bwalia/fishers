//! Browser push, over the Web Push protocol.
//!
//! Three standards stacked: RFC 8030 says how to POST to a push service,
//! RFC 8291 says the body must be encrypted so the push service cannot read
//! it, and RFC 8292 (VAPID) says how this server identifies itself. The
//! encryption and the JWT come from `web-push-native`; the HTTP is reqwest,
//! because the workspace is rustls and no part of it links OpenSSL.

use base64::Engine;
use serde::{Deserialize, Serialize};
use web_push_native::{
    jwt_simple::algorithms::ES256KeyPair, p256::PublicKey, Auth, WebPushBuilder,
};

/// What a browser hands over when it subscribes.
///
/// Stored verbatim in `device_tokens.device_token`, because it is opaque to
/// us and the browser is the only thing that can produce another one.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushSubscription {
    pub endpoint: String,
    pub keys: SubscriptionKeys,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubscriptionKeys {
    /// The browser's public key, base64url.
    pub p256dh: String,
    /// A shared secret, base64url.
    pub auth: String,
}

/// Why a push did not arrive — and, crucially, whether to try again.
#[derive(Debug)]
pub enum PushOutcome {
    Delivered,
    /// This subscription can never be pushed to by this server. Browsers
    /// rotate them on reinstall and clear them on "clear site data", so it is
    /// routine rather than exceptional — the row should go, and the browser
    /// makes a fresh one next time somebody opens the app.
    Gone,
    /// Something else. Worth a log, not worth deleting anybody's subscription.
    Failed(String),
}

#[derive(Clone)]
pub struct WebPushService {
    /// `mailto:` or an https URL. Push services use it to contact whoever is
    /// sending, and reject a VAPID JWT without one.
    subject: String,
    /// Private half, for signing. Parsed once at boot so a malformed key
    /// fails there rather than on the first notification. Behind an `Arc`
    /// because the key pair is not `Clone` and this service is shared.
    key: Option<std::sync::Arc<ES256KeyPair>>,
    /// Public half, base64url — handed to the browser so it can subscribe to
    /// *this* server and no other.
    pub public_key: Option<String>,
    client: reqwest::Client,
}

impl std::fmt::Debug for WebPushService {
    // The private key must never reach a log line.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("WebPushService")
            .field("subject", &self.subject)
            .field("configured", &self.key.is_some())
            .finish()
    }
}

const B64: base64::engine::general_purpose::GeneralPurpose =
    base64::engine::general_purpose::URL_SAFE_NO_PAD;

impl WebPushService {
    /// Reads `VAPID_PRIVATE_KEY` and `VAPID_PUBLIC_KEY`, both base64url of the
    /// raw key material, and `VAPID_SUBJECT`.
    ///
    /// Unconfigured is a normal state, not an error: a developer without keys
    /// gets an app where the bell still works and the browser is simply never
    /// offered push. Generate a pair with `scripts/vapid-keys.sh`.
    pub fn from_env() -> Self {
        let subject = std::env::var("VAPID_SUBJECT")
            .unwrap_or_else(|_| "mailto:hello@fishers.cloud".into());

        let key = std::env::var("VAPID_PRIVATE_KEY")
            .ok()
            .filter(|raw| !raw.trim().is_empty())
            .and_then(|raw| match B64.decode(raw.trim()) {
                Ok(bytes) => match ES256KeyPair::from_bytes(&bytes) {
                    Ok(key) => Some(std::sync::Arc::new(key)),
                    Err(error) => {
                        tracing::error!(%error, "VAPID_PRIVATE_KEY is not a P-256 key");
                        None
                    }
                },
                Err(error) => {
                    tracing::error!(%error, "VAPID_PRIVATE_KEY is not base64url");
                    None
                }
            });

        let public_key = std::env::var("VAPID_PUBLIC_KEY")
            .ok()
            .filter(|raw| !raw.trim().is_empty())
            .map(|raw| raw.trim().to_string());

        if key.is_some() != public_key.is_some() {
            tracing::error!(
                "VAPID needs both halves — browsers subscribe with the public key and \
                 the push service verifies the private one. Push is off."
            );
        }

        Self {
            subject,
            key,
            public_key,
            client: reqwest::Client::new(),
        }
    }

    pub fn is_configured(&self) -> bool {
        self.key.is_some() && self.public_key.is_some()
    }

    /// Encrypt one notification and POST it to the browser's push service.
    pub async fn send(
        &self,
        subscription: &PushSubscription,
        title: &str,
        body: &str,
        url: Option<&str>,
        tag: Option<&str>,
    ) -> PushOutcome {
        let Some(key) = self.key.as_ref() else {
            return PushOutcome::Failed("web push is not configured".into());
        };

        let ua_public = match B64
            .decode(&subscription.keys.p256dh)
            .ok()
            .and_then(|raw| PublicKey::from_sec1_bytes(&raw).ok())
        {
            Some(k) => k,
            // A subscription we cannot decode will never work. Treat it as
            // gone so it is cleaned up rather than retried forever.
            None => return PushOutcome::Gone,
        };
        let ua_auth = match B64.decode(&subscription.keys.auth) {
            Ok(raw) if raw.len() == 16 => Auth::clone_from_slice(&raw),
            _ => return PushOutcome::Gone,
        };

        let endpoint = match subscription.endpoint.parse() {
            Ok(uri) => uri,
            Err(_) => return PushOutcome::Gone,
        };

        // The payload the service worker receives. Kept small: push services
        // cap the encrypted body around 4KB, and this only has to be enough
        // to draw a notification and know where it goes.
        let mut payload = serde_json::json!({
            "title": title,
            "body": body,
            "url": url.unwrap_or("/notifications"),
        });
        // What makes two notifications "the same thing", so the newer one
        // replaces the older; without it the service worker goes by the URL.
        if let Some(tag) = tag {
            payload["tag"] = tag.into();
        }
        let payload = payload.to_string();

        let request = match WebPushBuilder::new(endpoint, ua_public, ua_auth)
            .with_vapid(key, &self.subject)
            .build(payload.into_bytes())
        {
            Ok(request) => request,
            Err(error) => return PushOutcome::Failed(error.to_string()),
        };

        let (parts, body) = request.into_parts();
        let mut send = self
            .client
            .post(parts.uri.to_string())
            .body(body)
            .timeout(std::time::Duration::from_secs(10));
        for (name, value) in parts.headers.iter() {
            send = send.header(name.as_str(), value.as_bytes());
        }

        match send.send().await {
            Ok(response) if response.status().is_success() => PushOutcome::Delivered,
            // 404 and 410 mean the subscription is gone. 403 means it was made
            // against different VAPID keys — which happens to *every* existing
            // subscription the moment the keys are rotated, and no amount of
            // retrying will fix it. Without this, one key change leaves every
            // subscriber failing forever and the rows never reaped.
            Ok(response) if retires_subscription(response.status().as_u16()) => {
                PushOutcome::Gone
            }
            Ok(response) => {
                let status = response.status();
                let detail = response.text().await.unwrap_or_default();
                PushOutcome::Failed(format!("{status}: {}", detail.chars().take(200).collect::<String>()))
            }
            Err(error) => PushOutcome::Failed(error.to_string()),
        }
    }
}

/// Statuses after which this subscription will never work again.
///
/// 404 and 410: the push service has forgotten it. 403: it was created
/// against different VAPID keys, which is true of every subscription in
/// existence the moment those keys are rotated. Everything else — rate
/// limits, outages — is worth another go later.
fn retires_subscription(status: u16) -> bool {
    matches!(status, 403 | 404 | 410)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_subscription_round_trips_through_json() {
        // Exactly the shape `PushSubscription.toJSON()` produces in a browser.
        let raw = r#"{
            "endpoint": "https://fcm.googleapis.com/fcm/send/abc123",
            "expirationTime": null,
            "keys": {
              "p256dh": "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM",
              "auth": "tBHItJI5svbpez7KI4CCXg"
            }
        }"#;
        let sub: PushSubscription = serde_json::from_str(raw).expect("browser JSON parses");
        assert!(sub.endpoint.starts_with("https://"));
        assert_eq!(sub.keys.auth.len(), 22);
        // `expirationTime` is present and unused; an unknown field must not
        // break a subscription we would otherwise be able to push to.
        let back = serde_json::to_string(&sub).unwrap();
        assert!(back.contains("p256dh"));
    }

    /// Which HTTP statuses mean "stop trying".
    ///
    /// Rotating the VAPID keys invalidates every subscription already handed
    /// out, and push services answer those with 403. Treating that as a
    /// retryable failure means every notification, forever, tries to reach
    /// subscriptions that can never work.
    #[test]
    fn the_statuses_that_retire_a_subscription() {
        for status in [403u16, 404, 410] {
            assert!(retires_subscription(status), "{status} must retire it");
        }
        for status in [429u16, 500, 502, 503] {
            assert!(!retires_subscription(status), "{status} is worth retrying");
        }
    }

    #[tokio::test]
    async fn an_unconfigured_service_refuses_rather_than_panicking() {
        // The common developer setup: no keys, and nothing should explode.
        let service = WebPushService {
            subject: "mailto:test@example.com".into(),
            key: None,
            public_key: None,
            client: reqwest::Client::new(),
        };
        assert!(!service.is_configured());
        let sub = PushSubscription {
            endpoint: "https://example.com/x".into(),
            keys: SubscriptionKeys { p256dh: "x".into(), auth: "y".into() },
        };
        assert!(matches!(
            service.send(&sub, "t", "b", None, None).await,
            PushOutcome::Failed(_)
        ));
    }

    /// The generator and the parser have to agree, and they are written in
    /// different languages by different people. This pins the contract:
    /// `scripts/vapid-keys.sh` emits base64url of a 32-byte P-256 scalar, and
    /// that is exactly what `from_env` feeds `ES256KeyPair::from_bytes`.
    #[test]
    fn a_key_from_the_generator_script_loads() {
        // Produced by scripts/vapid-keys.sh. A key that is the right *length*
        // but the wrong bytes still fails here, which is the point.
        let generated = std::env::var("FISHERS_TEST_VAPID_PRIVATE")
            .unwrap_or_else(|_| String::new());
        if generated.is_empty() {
            // Nothing to check against in a plain `cargo test`; the shell
            // suite passes one in.
            return;
        }
        let bytes = B64.decode(generated.trim()).expect("base64url");
        assert_eq!(bytes.len(), 32, "a P-256 scalar is 32 bytes");
        ES256KeyPair::from_bytes(&bytes).expect("the script's key must load");
    }

    #[tokio::test]
    async fn a_subscription_with_undecodable_keys_is_gone_not_retried() {
        // Retrying one of these forever is how a queue fills up with rubbish.
        let mut service = WebPushService::from_env();
        service.key = Some(std::sync::Arc::new(ES256KeyPair::generate()));
        service.public_key = Some("stub".into());
        let sub = PushSubscription {
            endpoint: "https://example.com/x".into(),
            keys: SubscriptionKeys { p256dh: "not-base64!!".into(), auth: "also-not".into() },
        };
        assert!(matches!(service.send(&sub, "t", "b", None, None).await, PushOutcome::Gone));
    }
}
