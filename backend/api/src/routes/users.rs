use axum::extract::State;
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::users as users_repo;
use fishers_domain::{reliability, PublicUser, UpdateProfileRequest};
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me", get(me).patch(update_me))
        .route("/me/avatar", post(upload_avatar))
}

async fn me(State(state): State<AppState>, auth: AuthUser) -> ApiResult<Json<PublicUser>> {
    let user = users_repo::find_by_id(&state.pool, auth.user_id)
        .await?
        .ok_or_else(|| ApiError::not_found("user not found"))?;
    Ok(Json(with_reliability(&state, user).await?))
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
