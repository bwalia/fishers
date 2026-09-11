//! Confirming an email address or a phone number with a one-time code.
//!
//! One flow for both channels: send a six-digit code, confirm it. Codes last
//! ten minutes, allow five guesses, and at most five can be sent an hour — so a
//! six-digit code cannot be brute-forced, and nobody can use this to flood a
//! stranger's inbox or phone.

use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::users as users_repo;
use fishers_db::repos::verification as codes;
use fishers_domain::{PublicUser, User};
use hmac::{Hmac, Mac};
use rand::Rng;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use tracing::warn;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

const TTL_SECS: i64 = 600;
const MAX_ATTEMPTS: i32 = 5;
const RESEND_AFTER_SECS: i64 = 60;
const MAX_PER_HOUR: i64 = 5;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/verification", get(status))
        .route("/me/verification/{channel}", post(send))
        .route("/me/verification/{channel}/confirm", post(confirm))
}

#[derive(Serialize)]
struct ChannelStatus {
    address: Option<String>,
    verified: bool,
    /// Whether this server can send a code on this channel right now.
    available: bool,
}

#[derive(Serialize)]
struct Status {
    /// Whether this server asks for confirmation at all (VERIFICATION_REQUIRED).
    /// The web app shows the confirm step only when it does.
    enabled: bool,
    email: ChannelStatus,
    phone: ChannelStatus,
    /// True when starting a club or accepting an invite will be refused until
    /// one contact is verified. False when nothing is verifiable here, because
    /// requiring a code that can never arrive would lock people out.
    verification_required: bool,
}

async fn status(State(state): State<AppState>, auth: AuthUser) -> ApiResult<Json<Status>> {
    let user = load(&state, auth.user_id).await?;
    Ok(Json(Status {
        enabled: state.verification_required,
        email: ChannelStatus {
            available: user.email.is_some() && state.email.enabled(),
            verified: user.email_verified_at.is_some(),
            address: user.email.clone(),
        },
        phone: ChannelStatus {
            available: user
                .phone
                .as_deref()
                .is_some_and(|p| state.whatsapp.enabled() && state.whatsapp.normalize(p).is_some()),
            verified: user.phone_verified_at.is_some(),
            address: user.phone.clone(),
        },
        verification_required: needs_verifying(&state, &user),
    }))
}

/// Gate for the actions a fake account must not be able to take: starting a
/// club, accepting an invite. Either verified contact will do.
pub async fn require_verified(state: &AppState, user_id: Uuid) -> ApiResult<()> {
    let user = load(state, user_id).await?;
    if needs_verifying(state, &user) {
        return Err(ApiError::forbidden(
            "confirm your email or phone number first — it takes a minute",
        )
        .with_code("unverified"));
    }
    Ok(())
}

fn needs_verifying(state: &AppState, user: &User) -> bool {
    if !state.verification_required {
        return false;
    }
    let verified = user.email_verified_at.is_some() || user.phone_verified_at.is_some();
    let can_verify = (user.email.is_some() && state.email.enabled())
        || (user.phone.is_some() && state.whatsapp.enabled());
    can_verify && !verified
}

#[derive(Serialize)]
pub struct Sent {
    /// Masked, so a screenshot of the screen does not leak the address.
    sent_to: String,
    expires_in: i64,
    resend_after: i64,
}

async fn send(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(channel): Path<String>,
) -> ApiResult<Json<Sent>> {
    let user = load(&state, auth.user_id).await?;
    Ok(Json(issue(&state, &user, channel_of(&channel)?).await?))
}

