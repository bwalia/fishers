//! Stripe payment integration.
//!
//! `create_payment_intent` calls Stripe when a secret key is configured, and
//! falls back to a stub when one is not — which is how local development and
//! CI run, and the only reason the stub still exists. Webhook *verification* is
//! never stubbed: an unsigned webhook is how someone marks their own fee paid.
//!
//! **The platform account is the merchant of record here.** Money lands in the
//! Fishers Stripe account, not the club's. Paying it on to clubs is Stripe
//! Connect and a different shape: `destination` / `on_behalf_of` on the intent,
//! a `connected_account_id` on the club, and an FCA position worth confirming
//! before it is switched on. The call below is deliberately one function, so
//! that change lands in one place.

use fishers_domain::{CreatePaymentIntentRequest, PaymentIntentResponse, PaymentStatus};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use tracing::{info, warn};
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

/// Stripe rejects signatures older than this; so do we, so a captured webhook
/// cannot be replayed tomorrow.
const MAX_SIGNATURE_AGE_SECS: i64 = 300;

const PAYMENT_INTENTS_URL: &str = "https://api.stripe.com/v1/payment_intents";

/// Stripe is in the request path of somebody tapping Pay. It answers in well
/// under a second normally; past this the caller gets an error they can retry
/// rather than a spinner that never ends.
const STRIPE_TIMEOUT_SECS: u64 = 15;

#[derive(Debug, Clone, Default)]
pub struct StripeClient {
    pub secret_key: Option<String>,
    webhook_secret: Option<String>,
    http: reqwest::Client,
}

#[derive(Debug, PartialEq, Eq)]
pub enum WebhookVerification {
    Ok,
    /// No webhook secret configured. Allowed only when the caller decides local
    /// development is acceptable — never in production.
    Unconfigured,
    BadSignature(&'static str),
}

impl StripeClient {
    pub fn from_env() -> Self {
        let webhook_secret = std::env::var("STRIPE_WEBHOOK_SECRET")
            .ok()
            .filter(|s| !s.is_empty());
        if webhook_secret.is_none() {
            warn!("STRIPE_WEBHOOK_SECRET unset — payment webhooks will be refused");
        }
        Self {
            secret_key: std::env::var("STRIPE_SECRET_KEY")
                .ok()
                .filter(|s| !s.is_empty()),
            webhook_secret,
            ..Self::default()
        }
    }

    pub fn is_configured(&self) -> bool {
        self.secret_key.is_some()
    }

    /// Open a payment at Stripe and hand back the client secret the app needs
    /// to confirm it.
    ///
    /// Our own payment id goes into the intent's metadata *and* is used as the
    /// idempotency key. The metadata is what the webhook reads to know which
    /// row it is settling; the idempotency key is what stops a double tap, or a
    /// retried request, opening a second payment for the same thing — Stripe
    /// returns the original intent instead of creating another.
    pub async fn create_payment_intent(
        &self,
        payment_id: Uuid,
        req: &CreatePaymentIntentRequest,
    ) -> anyhow::Result<PaymentIntentResponse> {
        let currency = req
            .currency
            .clone()
            .unwrap_or_else(|| "GBP".to_string())
            .to_lowercase();

        let Some(key) = self.secret_key.as_deref() else {
            // No key: local development and CI. Nothing is charged, and the
            // stub secret is obviously not a real one to anybody reading a log.
            info!(
                payment_id = %payment_id,
                amount = req.amount_cents,
                "STRIPE_SECRET_KEY unset — issuing a stub payment intent, nothing will be charged"
            );
            return Ok(PaymentIntentResponse {
                payment_id,
                client_secret: format!("pi_stub_{payment_id}_secret_stub"),
                intent_id: format!("pi_stub_{payment_id}"),
                amount_cents: req.amount_cents,
                currency,
                status: PaymentStatus::Pending,
            });
        };

        let amount = req.amount_cents.to_string();
        let reference = payment_id.to_string();
        let form = [
            ("amount", amount.as_str()),
            ("currency", currency.as_str()),
            // Let Stripe decide which methods to offer from the dashboard
            // rather than pinning the list in code and shipping to change it.
            ("automatic_payment_methods[enabled]", "true"),
            ("metadata[fishers_payment_id]", reference.as_str()),
        ];

        let response = self
            .http
            .post(PAYMENT_INTENTS_URL)
            .bearer_auth(key)
            .header("Idempotency-Key", reference.as_str())
            .timeout(std::time::Duration::from_secs(STRIPE_TIMEOUT_SECS))
            .form(&form)
            .send()
            .await?;

        let status = response.status();
        let body = response.text().await?;
        if !status.is_success() {
            // Stripe's message is safe to log; it describes the request, not
            // the key. The key never appears in an error body.
            warn!(%payment_id, %status, "Stripe refused a payment intent");
            anyhow::bail!("Stripe rejected the payment ({status}): {}", stripe_error(&body));
        }

        let intent: StripeIntent = serde_json::from_str(&body)?;
        let client_secret = intent
            .client_secret
            .ok_or_else(|| anyhow::anyhow!("Stripe returned an intent with no client secret"))?;

        info!(%payment_id, intent = %intent.id, "opened a Stripe payment intent");
        Ok(PaymentIntentResponse {
            payment_id,
            client_secret,
            intent_id: intent.id,
            amount_cents: req.amount_cents,
            currency,
            // Ours, not Stripe's: the money is not ours until the webhook says
            // so, whatever the intent claims at the moment it is created.
            status: PaymentStatus::Pending,
        })
    }

