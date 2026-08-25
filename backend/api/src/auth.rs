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
