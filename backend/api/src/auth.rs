use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: Uuid,
    pub exp: i64,
    pub iat: i64,
    pub typ: String,
    /// Unique per issuance.
    ///
    /// Without it the claims are entirely determined by the user, the type and
    /// the second, so two tokens minted for the same user inside one second are
    /// byte-identical — and storing the second refresh token then violates the
    /// unique index on its hash. Optional so tokens issued before this existed
    /// still decode.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub jti: Option<Uuid>,
}

#[derive(Debug, Clone)]
pub struct AuthUser {
    pub user_id: Uuid,
}

pub fn hash_token(token: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    format!("{:x}", hasher.finalize())
}

pub fn issue_access_token(state: &AppState, user_id: Uuid) -> ApiResult<String> {
    let now = Utc::now();
    let claims = Claims {
        sub: user_id,
        iat: now.timestamp(),
        exp: (now + Duration::seconds(state.access_ttl_secs)).timestamp(),
        typ: "access".into(),
        jti: Some(Uuid::new_v4()),
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| ApiError::internal("failed to issue access token"))
}

pub fn issue_refresh_token(state: &AppState, user_id: Uuid) -> ApiResult<(String, chrono::DateTime<Utc>)> {
    let now = Utc::now();
    let exp = now + Duration::seconds(state.refresh_ttl_secs);
    let claims = Claims {
        sub: user_id,
        iat: now.timestamp(),
        exp: exp.timestamp(),
        typ: "refresh".into(),
        jti: Some(Uuid::new_v4()),
    };
    let token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| ApiError::internal("failed to issue refresh token"))?;
    Ok((token, exp))
}

pub fn decode_token(state: &AppState, token: &str) -> ApiResult<Claims> {
    decode::<Claims>(
        token,
        &DecodingKey::from_secret(state.jwt_secret.as_bytes()),
        &Validation::default(),
    )
    .map(|d| d.claims)
    .map_err(|_| ApiError::unauthorized("invalid token"))
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| ApiError::unauthorized("missing Authorization header"))?;

        let token = auth
            .strip_prefix("Bearer ")
            .ok_or_else(|| ApiError::unauthorized("expected Bearer token"))?;

        let claims = decode_token(state, token)?;
        if claims.typ != "access" {
            return Err(ApiError::unauthorized("access token required"));
        }
        Ok(AuthUser {
            user_id: claims.sub,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encode_with(jti: Option<Uuid>, sub: Uuid, secs: i64) -> String {
        let claims = Claims {
            sub,
            iat: secs,
            exp: secs + 900,
            typ: "refresh".into(),
            jti,
        };
        encode(
            &Header::default(),
            &claims,
            &EncodingKey::from_secret(b"test-secret"),
        )
        .expect("encodes")
    }

    /// Two refresh tokens for the same user in the same second must differ.
    ///
    /// They are stored by SHA-256 of the token under a unique index, so
    /// identical tokens made the second `store_refresh_token` fail with a
    /// duplicate key — which is what a refresh landing in the same second as
    /// the login did.
    #[test]
    fn tokens_issued_in_the_same_second_are_distinct() {
        let user = Uuid::new_v4();
        let now = 1_760_000_000;
        let a = encode_with(Some(Uuid::new_v4()), user, now);
        let b = encode_with(Some(Uuid::new_v4()), user, now);
        assert_ne!(a, b, "same-second tokens collided");
        assert_ne!(hash_token(&a), hash_token(&b));
    }

    /// The claims carry nothing else unique, so without `jti` they are equal —
    /// this is the bug the field exists to prevent.
    #[test]
    fn without_a_nonce_the_claims_alone_collide() {
        let user = Uuid::new_v4();
        let now = 1_760_000_000;
        assert_eq!(encode_with(None, user, now), encode_with(None, user, now));
    }

    /// A token minted before `jti` existed still decodes.
    #[test]
    fn claims_without_jti_still_parse() {
        let token = encode_with(None, Uuid::new_v4(), 1_760_000_000);
        let claims: Claims = decode(
            &token,
            &DecodingKey::from_secret(b"test-secret"),
            &{
                let mut v = Validation::default();
                v.validate_exp = false;
                v
            },
        )
        .expect("decodes")
        .claims;
        assert!(claims.jti.is_none());
    }
}
