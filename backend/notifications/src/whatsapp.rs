//! Verification codes over WhatsApp, through Meta's official Cloud API.
//!
//! Not an unofficial gateway: those drive a real phone number through the
//! WhatsApp Web protocol, the number gets banned, and a ban here would stop
//! every phone verification at once. The Cloud API sends an approved
//! "authentication" template, which is what WhatsApp built for one-time codes.
//!
//! Configured from the environment (the vault, in the cluster):
//!
//!   WHATSAPP_TOKEN            a system-user access token — unset means off
//!   WHATSAPP_PHONE_NUMBER_ID  the sending number's id, from WhatsApp Manager
//!   WHATSAPP_TEMPLATE         the approved authentication template (fishers_verification)
//!   WHATSAPP_TEMPLATE_LANG    the language it was approved in (en_GB)
//!   WHATSAPP_DEFAULT_COUNTRY  calling code for numbers typed without one (44)
//!   WHATSAPP_API_VERSION      Graph API version (v23.0)

use anyhow::{bail, Context};
use serde_json::json;
use tracing::info;

#[derive(Debug, Clone)]
struct Config {
    token: String,
    phone_number_id: String,
    template: String,
    lang: String,
    default_country: String,
    api_version: String,
}

#[derive(Debug, Clone, Default)]
pub struct WhatsAppService {
    config: Option<Config>,
    client: reqwest::Client,
}

impl WhatsAppService {
    pub fn from_env() -> Self {
        let var = |k: &str| std::env::var(k).ok().filter(|v| !v.trim().is_empty());
        let config = match (var("WHATSAPP_TOKEN"), var("WHATSAPP_PHONE_NUMBER_ID")) {
            (Some(token), Some(phone_number_id)) => Some(Config {
                token,
                phone_number_id,
                template: var("WHATSAPP_TEMPLATE").unwrap_or_else(|| "fishers_verification".into()),
                lang: var("WHATSAPP_TEMPLATE_LANG").unwrap_or_else(|| "en_GB".into()),
                default_country: var("WHATSAPP_DEFAULT_COUNTRY").unwrap_or_else(|| "44".into()),
                api_version: var("WHATSAPP_API_VERSION").unwrap_or_else(|| "v23.0".into()),
            }),
            _ => None,
        };
        info!(enabled = config.is_some(), "whatsapp verification");
        Self {
            config,
            client: reqwest::Client::new(),
        }
    }

    pub fn enabled(&self) -> bool {
        self.config.is_some()
    }

    /// The number as WhatsApp wants it, or None if it cannot be one.
    pub fn normalize(&self, raw: &str) -> Option<String> {
        let cc = self
            .config
            .as_ref()
            .map_or("44", |c| c.default_country.as_str());
        normalize_msisdn(raw, cc)
    }

    /// Sends the code. An authentication template carries it twice: once in
    /// the body, once behind the copy-code button — Meta rejects the message
    /// if the button parameter is missing.
    pub async fn send_code(&self, to: &str, code: &str) -> anyhow::Result<()> {
        let Some(c) = &self.config else {
            bail!("WhatsApp verification is not configured");
        };
        let to = self
            .normalize(to)
            .context("not a phone number WhatsApp can reach")?;
        let url = format!(
            "https://graph.facebook.com/{}/{}/messages",
            c.api_version, c.phone_number_id
        );
        let body = json!({
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": to,
            "type": "template",
            "template": {
                "name": c.template,
                "language": { "code": c.lang },
                "components": [
                    { "type": "body", "parameters": [{ "type": "text", "text": code }] },
                    { "type": "button", "sub_type": "url", "index": "0",
                      "parameters": [{ "type": "text", "text": code }] }
                ]
            }
        });
        let resp = self
            .client
            .post(url)
            .bearer_auth(&c.token)
            .timeout(std::time::Duration::from_secs(20))
            .json(&body)
            .send()
            .await?;
        if !resp.status().is_success() {
            // Meta's error body names the problem (unapproved template, bad
            // number, expired token). It never contains the code.
            let status = resp.status();
            let detail = resp.text().await.unwrap_or_default();
            bail!("WhatsApp Cloud API {status}: {detail}");
        }
        info!("whatsapp verification code sent");
        Ok(())
    }
}

/// Digits with the country code, no `+`: what the Cloud API takes as `to`.
///
/// People type numbers every way there is. `+44 7700 900123`, `0044…` and a
/// UK `07700 900123` all mean the same number; a leading 0 is a national
/// number, so it gets `default_country` in place of the 0.
pub fn normalize_msisdn(raw: &str, default_country: &str) -> Option<String> {
    let trimmed = raw.trim();
    let digits: String = trimmed.chars().filter(char::is_ascii_digit).collect();
    let full = if trimmed.starts_with('+') {
        digits
    } else if let Some(rest) = digits.strip_prefix("00") {
        rest.to_string()
    } else if let Some(rest) = digits.strip_prefix('0') {
        format!("{default_country}{rest}")
    } else {
        digits
    };
    // E.164 caps a number at 15 digits; nothing real is shorter than 8.
    (8..=15).contains(&full.len()).then_some(full)
}

#[cfg(test)]
mod tests {
    use super::normalize_msisdn;

    #[test]
    fn every_way_of_typing_a_uk_mobile_is_the_same_number() {
        for typed in [
            "+44 7700 900123",
            "0044 7700 900123",
            "07700 900123",
            "(07700) 900-123",
            "447700900123",
        ] {
            assert_eq!(
                normalize_msisdn(typed, "44").as_deref(),
                Some("447700900123"),
                "{typed}"
            );
        }
    }

    #[test]
    fn a_national_number_takes_the_configured_country() {
        assert_eq!(
            normalize_msisdn("098765 43210", "91").as_deref(),
            Some("919876543210")
        );
    }

    #[test]
    fn junk_is_refused_rather_than_sent() {
        assert_eq!(normalize_msisdn("123", "44"), None);
        assert_eq!(normalize_msisdn("", "44"), None);
        assert_eq!(normalize_msisdn("+1234567890123456", "44"), None);
    }
}
