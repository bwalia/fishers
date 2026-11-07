//! Which app this API is: the name, colour and addresses its email carries.
//!
//! Every brand runs the same image in its own namespace, so the brand reaches
//! the API as environment, generated from `brands/<id>.yaml` by tools/brand.
//! Unset means Fishers — which is what every email said before this existed,
//! and why a Gully Cricket player was sent a code "from FISHERS".

/// Escape text for an HTML body.
pub fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

#[derive(Debug, Clone)]
pub struct Brand {
    /// "Gully Cricket".
    pub name: String,
    /// A colour that carries white text: headers and buttons.
    pub colour: String,
    /// A pale tint of it: panels and code boxes.
    pub tint: String,
    pub support_email: String,
    /// "https://www.gullycricket.app", for links in email.
    pub web_base: String,
}

impl Default for Brand {
    fn default() -> Self {
        Brand {
            name: "Fishers".into(),
            colour: "#556754".into(),
            tint: "#eef2ea".into(),
            support_email: "hello@fishers.cloud".into(),
            web_base: "https://www.fishers.cloud".into(),
        }
    }
}

impl Brand {
    pub fn from_env() -> Self {
        let var = |k: &str| std::env::var(k).ok().filter(|v| !v.trim().is_empty());
        let d = Brand::default();
        // Only a #rrggbb colour goes into a style attribute.
        let colour = |k: &str, fallback: String| {
            var(k)
                .filter(|c| c.len() == 7 && c.starts_with('#') && c[1..].chars().all(|h| h.is_ascii_hexdigit()))
                .unwrap_or(fallback)
        };
        Brand {
            name: var("BRAND_NAME").unwrap_or(d.name),
            colour: colour("BRAND_COLOR", d.colour),
            tint: colour("BRAND_TINT", d.tint),
            support_email: var("BRAND_SUPPORT_EMAIL").unwrap_or(d.support_email),
            web_base: var("PUBLIC_WEB_BASE")
                .map(|b| b.trim_end_matches('/').to_string())
                .unwrap_or(d.web_base),
        }
    }

    /// The frame every email sits in: the brand's name at the top, the body,
    /// and an optional footer (an unsubscribe line, say). `body` is HTML the
    /// caller has already escaped.
    pub fn email_html(&self, body: &str, footer: Option<&str>) -> String {
        let name = html_escape(&self.name.to_uppercase());
        let colour = &self.colour;
        let footer = footer
            .map(|f| {
                format!(
                    r#"<tr><td style="padding:0 28px 24px;font-size:12px;line-height:1.6;color:#7a847e">{f}</td></tr>"#
                )
            })
            .unwrap_or_default();
        format!(
            r#"<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"></head>
<body style="margin:0;background:#f4f1e8;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1f2a22">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 12px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:14px;border:1px solid #e3ddd0">
<tr><td style="padding:24px 28px 8px;font-size:15px;font-weight:700;letter-spacing:.08em;color:{colour}">{name}</td></tr>
{body}
{footer}
</table></td></tr></table></body></html>"#
        )
    }

    /// A one-time code, in the brand's colours.
    pub fn code_email_html(&self, intro: &str, code: &str, after: &str) -> String {
        let body = format!(
            r#"<tr><td style="padding:8px 28px;font-size:15px;line-height:1.6">{intro}</td></tr>
<tr><td style="padding:12px 28px"><div style="font-size:34px;font-weight:700;letter-spacing:.3em;background:{tint};border-radius:10px;padding:16px 0;text-align:center;color:{colour}">{code}</div></td></tr>
<tr><td style="padding:8px 28px 28px;font-size:13px;line-height:1.6;color:#5b6660">{after}</td></tr>"#,
            intro = intro,
            code = html_escape(code),
            after = after,
            tint = self.tint,
            colour = self.colour,
        );
        self.email_html(&body, None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_colour_that_is_not_a_colour_is_not_used() {
        std::env::set_var("BRAND_COLOR", "red;background:url(x)");
        std::env::set_var("BRAND_NAME", "Gully Cricket");
        let b = Brand::from_env();
        assert_eq!(b.colour, Brand::default().colour);
        assert_eq!(b.name, "Gully Cricket");
        assert!(b.email_html("", None).contains("GULLY CRICKET"));
        std::env::remove_var("BRAND_COLOR");
        std::env::remove_var("BRAND_NAME");
    }
}
