//! Push and email delivery.
//!
//! Browser push is real (see `webpush`); APNs is still a stub.

pub mod webpush;
pub mod whatsapp;

use lettre::message::header::ContentType;
use lettre::message::{Mailbox, MultiPart};
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor};
use serde_json::Value;
use tracing::{info, warn};
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
        let url = payload.get("url").and_then(Value::as_str);
        let tag = payload.get("tag").and_then(Value::as_str);

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
            match self.web.send(&subscription, title, body, url, tag).await {
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

/// Email over SMTP: verification codes, selection reconfirmations, fee
/// reminders.
///
/// Configured entirely from the environment (the vault, in the cluster):
///
///   SMTP_HOST      smtp.gmail.com — unset means email is off
///   SMTP_PORT      587 (default)
///   SMTP_TLS       starttls (default) | tls (implicit, port 465) | none (a local catcher)
///   SMTP_USERNAME  the Gmail address
///   SMTP_PASSWORD  a Gmail *app password*; the account password is refused
///   EMAIL_FROM     "Fishers <address>"; defaults to SMTP_USERNAME, which is
///                  what Gmail will stamp on it anyway unless an alias is set up
///
/// Never logs a message body: a verification code is in there.
#[derive(Clone)]
pub struct EmailService {
    pub from_address: String,
    transport: Option<AsyncSmtpTransport<Tokio1Executor>>,
}

impl std::fmt::Debug for EmailService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EmailService")
            .field("from_address", &self.from_address)
            .field("enabled", &self.enabled())
            .finish()
    }
}

impl Default for EmailService {
    fn default() -> Self {
        Self {
            from_address: "Fishers <no-reply@fishers.cloud>".into(),
            transport: None,
        }
    }
}

impl EmailService {
    pub fn from_env() -> Self {
        let var = |k: &str| std::env::var(k).ok().filter(|v| !v.trim().is_empty());
        let Some(host) = var("SMTP_HOST") else {
            info!("SMTP_HOST not set: email is off, and so is email verification");
            return Self::default();
        };
        let username = var("SMTP_USERNAME");
        let from_address = var("EMAIL_FROM")
            .or_else(|| username.as_ref().map(|u| format!("Fishers <{u}>")))
            .unwrap_or_else(|| Self::default().from_address);
        let port: u16 = var("SMTP_PORT").and_then(|p| p.parse().ok()).unwrap_or(587);

        let builder = match var("SMTP_TLS").as_deref().unwrap_or("starttls") {
            "tls" => AsyncSmtpTransport::<Tokio1Executor>::relay(&host),
            "none" => Ok(AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(&host)),
            _ => AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&host),
        };
        let mut builder = match builder {
            Ok(b) => b.port(port).timeout(Some(std::time::Duration::from_secs(20))),
            Err(e) => {
                warn!(error = %e, host, "SMTP transport could not be built: email is off");
                return Self::default();
            }
        };
        if let (Some(u), Some(p)) = (username, var("SMTP_PASSWORD")) {
            builder = builder.credentials(Credentials::new(u, p));
        }
        info!(host, port, from = %from_address, "email on");
        Self {
            from_address,
            transport: Some(builder.build()),
        }
    }

    /// Whether mail can actually leave. Verification is only required when
    /// it can: asking for a code that can never arrive locks people out.
    pub fn enabled(&self) -> bool {
        self.transport.is_some()
    }

    /// Plain text.
    pub async fn send(&self, to: &str, subject: &str, body: &str) -> anyhow::Result<()> {
        self.deliver(to, subject, body, None).await
    }

    /// Text and HTML alternatives: HTML for mail apps, text for the rest.
    pub async fn send_html(&self, to: &str, subject: &str, text: &str, html: &str) -> anyhow::Result<()> {
        self.deliver(to, subject, text, Some(html)).await
    }

    async fn deliver(&self, to: &str, subject: &str, text: &str, html: Option<&str>) -> anyhow::Result<()> {
        let Some(transport) = &self.transport else {
            info!(to, subject, "email off: not sent");
            return Ok(());
        };
        let builder = Message::builder()
            .from(self.from_address.parse::<Mailbox>()?)
            .to(to.parse::<Mailbox>()?)
            .subject(subject);
        let message = match html {
            Some(html) => builder.multipart(MultiPart::alternative_plain_html(
                text.to_string(),
                html.to_string(),
            ))?,
            None => builder.header(ContentType::TEXT_PLAIN).body(text.to_string())?,
        };
        transport.send(message).await?;
        info!(to, subject, "email sent");
        Ok(())
    }
}