/// Sends a fresh code. Also used right after signup, so the first email is
/// already on its way by the time the dashboard loads.
pub async fn issue(state: &AppState, user: &User, channel: &'static str) -> ApiResult<Sent> {
    let (target, verified, available) = match channel {
        "email" => (
            user.email.clone(),
            user.email_verified_at.is_some(),
            state.email.enabled(),
        ),
        _ => (
            user.phone.clone(),
            user.phone_verified_at.is_some(),
            state.whatsapp.enabled(),
        ),
    };
    let target = target.ok_or_else(|| {
        ApiError::bad_request(format!("add your {} to your profile first", noun(channel)))
    })?;
    if verified {
        return Err(ApiError::conflict(format!(
            "your {} is already confirmed",
            noun(channel)
        )));
    }
    if !available {
        return Err(ApiError::unavailable(format!(
            "{} codes are not switched on for this server yet",
            if channel == "email" {
                "Email"
            } else {
                "WhatsApp"
            }
        )));
    }
    if channel == "phone" && state.whatsapp.normalize(&target).is_none() {
        return Err(ApiError::bad_request(
            "that does not look like a full phone number — include the country code, e.g. +44 7700 900123",
        ));
    }

    let (sent_this_hour, secs_since_last) =
        codes::recent_sends(&state.pool, user.id, channel, 3600).await?;
    if let Some(secs) = secs_since_last.filter(|s| *s < RESEND_AFTER_SECS) {
        return Err(ApiError::too_many(format!(
            "a code is on its way — you can ask for another in {}s",
            RESEND_AFTER_SECS - secs
        )));
    }
    if sent_this_hour >= MAX_PER_HOUR {
        return Err(ApiError::too_many(
            "too many codes this hour — try again later",
        ));
    }

    let code = format!("{:06}", rand::rngs::OsRng.gen_range(0..1_000_000u32));
    let hash = hash_code(&state.jwt_secret, user.id, channel, &target, &code);
    codes::create(&state.pool, user.id, channel, &target, &hash, TTL_SECS).await?;

    let delivered = match channel {
        "email" => {
            let (text, html) = email_body(&user.name, &code);
            state
                .email
                .send_html(
                    &target,
                    &format!("{code} is your Fishers code"),
                    &text,
                    &html,
                )
                .await
        }
        _ => state.whatsapp.send_code(&target, &code).await,
    };
    if let Err(e) = delivered {
        warn!(error = %e, channel, "verification code not delivered");
        // Leave nothing live that nobody received.
        if let Ok(Some(live)) = codes::active(&state.pool, user.id, channel).await {
            let _ = codes::consume(&state.pool, live.id).await;
        }
        return Err(ApiError {
            status: axum::http::StatusCode::BAD_GATEWAY,
            message: format!(
                "we could not send the code to your {} — try again shortly",
                noun(channel)
            ),
            code: None,
        });
    }

    Ok(Sent {
        sent_to: mask(channel, &target),
        expires_in: TTL_SECS,
        resend_after: RESEND_AFTER_SECS,
    })
}

#[derive(Deserialize)]
struct ConfirmRequest {
    code: String,
}

async fn confirm(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(channel): Path<String>,
    Json(body): Json<ConfirmRequest>,
) -> ApiResult<Json<PublicUser>> {
    let channel = channel_of(&channel)?;
    let code = body.code.trim();
    if code.len() != 6 || !code.bytes().all(|b| b.is_ascii_digit()) {
        return Err(ApiError::bad_request("the code is six digits"));
    }
    let live = codes::active(&state.pool, auth.user_id, channel)
        .await?
        .ok_or_else(|| {
            ApiError::bad_request("that code has expired — send a new one")
                .with_code("code_expired")
        })?;
    if live.attempts >= MAX_ATTEMPTS {
        return Err(
            ApiError::too_many("too many wrong codes — send a new one").with_code("code_expired")
        );
    }
    // Counted before comparing, so a wrong guess is never free.
    codes::record_attempt(&state.pool, live.id).await?;

    let expected = hash_code(&state.jwt_secret, auth.user_id, channel, &live.target, code);
    if !constant_time_eq(expected.as_bytes(), live.code_hash.as_bytes()) {
        let left = MAX_ATTEMPTS - live.attempts - 1;
        return Err(ApiError::bad_request(if left > 0 {
            format!(
                "that code is not right — {left} more tr{}",
                if left == 1 { "y" } else { "ies" }
            )
        } else {
            "that code is not right — send a new one".to_string()
        }));
    }

    codes::consume(&state.pool, live.id).await?;
    if !users_repo::mark_verified(&state.pool, auth.user_id, channel, &live.target).await? {
        return Err(ApiError::conflict(format!(
            "your {} changed after the code was sent — send a new one",
            noun(channel)
        )));
    }
    Ok(Json(load(&state, auth.user_id).await?.into()))
}

async fn load(state: &AppState, user_id: Uuid) -> ApiResult<User> {
    users_repo::find_by_id(&state.pool, user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("user not found"))
}

