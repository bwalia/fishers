use argon2::password_hash::{PasswordHash, PasswordVerifier};
use argon2::Argon2;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::users as users_repo;
use fishers_domain::{reliability, PublicUser, SportProfile, UpdateProfileRequest};
use rand::distributions::{Alphanumeric, DistString};
use serde::Serialize;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me", get(me).patch(update_me))
        .route("/me/delete", post(delete_me))
        .route("/me/avatar", post(upload_avatar))
        .route("/me/share-link", post(share_link))
        .route("/players/card/{token}", get(shared_card))
}

#[derive(Serialize)]
struct ShareLink {
    token: String,
}

#[derive(serde::Deserialize)]
struct DeleteAccount {
    /// Asked for when the account has one. Accounts that sign in with Google
    /// have no password to give, and confirm in the app instead.
    #[serde(default)]
    password: Option<String>,
}

/// Delete this account, which cannot be undone.
///
/// App Store Review 5.1.1(v) requires this to exist in the app for anything
/// that lets you create an account. POST rather than DELETE because the
/// password travels in the body, and a DELETE body is the kind of thing
/// proxies drop.
///
/// What goes: name, email, phone, password, avatar, location, everything on
/// the player profile, every session and every device token. What stays: the
/// scorecards, the club history and the averages built on them, under a name
/// that no longer points at anybody. Those belong to other people too, and a
/// match that loses a player stops adding up.
async fn delete_me(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<DeleteAccount>,
) -> ApiResult<StatusCode> {
    let user = users_repo::find_by_id(&state.pool, auth.user_id)
        .await?
        .ok_or_else(|| ApiError::unauthorized("not signed in"))?;

    // A live session on a borrowed phone should not be enough to end somebody's
    // account, so where there is a password it has to be typed again.
    if let Some(hash) = user.password_hash.as_deref() {
        let given = body.password.unwrap_or_default();
        let parsed =
            PasswordHash::new(hash).map_err(|_| ApiError::internal("bad password hash"))?;
        Argon2::default()
            .verify_password(given.as_bytes(), &parsed)
            .map_err(|_| ApiError::unauthorized("that password does not match"))?;
    }

    users_repo::delete_account(&state.pool, auth.user_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// The token behind a player's "send my profile to a club" link. Minted once
/// and kept, so a link already sent to a secretary keeps working.
async fn share_link(State(state): State<AppState>, auth: AuthUser) -> ApiResult<Json<ShareLink>> {
    // 24 alphanumerics ≈ 143 bits: not guessable, and short enough to text.
    let fresh = Alphanumeric.sample_string(&mut rand::rngs::OsRng, 24);
    let token = users_repo::share_token(&state.pool, auth.user_id, &fresh).await?;
    Ok(Json(ShareLink { token }))
}

/// What a secretary sees on a shared link: enough to decide to invite them —
/// who, what they play, where — and nothing a stranger should have. No email,
/// no phone, no emergency contact: those come with club membership, which the
/// player still has to accept.
#[derive(Serialize)]
struct SharedCard {
    id: Uuid,
    name: String,
    avatar_url: Option<String>,
    primary_sport: Option<String>,
    sport_profiles: Vec<SportProfile>,
    area: Option<String>,
}

async fn shared_card(
    State(state): State<AppState>,
    _auth: AuthUser,
    Path(token): Path<String>,
) -> ApiResult<Json<SharedCard>> {
    let user = users_repo::find_by_share_token(&state.pool, &token)
        .await?
        .ok_or_else(|| ApiError::not_found("that profile link is not valid"))?;
    Ok(Json(SharedCard {
        id: user.id,
        name: user.name,
        avatar_url: user.avatar_url,
        primary_sport: user.primary_sport,
        sport_profiles: user.sport_profiles.0,
        area: user.location.and_then(|l| l.0.area),
    }))
}

async fn me(State(state): State<AppState>, auth: AuthUser) -> ApiResult<Json<PublicUser>> {
    let user = users_repo::find_by_id(&state.pool, auth.user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("user not found"))?;
    let mut me = with_reliability(&state, user).await?;
    // Only here. Every other route that hands back a PublicUser is describing
    // somebody else, and whether they run the place is not a fact those
    // callers should be able to read off a teammate's profile.
    me.platform_admin = crate::rbac::is_platform_admin(&state, auth.user_id).await?;
    Ok(Json(me))
}

async fn update_me(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<UpdateProfileRequest>,
) -> ApiResult<Json<PublicUser>> {
    body.validate()?;
    let user = users_repo::update_profile(&state.pool, auth.user_id, &body).await?;
    Ok(Json(with_reliability(&state, user).await?))
}

/// Reliability is earned, not submitted: it is computed from attendance and
/// payment history on every read rather than stored on the user.
async fn with_reliability(
    state: &AppState,
    user: fishers_domain::User,
) -> Result<PublicUser, ApiError> {
    let counts = users_repo::reliability_counts(&state.pool, user.id).await?;
    Ok(PublicUser::from(user).with_reliability(reliability::score(counts)))
}

/// Two megabytes. A profile picture is displayed at 96px; anything larger is
/// somebody's camera roll, and the limit is what stops a signed-in user
/// filling the bucket.
const MAX_AVATAR_BYTES: usize = 2 * 1024 * 1024;

/// What we are willing to serve back, checked against the bytes rather than
/// the caller's word for it.
fn sniff_image(bytes: &[u8]) -> Option<(&'static str, &'static str)> {
    match bytes {
        [0xFF, 0xD8, 0xFF, ..] => Some(("image/jpeg", "jpg")),
        [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, ..] => Some(("image/png", "png")),
        [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] => {
            Some(("image/webp", "webp"))
        }
        _ => None,
    }
}

/// A profile picture.
///
/// The content type is taken from the file's own magic bytes, never from the
/// multipart header: a caller who says "image/png" and sends HTML would
/// otherwise get it served back from our own origin.
async fn upload_avatar(
    State(state): State<AppState>,
    auth: AuthUser,
    mut form: axum::extract::Multipart,
) -> ApiResult<Json<PublicUser>> {
    let storage = state
        .storage
        .as_ref()
        .ok_or_else(|| ApiError::bad_request("uploads are not configured on this server"))?;

    let mut bytes: Option<Vec<u8>> = None;
    while let Some(field) = form
        .next_field()
        .await
        .map_err(|e| ApiError::bad_request(format!("could not read the upload: {e}")))?
    {
        if field.name() == Some("file") {
            let data = field
                .bytes()
                .await
                .map_err(|e| ApiError::bad_request(format!("could not read the file: {e}")))?;
            if data.len() > MAX_AVATAR_BYTES {
                return Err(ApiError::bad_request("that picture is over 2MB"));
            }
            bytes = Some(data.to_vec());
            break;
        }
    }
    let bytes = bytes.ok_or_else(|| ApiError::bad_request("no file was sent"))?;
    let (content_type, ext) = sniff_image(&bytes)
        .ok_or_else(|| ApiError::bad_request("that is not a JPEG, PNG or WebP"))?;

    // Keyed by user and a fresh id, so a new picture never serves a stale one
    // out of somebody's cache.
    let key = format!("avatars/{}/{}.{ext}", auth.user_id, Uuid::new_v4());
    let url = storage
        .put(&key, content_type, bytes)
        .await
        .map_err(|e| ApiError::internal(format!("could not store the picture: {e}")))?;

    let update = fishers_domain::UpdateProfileRequest {
        avatar_url: Some(url),
        ..Default::default()
    };
    Ok(Json(
        users_repo::update_profile(&state.pool, auth.user_id, &update)
            .await?
            .into(),
    ))
}
