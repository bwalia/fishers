//! APNs / push notification service (stub for Phase 3).

use serde_json::Value;
use tracing::info;
use uuid::Uuid;

#[derive(Debug, Clone, Default)]
pub struct PushService {
    pub bundle_id: String,
}

impl PushService {
    pub fn from_env() -> Self {
        Self {
            bundle_id: std::env::var("APNS_BUNDLE_ID")
                .unwrap_or_else(|_| "com.fishers.app".into()),
        }
    }

    pub async fn send(
        &self,
        user_id: Uuid,
        notification_type: &str,
        title: &str,
        body: &str,
        payload: Value,
    ) -> anyhow::Result<()> {
        info!(
            %user_id,
            notification_type,
            title,
            body,
            %payload,
            bundle = %self.bundle_id,
            "push notification stub (wire APNs in phase 3)"
        );
        Ok(())
    }
}

/// Email, used for selection announcements, reconfirmation chases and fee
/// reminders. A stub like `PushService`: swap `send` for SES/SendGrid/SMTP
/// without touching callers.
#[derive(Debug, Clone)]
pub struct EmailService {
    pub from_address: String,
    pub enabled: bool,
}

impl Default for EmailService {
    fn default() -> Self {
        Self {
            from_address: "no-reply@fishers.app".into(),
            enabled: false,
        }
    }
}

impl EmailService {
    pub fn from_env() -> Self {
        let from_address =
            std::env::var("EMAIL_FROM").unwrap_or_else(|_| "no-reply@fishers.app".into());
        // No provider is wired yet; set EMAIL_PROVIDER once one is.
        let enabled = std::env::var("EMAIL_PROVIDER")
            .map(|p| !p.is_empty())
            .unwrap_or(false);
        Self {
            from_address,
            enabled,
        }
    }

    pub async fn send(
        &self,
        to: &str,
        subject: &str,
        body: &str,
    ) -> anyhow::Result<()> {
        info!(
            to,
            subject,
            body,
            from = %self.from_address,
            enabled = self.enabled,
            "email stub (wire a provider to actually send)"
        );
        Ok(())
    }
}