    /// Verify a `Stripe-Signature` header against the raw request body.
    ///
    /// Header shape: `t=1614556800,v1=hex…[,v1=hex…]`. The signed payload is
    /// `"{t}.{body}"`, HMAC-SHA256 with the webhook secret.
    pub fn verify_webhook_signature(
        &self,
        payload: &[u8],
        signature_header: &str,
        now_unix: i64,
    ) -> WebhookVerification {
        let Some(secret) = self.webhook_secret.as_deref() else {
            return WebhookVerification::Unconfigured;
        };

        let mut timestamp: Option<i64> = None;
        let mut candidates: Vec<&str> = Vec::new();
        for part in signature_header.split(',') {
            match part.trim().split_once('=') {
                Some(("t", value)) => timestamp = value.parse().ok(),
                Some(("v1", value)) => candidates.push(value),
                _ => {}
            }
        }

        let Some(timestamp) = timestamp else {
            return WebhookVerification::BadSignature("no timestamp in signature header");
        };
        if (now_unix - timestamp).abs() > MAX_SIGNATURE_AGE_SECS {
            return WebhookVerification::BadSignature("signature timestamp is outside the window");
        }
        if candidates.is_empty() {
            return WebhookVerification::BadSignature("no v1 signature in header");
        }

        let mut mac = match HmacSha256::new_from_slice(secret.as_bytes()) {
            Ok(mac) => mac,
            Err(_) => return WebhookVerification::BadSignature("unusable webhook secret"),
        };
        mac.update(timestamp.to_string().as_bytes());
        mac.update(b".");
        mac.update(payload);
        let expected = mac.finalize().into_bytes();

        for candidate in candidates {
            if let Ok(bytes) = hex::decode(candidate) {
                // `ct_eq` via the MAC type: constant time, no early return.
                if bytes.len() == expected.len()
                    && bytes
                        .iter()
                        .zip(expected.iter())
                        .fold(0u8, |acc, (a, b)| acc | (a ^ b))
                        == 0
                {
                    return WebhookVerification::Ok;
                }
            }
        }
        WebhookVerification::BadSignature("signature did not match")
    }
}

/// The three fields we read back. Stripe sends a great deal more.
#[derive(serde::Deserialize)]
struct StripeIntent {
    id: String,
    client_secret: Option<String>,
}

/// Stripe's own words for what went wrong, for the log and the error we raise.
fn stripe_error(body: &str) -> String {
    serde_json::from_str::<serde_json::Value>(body)
        .ok()
        .and_then(|v| {
            v.get("error")
                .and_then(|e| e.get("message"))
                .and_then(|m| m.as_str())
                .map(str::to_string)
        })
        .unwrap_or_else(|| "no reason given".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn signed(secret: &str, timestamp: i64, body: &[u8]) -> String {
        let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
        mac.update(timestamp.to_string().as_bytes());
        mac.update(b".");
        mac.update(body);
        format!("t={timestamp},v1={}", hex::encode(mac.finalize().into_bytes()))
    }

    fn client(secret: Option<&str>) -> StripeClient {
        StripeClient {
            secret_key: None,
            webhook_secret: secret.map(str::to_string),
            ..StripeClient::default()
        }
    }

    #[test]
    fn a_correct_signature_verifies() {
        let body = br#"{"id":"evt_1","type":"payment_intent.succeeded"}"#;
        let header = signed("whsec_test", 1_700_000_000, body);
        assert_eq!(
            client(Some("whsec_test")).verify_webhook_signature(body, &header, 1_700_000_010),
            WebhookVerification::Ok
        );
    }

    #[test]
    fn a_tampered_body_does_not_verify() {
        let body = br#"{"amount":100}"#;
        let header = signed("whsec_test", 1_700_000_000, body);
        let tampered = br#"{"amount":999}"#;
        assert!(matches!(
            client(Some("whsec_test")).verify_webhook_signature(tampered, &header, 1_700_000_010),
            WebhookVerification::BadSignature(_)
        ));
    }

    #[test]
    fn another_secret_does_not_verify() {
        let body = br#"{"amount":100}"#;
        let header = signed("whsec_attacker", 1_700_000_000, body);
        assert!(matches!(
            client(Some("whsec_test")).verify_webhook_signature(body, &header, 1_700_000_010),
            WebhookVerification::BadSignature(_)
        ));
    }

    #[test]
    fn a_replayed_signature_expires() {
        let body = br#"{"amount":100}"#;
        let header = signed("whsec_test", 1_700_000_000, body);
        assert!(matches!(
            client(Some("whsec_test")).verify_webhook_signature(body, &header, 1_700_099_999),
            WebhookVerification::BadSignature(_)
        ));
    }

    #[test]
    fn a_missing_secret_is_reported_rather_than_waved_through() {
        assert_eq!(
            client(None).verify_webhook_signature(b"{}", "t=1,v1=aa", 1),
            WebhookVerification::Unconfigured
        );
    }

    #[test]
    fn a_malformed_header_is_rejected() {
        for header in ["", "nonsense", "v1=abcd", "t=notanumber,v1=abcd"] {
            assert!(matches!(
                client(Some("whsec_test")).verify_webhook_signature(b"{}", header, 1_700_000_000),
                WebhookVerification::BadSignature(_)
            ), "accepted {header:?}");
        }
    }
}
