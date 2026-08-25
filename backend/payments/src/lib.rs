//! Stripe payment integration (stub for Phase 4 — swap for real Stripe SDK calls).

use fishers_domain::{CreatePaymentIntentRequest, PaymentIntentResponse, PaymentStatus};
use tracing::info;
use uuid::Uuid;

#[derive(Debug, Clone, Default)]
pub struct StripeClient {
    pub secret_key: Option<String>,
}

impl StripeClient {
    pub fn from_env() -> Self {
        Self {
            secret_key: std::env::var("STRIPE_SECRET_KEY").ok().filter(|s| !s.is_empty()),
        }
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

        // Stub: real implementation calls Stripe PaymentIntents API.
        let fake_secret = format!("pi_stub_{payment_id}_secret_stub");
        info!(
            payment_id = %payment_id,
            amount = req.amount_cents,
            configured = self.secret_key.is_some(),
            "created stub payment intent"
        );

        Ok(PaymentIntentResponse {
            payment_id,
            client_secret: fake_secret,
            amount_cents: req.amount_cents,
            currency,
            status: PaymentStatus::Pending,
        })
    }

    pub fn verify_webhook_signature(&self, _payload: &[u8], _sig: &str) -> bool {
        // Stub — always accept in local/dev when no webhook secret is set.
        std::env::var("STRIPE_WEBHOOK_SECRET")
            .ok()
            .filter(|s| !s.is_empty())
            .is_none()
    }
}
