//! Stripe payment integration.
//!
//! The API calls are still stubbed — swap `create_payment_intent` for a real
//! Stripe call and nothing else moves. Webhook *verification* is not stubbed:
//! an unsigned webhook is how someone marks their own match fee paid.

use fishers_domain::{CreatePaymentIntentRequest, PaymentIntentResponse, PaymentStatus};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use tracing::{info, warn};
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

/// Stripe rejects signatures older than this; so do we, so a captured webhook
/// cannot be replayed tomorrow.
const MAX_SIGNATURE_AGE_SECS: i64 = 300;

#[derive(Debug, Clone, Default)]
pub struct StripeClient {
    pub secret_key: Option<String>,
    webhook_secret: Option<String>,
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
        }
    }

    pub fn is_configured(&self) -> bool {
        self.secret_key.is_some()
    }

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

        // Stub: a real implementation calls the Stripe PaymentIntents API here.
        let client_secret = format!("pi_stub_{payment_id}_secret_stub");
        info!(
            payment_id = %payment_id,
            amount = req.amount_cents,
            configured = self.secret_key.is_some(),
            "created stub payment intent"
        );

        Ok(PaymentIntentResponse {
            payment_id,
            client_secret,
            amount_cents: req.amount_cents,
            currency,
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
