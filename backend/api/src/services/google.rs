//! Sign in with Google: checking the ID token Google's button hands the page.
//!
//! The token is a JWT signed by Google. It is trusted only after checking,
//! here and not by asking Google each time: the signature against Google's
//! published keys, that it was issued by Google, for this app (`aud` is our
//! client id — a token minted for any other site is refused), and that it has
//! not expired. The keys are cached for as long as Google says they may be.
//!
//! Off without GOOGLE_CLIENT_ID, and the sign-in page then simply does not
//! offer it.

use std::time::{Duration, Instant};

use jsonwebtoken::jwk::JwkSet;
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use tokio::sync::RwLock;

const CERTS: &str = "https://www.googleapis.com/oauth2/v3/certs";
const ISSUERS: [&str; 2] = ["accounts.google.com", "https://accounts.google.com"];

/// Who Google says this is.
#[derive(Debug, Clone, Deserialize)]
pub struct GoogleIdentity {
    /// Google's permanent id for the account.
    pub sub: String,
    pub email: Option<String>,
    #[serde(default)]
    pub email_verified: bool,
    pub name: Option<String>,
    pub picture: Option<String>,
}

pub struct GoogleSignIn {
    client_id: Option<String>,
    certs: String,
    http: reqwest::Client,
    keys: RwLock<Option<(JwkSet, Instant)>>,
}

impl GoogleSignIn {
    pub fn from_env() -> Self {
        Self {
            client_id: std::env::var("GOOGLE_CLIENT_ID")
                .ok()
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty()),
            certs: certs_url(),
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(10))
                .build()
                .unwrap_or_default(),
            keys: RwLock::new(None),
        }
    }

    /// The public client id the page renders Google's button with.
    pub fn client_id(&self) -> Option<&str> {
        self.client_id.as_deref()
    }

    pub async fn verify(&self, token: &str) -> Result<GoogleIdentity, String> {
        let client_id = self.client_id.as_deref().ok_or("Google sign-in is not set up")?;
        let kid = decode_header(token)
            .map_err(|_| "not a Google sign-in token")?
            .kid
            .ok_or("the token names no key")?;

        // Google rotates its keys; one we have not seen yet means ours are
        // stale, so fetch once more before giving up on it.
        let jwk = match self.key(&kid, false).await? {
            Some(jwk) => jwk,
            None => self.key(&kid, true).await?.ok_or("signed with a key Google does not publish")?,
        };
        let key = DecodingKey::from_jwk(&jwk).map_err(|_| "unusable Google key")?;

        let mut rules = Validation::new(Algorithm::RS256);
        rules.set_audience(&[client_id]);
        rules.set_issuer(&ISSUERS);
        decode::<GoogleIdentity>(token, &key, &rules)
            .map(|data| data.claims)
            .map_err(|e| format!("Google sign-in token refused: {e}"))
    }

    async fn key(&self, kid: &str, refresh: bool) -> Result<Option<jsonwebtoken::jwk::Jwk>, String> {
        if !refresh {
            if let Some((set, until)) = self.keys.read().await.as_ref() {
                if Instant::now() < *until {
                    return Ok(set.find(kid).cloned());
                }
            }
        }
        let response = self
            .http
            .get(&self.certs)
            .send()
            .await
            .map_err(|e| format!("could not reach Google: {e}"))?;
        let ttl = max_age(response.headers()).unwrap_or(Duration::from_secs(3600));
        let set: JwkSet = response
            .json()
            .await
            .map_err(|e| format!("Google's keys did not parse: {e}"))?;
        let found = set.find(kid).cloned();
        *self.keys.write().await = Some((set, Instant::now() + ttl));
        Ok(found)
    }
}

/// Where Google's signing keys are published.
///
/// A development build may be pointed at a stand-in, so the sign-in flow can
/// be tested end to end without a Google account. Compiled out of release
/// builds — which is what every deployed ring runs — so no setting can ever
/// make production trust keys that are not Google's.
fn certs_url() -> String {
    #[cfg(debug_assertions)]
    if let Ok(url) = std::env::var("GOOGLE_CERTS_URL") {
        tracing::warn!(%url, "Google sign-in is trusting a stand-in for Google's keys");
        return url;
    }
    CERTS.to_string()
}

/// `Cache-Control: max-age=N`, as Google sends with its keys.
fn max_age(headers: &reqwest::header::HeaderMap) -> Option<Duration> {
    headers
        .get(reqwest::header::CACHE_CONTROL)?
        .to_str()
        .ok()?
        .split(',')
        .find_map(|part| part.trim().strip_prefix("max-age="))?
        .parse()
        .ok()
        .map(Duration::from_secs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_max_age_among_other_directives() {
        let mut h = reqwest::header::HeaderMap::new();
        h.insert(reqwest::header::CACHE_CONTROL, "public, max-age=21436, must-revalidate, no-transform".parse().unwrap());
        assert_eq!(max_age(&h), Some(Duration::from_secs(21436)));
        h.insert(reqwest::header::CACHE_CONTROL, "no-cache".parse().unwrap());
        assert_eq!(max_age(&h), None);
    }

    #[tokio::test]
    async fn refuses_without_a_client_id_and_refuses_junk() {
        let off = GoogleSignIn { client_id: None, certs: CERTS.into(), http: reqwest::Client::new(), keys: RwLock::new(None) };
        assert!(off.verify("a.b.c").await.is_err());
        let on = GoogleSignIn { client_id: Some("x.apps.googleusercontent.com".into()), certs: CERTS.into(), http: reqwest::Client::new(), keys: RwLock::new(None) };
        assert!(on.verify("not-a-jwt").await.is_err());
    }
}