fn channel_of(raw: &str) -> ApiResult<&'static str> {
    match raw {
        "email" => Ok("email"),
        "phone" => Ok("phone"),
        _ => Err(ApiError::not_found("no such verification channel")),
    }
}

fn noun(channel: &str) -> &'static str {
    if channel == "email" {
        "email address"
    } else {
        "phone number"
    }
}

/// Keyed by the server's secret and bound to the person, channel and address,
/// so a stored hash is useless on its own and cannot be replayed elsewhere.
fn hash_code(secret: &str, user_id: Uuid, channel: &str, target: &str, code: &str) -> String {
    let mut mac = Hmac::<Sha256>::new_from_slice(secret.as_bytes()).expect("any key length");
    mac.update(format!("{user_id}|{channel}|{}|{code}", target.to_lowercase()).as_bytes());
    mac.finalize()
        .into_bytes()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

fn mask(channel: &str, target: &str) -> String {
    if channel == "email" {
        match target.split_once('@') {
            Some((local, domain)) => {
                let first = local.chars().next().unwrap_or('*');
                format!("{first}•••@{domain}")
            }
            None => "your email".into(),
        }
    } else {
        let digits: String = target.chars().filter(char::is_ascii_digit).collect();
        format!("•••• {}", &digits[digits.len().saturating_sub(4)..])
    }
}

fn email_body(name: &str, code: &str) -> (String, String) {
    let first = name.split_whitespace().next().unwrap_or("there");
    let text = format!(
        "Hi {first},\n\nYour Fishers code is:\n\n    {code}\n\nIt expires in 10 minutes. \
         If you did not ask for it, ignore this email — nobody can use it without your password.\n\n— Fishers\n"
    );
    let first = html_escape(first);
    let html = format!(
        r#"<!doctype html><html><body style="margin:0;background:#f4f1e8;font-family:-apple-system,Segoe UI,Roboto,sans-serif;color:#1f2a22">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" style="max-width:460px;background:#ffffff;border-radius:14px;border:1px solid #e3ddd0">
<tr><td style="padding:28px 28px 8px;font-size:15px;font-weight:700;letter-spacing:.08em">FISHERS</td></tr>
<tr><td style="padding:8px 28px;font-size:15px;line-height:1.6">Hi {first}, here is your code:</td></tr>
<tr><td style="padding:12px 28px"><div style="font-size:34px;font-weight:700;letter-spacing:.3em;background:#eef2ea;border-radius:10px;padding:16px 0;text-align:center;color:#2f4a36">{code}</div></td></tr>
<tr><td style="padding:8px 28px 28px;font-size:13px;line-height:1.6;color:#5b6660">It expires in 10 minutes. If you did not ask for it, ignore this email — nobody can use it without your password.</td></tr>
</table></td></tr></table></body></html>"#
    );
    (text, html)
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_code_only_matches_for_the_person_and_address_it_was_sent_to() {
        let u = Uuid::new_v4();
        let h = hash_code("k", u, "email", "a@b.co", "123456");
        assert_eq!(
            h,
            hash_code("k", u, "email", "A@B.co", "123456"),
            "case of the address is not identity"
        );
        assert_ne!(h, hash_code("k", u, "email", "a@b.co", "123457"));
        assert_ne!(
            h,
            hash_code("k", Uuid::new_v4(), "email", "a@b.co", "123456")
        );
        assert_ne!(h, hash_code("k", u, "phone", "a@b.co", "123456"));
        assert_ne!(h, hash_code("k", u, "email", "other@b.co", "123456"));
        assert_ne!(h, hash_code("other-secret", u, "email", "a@b.co", "123456"));
    }

    #[test]
    fn masking_keeps_enough_to_recognise_and_no_more() {
        assert_eq!(mask("email", "jiyona@gmail.com"), "j•••@gmail.com");
        assert_eq!(mask("phone", "+44 7700 900123"), "•••• 0123");
    }

    #[test]
    fn constant_time_eq_is_still_eq() {
        assert!(constant_time_eq(b"abc", b"abc"));
        assert!(!constant_time_eq(b"abc", b"abd"));
        assert!(!constant_time_eq(b"abc", b"ab"));
    }

    #[test]
    fn a_name_cannot_inject_html_into_the_email() {
        let (_, html) = email_body("<script>x</script> Smith", "000111");
        assert!(!html.contains("<script>"));
    }
}
