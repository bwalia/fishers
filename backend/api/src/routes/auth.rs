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
    if users_repo::find_by_email(&state.pool, &body.email)
        .await?
        .is_some()
    {
        return Err(ApiError::conflict("email already registered"));
    }

    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default()
        .hash_password(body.password.as_bytes(), &salt)
        .map_err(|_| ApiError::internal("password hash failed"))?
        .to_string();

    let user = users_repo::create_user(
        &state.pool,
        &body.name,
        &body.email,
        &hash,
        body.phone.as_deref(),
    )
    .await?;

    issue_tokens(&state, user).await
}

async fn login(
    State(state): State<AppState>,
    Json(body): Json<LoginRequest>,
) -> ApiResult<Json<AuthTokens>> {
    body.validate()?;
    let user = users_repo::find_by_email(&state.pool, &body.email)
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
