//! Sign in with Apple: checking the identity token the iOS app hands us.
//!
//! Same shape as Google — JWT, RS256, published keys — with Apple's issuer
//! and our app's bundle id as the audience. Off without APPLE_CLIENT_ID
//! (defaults to `com.fishers.app` when unset so a native iOS build can work
//! without an extra vault key; set it explicitly for web Services IDs).

use std::time::{Duration, Instant};

use jsonwebtoken::jwk::JwkSet;
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use tokio::sync::RwLock;

const CERTS: &str = "https://appleid.apple.com/auth/keys";
const ISSUER: &str = "https://appleid.apple.com";
const DEFAULT_CLIENT_ID: &str = "com.fishers.app";

/// Who Apple says this is.
#[derive(Debug, Clone, Deserialize)]
pub struct AppleIdentity {
    /// Apple's permanent id for the account on this app.
    pub sub: String,
    pub email: Option<String>,
    /// Apple sends this as a string ("true") or a bool depending on the token.
    #[serde(default, deserialize_with = "truthy")]
    pub email_verified: bool,
    /// True when Apple is hiding the real address behind a private relay.
    #[serde(default, deserialize_with = "truthy")]
    pub is_private_email: bool,
}

fn truthy<'de, D: serde::Deserializer<'de>>(d: D) -> Result<bool, D::Error> {
    use serde::de::{Error, Unexpected, Visitor};
    use std::fmt;
    struct V;
    impl<'de> Visitor<'de> for V {
        type Value = bool;
        fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
            f.write_str("a bool or the string true/false")
        }
        fn visit_bool<E: Error>(self, v: bool) -> Result<bool, E> {
            Ok(v)
        }
        fn visit_str<E: Error>(self, v: &str) -> Result<bool, E> {
            match v {
                "true" | "TRUE" | "1" => Ok(true),
                "false" | "FALSE" | "0" => Ok(false),
                other => Err(E::invalid_value(Unexpected::Str(other), &self)),
            }
        }
        fn visit_unit<E: Error>(self) -> Result<bool, E> {
            Ok(false)
        }
    }
    d.deserialize_any(V)
}

pub struct AppleSignIn {
    client_id: String,
    certs: String,
    http: reqwest::Client,
    keys: RwLock<Option<(JwkSet, Instant)>>,
}

impl AppleSignIn {
    pub fn from_env() -> Self {
        let client_id = std::env::var("APPLE_CLIENT_ID")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| DEFAULT_CLIENT_ID.to_string());
        Self {
            client_id,
            certs: CERTS.to_string(),
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(10))
                .build()
                .unwrap_or_default(),
            keys: RwLock::new(None),
        }
    }

    pub fn client_id(&self) -> &str {
        &self.client_id
    }

    /// Always on for the native app bundle; a wrong APPLE_CLIENT_ID just fails
    /// verification rather than hiding the button.
    pub fn enabled(&self) -> bool {
        !self.client_id.is_empty()
    }

    pub async fn verify(&self, token: &str) -> Result<AppleIdentity, String> {
        let kid = decode_header(token)
            .map_err(|_| "not an Apple sign-in token")?
            .kid
            .ok_or("the token names no key")?;

        let jwk = match self.key(&kid, false).await? {
            Some(jwk) => jwk,
            None => self
                .key(&kid, true)
                .await?
                .ok_or("signed with a key Apple does not publish")?,
        };
        let key = DecodingKey::from_jwk(&jwk).map_err(|_| "unusable Apple key")?;

        let mut rules = Validation::new(Algorithm::RS256);
        rules.set_audience(&[&self.client_id]);
        rules.set_issuer(&[ISSUER]);
        decode::<AppleIdentity>(token, &key, &rules)
            .map(|data| data.claims)
            .map_err(|e| format!("Apple sign-in token refused: {e}"))
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
            .map_err(|e| format!("could not reach Apple: {e}"))?;
        let ttl = max_age(response.headers()).unwrap_or(Duration::from_secs(3600));
        let set: JwkSet = response
            .json()
            .await
            .map_err(|e| format!("Apple's keys did not parse: {e}"))?;
        let found = set.find(kid).cloned();
        *self.keys.write().await = Some((set, Instant::now() + ttl));
        Ok(found)
    }
}

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

    #[tokio::test]
    async fn refuses_junk() {
        let apple = AppleSignIn::from_env();
        assert!(apple.enabled());
        assert!(apple.verify("not-a-jwt").await.is_err());
    }
}
