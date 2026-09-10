//! Push and email delivery.
//!
//! Browser push is real (see `webpush`); APNs is still a stub.

pub mod webpush;

use serde_json::Value;
use tracing::info;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct PushService {
    pub bundle_id: String,
    pub web: webpush::WebPushService,
}

impl Default for PushService {
    fn default() -> Self {
        Self {
            bundle_id: "com.fishers.app".into(),
            web: webpush::WebPushService::from_env(),
        }
    }
}

impl PushService {
    pub fn from_env() -> Self {
        Self {
            bundle_id: std::env::var("APNS_BUNDLE_ID")
                .unwrap_or_else(|_| "com.fishers.app".into()),
            web: webpush::WebPushService::from_env(),
        }
    }

    /// Deliver to every device this person has registered.
    ///
    /// Browsers get a real encrypted push; iOS is still a log line until APNs
    /// is wired. A failure to one device never stops the others, and a
    /// subscription the push service says is gone is deleted rather than
    /// retried until the end of time — browsers rotate them on reinstall, so
    /// dead rows accumulate quietly otherwise.
    pub async fn send(
        &self,
        pool: &sqlx::PgPool,
        user_id: Uuid,
        notification_type: &str,
        title: &str,
        body: &str,
        payload: Value,
    ) -> anyhow::Result<()> {
        let devices: Vec<(Uuid, String, String)> = sqlx::query_as(
            "SELECT id, device_token, platform FROM device_tokens WHERE user_id = $1",
        )
        .bind(user_id)
        .fetch_all(pool)
        .await?;

        // A deep link, when the notification is about something in particular.
        let url = payload
            .get("url")
            .and_then(Value::as_str)
            .map(str::to_string);

        let mut dead = Vec::new();
        for (id, token, platform) in devices {
            if platform != "web" {
                info!(%user_id, notification_type, platform, "APNs push stub");
                continue;
            }
            let Ok(subscription) = serde_json::from_str::<webpush::PushSubscription>(&token) else {
                // Not a subscription at all. It will never become one.
                dead.push(id);
                continue;
            };
            match self.web.send(&subscription, title, body, url.as_deref()).await {
                webpush::PushOutcome::Delivered => {}
                webpush::PushOutcome::Gone => dead.push(id),
                webpush::PushOutcome::Failed(error) => {
                    tracing::warn!(%user_id, notification_type, error, "web push failed");
                }
            }
        }

        if !dead.is_empty() {
            sqlx::query("DELETE FROM device_tokens WHERE id = ANY($1)")
                .bind(&dead)
                .execute(pool)
                .await?;
            info!(count = dead.len(), "removed expired push subscriptions");
        }
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
