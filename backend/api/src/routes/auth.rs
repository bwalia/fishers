use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use axum::extract::State;
use axum::routing::post;
use axum::{Json, Router};
use fishers_db::repos::users as users_repo;
use fishers_domain::{AuthTokens, LoginRequest, RefreshRequest, SignupRequest};
use rand::rngs::OsRng;
use validator::Validate;

use crate::auth::{hash_token, issue_access_token, issue_refresh_token, decode_token};
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/auth/signup", post(signup))
        .route("/auth/login", post(login))
        .route("/auth/refresh", post(refresh))
}

async fn signup(
    State(state): State<AppState>,
    Json(body): Json<SignupRequest>,
) -> ApiResult<Json<AuthTokens>> {
    body.validate()?;
    let (email, phone) = body.identifiers();
    // One of the two identifies a person. Requiring an address keeps out
    // members who have a phone and nothing else.
    if email.is_none() && phone.is_none() {
        return Err(ApiError::bad_request(
            "give an email address or a mobile number",
        ));
    }
    if let Some(address) = email.as_deref() {
        if users_repo::find_by_email(&state.pool, address).await?.is_some() {
            return Err(ApiError::conflict("that email is already registered"));
        }
    }
    if let Some(number) = phone.as_deref() {
        if users_repo::find_by_phone(&state.pool, number).await?.is_some() {
            return Err(ApiError::conflict("that mobile number is already registered"));
        }
    }

    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default()
        .hash_password(body.password.as_bytes(), &salt)
        .map_err(|_| ApiError::internal("password hash failed"))?
        .to_string();

    let user = users_repo::create_user(
        &state.pool,
        &body.name,
        email.as_deref(),
        &hash,
        phone.as_deref(),
    )
    .await?;

    // The first code is already on its way when the dashboard loads. In the
    // background: a slow or unreachable mail server must never fail a signup.
    if user.email.is_some() && state.email.enabled() {
        let (state, user) = (state.clone(), user.clone());
        tokio::spawn(async move {
            if let Err(e) = super::verification::issue(&state, &user, "email").await {
                tracing::warn!(error = %e.message, "signup verification email not sent");
            }
        });
    }

    issue_tokens(&state, user).await
}

async fn login(
    State(state): State<AppState>,
    Json(body): Json<LoginRequest>,
) -> ApiResult<Json<AuthTokens>> {
    body.validate()?;
    // Either identifier signs you in, whichever you registered with.
    let user = users_repo::find_by_identifier(&state.pool, &body.identifier)
        .await?
        .ok_or_else(|| ApiError::unauthorized("invalid credentials"))?;

    let hash = user
        .password_hash
        .as_deref()
        .ok_or_else(|| ApiError::unauthorized("invalid credentials"))?;
    let parsed = PasswordHash::new(hash).map_err(|_| ApiError::internal("bad password hash"))?;
    Argon2::default()
        .verify_password(body.password.as_bytes(), &parsed)
        .map_err(|_| ApiError::unauthorized("invalid credentials"))?;

    issue_tokens(&state, user).await
}

async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshRequest>,
) -> ApiResult<Json<AuthTokens>> {
    let claims = decode_token(&state, &body.refresh_token)?;
    if claims.typ != "refresh" {
        return Err(ApiError::unauthorized("refresh token required"));
    }
    let token_hash = hash_token(&body.refresh_token);
    let valid = users_repo::find_valid_refresh_token(&state.pool, &token_hash)
        .await?
        .ok_or_else(|| ApiError::unauthorized("refresh token revoked or expired"))?;
    if valid.0 != claims.sub {
        return Err(ApiError::unauthorized("token mismatch"));
    }
    users_repo::revoke_refresh_token(&state.pool, &token_hash).await?;

    let user = users_repo::find_by_id(&state.pool, claims.sub)
        .await?
        .ok_or_else(|| ApiError::unauthorized("user not found"))?;
    issue_tokens(&state, user).await
}

async fn issue_tokens(
    state: &AppState,
    user: fishers_domain::User,
) -> ApiResult<Json<AuthTokens>> {
    let access = issue_access_token(state, user.id)?;
    let (refresh, exp) = issue_refresh_token(state, user.id)?;
    users_repo::store_refresh_token(&state.pool, user.id, &hash_token(&refresh), exp).await?;

    Ok(Json(AuthTokens {
        access_token: access,
        refresh_token: refresh,
        token_type: "Bearer".into(),
        expires_in: state.access_ttl_secs,
        user: user.into(),
    }))
}
